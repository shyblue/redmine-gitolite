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


    def update_repositories(project)

      projects = project.self_and_descendants

      # Only take projects that have Git repos.
      git_projects = projects.uniq.select{|p| p.gl_repos.any?}
      return if git_projects.empty?

      clone_gitolite_admin_repo

      if GitoliteHosting.lock
        git_projects.each do |project|
          project.gl_repos.each do |repository|
            if repository.url != GitoliteHosting.repository_absolute_path(repository)

              logger.info "[Gitolite] I think we must update repo path"
              logger.info "[Gitolite] Update Project infos : #{project.identifier}"

              project_name = project.identifier
              repo_name    = repository.identifier

              old_absolute_path  = "#{repository.url}"
              new_absolute_path  = "#{GitoliteConfig.repository_absolute_base_path}#{GitoliteHosting.repository_name(repository)}.git"
              old_relative_path  = "#{GitoliteConfig.repository_relative_base_path}#{old_absolute_path.gsub(GitoliteConfig.repository_absolute_base_path, '')}"
              new_relative_path  = "#{GitoliteConfig.repository_relative_base_path}#{GitoliteHosting.repository_name(repository)}.git"
              old_repo_hierarchy = "#{old_absolute_path.gsub(GitoliteConfig.repository_absolute_base_path, '').gsub('.git', '')}"
              new_repo_hierarchy = "#{GitoliteHosting.repository_name(repository)}"

              puts "[Gitolite] Update Repository infos :"
              puts "[Gitolite] Old Absolute path (for Redmine code browser) : #{old_absolute_path}"
              puts "[Gitolite] New Absolute path (for Redmine code browser) : #{new_absolute_path}"
              puts "[Gitolite] Old Relative path (for Gitolite)             : #{old_relative_path}"
              puts "[Gitolite] New Relative path (for Gitolite)             : #{new_relative_path}"
              puts "[Gitolite] Old Repo hierarchy (for Gitolite)            : #{old_repo_hierarchy}"
              puts "[Gitolite] New Repo hierarchy (for Gitolite)            : #{new_repo_hierarchy}"
              puts ""

              GitoliteHosting.move_physical_repo(old_relative_path, new_relative_path)

              Repository.observers.disable :all do
                repository.url = "#{new_absolute_path}"
                repository.save!
              end

              # update gitolite conf
              repo_conf = @gitolite_admin.config.repos[old_repo_hierarchy]
              if !repo_conf
                logger.error "[Gitolite] Repository hierarchy '#{old_repo_hierarchy}' does not exist in Gitolite conf !"
                return
              else
                @gitolite_admin.config.rm_repo(old_repo_hierarchy)
                repo_conf = Gitolite::Config::Repo.new(new_repo_hierarchy)
                repo_conf.set_git_config("hooks.redmine_gitolite.projectid", project_name)
                repo_conf.set_git_config("hooks.redmine_gitolite.repoid", repo_name)
                @gitolite_admin.config.add_repo(repo_conf)

                users = project.member_principals.map(&:user).compact.uniq
                repo_conf.permissions = build_permissions(users, project)
              end

            end
          end
        end

        @gitolite_admin.save_and_apply

        FileUtils.rm_rf @tmp_dir

        GitoliteHosting.unlock

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

        unless repo_conf
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
