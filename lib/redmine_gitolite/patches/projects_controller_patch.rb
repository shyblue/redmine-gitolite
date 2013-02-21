module RedmineGitolite
  module Patches
    module ProjectsControllerPatch
      unloadable

      def self.included(base)
        base.send(:alias_method_chain, :create, :disable_update)
        base.send(:alias_method_chain, :update, :disable_update)
      end


      def git_repo_init
        users = @project.member_principals.map(&:user).compact.uniq
        if users.length == 0
          membership = Member.new(
            :principal=>User.current,
            :project_id=>@project.id,
            :role_ids=>[3]
          )
          membership.save
        end


        if @project.module_enabled?('repository') && GitoliteConfig.all_projects_use_git?
          # Create new repository
          Rails.logger.info "[Gitolite] About to create new repo!"
          repo = Repository.factory("Git")
          @project.repositories << repo
          Rails.logger.info "[Gitolite] Done creating new repo!"
        end
      end


      def create_with_disable_update
        # Turn of updates during repository update
        GitoliteObserver.set_update_active(false);

        # Do actual update
        create_without_disable_update

        # Fix up repository
        git_repo_init

        # Reenable updates to perform a single update
        GitoliteObserver.set_update_active(true);
      end


      def update_with_disable_update
        # Turn of updates during repository update
        GitoliteObserver.set_update_active(false);

        # Do actual update
        update_without_disable_update

        if @project.gl_repos.detect {|repo| repo.url != GitoliteHosting::repository_path(repo) || repo.url != repo.root_url}
          # Hm... something about parent hierarchy changed.  Update us and our children
          GitoliteObserver.set_update_active(@project, :descendants)
        else
          # Reenable updates to perform a single update
          GitoliteObserver.set_update_active(true);
        end
      end

    end
  end
end

unless ProjectsController.included_modules.include?(RedmineGitolite::Patches::ProjectsControllerPatch)
  ProjectsController.send(:include, RedmineGitolite::Patches::ProjectsControllerPatch)
end
