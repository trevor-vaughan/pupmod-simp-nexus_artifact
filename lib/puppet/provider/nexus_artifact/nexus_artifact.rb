Puppet::Type.type(:nexus_artifact).provide(:nexus_artifact) do
  desc 'Provider for Nexus artifacts'

  def ensure
    return :absent unless File.exist?(resource[:path])

    if resource[:ensure] == :present
      return :present if File.exist?(resource[:path])
    end

    attrs = get_file_attrs(resource[:path])

    if attrs && attrs['user.pup.simp.nexus.ver']
      return attrs['user.pup.simp.nexus.ver']
    else
      return :unknown_version
    end
  end

  def insync?(is, should)
    retval = false
    do_full_checksum = false

    if resource[:ensure] == :present
      retval = File.exist?(resource[:path])
    elsif resource[:ensure] == :absent
      retval = !File.exist?(resource[:path])
    else
      if File.exist?(resource[:path])
        file_attrs = get_file_attrs(resource[:path])

        if file_attrs
          # If the file has been modified, assume that it is out of sync
          if file_attrs["#{attr_prefix}.pup.simp.mtime"].to_i == File.mtime(resource[:path]).to_i

            # No reason to hit the network if we can determine that we have the
            # correct version
            current_version = file_attrs["#{attr_prefix}.pup.simp.nexus.ver"]
            if current_version
              unless resource[:ensure] == :latest
                retval = resource[:ensure] == current_version
              end

              unless retval
                artifact = get_artifact(resource)

                if artifact
                  retval = artifact['version'] == file_attrs['user.pup.simp.nexus.ver']
                end
              end
            else
              # We don't have a local version so we need to fall back on checksum metadata
              # TODO
            end
          end
        else
          do_full_checksum = true
        end
      end
    end

    if do_full_checksum
      # TODO: Perform a full file checksum
    end

    return retval
  end

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

  def destroy(path)
    if File.file?(path)
      Puppet::FileSystem.unlink(path)
    else
      raise Puppet::Error, "Refusing to remove directory at #{path}"
    end
  end

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

  def download_asset(path, artifact, verify=false)
    target_dir = File.dirname(path)
    target_filename = File.basename(path)
    temp_file = File.join(target_dir, '.' + target_filename)

    unless File.directory?(target_dir)
      raise Puppet::Erorr, "Target directory '#{target_dir}' does not exist"
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
        #TODO: Cheksum stuff, raise error on failure and remove temp_file
      end

      FileUtils.mv(temp_file, path)
    rescue => e
      raise(Puppet::Error, "Error when downloading '#{url}' => '#{e}'")
    end
  end

  def attr_prefix
    Puppet.features.root? ? 'trusted' : 'user'
  end

  def getfattr
    @getfattr ||= Puppet::Util.which('getfattr')

    return @getfattr
  end

  def get_file_attribute(path, key)
    command = [getfattr, '-d', '-m', key, path]
    output = Puppet::Util::Execution.execute(command, failonfail: false, combine: true)

    unless output.exitstatus == 0
      Puppet.debug("Could not get attributes on #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
    end

    return output
  end

  def get_file_attrs(path)
    attrs = nil

    return attrs unless File.exist?(path)

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
        Puppet.debug('getfattr not found, cannot get extended attributes')
      end
    end

    return attrs
  end

  def setfattr
    @setfattr ||= Puppet::Util.which('setfattr')

    return @setfattr
  end

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
              Puppet.debug("Could not set attributes on #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
            end
          end
        else
          Puppet.debug('setfattr not found, cannot set extended attributes')
        end
      end
    end
  end
end
