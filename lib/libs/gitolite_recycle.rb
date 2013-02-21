module GitoliteRedmine

  # This class implements a basic recycle bit for repositories deleted from the gitolite repository
  #
  # Whenever repositories are deleted, we rename them and place them in the recycle_bin.
  # Assuming that GitoliteRecycle.delete_expired_files is called regularly, files in the recycle_bin
  # older than 'preserve_time' will be deleted.  Both the path for the recycle_bin and the preserve_time
  # are settable as settings.
  #
  # John Kubiatowicz, 11/21/11

  class GitoliteRecycle

    # Separator character(s) used to replace '/' in name
    TRASH_DIR_SEP = "__"


    def self.logger
      return Rails.logger
    end


    # This routine takes a name and turns it into a name for the recycle bit,
    # where we have a 1-level directory full of deleted repositories which
    # we keep for 'preserve_time'.
    def self.name_to_recycle_name repo_name
      new_trash_name = "#{repo_name}".gsub(/\//,"#{TRASH_DIR_SEP}")
    end


    # Scan through the recyclebin and delete files older than 'preserve_time' minutes
    def self.delete_expired_files
      return unless GitoliteHosting.file_exists?(GitoliteConfig.recycle_bin_base_path)

      result = %x[#{GitoliteHosting.git_user_runner} find '#{GitoliteConfig.recycle_bin_base_path}' -type d -regex '.*\.git' -cmin +#{GitoliteConfig.recycle_bin_expire_time} -prune -print].chomp.split("\n")
      if result.length > 0
        logger.warn "Garbage-collecting expired file#{(result.length != 1) ? "s" : ""} from recycle bin:"
        result.each do |filename|
          begin
            GitoliteHosting.shell %[#{GitoliteHosting.git_user_runner} rm -r #{filename}]
            logger.warn "  Deleting #{filename}"
          rescue
            logger.error "GitoliteRecycle.delete_expired_files() failed trying to delete repository #{filename}!"
          end
        end

        # Optionally remove recycle_bin (but only if empty).  Ignore error if non-empty
        %x[#{GitoliteHosting.git_user_runner} rmdir #{GitoliteConfig.recycle_bin_base_path}]
      end
    end


    def self.move_repository_to_recycle(repository)
      repo_name      = repository.identifier
      repo_path      = GitoliteHosting.repository_relative_path(repository)
      repo_hierarchy = GitoliteHosting.repository_name(repository)

      # Only bother if actually exists!
      if !GitoliteHosting.git_repository_exists?(repository)
        logger.warn "[Gitolite] Repository does not exist #{repo_path}"
        logger.warn ""
        return
      end

      new_path = File.join(GitoliteConfig.recycle_bin_base_path, "#{Time.now.to_i.to_s}#{TRASH_DIR_SEP}#{name_to_recycle_name(repo_name)}.git")

      begin
        GitoliteHosting.shell %[#{GitoliteHosting.git_user_runner} mkdir -p '#{GitoliteConfig.recycle_bin_base_path}']
        GitoliteHosting.shell %[#{GitoliteHosting.git_user_runner} chmod 770 '#{GitoliteConfig.recycle_bin_base_path}']
        GitoliteHosting.shell %[#{GitoliteHosting.git_user_runner} mv '#{repo_path}' '#{new_path}']
        logger.warn "[Gitolite] Moving '#{repo_path}' from Gitolite repositories to '#{new_path}'"
        logger.warn "[Gitolite] Will remain for at least #{GitoliteConfig.recycle_bin_expire_time/60.0} hours"
        logger.warn ""

        # If any empty directories left behind, try to delete them.  Ignore failure.
        old_prefix = repo_hierarchy[/.*?(?=\/)/] # Top-level old directory without trailing '/'
        if old_prefix
          repo_subpath = File.join(GitoliteConfig.repository_relative_base_path, old_prefix)
          result = %x[#{GitoliteHosting.git_user_runner} find '#{repo_subpath}' -depth -type d ! -regex '.*\.git/.*' -empty -delete -print].chomp.split("\n")
          result.each { |dir| logger.warn "[Gitolite] Removing empty repository subdirectory : #{dir}"}
          logger.warn ""
        end
        return true
      rescue
        logger.error "[Gitolite] Attempt to move repository '#{repo_path}' to recycle bin failed"
        return false
      end

    end

  end
end
