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

  newparam(:source) do
    desc <<~DOC
      The URI to the Nexus artifact in the form http(s)://<server.fqdn>/<repository_name>/<artifact_name>
    DOC

    newvalues(%r{^http(s)?://.+/.+/.+$})
  end

  newparam(:sleep) do
    desc <<~DOC
      The number of seconds to sleep between pagination updates. Fractions of a second are supported.
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
    raise Puppet::Error, 'You must specify a :source' unless self[:source]
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
