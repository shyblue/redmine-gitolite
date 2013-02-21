module RedmineGitolite
  module Patches
    module ProjectPatch
      unloadable

      def self.included(base)
        base.class_eval do
          scope :archived, { :conditions => {:status => "#{Project::STATUS_ARCHIVED}"}}
          scope :active_or_archived, { :conditions => "status=#{Project::STATUS_ACTIVE} OR status=#{Project::STATUS_ARCHIVED}" }
          validate :additional_ident_constraints
        end
      end


      # Find all repositories owned by project which are Repository::Git
      # Works for multi-repo/project ONLY!
      def gl_repos
        all_repos.select{|x| x.is_a?(Repository::Git)}
      end


      # Find all repositories owned by project.
      # Works for multi-repo/project ONLY!
      def all_repos
        repositories
      end


      # Return first repo with a blank identifier (should be only one!)
      def repo_blank_ident
        Repository.find_by_project_id(id,:conditions => ["identifier = '' or identifier is null"])
      end


      # Make sure that identifier does not match existing repository identifier
      def additional_ident_constraints
        if new_record? && !identifier.blank? && Repository.find_by_identifier_and_type(identifier, "Git")
          errors.add(:identifier, :ident_not_unique)
        end
      end

    end
  end
end

unless Project.included_modules.include?(RedmineGitolite::Patches::ProjectPatch)
  Project.send(:include, RedmineGitolite::Patches::ProjectPatch)
end
