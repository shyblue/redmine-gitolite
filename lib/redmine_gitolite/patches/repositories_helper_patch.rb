module RedmineGitolite
  module Patches
    module RepositoriesHelperPatch
      unloadable

      def self.included(base)
        base.send(:alias_method_chain, :git_field_tags, :disabled_configuration)
      end

      def git_field_tags_with_disabled_configuration(form, repository)
        ''
      end

    end
  end
end

unless RepositoriesHelper.include?(RedmineGitolite::Patches::RepositoriesHelperPatch)
  RepositoriesHelper.send(:include, RedmineGitolite::Patches::RepositoriesHelperPatch)
end
