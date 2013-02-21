module RedmineGitolite
  module Patches
    module RepositoryPatch
      unloadable

      def self.included(base)
        base.send(:include, InstanceMethods)
        base.class_eval do
          after_create :update_values
        end
      end

      module InstanceMethods

        def update_values
          if self.is_a?(Repository::Git)
            self.url = File.join(GitoliteConfig.repository_absolute_base_path, GitoliteHosting::repository_name(self) + ".git")
            self.save!
          end
        end

        # Use directory notation: <project identifier>/<repo identifier>
        def git_label
          return "#{project.identifier}/#{identifier}"
        end

        def gitolite_http_url
          return "http://#{GitoliteConfig.gitolite_server_domain}/projects/#{project.identifier}/repository/#{identifier}"
        end

        def gitolite_git_url
          repo_name = GitoliteHosting.repository_name(self)
          return "#{GitoliteConfig.gitolite_user}@#{GitoliteConfig.gitolite_server_domain}:#{repo_name}.git"
        end
      end

    end
  end
end

unless Repository.included_modules.include?(RedmineGitolite::Patches::RepositoryPatch)
  Repository.send(:include, RedmineGitolite::Patches::RepositoryPatch)
end
