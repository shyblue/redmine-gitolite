redmine-gitolite
================

CURRENT HEAD VERSION WORKS WITH TRUNK REDMINE (certified with 2.2.3)

THIS PLUGIN IS COMPATIBLE WITH REDMINE 2.X ONLY !

It combines `redmine-gitolite`__ with `redmine_git_hosting`__

A Redmine plugin which manages your Gitolite configuration based on your projects and user memberships in Redmine.

__ https://github.com/ivyl/redmine-gitolite
__ https://github.com/ericpaulbishop/redmine_git_hosting


Gems
----
* net-ssh
* lockfile
* `gitolite`__ (works with 1.1.0)

__ https://github.com/wingrunr21/gitolite

Other
-----
* Gitolite server (works with v2.3.1 and v3.3)
* accessible Git executable (works with 1.7.2.5)
* curl

Setup
-----

1. Install Redmine and put this plugin in redmine/plugins directory and migrate database (plugins)

.. code:: ruby

    $ cd redmine/plugins
    $ git clone git://github.com/pitit-atchoum/redmine-gitolite.git redmine_gitolite
    $ cd ..
    $ RAILS_ENV=production rake db:migrate_plugins


2. Create SSH Keys for user running Redmine

.. code:: ruby

    $ sudo su - redmine
    $ ssh-keygen -N '' -f ~/.ssh/redmine_gitolite_admin_id_rsa

3. User running Redmine must have RW+ access to gitolite-admin (assuming that you have Gitolite installed).

Otherwise you can install Gitolite by following this :

.. code:: ruby

    Server requirements:

      * any unix system
      * sh
      * git 1.6.6+
      * perl 5.8.8+
      * openssh 5.0+
      * a dedicated userid to host the repos (in this document, we assume it
        is 'git'), with shell access ONLY by 'su - git' from some other userid
        on the same server.

    Steps to install:

      * login as 'git' as described above

      * make sure ~/.ssh/authorized_keys is empty or non-existent

      * make sure Redmine SSH public key is available at $HOME/redmine_gitolite_admin_id_rsa.pub

      * add this in ~/.profile

            # set PATH so it includes user private bin if it exists
            if [ -d "$HOME/bin" ] ; then
                PATH="$PATH:$HOME/bin"
            fi

      * run the following commands:
            
            source ~/.profile
            git clone git://github.com/sitaramc/gitolite
            mkdir -p $HOME/bin
            gitolite/install -to $HOME/bin
            gitolite setup -pk redmine_gitolite_admin_id_rsa.pub


4. Make sure that Redmine user has Gitolite server in his known_hosts list (This is also a good check to see if Gitolite works)

.. code:: ruby

  $ sudo su - redmine
  $ ssh git@localhost
  * [accept key]

You should get something like that :

.. code:: ruby

    hello redmine_redmine, this is gitolite v2.3.1-0-g912a8bd-dt running on git 1.7.2.5
    the gitolite config gives you the following access:
        R   W  gitolite-admin
        @R_ @W_ testing

Or

.. code:: ruby

    hello redmine_gitolite_admin_id_rsa, this is git@dev running gitolite3 v3.3-11-ga1aba93 on git 1.7.2.5
        R W  gitolite-admin
        R W  testing

5. Configure email and name of Gitolite user for your Redmine account

.. code:: ruby

    $ sudo su - redmine
    $ git config --global user.email "redmine@gitolite.org"
    $ git config --global user.name "Redmine Gitolite"

6. Add post-receive hook to common Gitolite hooks (script is in contrib dir) and configure it (Redmine Host and API key)

.. code:: ruby

    $ sudo su - gitolite #login on gitolite user
    $ cat > .gitolite/hooks/common/post-receive
    * [paste hook]
    $ vim .gitolite/hooks/common/post-receive
    * [enable WS for repository management in administration->settings->repositories]
    * [copy generated API key] (DEFAULT_REDMINE_KEY)
    * [set Redmine server URL] (DEFAULT_REDMINE_SERVER)
    $ chmod +x .gitolite/hooks/common/post-receive
    $ vim .gitolite.rc
    * [add ".*" to the GL_GIT_CONFIG_KEYS setting
    * [ set $REPO_UMASK = 0022; ]
    $ gl-setup

7. Configure plugin in Redmine settings

Found a bug?
------------

Open new issue and complain. You can also fix it and sent pull request.
This plugin is in active usage in current, edge Redmine. Any suggestions are welcome.
