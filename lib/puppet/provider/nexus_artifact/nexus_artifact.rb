Puppet::Type.type(:nexus_artifact).provide(:nexus_artifact) do
  desc 'Provider for Nexus artifacts'

  # Get the state of the resource on disk
  #
  # @return [:absent, :present, String] the state of the resource on disk
  #   * :absent          => the file is not present
  #   * :present         => the file is present and that is what the resource cares about
  #   * String           => the actual version of the file from the file metadata
  #   * :unknown_version => unable to determine the version from the file metadata
  def ensure
    return :absent unless File.exist?(resource[:path])
    return :present if (resource[:ensure] == :present && File.exist?(resource[:path]))

    attrs = get_file_attrs(resource[:path])

    if attrs && attrs["#{attr_prefix}.pup.simp.nexus.ver"]
      return attrs["#{attr_prefix}.pup.simp.nexus.ver"]
    else
      return :unknown_version
    end
  end

  # Determine if the file is in sync with the expected state
  #
  # @param is [Symbol, String] the current state of the resource as returned from #ensure
  # @param should [Symbol, String] the expected state of the resource
  #
  # @return [Boolean] whether or not the resource is in sync with the expected state
  def insync?(is, should)
    is_insync = false
    do_full_checksum = false

    # Check if the resource is present
    if resource[:ensure] == :present
      is_insync = File.exist?(resource[:path])
    # Check if the resource is absent
    elsif resource[:ensure] == :absent
      is_insync = !File.exist?(resource[:path])
    else
      file_attrs = get_file_attrs(resource[:path])

      # If the resource has file attributes...
      if file_attrs && !file_attrs.empty?
        # If the file has been modified, assume that it is out of sync
        Puppet.debug("#{self.to_s}: Checking mtime of '#{resource[:path]}'")

        # And the modification time has not changed...
        if file_attrs["#{attr_prefix}.pup.simp.mtime"].to_i == File.mtime(resource[:path]).to_i

          current_version = file_attrs["#{attr_prefix}.pup.simp.nexus.ver"]
          if current_version
            Puppet.debug("#{self.to_s}: Found metadata version '#{current_version}' for '#{resource[:path]}'")

            # Avoid network calls if we already have a matching version
            unless resource[:ensure] == :latest
              is_insync = resource[:ensure] == current_version
            end

            # If we do not have a matching version, then fetch the resource
            # metadata from Nexus and perform the comparison
            unless is_insync
              artifact = get_artifact(resource)

              Puppet.debug("#{self.to_s}: Checking upstream version '#{artifact['version']}' against '#{current_version}' for '#{resource[:path]}'")

              if artifact
                is_insync = artifact['version'] == file_attrs['user.pup.simp.nexus.ver']
              end
            end
          else
            # If we could not find the current version in the metadata, we need
            # to rely on checksums
            checksums = file_attrs.keys.grep(/\.cksum\..+/)

            # If there is no checksum metadata, request a full checksum
            if checksums.empty?
              Puppet.debug("#{self.to_s}: No metadata checksums found for '#{resource[:path]}'")

              do_full_checksum = true
            else
              # If there is checksum metadata, loop through all metadata and
              # compare the metadata
              artifact = get_artifact(resource)

              checksums.each do |cksum|
                cksum_type = cksum.split('.').last

                if artifact['checksum'] && artifact['checksum'][cksum_type]

                  artifact_checksum = artifact['checksum'][cksum_type]

                  Puppet.debug("#{self.to_s}: Checking upstream '#{cksum_type}' with value '#{cksum}' against metadata '#{file_attrs[cksum]}' for '#{resource[:path]}'")

                  is_insync = true if (artifact_checksum && (artifact_checksum == file_attrs[cksum]))

                  break
                end
              end
            end
          end
        end
      else
        # If we have no file metadata, we have to compare based on a full
        # checksum
        Puppet.debug("#{self.to_s}: No local file metadata found for '#{resource[:path]}'")

        do_full_checksum = true
      end

      # Perform a full file checksum if requested
      if do_full_checksum
        Puppet.debug("#{self.to_s}: Performing a full checksum on '#{resource[:path]}'")

        artifact = get_artifact(resource)

        artifact['checksum'].sort.each do |cksum_type, artifact_cksum|
          if checksum_file(resource[:path], cksum_type, artifact_cksum)
            is_insync = true
            break
          end
        end
      end
    end

    return is_insync
  end

  # Bring the system into a compliant state
  #
  # @param should [Symbol, String] the state that the system should be in
  #
  # @return [void]
  def ensure=(should)
    # We always download the latest one by default
    if should == :absent
      FileUtils.rm_f(resource[:path])
    else
      artifact = get_artifact(resource)

      if artifact
        download_asset(resource[:path], artifact, resource[:verify_download])
        set_file_attrs(resource[:path], artifact)
      else
        raise Puppet::Error, "Could not find '#{resource[:repository]}/#{resource[:artifact]}' version '#{resource[:ensure]}' on '#{resource[:server]}'"
      end
    end
  end

  private

  # Remove a file from the system
  #
  # @param path [String] the full path to the file to remove
  #
  # @raise [Puppet::Error] if you attempt to remove a directory
  #
  # @return [void]
  def destroy(path)
    if File.file?(path)
      Puppet::FileSystem.unlink(path)
    else
      raise Puppet::Error, "Refusing to remove directory at #{path}"
    end
  end

  # Set up a valid HTTP(S) connection and return it alongside the crafted
  # request
  #
  # Exceptions raised from the underlying net/http library will not be caught
  #
  # @param uri [String] the URI to which to connect
  # @param resource [Puppet::Type::Nexus_artifact] the puppet resource that is
  #   being processed
  #
  #   * Options set in the resource determine the behavior of the underlying
  #     connection state
  #
  # @raise [Puppet::Error] If an SSL certificate is not found but one was
  #   requested for use
  #
  # @return [Array[Net::HTTP::Get, Net::HTTP]] the request and connection
  #   objects respectively
  def setup_connection(uri, resource)
    request = Net::HTTP::Get.new(uri)

    if resource[:user] && resource[:password]
      request.basic_auth(resource[:user], resource[:password])
    end

    conn = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == 'https'
      conn.use_ssl = true

      unless resource[:ssl_verify].nil?
        require 'openssl'

        if resource[:ssl_verify]
          conn.verify_mode = OpenSSL::SSL::VERIFY_PEER

          if resource[:ssl_verify].is_a?(String)
            conn.verify_depth = resource[:ssl_verify]
          end
        else
          conn.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end

      if resource[:ca_certificate]
        if File.exist?(resource[:ca_certificate])
          if File.directory?(resource[:ca_certificate])
            conn.ca_path = resource[:ca_certificate]
          else
            conn.ca_file = resource[:ca_certificate]
          end
        else
          raise Puppet::Error, "ca_certificate not found at '#{resource[:ca_certificate]}'"
        end
      end
    end

    if resource[:connection_timeout] && (resource[:connection_timeout] > 0)
      conn.read_timeout = resource[:connection_timeout]
    end

    if resource[:proxy]
      conn.proxy_uri = URI(resource[:proxy])

      if resource[:proxy_user] && resource[:proxy_pass]
        conn.proxy_user = resource[:proxy_user]
        conn.proxy_pass = resource[:proxy_pass]
      end
    end

    return [request, conn]
  end

  # Download an artifact from the Nexus server
  #
  # @param resource [Puppet::Type::Nexus_artifact] the puppet resource that is
  #   being processed
  #
  # @return [Hash, nil] the discovered artifact or `nil` if not found
  #   The behavior changes based on the expected resource state
  #
  #   * :latest => Return the latest resource from the remote system
  #   * String => Return the matching resource from the remote system
  def get_artifact(resource)
    artifacts = get_artifacts(resource)

    retval = nil

    if resource[:ensure].to_s == 'latest'
      return @latest_artifact if @latest_artifact

      retval = artifacts.sort do |a, b|
        # If we have two versions, compare them
        if a['version'] && b['version']
          Puppet::Util::Package.versioncmp( a['version'], b['version'] )
        # If only a has a version, it wins
        elsif a['version']
          1
        # If only b has a version, it wins
        elsif b['version']
          -1
        # If neither have a version, they tie
        else
          0
        end
      end.last
    else
      retval = artifacts.find{|a| a['version'] == resource[:ensure]}
    end

    if retval
      # We don't need all the cruft
      artifact_version = retval['version']
      retval = retval['assets'].first
      retval['version'] = artifact_version

      @latest_artifact = retval if (resource[:ensure].to_s == 'latest')
    end

    return retval
  end

  # Retrieve all artifacts on the Nexus server that match the resource query
  #
  # Fully handles pagination
  #
  # @see https://help.sonatype.com/repomanager3/rest-and-integration-api/pagination
  #
  # @param source [String] The source URI to be processed
  # @param resource [Puppet::Type::Nexus_artifact] the puppet resource that is
  #   being processed
  #
  # @return [Hash] The full list of resources retrieved from the server
  def get_artifact_items(source, resource)
    request, conn = setup_connection(URI(source), resource)

    conn.start do |http|
      response = http.request(request)

      raise Puppet::Error, response.message unless (response.code == '200')

      require 'json'

      response_body = JSON.load(response.body)

      sleep(resource[:sleep] || 0)

      if response_body['continuationToken']
        _source = source.split('&continuationToken').first

        return response_body['items'] + get_artifact_items("#{_source}&continuationToken=#{response_body['continuationToken']}", resource)
      else
        return response_body['items']
      end
    end
  end

  # Retrieve all artifacts on the Nexus server that match the resource parameters
  #
  # @param resource [Puppet::Type::Nexus_artifact] the puppet resource that is
  #   being processed
  #
  # @raise [Puppet::Error]
  #   * No matching remote artifacts could be discovered
  #   * An arbitrary error occured when fetching artifacts
  #
  # @return [Hash] The full list of resources retrieved from the server
  def get_artifacts(resource)
    return @remote_artifacts if @remote_artifacts

    require 'net/http'

    source = resource[:protocol].to_s + '://' +
      resource[:server] +
      '/service/rest/v1/search?' +
      'repository=' + resource[:repository] +
      '&name=' + resource[:artifact]

    begin
      artifact_items = get_artifact_items(source, resource)

      raise Puppet::Error, "No remote artifacts found at #{source}" if artifact_items.empty?

      @remote_artifacts = artifact_items
      return @remote_artifacts
    rescue => e
      # This catches all of the random possible things that can go wrong with
      # HTTP connections.
      raise Puppet::Error, "Could not fetch artifacts from '#{resource[:repository]}/#{resource[:artifact]}' => '#{e}'"
    end
  end

  # Download a specific asset from Nexus
  #
  # @param path [String] the target path for the downloaded file
  # @param artifact [Hash] the artifact to be downloaded as returned by #get_artifacts
  # @param verify [Boolean] perform a post-download checksum on the asset
  #
  # @raise [Puppet::Error]
  #   * If the target directory does not exist (parent directories are not created)
  #   * If there was an error when downloading the asset from the server
  #   * If the downloaded asset does not match the server checksum value or a
  #     matching checksum could not be performed
  #
  # @return [void]
  def download_asset(path, artifact, verify=false)
    target_dir = File.dirname(path)
    target_filename = File.basename(path)
    temp_file = File.join(target_dir, '.' + target_filename)

    unless File.directory?(target_dir)
      raise Puppet::Error, "Target directory '#{target_dir}' does not exist"
    end

    begin
      request, conn = setup_connection(URI(artifact['downloadUrl']), resource)

      conn.request(request) do |response|
        File.open(temp_file, 'wb') do |fh|
          response.read_body do |chunk|
            fh.write chunk
          end
        end
      end

      if verify
        Puppet.debug("#{self.to_s}: Performing download validation on '#{temp_file}'")

        validation_failed = true

        artifact['checksum'].sort.each do |cksum_type, artifact_cksum|
          file_checksum = checksum_file(temp_file, cksum_type)

          if file_checksum
            raise Puppet::Error, "Checksum did not match '#{artifact_cksum}'" if (file_checksum != artifact_cksum)

            validation_failed = false
          end
        end

        raise Puppet::Error, 'No checksums could be computed' if  validation_failed
      end

      FileUtils.mv(temp_file, path)
    rescue => e
      raise(Puppet::Error, "Error when downloading '#{artifact['downloadUrl']}' => '#{e}'")
    ensure
      FileUtils.rm(temp_file) if File.exist?(temp_file)
    end
  end

  # Return the appropriate `attr` prefix for the current user
  #
  # @see attr(1)
  #
  # @return [String] `trusted` if running as `root` and `user` otherwise
  def attr_prefix
    Puppet.features.root? ? 'trusted' : 'user'
  end

  # Return the path to the `getfattr` command
  #
  # @return [String, nil] the path to the `getfattr` command or `nil` otherwise
  def getfattr
    @getfattr ||= Puppet::Util.which('getfattr')

    return @getfattr
  end

  # Return a specific file attribute from a file that matches `key`
  #
  # @see getfattr(1)
  #
  # @param path [String] the path to the file
  # @param key [String] the key that should be retrieved
  #
  #   * This is passed directly to the `getfattr` command so can be whatever the
  #     `-m` option can process
  #   * Pass `-` to return all known items
  #
  # @return [String,nil] the matching file attribute
  def get_file_attribute(path, key)
    command = [getfattr, '-d', '-m', key, path]
    output = Puppet::Util::Execution.execute(command, failonfail: false, combine: true)

    unless output.exitstatus == 0
      Puppet.debug("#{self.to_s}: Could not get attributes on #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
    end

    return output
  end

  # Return all extended file attributes
  #
  # @param path [String] the path to the file
  #
  # @return [Hash, nil] all extended file attributes or `nil` if none could be found
  def get_file_attrs(path)
    attrs = nil

    return attrs unless File.exist?(path)

    Puppet.debug("#{self.to_s}: Getting extended attributes from '#{path}'")

    if Facter.value(:kernel).downcase == 'windows'
      # TODO
    else
      if getfattr
        output = get_file_attribute(path, "#{attr_prefix}.")

        if output.exitstatus == 0
          attrs = Hash[
            output.lines.grep(/=/).map do |line|
              k,v = line.strip.split('=')
              v.gsub!(/(\A"|"\Z)/, '')
              [k,v]
            end
          ]
        end
      else
        Puppet.debug("#{self.to_s}: getfattr not found, cannot get extended attributes")
      end
    end

    return attrs
  end

  # Return the path to the `setfattr` command
  #
  # @return [String, nil] the path to the `setfattr` command or `nil` otherwise
  def setfattr
    @setfattr ||= Puppet::Util.which('setfattr')

    return @setfattr
  end

  # Set all file metadata
  #
  # This will always set the `pup.simp.mtime` metadata but may also set
  # `pup.simp.nexus.ver` and `cksum.<checksum_family>` items as appropriate
  #
  # @param path [String] the path to the file
  # @param asset_info [Hash] information about the asset as retrieved from #get_artifact
  #
  # @see setfattr(1)
  #
  # @return [String,nil] the matching file attribute
  def set_file_attrs(path, asset_info={})
    if File.exist?(path)
      attrs = [
        %{#{attr_prefix}.pup.simp.mtime="#{File.mtime(path).to_i}"}
      ]

      if asset_info['checksum']
        asset_info['checksum'].each do |family, value|
          attrs << %{#{attr_prefix}.cksum.#{family}="#{value}"}
        end
      end

      if asset_info['version']
        attrs << %{#{attr_prefix}.pup.simp.nexus.ver="#{asset_info['version']}"}
      end

      Puppet.debug("#{self.to_s}: Setting extended attributes on '#{path}'")

      if Facter.value(:kernel).downcase == 'windows'
        # TODO
      else
        if setfattr
          Dir.mktmpdir do |tmpdir|
            # The 'getfattr --dump' format allows for a single command call
            File.write('temp.attrs', ([ "# file: #{path}" ] + attrs).join("\n"))

            command = [setfattr, '--restore', 'temp.attrs']
            output = Puppet::Util::Execution.execute(command, failonfail: false, combine: true)

            unless output.exitstatus == 0
              Puppet.debug("#{self.to_s}: Could not set attributes on #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
            end
          end
        else
          Puppet.debug("#{self.to_s}: setfattr not found, cannot set extended attributes")
        end
      end
    end
  end

  # Perform a file checksum
  #
  # @param path [String] the file to checksum
  # @param cksum_type [String] the checksum type to use
  #
  #   @see {Puppet::Util::Checksums}
  #
  # @param to_match [String] a checksum to match
  #
  # @return [String, Boolean, nil]
  #   * String (default) => The checksum of the file
  #   * Boolean => if `to_match` is passed
  #   * nil => If no checksum could be performed using cksum_type
  def checksum_file(path, cksum_type, to_match=nil)
    file_checksum = nil

    if Puppet::Util::Checksums.respond_to?("#{cksum_type}_file")
      begin
        Puppet.debug("#{self.to_s}: Processing #{path} with checksum #{cksum_type}")

        file_checksum = Puppet::Util::Checksums.public_send("#{cksum_type}_file", path)
      rescue => e
        # Catch any errors in performing the checksum since the
        # underlying platform may not support all types
        #
        # If all checks fail, the resource will be marked as out of sync
        # and re-downloaded
        Puppet.debug("#{self.to_s}: Could not use checksum #{cksum_type} => #{e}")
      end
    end

    if to_match
      return file_checksum == to_match
    else
      return file_checksum
    end
  end
end
