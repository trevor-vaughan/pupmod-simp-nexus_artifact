Puppet::Type.type(:nexus_artifact).provide(:nexus_artifact) do
  desc 'Provider for Nexus artifacts'

  #Puppet::Util.which('setfattr')

  def exists?
    remote_artifacts = get_artifacts(resource)

    require 'pry'
    binding.pry
  end

  def create
    puts 'foo'

  end

  def destroy
    puts 'foo'

  end

  def insync?(is, should)
    require 'pry'
    binding.pry
  end

  private

  def get_artifact_items(source, resource)
    uri = URI(source)

    request = Net::HTTP::Get.new(uri)

    if resource[:user] && resource[:password]
      request.basic_auth(resource[:user], resource[:password])
    end

    conn = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == 'https'
      conn.use_ssl = true
    end

    if resource[:proxy]
      conn.proxy_uri = URI(resource[:proxy])

      if resource[:proxy_user] && resource[:proxy_pass]
        conn.proxy_user = resource[:proxy_user]
        conn.proxy_pass = resource[:proxy_pass]
      end
    end

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
      return get_artifact_items(source, resource)
    rescue => e
      # This catches all of the random possible things that can go wrong with
      # HTTP connections.
      raise Puppet::Error, "Could not fetch artifacts from '#{resource[:repository]}/#{resource[:artifact]}' => '#{e}'"
    end
  end
end
