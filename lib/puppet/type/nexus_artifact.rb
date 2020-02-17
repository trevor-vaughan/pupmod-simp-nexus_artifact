# frozen_string_literal: true

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

  # Mandatory Parameters

  newparam(:path, namevar: true) do
    desc 'The absolute path for the downloaded artifact'

    validate do |value|
      unless Puppet::Util.absolute_path?(value, :posix) || Puppet::Util.absolute_path?(value, :windows)
        raise ArgumentError, %(File paths must be fully qualified, not '#{value}')
      end
    end
  end

  newproperty(:ensure) do
    desc <<~DOC
      The state that the resource should be in on the system. May be one of:

        * present          => Ensure that the resource exists at all
        * absent           => Ensure that the resource is not present on the system
        * latest           => Ensure that the resource is the latest available
        * <version string> => Attempt to match the specified version, raise an error if the version does not exist
    DOC

    newvalues(:present, :absent, :latest, %r{.})

    defaultto(:present)

    munge do |value|
      value = case value
      when true
        :present
      when false
        :absent
      when 'present', 'absent', 'latest'
        value.to_sym
      else
        value
      end
    end

    def insync?(current_value)
      provider.ensure_insync?(current_value, should)
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

  # Optional Items

  ## Nexus Auth

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

  ## Proxy

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

  ## Validation

  newparam(:ca_certificate) do
    desc <<~DOC
      The path to a file containing the CA public certificate or a directory
      containing CA public certificates
    DOC

    validate do |value|
      unless Puppet::Util.absolute_path?(value, :posix) || Puppet::Util.absolute_path?(value, :windows)
        raise ArgumentError, %(File paths must be fully qualified, not '#{value}')
      end
    end
  end

  newparam(:ssl_verify) do
    desc <<~DOC
      Disable or set the dept for SSL server validation

      Has no effect if `$ca_certificate` is not set
    DOC

    newvalues(true, false, :true, :false, %r{\A\d+\Z})

    defaultto('true')

    munge do |value|
      case value
      when 'true', true
        true
      when 'false', false
        false
      else
        value.to_i
      end
    end
  end

  newparam(:verify_download, boolean: false, parent: Puppet::Parameter::Boolean) do
    desc <<~DOC
      If a file has been downloaded, validate that the downloaded artifact
      checksum matches the one that was provided by Nexus.

      WARNING: This may add a great deal of load to your system for large artifacts.

      In general, this is not necessary but may be wise on critical assets.
    DOC
    defaultto false
  end

  ## Be nice to your servers

  newparam(:sleep) do
    desc <<~DOC
      The number of seconds to sleep between pagination updates

      Use this to prevent excessive load on the server for large projects

      Fractions of a second are supported
    DOC

    defaultto('0')

    newvalues(%r{\A\d(\.\d)?\Z})

    munge do |value|
      value.to_f
    end
  end

  newparam(:connection_timeout) do
    desc <<~DOC
      Number of seconds to wait for a response and artifact download from the server

      NOTE: This will *kill* any existing connection and large downloads may not
      be retrieved successfully
    DOC

    newvalues(%r{\A\d+\Z})

    munge do |value|
      value.to_i
    end
  end

  validate do
    required_parameters = [:server, :repository, :artifact]
    missing_parameters = required_parameters.reject { |x| self[x] }

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
