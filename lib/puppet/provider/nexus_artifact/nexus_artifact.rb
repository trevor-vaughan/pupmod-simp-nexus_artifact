Puppet::Type.type(:nexus_artifact).provide(:nexus_artifact) do
  desc 'Provider for Nexus artifacts'

  #Puppet::Util.which('setfattr')

  def exists?
    remote_artifacts = get_artifacts(resource[:source], resource[:sleep])

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

  def get_artifact_items(source, sleep_time=0)
    uri = URI(source)

    Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)

      response = http.request(request)

      unless response.code == '200'
        raise Puppet::Error, response.message
      end

      require 'json'

      response_body = JSON.load(response.body)

      sleep(sleep_time)

      if response_body['continuationToken']
        _source = source.split('&continuationToken').first

        return response_body['items'] + get_artifact_items("#{_source}&continuationToken=#{response_body['continuationToken']}", sleep_time)
      else
        return response_body['items']
      end
    end
  end

  def get_artifacts(source, sleep_time)
    require 'net/http'

    if source.include?('?')
      _source = source.dup
    else
      uri_regex = %r{\A
        (?<header>http(s)?://)
        (?<server>.+?)/
        (?<repo_name>.+?)/
        (?<artifact_name>.+)
        \Z
      }x

      matches = uri_regex.match(source)

      _source = matches[:header] +
        matches[:server] +
        '/service/rest/v1/search?' +
        'repository=' + matches[:repo_name] +
        '&name=' + matches[:artifact_name]
    end

    begin
      return get_artifact_items(_source, sleep_time)
    rescue => e
      # This catches all of the random possible things that can go wrong with
      # HTTP connections.
      raise Puppet::Error, "Could not fetch results from '#{source}' => '#{e}'"
    end
  end
end
