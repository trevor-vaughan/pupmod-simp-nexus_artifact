Puppet::Type.newtype(:nexus_artifact) do
  @doc = <<~DOC
    Provides the capability to manage local artifacts as retrieved from a
    Sonatype Nexus server.

    **Autorequires:**

      * `File[<base directory of $name>]`
      * `Package['attr']`

    **Autonotifies:**

      * `File[$name]`
  DOC

  newparam(:path, :namevar => true) do
    desc 'The absolute path for the downloaded artifact'

    validate do |value|
      unless Puppet::Util.absolute_path?(value, :posix) || Puppet::Util.absolute_path?(value, :windows)
        raise ArgumentError, %{File paths must be fully qualified, not '#{value}'}
      end
    end
  end

  newparam(:server) do
    desc <<~DOC
      The Nexus server to which to connect
    DOC
  end

  newparam(:protocol) do
    desc <<~DOC
      The protocol that should be used to connect to `$server`
    DOC

    newvalues(:http, :https)

    defaultto(:https)
  end

  newparam(:user) do
    desc <<~DOC
      The user to use for authenticating to `$server`
    DOC
  end

  newparam(:password) do
    desc <<~DOC
      The password to use for authenticating to `$server`

      Has no effect if `$user` is not set
    DOC
  end

  newparam(:proxy) do
    desc <<~DOC
      The proxy server to use for connecting to the `$server`
    DOC
  end

  newparam(:proxy_user) do
    desc <<~DOC
      The user to use for authenticating to `$proxy`
    DOC
  end

  newparam(:proxy_password) do
    desc <<~DOC
      The password to use for authenticating to `$proxy`

      Has no effect if `$proxy_user` is not set
    DOC
  end

  newparam(:repository) do
    desc <<~DOC
      The repository to search for the artifact
    DOC
  end

  newparam(:artifact) do
    desc <<~DOC
      The full path to the artifact in `$repository`

      For instance, if you want to find find the artifact in `foo/app` then this
      should be `foo/app`
    DOC
  end

  newparam(:sleep) do
    desc <<~DOC
      The number of seconds to sleep between pagination updates

      Use this to prevent excessive load on the server for large projects

      Fractions of a second are supported
    DOC

    defaultto('0')

    newvalues(/\A\d(\.\d)?\Z/)

    munge do |value|
      value.to_f
    end
  end

  ensurable do
    desc <<~DOC
      The state that the resource should be in on the system. May be one of:

        * present          => Ensure that the resource exists at all
        * absent           => Ensure that the resource is not present on the system
        * latest           => Ensure that the resource is the latest available
        * <version string> => Attempt to match the specified version, raise an error if the version does not exist
    DOC

    newvalues(:present, :absent, :latest, /./)

    def insync?(is)
      provider.insync?(is, @should)
    end
  end

  validate do
    required_parameters = [:server, :repository, :artifact]
    missing_parameters = required_parameters.select{|x| !self[x] }

    unless missing_parameters.empty?
      raise Puppet::Error, "The following parameters must be specified: '#{required_parameters.join(', ')}'"
    end
  end

  autorequire(:file) do
    [File.dirname(self[:path])]
  end

  autorequire(:package) do
    ['attr']
  end

  autonotify(:file) do
    [File.basename(self[:path])]
  end
end
