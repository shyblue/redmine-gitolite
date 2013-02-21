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

5. Configure email and name of git user for your redmine account

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

.. code:: ruby

    * [Adminitration -> Plugins -> Redmine Gitolite]
    * [Gitolite URL should be set to your gitolite-admin git repository]
    * [Base path should point to the Gitolite directory which will hold local copies (must exist, example : /home/gitolite/repositories)
    * [Set developer and ro urls as in given examples (just slightly modify them)]
      [%{name} will be replaced with your repository identifier]

Found a bug?
------------

Open new issue and complain. You can also fix it and sent pull request.
This plugin is in active usage in current, edge Redmine. Any suggestions are welcome.
