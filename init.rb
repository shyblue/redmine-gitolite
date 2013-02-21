require 'redmine'

require 'redmine_gitolite'

VERSION_NUMBER = '0.0.3'

Redmine::Plugin.register :redmine_gitolite do
  name 'Redmine Gitolite plugin'
  author 'Arkadiusz Hiler, Joshua Hogendorn, Jan Schulz-Hofen, Kah Seng Tay, Jakob Skjerning, Nicolas Rodriguez'
  description 'Enables Redmine to manage Gitolite repositories.'
  version VERSION_NUMBER
  url 'https://github.com/pitit-atchoum/redmine-gitolite/'
  author_url 'http://ivyl.0xcafe.eu/'

  requires_redmine :version_or_higher => '2.0.0'

  settings({
    :partial => 'settings/redmine_gitolite',
    :default => {
      # global settings
      'gitoliteIdentityPrivateKeyFile'     => (ENV['HOME'] + "/.ssh/redmine_gitolite_admin_id_rsa").to_s,
      'gitoliteIdentityPublicKeyFile'      => (ENV['HOME'] + "/.ssh/redmine_gitolite_admin_id_rsa.pub").to_s,
      'gitoliteRepositoryAbsoluteBasePath' => '/home/git/repositories/',
      'gitoliteUser'                       => 'git',
      'gitoliteServer'                     => 'localhost',
      'gitoliteServerDomain'               => 'example.com',
      'gitoliteLockWaitTime'               => '10',
      'gitoliteAllProjectsUseGit'          => true,

      # recycle bin settings
      'gitoliteRecycleBinDeleteRepositories' => true,
      'gitoliteRecycleBinBasePath'           => 'recycle_bin/',
      'gitoliteRecycleBinExpireTime'         => '24.0',
    }
  })
end

# initialize hook
class GitolitePublicKeyHook < Redmine::Hook::ViewListener
  render_on :view_my_account_contextual, :inline => "| <%= link_to(l(:label_public_keys), public_keys_path) %>"
end

class GitoliteProjectShowHook < Redmine::Hook::ViewListener
  render_on :view_projects_show_left, :partial => 'redmine_gitolite'
end

# initialize association from user -> public keys
User.send(:has_many, :gitolite_public_keys, :dependent => :destroy)

# initialize observer
ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitoliteObserver

Rails.configuration.after_initialize do
  ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitoliteHostingSettingsObserver
  GitoliteHostingSettingsObserver.instance.reload_this_observer
end
