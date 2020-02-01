Puppet::Type.type(:nexus_artifact).provide(:nexus_artifact) do
  desc 'Provider for Nexus artifacts'

  def ensure
    @remote_artifacts = get_artifacts(resource)
    @latest_artifact = find_latest_artifact(@remote_artifacts)

    return :absent unless File.exist?(resource[:path])

    if resource[:ensure] == :present
      return :present if File.exist?(resource[:path])
    end

    attrs = get_file_attrs(resource[:path])

    if attrs && attrs['version']
      return attrs['version']
    else
      return :undefined
    end
  end

  def insync?(is, should)
    retval = false

    if [:present, :absent].include?(resource[:ensure])
      retval = File.exist?(resource[:path])
    else
      if resource[:ensure] == :latest
        require 'pry'
        binding.pry
      else
        require 'pry'
        binding.pry

        puts 'foo'
      end
    end

    return retval
  end

  def ensure=(should)
    # We always download the latest one by default
    if [:present, :latest].include?(should)
      download_asset(resource[:path], @latest_artifact['downloadUrl'])
      set_file_attrs(resource[:path], @latest_artifact)

    # The removal case
    elsif should == :absent

    # The case where we want a specific version
    else
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

  def find_latest_artifact(artifacts)
    latest_artifact = artifacts.sort do |a, b|
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

    # We don't need all the cruft
    artifact_version = latest_artifact['version']
    latest_artifact = latest_artifact['assets'].first
    latest_artifact['version'] = artifact_version

    return latest_artifact
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
    require 'net/http'

    source = resource[:protocol].to_s + '://' +
      resource[:server] +
      '/service/rest/v1/search?' +
      'repository=' + resource[:repository] +
      '&name=' + resource[:artifact]

    begin
      artifact_items = get_artifact_items(source, resource)

      raise Puppet::Error, "No remote artifacts found at #{source}" if artifact_items.empty?

      return artifact_items
    rescue => e
      # This catches all of the random possible things that can go wrong with
      # HTTP connections.
      raise Puppet::Error, "Could not fetch artifacts from '#{resource[:repository]}/#{resource[:artifact]}' => '#{e}'"
    end
  end

  def download_asset(path, url)
    target_dir = File.dirname(path)
    target_filename = File.basename(path)
    temp_file = File.join(target_dir, '.' + target_filename)

    unless File.directory?(target_dir)
      raise Puppet::Erorr, "Target directory '#{target_dir}' does not exist"
    end

    begin
      request, conn = setup_connection(URI(url), resource)

      conn.request(request) do |response|
        File.open(temp_file, 'wb') do |fh|
          response.read_body do |chunk|
            fh.write chunk
          end
        end
      end

      FileUtils.mv(temp_file, path)
    rescue => e
      raise(Puppet::Error, "Error when downloading '#{url}' => '#{e}'")
    end
  end

  def attr_prefix
    Puppet.features.root? ? 'trusted' : 'user'
  end

  def get_file_attrs(path)
    attrs = nil

    return attrs unless File.exist?(path)

    if Facter.value(:kernel).downcase == 'windows'
      # TBD
    else
      getfattr = Puppet::Util.which('getfattr')

      if getfattr
        command = [getfattr, '-d', '-m', "'^#{attr_prefix}\.puppet\.simp'", path]
        output = Puppet::Util::Execution.execute(command, failonfail: false, combine: true)

        if output.exitstatus == 0
          attrs = Hash[
            output.lines.grep(/=/).map do |line|
              k,v = line.strip.split('=')
              v.gsub!(/(\A"|"\Z)/, '')
              [k,v]
            end
          ]
        else
          Puppet.debug("Could not get attributes from #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
        end
      else
        Puppet.debug('getfattr not found, cannot set extended attributes')
      end
    end

    attrs
  end

  def set_file_attrs(path, asset_info={})
    attrs = {}

    return attrs unless File.exist?(path)

    if Facter.value(:kernel).downcase == 'windows'
      # TBD
    else
      setfattr = Puppet::Util.which('setfattr')

      if setfattr
        if asset_info['checksum']
          asset_info['checksum'].each do |family, value|
            command = [setfattr, '-n', "#{attr_prefix}.checksum.#{family}", '-v', "#{value}", path]

            output = Puppet::Util::Execution.execute(command, failonfail: false, combine: true)

            unless output.exitstatus == 0
              Puppet.debug("Could not set attributes on #{path} '#{command.join(' ')}' failed: '#{output.to_s}'")
            end
          end
        end

        if asset_info['version']
          command = [setfattr, '-n', "#{attr_prefix}.puppet.simp.nexus.version", '-v', "#{asset_info['version']}", path]

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
