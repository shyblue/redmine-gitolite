class GitoliteObserver < ActiveRecord::Observer
  unloadable

  observe :project, :user, :gitolite_public_key, :member, :role, :repository

  def after_save(object)
    update_repositories(object)
  end


  def after_destroy(object)
    gr = GitoliteRedmine::AdminHandler.new
    if object.is_a?(Repository::Git)
      gr.delete_repository(object)
    elsif object.is_a?(GitolitePublicKey)
      gr.delete_user_ssh_key(object)
    else
      update_repositories(object)
    end
  end


  def after_update(object)
    gr = GitoliteRedmine::AdminHandler.new
    if object.is_a?(GitolitePublicKey)
      if !object.active?
        gr.delete_user_ssh_key(object)
      end
    end
  end


  @@updating_active = true
  @@updating_active_stack = 0
  @@updating_active_flags = {}
  @@cached_project_updates = []
  def self.set_update_active(*is_active)
    if !is_active || !is_active.first
      @@updating_active_stack += 1
    else
      is_active.each do |item|
        case item
          when Symbol then @@updating_active_flags[item] = true
          when Hash then @@updating_active_flags.merge!(item)
          when Project then @@cached_project_updates |= [item]
        end
      end

      # If about to transition to zero and have something to run, do it
      if @@updating_active_stack == 1 && (@@cached_project_updates.length > 0 || !@@updating_active_flags.empty?)
        @@cached_project_updates = @@cached_project_updates.flatten.uniq.compact
        gr = GitoliteRedmine::AdminHandler.new
        gr.update_repositories(@@cached_project_updates, @@updating_active_flags)
        @@cached_project_updates = []
        @@updating_active_flags = {}
      end

      # Wait until after running update_repositories before releasing
      @@updating_active_stack -= 1
      if @@updating_active_stack < 0
        @@updating_active_stack = 0
      end
    end
    @@updating_active = (@@updating_active_stack == 0)
  end

  protected

  def update_repositories(object)
    gr = GitoliteRedmine::AdminHandler.new
    case object
      when Repository then gr.update_projects(object.project)
      when User then (gr.update_projects(object.projects) && gr.update_user(object)) unless is_login_save?(object)
      when GitolitePublicKey then gr.update_user(object.user)
      when Member then gr.update_projects(object.project)
      when Role then gr.update_projects(object.members.map(&:project).uniq.compact)
    end
  end

  private

  # Test for the fingerprint of changes to the user model when the User actually logs in.
  def is_login_save?(user)
    user.changed? && user.changed.length == 2 && user.changed.include?("updated_on") && user.changed.include?("last_login_on")
  end
end
