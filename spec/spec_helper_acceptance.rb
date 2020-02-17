require 'beaker-rspec'
require 'tmpdir'
require 'yaml'
require 'simp/beaker_helpers'
include Simp::BeakerHelpers

require 'beaker/puppet_install_helper'

unless ENV['BEAKER_provision'] == 'no'
  hosts.each do |host|
    # Install Puppet
    if host.is_pe?
      install_pe
    else
      install_puppet
    end

    include Simp::BeakerHelpers::Windows if is_windows?(host)
  end
end

RSpec.configure do |c|
  # ensure that environment OS is ready on each host
  fix_errata_on(hosts)

  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    begin
      # Install modules and dependencies from spec/fixtures/modules
      copy_fixture_modules_to( hosts )

      nonwin = hosts.dup
      nonwin.delete_if {|h| h[:platform] =~ /windows/ }

      unless nonwin.empty?
        begin
          server = only_host_with_role(nonwin, 'server')
        rescue ArgumentError => e
          server = hosts_with_role(nonwin, 'default').first
        end
        # Generate and install PKI certificates on each SUT
        Dir.mktmpdir do |cert_dir|
          run_fake_pki_ca_on(server, nonwin, cert_dir )
          nonwin.each{ |sut| copy_pki_to( sut, cert_dir, '/etc/pki/simp-testing' )}
        end

        # add PKI keys
        copy_keydist_to(server)
      end
    rescue StandardError, ScriptError => e
      if ENV['PRY']
        require 'pry'; binding.pry
      else
        raise e
      end
    end
  end
end
