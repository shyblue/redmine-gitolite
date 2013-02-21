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
        # Do actual update
        create_without_disable_update

        # Fix up repository
        git_repo_init
      end


      def update_with_disable_update
        # Do actual update
        update_without_disable_update

        gr = GitoliteRedmine::AdminHandler.new
        gr.update_repositories(@project)

      end

    end
  end
end

unless ProjectsController.included_modules.include?(RedmineGitolite::Patches::ProjectsControllerPatch)
  ProjectsController.send(:include, RedmineGitolite::Patches::ProjectsControllerPatch)
end
