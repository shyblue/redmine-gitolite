module GitoliteConfig


  ###############################
  ##                           ##
  ##        SSH SETTINGS       ##
  ##                           ##
  ###############################
  GITOLITE_USER                     = 'git'
  GITOLITE_SERVER                   = 'localhost'
  GITOLITE_SERVER_DOMAIN            = 'example.com'
  GITOLITE_ADMIN_REPO               = 'gitolite-admin.git'
  GITOLITE_LOCK_WAIT_TIME           = 10
  GITOLITE_SCRIPT_DIR               = (Rails.root + "tmp/redmine_gitolite_scripts").to_s
  GITOLITE_SCRIPT_PARENT            = 'bin'
  GITOLITE_SSH_PRIVATE_KEY          = (ENV['HOME'] + "/.ssh/redmine_gitolite_admin_id_rsa").to_s
  GITOLITE_REPOSITORY_ABSOLUTE_PATH = '/home/git/repositories/'
  GITOLITE_ALL_PROJECTS_USE_GIT     = true


  # Gitolite SSH Private Key
  def self.gitolite_ssh_private_key
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteIdentityPrivateKeyFile'].nil?
      Setting.plugin_redmine_gitolite['gitoliteIdentityPrivateKeyFile']
    else
      GITOLITE_SSH_PRIVATE_KEY
    end
  end


  # Gitolite user
  def self.gitolite_user
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteUser'].nil?
      Setting.plugin_redmine_gitolite['gitoliteUser']
    else
      GITOLITE_USER
    end
  end


  # Gitolite server
  def self.gitolite_server
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteServer'].nil?
      Setting.plugin_redmine_gitolite['gitoliteServer']
    else
      GITOLITE_SERVER
    end
  end


  # Gitolite server domain
  def self.gitolite_server_domain
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteServerDomain'].nil?
      Setting.plugin_redmine_gitolite['gitoliteServerDomain']
    else
      GITOLITE_SERVER_DOMAIN
    end
  end


  # Full Gitolite URL
  def self.gitolite_admin_url
    return "#{gitolite_user}@#{gitolite_server}:#{GITOLITE_ADMIN_REPO}"
  end


  # Time in seconds to wait before giving up on acquiring the lock
  def self.lock_wait_time
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteLockWaitTime'].nil?
      Setting.plugin_redmine_gitolite['gitoliteLockWaitTime'].to_i
    else
      GITOLITE_LOCK_WAIT_TIME
    end
  end


  # Repository absolute base path
  def self.repository_absolute_base_path
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteRepositoryAbsoluteBasePath'].nil?
      Setting.plugin_redmine_gitolite['gitoliteRepositoryAbsoluteBasePath']
    else
      GITOLITE_REPOSITORY_ABSOLUTE_PATH
    end
  end


  # Repository base path (relative to git user home directory)
  def self.repository_relative_base_path
    relative_path = File.basename(repository_absolute_base_path).to_s
    return "#{relative_path}/"
  end


  # All projects use Git?
  def self.all_projects_use_git?
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteAllProjectsUseGit'].nil?
      if Setting.plugin_redmine_gitolite['gitoliteAllProjectsUseGit'] == 'true'
        return true
      else
        return false
      end
    else
      GITOLITE_ALL_PROJECTS_USE_GIT
    end
  end


  ###############################
  ##                           ##
  ##   RECYCLE BIN SETTINGS    ##
  ##                           ##
  ###############################
  GITOLITE_RECYCLE_BIN_BASE_PATH   = "recycle_bin/"
  GITOLITE_RECYCLE_BIN_EXPIRE_TIME = 1440
  GITOLITE_RECYCLE_BIN_DELETE      = true


  # Recycle bin base path (relative to git user home directory)
  def self.recycle_bin_base_path
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteRecycleBinBasePath'].nil?
      Setting.plugin_redmine_gitolite['gitoliteRecycleBinBasePath']
    else
      GITOLITE_RECYCLE_BIN_BASE_PATH
    end
  end


  # Recycle bin expire time (in minutes)
  def self.recycle_bin_expire_time
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteRecycleBinExpireTime'].nil?
      (Setting.plugin_redmine_gitolite['gitoliteRecycleBinExpireTime'].to_f * 60).to_i
    else
      GITOLITE_RECYCLE_BIN_EXPIRE_TIME
    end
  end


  # Delete to recycle bin ?
  def self.recycle_bin_delete?
    if !Setting.plugin_redmine_gitolite.nil? and !Setting.plugin_redmine_gitolite['gitoliteRecycleBinDeleteRepositories'].nil?
      if Setting.plugin_redmine_gitolite['gitoliteRecycleBinDeleteRepositories'] == 'true'
        return true
      else
        return false
      end
    else
      GITOLITE_RECYCLE_BIN_DELETE
    end
  end

end
