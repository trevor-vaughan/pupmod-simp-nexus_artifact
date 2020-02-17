require 'spec_helper_acceptance'

test_name 'Nexus Artifact Download'

describe 'nexus artifact download' do
  # TODO: Change this to something not real :-|
  let(:manifest) {
    <<~EOS
      nexus_artifact { "#{target_path}":
        ensure => '#{pkg_version}',
        server => 'nexus3.onap.org',
        repository => 'PyPi',
        artifact => 'pip'
      }
    EOS
  }

  hosts.each do |host|
    context 'ensure=present' do
      let(:pkg_version){ 'present' }

      is_windows = fact_on(host, 'kernel').casecmp?('windows')

      if is_windows
        let(:target_path){ 'C:/Windows/Temp/nexus_download' }
      else
        let(:target_path){ '/tmp/nexus_download' }

        it 'should prep the system' do
          install_package(host, 'attr')
        end
      end

      it 'should apply without errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, :catch_changes => true)
      end

      it 'should have downloaded the file' do
        expect(file_exists_on(host, target_path)).to be true
      end

      it 'should have file metadata' do
        content = 'no content found'

        if is_windows
          content = file_contents_on(host, "#{target_path}:pup_nexus_artifact")
        else
          content = on(host, "getfattr -d -m - #{target_path}").stdout
        end

        expect(content).to match(/pup.simp.size=/m)
      end
    end
  end
end
