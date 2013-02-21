class GitoliteHostingSettingsObserver < ActiveRecord::Observer
  unloadable

  observe :setting

  @@old_valuehash = ((Setting.plugin_redmine_gitolite).clone rescue {})

  def reload_this_observer
    observed_classes.each do |klass|
      klass.name.constantize.add_observer(self)
    end
  end

  # There is a long-running bug in ActiveRecord::Observer that prevents us from
  # returning from before_save() with false to signal verification failure.
  #
  # Thus, we can only silently refuse to perform bad changes and/or perform
  # slight corrections to badly formatted values.
  def before_save(object)

    # Only validate settings for our plugin
    if object.name == "plugin_redmine_gitolite"

      valuehash = object.value

      if !GitoliteHosting.bin_dir_writeable?
        # If bin directory not alterable, don't allow changes to
        # Script directory, Git Username, or Gitolite public or private keys
        valuehash['gitoliteUser']                   = @@old_valuehash['gitoliteUser']
        valuehash['gitoliteIdentityPrivateKeyFile'] = @@old_valuehash['gitoliteIdentityPrivateKeyFile']
        valuehash['gitoliteIdentityPublicKeyFile']  = @@old_valuehash['gitoliteIdentityPublicKeyFile']

      elsif valuehash['gitoliteUser'] != @@old_valuehash['gitoliteUser'] ||
        valuehash['gitoliteIdentityPrivateKeyFile'] != @@old_valuehash['gitoliteIdentityPrivateKeyFile'] ||
        valuehash['gitoliteIdentityPublicKeyFile'] != @@old_valuehash['gitoliteIdentityPublicKeyFile']
          # Remove old scripts, since about to change content (leave directory alone)
          %x[ rm -f '#{ GitoliteHosting.get_bin_dir }'* ]
      end


      # Server should not include any path components. Also, ports should be numeric.
      if valuehash['gitoliteServer']
        normalizedServer = valuehash['gitoliteServer'].lstrip.rstrip.split('/').first
        if (!normalizedServer.match(/^[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)*(:\d+)?$/))
          valuehash['gitoliteServer'] = @@old_valuehash['gitoliteServer']
        else
          valuehash['gitoliteServer'] = normalizedServer
        end
      end


      # Server domain should not include any path components. Also, ports should be numeric.
      if valuehash['gitoliteServerDomain']
        normalizedServer = valuehash['gitoliteServerDomain'].lstrip.rstrip.split('/').first
        if (!normalizedServer.match(/^[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)*(:\d+)?$/))
          valuehash['gitoliteServerDomain'] = @@old_valuehash['gitoliteServerDomain']
        else
          valuehash['gitoliteServerDomain'] = normalizedServer
        end
      end


      # Validate wait time > 0 (and exclude non-numbers)
      if valuehash['gitoliteLockWaitTime']
        if valuehash['gitoliteLockWaitTime'].to_i > 0
          valuehash['gitoliteLockWaitTime'] = "#{valuehash['gitoliteLockWaitTime'].to_i}"
        else
          valuehash['gitoliteLockWaitTime'] = @@old_valuehash['gitoliteLockWaitTime']
        end
      end


      # Normalize Recycle bin path, should be relative and end in '/'
      if valuehash['gitoliteRecycleBinBasePath']
        normalizedFile  = File.expand_path(valuehash['gitoliteRecycleBinBasePath'].lstrip.rstrip,"/")
        if (normalizedFile != "/")
          valuehash['gitoliteRecycleBinBasePath'] = normalizedFile[1..-1] + "/"  # Clobber leading '/' add trailing '/'
        else
          valuehash['gitoliteRecycleBinBasePath'] = @@old_valuehash['gitoliteRecycleBinBasePath']
        end
      end


      # Exclude bad expire times (and exclude non-numbers)
      if valuehash['gitoliteRecycleBinExpireTime']
        if valuehash['gitoliteRecycleBinExpireTime'].to_f > 0
          valuehash['gitoliteRecycleBinExpireTime'] = "#{(valuehash['gitoliteRecycleBinExpireTime'].to_f * 10).to_i / 10.0}"
        else
          valuehash['gitoliteRecycleBinExpireTime'] = @@old_valuehash['gitoliteRecycleBinExpireTime']
        end
      end

      # Save back results
      object.value = valuehash

    end

  end


  def after_save(object)

    # Only perform after-actions on settings for our plugin
    if object.name == "plugin_redmine_gitolite"

      valuehash = object.value

      # Settings cache doesn't seem to invalidate symbolic versions of Settings immediately,
      # so, any use of Setting.plugin_redmine_git_hosting[] by things called during this
      # callback will be outdated.... True for at least some versions of redmine plugin...
      #
      # John Kubiatowicz 12/21/2011
      if Setting.respond_to?(:check_cache)
        # Clear out all cached settings.
        Setting.check_cache
      end

      if @@old_valuehash['gitoliteUser'] != valuehash['gitoliteUser'] ||
        @@old_valuehash['gitoliteIdentityPrivateKeyFile'] != valuehash['gitoliteIdentityPrivateKeyFile'] ||
        @@old_valuehash['gitoliteIdentityPublicKeyFile'] != valuehash['gitoliteIdentityPublicKeyFile']
          # Need to update scripts
          GitoliteHosting.update_git_exec
      end

      @@old_valuehash = valuehash.clone
    end

  end

end
