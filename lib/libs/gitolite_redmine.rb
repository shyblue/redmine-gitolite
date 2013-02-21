require 'lockfile'
require 'net/ssh'
require 'tmpdir'
require 'fileutils'
require 'gitolite'

module GitoliteRedmine

  class AdminHandler
    @@recursionCheck = false


    def update_projects(projects)
      recursion_check do
        projects = (projects.is_a?(Array) ? projects : [projects])

        if projects.detect{|p| p.repositories.detect{|r| r.is_a?(Repository::Git)}}
          if GitoliteHosting.lock
            clone_gitolite_admin_repo

            projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
              handle_project project
            end

            @gitolite_admin.save_and_apply

            FileUtils.rm_rf @tmp_dir
            GitoliteHosting.unlock
          end
        end

      end
    end


    def update_user(user)
      recursion_check do
        if GitoliteHosting.lock
          logger.info "[Gitolite] Handling User : #{user.login}"

          clone_gitolite_admin_repo

          add_active_keys(user.gitolite_public_keys.active)
          remove_inactive_keys(user.gitolite_public_keys.inactive)

          @gitolite_admin.save_and_apply

          FileUtils.rm_rf @tmp_dir
          GitoliteHosting.unlock
        end
      end
    end


    def delete_repository(repository)
      if GitoliteHosting.lock
        logger.info "[Gitolite] Delete Repository : #{repository.identifier}"

        repo_name = GitoliteHosting.repository_name(repository)

        clone_gitolite_admin_repo

        @gitolite_admin.config.rm_repo(repo_name)
        @gitolite_admin.save_and_apply

        FileUtils.rm_rf @tmp_dir

        GitoliteRecycle.move_repository_to_recycle repository if GitoliteConfig.recycle_bin_delete?

        GitoliteHosting.unlock
      end
    end


    def delete_user_ssh_key(ssh_key)
      if GitoliteHosting.lock
        logger.info "[Gitolite] Delete User's SSH Keys : #{ssh_key.identifier}"

        parts = ssh_key.key.split
        repo_key = Gitolite::SSHKey.new(parts[0], parts[1], parts[2])
        repo_key.location = ssh_key.location
        repo_key.owner = ssh_key.owner

        clone_gitolite_admin_repo

        @gitolite_admin.rm_key(repo_key)
        @gitolite_admin.save_and_apply

        FileUtils.rm_rf @tmp_dir
        GitoliteHosting.unlock
      end
    end


    def update_repositories(*args)
      flags = {}
      args.each {|arg| flags.merge!(arg) if arg.is_a?(Hash)}

      puts "#########################"
      puts YAML::dump(flags)
      puts "#########################"

      if flags[:descendants]
        logger.info "[Gitolite] I think we must update repo path"

        if Project.method_defined?(:self_and_descendants)
          projects = (args.flatten.select{|p| p.is_a?(Project)}).collect{|p| p.self_and_descendants}.flatten
        else
          projects = Project.active_or_archived.find(:all, :include => :repositories)
        end

        puts "#########################"
        puts projects
        puts YAML::dump(projects)
        puts "#########################"

        # Only take projects that have Git repos.
        git_projects = projects.uniq.select{|p| p.gl_repos.any?}
        return if git_projects.empty?

      end
    end


    private


    def local_dir
      @tmp_dir ||= File.join(Rails.root, "tmp", "redmine_gitolite_#{Time.now.to_i}")
    end


    def clone_gitolite_admin_repo
      local_dir
      logger.info ""
      logger.info "[Gitolite] Clone Gitolite Admin Repo"
      FileUtils.mkdir_p @tmp_dir
      result = `git clone #{GitoliteConfig.gitolite_admin_url} #{@tmp_dir}`
      logger.info "[Gitolite] #{result}"
      @gitolite_admin = Gitolite::GitoliteAdmin.new @tmp_dir
    end


    def handle_project(project)
      users = project.member_principals.map(&:user).compact.uniq
      project_name = project.identifier.to_s

      logger.info "[Gitolite] Handling Project : #{project_name}"

      project.repositories.select{|r| r.is_a?(Repository::Git)}.each do |repository|

        repo_hierarchy = GitoliteHosting.repository_name(repository)
        repo_name      = repository.identifier
        repo_conf      = @gitolite_admin.config.repos[repo_hierarchy]

        logger.info "[Gitolite] Handling Repository : #{repo_hierarchy}"

        if repo_conf
          logger.info "[Gitolite] Gitolite repo already exists, skip..."
          logger.debug "[Gitolite] Repo Conf : #{repo_conf}"
        else
          logger.info "[Gitolite] Gitolite repo does not exist, create..."
          repo_conf = Gitolite::Config::Repo.new(repo_hierarchy)
          repo_conf.set_git_config("hooks.redmine_gitolite.projectid", project_name)
          repo_conf.set_git_config("hooks.redmine_gitolite.repoid", repo_name)
          @gitolite_admin.config.add_repo(repo_conf)
        end

        repo_conf.permissions = build_permissions(users, project)
      end
    end


    def add_active_keys(keys)
      keys.each do |key|
        parts = key.key.split
        repo_keys = @gitolite_admin.ssh_keys[key.owner]
        repo_key = repo_keys.find_all{|k| k.location == key.location && k.owner == key.owner}.first
        if repo_key
          repo_key.type, repo_key.blob, repo_key.email = parts
          repo_key.owner = key.owner
        else
          repo_key = Gitolite::SSHKey.new(parts[0], parts[1], parts[2])
          repo_key.location = key.location
          repo_key.owner = key.owner
          @gitolite_admin.add_key repo_key
        end
      end
    end


    def remove_inactive_keys(keys)
      keys.each do |key|
        repo_keys = @gitolite_admin.ssh_keys[key.owner]
        repo_key = repo_keys.find_all{|k| k.location == key.location && k.owner == key.owner}.first
        @gitolite_admin.rm_key repo_key if repo_key
      end
    end


    def build_permissions(users, project)
      rewind_users = users.select{|user| user.allowed_to?(:manage_repository, project) }
      write_users = users.select{|user| user.allowed_to?(:commit_access, project) && !user.allowed_to?(:manage_repository, project) }
      read_users = users.select{|user| user.allowed_to?(:view_changesets, project) && !user.allowed_to?(:commit_access, project) && !user.allowed_to?(:manage_repository, project) }

      rewind = rewind_users.map{|usr| usr.login.underscore.gsub(/[^0-9a-zA-Z\-\_]/,'_')}.sort
      write = write_users.map{|usr| usr.login.underscore.gsub(/[^0-9a-zA-Z\-\_]/,'_')}.sort
      read = read_users.map{|usr| usr.login.underscore.gsub(/[^0-9a-zA-Z\-\_]/,'_')}.sort

      read << "redmine"
      read << "daemon" if User.anonymous.allowed_to?(:view_changesets, project)
      read << "gitweb" if User.anonymous.allowed_to?(:view_gitweb, project)

      permissions = {}
      permissions["RW+"] = {"" => rewind} unless rewind.empty?
      permissions["RW"] = {"" => write} unless write.empty?
      permissions["R"] = {"" => read} unless read.empty?

      [permissions]
    end


    def recursion_check
      return if @@recursionCheck
      begin
        @@recursionCheck = true
        yield
      rescue Exception => e
        logger.error "#{e.inspect} #{e.backtrace}"
      ensure
        @@recursionCheck = false
      end
    end


    def logger
      Rails.logger
    end

  end
end
