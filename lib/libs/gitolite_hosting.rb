require 'lockfile'
require 'net/ssh'
require 'tmpdir'
require 'tempfile'
require 'stringio'

module GitoliteHosting

  @@logger = nil
  def self.logger
    @@logger ||= MyLogger.new
  end


  ###############################
  ##                           ##
  ##     VARIOUS ACCESSORS     ##
  ##                           ##
  ###############################


  # Check to see if the given repository exists or not...
  # Need to work a bit, since we have to su to figure it out...
  def self.git_repository_exists?(repository)
    if repository.is_a?(String)
      file_exists?(repository)
    else
      file_exists?(repository_relative_path(repository))
    end
  end


  def self.git_user_runner
    if !File.exists?(git_user_runner_path())
      update_git_exec
    end
    return git_user_runner_path()
  end


  def self.git_user_runner_path
    return File.join(get_bin_dir, "run_as_git_user")
  end


  def self.git_exec_path
    return File.join(get_bin_dir, "run_git_as_git_user")
  end


  def self.gitolite_ssh_path
    return File.join(get_bin_dir, "gitolite_admin_ssh")
  end


  def self.gitolite_ssh_config_path
    return File.join(ENV['HOME'], "/.ssh/config")
  end


  def self.gitolite_ssh_exec
    if !File.exists?(gitolite_ssh_path())
      update_git_exec
    end
    return gitolite_ssh_path()
  end


  def self.repository_relative_path(repository)
    return File.join(GitoliteConfig.repository_relative_base_path, repository_name(repository)) + ".git"
  end


  def self.repository_absolute_path(repository)
    return File.join(GitoliteConfig.repository_absolute_base_path, repository_name(repository)) + ".git"
  end


  def self.repository_name(repository)
    return File.expand_path(File.join("./", get_full_parent_path(repository), repository.git_label), "/")[1..-1]
  end


  def self.get_full_parent_path(repository)
    project = repository.project

    return "" if !project.parent
    parent_parts = [];

    p = project
    while p.parent
      parent_id = p.parent.identifier.to_s
      parent_parts.unshift(parent_id)
      p = p.parent
    end

    return parent_parts.join("/")
  end


  ###############################
  ##                           ##
  ##      LOCK FUNCTIONS       ##
  ##                           ##
  ###############################


  @@lock_file = nil
  def self.lock
    is_locked = false
    retries   = GitoliteConfig.lock_wait_time

    lock_file_path = File.join(Rails.root,"tmp",'redmine_gitolite_lock')

    if @@lock_file.nil?
      @@lock_file = File.new(lock_file_path, File::CREAT|File::RDONLY)
    end

    while retries > 0
      is_locked = @@lock_file.flock(File::LOCK_EX|File::LOCK_NB)
      retries-=1
      if (!is_locked) && retries > 0
        sleep 1
      end
    end

    return is_locked
  end


  def self.unlock
    if !@@lock_file.nil?
      @@lock_file.flock(File::LOCK_UN)
    end
  end


  ###############################
  ##                           ##
  ##      SHELL FUNCTIONS      ##
  ##                           ##
  ###############################


  ## Check to see if the given file exists off the git user's homedirectory.
  ## Need to work a bit, since we have to su to figure it out...
  def self.file_exists?(filename)
    (%x[#{GitoliteHosting.git_user_runner} test -r '#{filename}' && echo 'yes' || echo 'no']).match(/yes/) ? true : false
  end


  ## GET CURRENT USER
  @@web_user = nil
  def self.web_user
    if @@web_user.nil?
      @@web_user = (%x[whoami]).chomp.strip
    end
    return @@web_user
  end


  def self.web_user=(setuser)
    @@web_user = setuser
  end


  ## GET OR CREATE BIN DIR
  @@git_hosting_bin_dir = nil
  @@previous_git_script_dir = nil
  def self.get_bin_dir
    script_dir = GitoliteConfig::GITOLITE_SCRIPT_DIR

    if @@previous_git_script_dir != script_dir
      @@previous_git_script_dir = script_dir
      @@git_bin_dir_writeable = nil

      @@git_hosting_bin_dir = File.join(script_dir, GitoliteConfig.gitolite_user, GitoliteConfig::GITOLITE_SCRIPT_PARENT) + "/"
    end

    if !File.directory?(@@git_hosting_bin_dir)
      logger.info "[Gitolite] Creating bin directory: #{@@git_hosting_bin_dir}, Owner #{web_user}"
      %x[mkdir -p "#{@@git_hosting_bin_dir}"]
      %x[chmod 750 "#{@@git_hosting_bin_dir}"]
      %x[chown #{web_user} "#{@@git_hosting_bin_dir}"]

      if !File.directory?(@@git_hosting_bin_dir)
        logger.error "[Gitolite] Cannot create bin directory: #{@@git_hosting_bin_dir}"
      end
    end

    return @@git_hosting_bin_dir
  end


  ## TEST DIRECTORY
  @@git_bin_dir_writeable = nil
  def self.bin_dir_writeable?(*option)
    mybindir = get_bin_dir

    mytestfile = "#{mybindir}/writecheck"
    if (!File.directory?(mybindir))
      @@git_bin_dir_writeable = false
    else
      %x[touch "#{mytestfile}"]
      if (!File.exists?("#{mytestfile}"))
        @@git_bin_dir_writeable = false
      else
        %x[rm "#{mytestfile}"]
        @@git_bin_dir_writeable = true
      end
    end

    @@git_bin_dir_writeable
  end


  ## DO SHELL COMMAND
  def self.shell(command)
    begin
      my_command = "#{command} 2>&1"
      result = %x[#{my_command}].chomp
      code = $?.exitstatus
    rescue Exception => e
      result=e.message
      code = -1
    end
    if code != 0
      logger.error "[Gitolite] Command failed (return #{code}): #{command}"
      message = "  "+result.split("\n").join("\n  ")
      logger.error message
      raise GitoliteHostingException, "Shell Error"
    end
  end


  ## SUDO TEST1
  @@sudo_web_to_git_user_stamp = nil
  @@sudo_web_to_git_user_cached = nil
  def self.sudo_web_to_git_user
    if not @@sudo_web_to_git_user_cached.nil? and (Time.new - @@sudo_web_to_git_user_stamp <= 0.5)
      return @@sudo_web_to_git_user_cached
    end

    gitolite_user = GitoliteConfig.gitolite_user

    logger.info "[Gitolite] Testing if web user(\"#{web_user}\") can sudo to git user(\"#{gitolite_user}\")"
    if gitolite_user == web_user
      @@sudo_web_to_git_user_cached = true
      @@sudo_web_to_git_user_stamp = Time.new
      return @@sudo_web_to_git_user_cached
    end

    test = %x[#{GitoliteHosting.git_user_runner} echo "yes"]
    if test.match(/yes/)
      @@sudo_web_to_git_user_cached = true
      @@sudo_web_to_git_user_stamp = Time.new
      return @@sudo_web_to_git_user_cached
    end

    logger.warn "[Gitolite] Error while testing sudo_web_to_git_user: #{test}"
    @@sudo_web_to_git_user_cached = test
    @@sudo_web_to_git_user_stamp = Time.new
    return @@sudo_web_to_git_user_cached
  end


  ## SUDO TEST2
  @@sudo_git_to_web_user_stamp = nil
  @@sudo_git_to_web_user_cached = nil
  def self.sudo_git_to_web_user
    if not @@sudo_git_to_web_user_cached.nil? and (Time.new - @@sudo_git_to_web_user_stamp <= 0.5)
      return @@sudo_git_to_web_user_cached
    end

    gitolite_user = GitoliteConfig.gitolite_user

    logger.info "[Gitolite] Testing if git user(\"#{gitolite_user}\") can sudo to web user(\"#{web_user}\")"
    if gitolite_user == web_user
      @@sudo_git_to_web_user_cached = true
      @@sudo_git_to_web_user_stamp = Time.new
      return @@sudo_git_to_web_user_cached
    end

    test = %x[#{GitoliteHosting.git_user_runner} sudo -nu #{web_user} echo "yes" ]
    if test.match(/yes/)
      @@sudo_git_to_web_user_cached = true
      @@sudo_git_to_web_user_stamp = Time.new
      return @@sudo_git_to_web_user_cached
    end

    logger.warn "[Gitolite] Error while testing sudo_git_to_web_user: #{test}"
    @@sudo_git_to_web_user_cached = test
    @@sudo_git_to_web_user_stamp = Time.new
    return @@sudo_git_to_web_user_cached
  end


  ## CREATE EXECUTABLE FILES
  def self.update_git_exec
    logger.info "[Gitolite] Setting up #{get_bin_dir}"
    gitolite_key    = GitoliteConfig.gitolite_ssh_private_key
    gitolite_user   = GitoliteConfig.gitolite_user
    gitolite_server = GitoliteConfig.gitolite_server

    File.open(gitolite_ssh_path(), "w") do |f|
      f.puts "#!/bin/sh"
      f.puts "exec ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i #{gitolite_key} \"$@\""
    end if !File.exists?(gitolite_ssh_path())

    File.open(gitolite_ssh_config_path(), "w") do |f|
      f.puts "## FILE MANAGED BY REDMINE GITOLITE PLUGIN"
      f.puts "## DO NOT MODIFY BY HAND, IT WILL BE OVERWRITTEN!"
      f.puts "Host #{gitolite_server}"
      f.puts "  HostName #{gitolite_server}"
      f.puts "  User #{gitolite_user}"
      f.puts "  IdentityFile #{gitolite_key}"
      f.puts "  IdentitiesOnly yes"
    end

    ##############################################################################################################################
    # So... older versions of sudo are completely different than newer versions of sudo
    # Try running sudo -i [user] 'ls -l' on sudo > 1.7.4 and you get an error that command 'ls -l' doesn't exist
    # do it on version < 1.7.3 and it runs just fine.  Different levels of escaping are necessary depending on which
    # version of sudo you are using... which just completely CRAZY, but I don't know how to avoid it
    #
    # Note: I don't know whether the switch is at 1.7.3 or 1.7.4, the switch is between ubuntu 10.10 which uses 1.7.2
    # and ubuntu 11.04 which uses 1.7.4.  I have tested that the latest 1.8.1p2 seems to have identical behavior to 1.7.4
    ##############################################################################################################################
    sudo_version_str=%x[ sudo -V 2>&1 | head -n1 | sed 's/^.* //g' | sed 's/[a-z].*$//g' ]
    split_version = sudo_version_str.split(/\./)
    sudo_version = 100*100*(split_version[0].to_i) + 100*(split_version[1].to_i) + split_version[2].to_i
    sudo_version_switch = (100*100*1) + (100 * 7) + 3

    File.open(git_exec_path(), "w") do |f|
      f.puts '#!/bin/sh'
      f.puts "if [ \"\$(whoami)\" = \"#{gitolite_user}\" ] ; then"
      f.puts '  cmd=$(printf "\\"%s\\" " "$@")'
      f.puts '  cd ~'
      f.puts '  eval "git $cmd"'
      f.puts "else"
      if sudo_version < sudo_version_switch
        f.puts '  cmd=$(printf "\\\\\\"%s\\\\\\" " "$@")'
        f.puts "  sudo -u #{gitolite_user} -i eval \"git $cmd\""
      else
        f.puts '  cmd=$(printf "\\"%s\\" " "$@")'
        f.puts "  sudo -u #{gitolite_user} -i eval \"git $cmd\""
      end
      f.puts 'fi'
    end if !File.exists?(git_exec_path())

    # use perl script for git_user_runner so we can
    # escape output more easily
    File.open(git_user_runner_path(), "w") do |f|
      f.puts '#!/usr/bin/perl'
      f.puts ''
      f.puts 'my $command = join(" ", @ARGV);'
      f.puts ''
      f.puts 'my $user = `whoami`;'
      f.puts 'chomp $user;'
      f.puts 'if ($user eq "' + gitolite_user + '")'
      f.puts '{'
      f.puts '  exec("cd ~ ; $command");'
      f.puts '}'
      f.puts 'else'
      f.puts '{'
      f.puts '  $command =~ s/\\\\/\\\\\\\\/g;'
      # Previous line turns \; => \\;
      # If old sudo, turn \\; => "\\;" to protect ';' from loss as command separator during eval
      if sudo_version < sudo_version_switch
        f.puts '  $command =~ s/(\\\\\\\\;)/"$1"/g;'
      end
      f.puts '  $command =~ s/"/\\\\"/g;'
      f.puts '  exec("sudo -u ' + gitolite_user + ' -i eval \"$command\"");'
      f.puts '}'
    end if !File.exists?(git_user_runner_path())

    File.chmod(0550, git_exec_path())
    File.chmod(0550, gitolite_ssh_path())
    File.chmod(0550, git_user_runner_path())
    %x[chown #{web_user} -R "#{get_bin_dir}"]
  end


  # This routine moves a repository in the gitolite repository structure.
  def self.move_physical_repo(old_path, new_path)
    begin
      logger.warn "[Gitolite] Moving gitolite repository from '#{old_path}' to '#{new_path}'"

      if !git_repository_exists? old_path
        logger.error "[Gitolite] Repository directory '#{old_path}' does not exists !"
        return
      end

      GitoliteHosting.shell %[#{git_user_runner} 'mv "#{old_path}" "#{new_path}"']

    rescue GitoliteHostingException
      logger.error "[Gitolite] move_physical_repo(#{old_path}, #{new_path}) failed"
    rescue => e
      logger.error e.message
      logger.error e.backtrace[0..4].join("\n")
      logger.error "[Gitolite] move_physical_repo(#{old_path}, #{new_path}) failed"
    end

  end


  ###############################
  ##                           ##
  ##   ADDITIONAL CLASSES      ##
  ##                           ##
  ###############################


  # Used to register errors when pulling and pushing the conf file
  class GitoliteHostingException < StandardError
  end

  class MyLogger
    # Prefix to error messages
    ERROR_PREFIX = "***> "

    # For errors, add our prefix to all messages
    def error(*progname, &block)
      if block_given?
        Rails.logger.error(*progname) { "#{ERROR_PREFIX}#{yield}".gsub(/\n/,"\n#{ERROR_PREFIX}") }
      else
        Rails.logger.error "#{ERROR_PREFIX}#{progname}".gsub(/\n/,"\n#{ERROR_PREFIX}")
      end
    end

    # Handle everything else with base object
    def method_missing(m, *args, &block)
      Rails.logger.send m, *args, &block
    end
  end

end
