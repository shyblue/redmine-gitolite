module RedmineGitolite
  module Patches
    module RepositoriesControllerPatch
      unloadable

      def self.included(base)
        base.send(:alias_method_chain, :show, :git_instructions)
        base.send(:alias_method_chain, :edit, :scm_settings)
        base.send(:alias_method_chain, :update, :scm_settings)
        base.send(:alias_method_chain, :create, :scm_settings)
      end

      def show_with_git_instructions
        if @repository.is_a?(Repository::Git) and @repository.entries(@path, @rev).blank?
          @repositories = @project.repositories
          render :action => 'git_instructions'
        else
          show_without_git_instructions
        end
      end

      def edit_with_scm_settings
        git_parametrize
        edit_without_scm_settings
      end

      def update_with_scm_settings
        git_parametrize
        update_without_scm_settings
      end

      def create_with_scm_settings
        git_parametrize
        create_without_scm_settings
      end

      private

      def git_parametrize
        params[:repository] ||= {}
        params[:repository][:extra_report_last_commit] = '1'
        params[:repository][:url] = File.join(GitoliteConfig.repository_absolute_base_path, params[:repository][:identifier] + ".git") if params[:repository_scm] == 'Git'
      end

    end
  end
end

unless RepositoriesController.include?(RedmineGitolite::Patches::RepositoriesControllerPatch)
  RepositoriesController.send(:include, RedmineGitolite::Patches::RepositoriesControllerPatch)
end
