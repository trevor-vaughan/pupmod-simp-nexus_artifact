#!/usr/bin/env rspec

require 'spec_helper'

nexus_artifact_type = Puppet::Type.type(:nexus_artifact)

describe nexus_artifact_type do
  before(:each) do
    @catalog = Puppet::Resource::Catalog.new

    allow(Puppet::Type::Nexus_artifact).to receive(:catalog).and_return(@catalog)
  end

  context 'when setting parameters' do
    let(:valid_paths){[
      '/foo',
      '/foo/bar/baz',
      'C:/foo',
      'D:/foo/bar/baz',
      'F:\\foo\\bar\\baz'
    ]}

    let(:invalid_paths){[
      'foo',
      'C:'
    ]}

    context 'required parameters' do
      params = {
        :server     => 'foo.bar.baz',
        :repository => 'test',
        :artifact   => 'thingy'
      }

      (0...params.keys.count).each do |x|
        key = params.keys[x]
        tmp_params = Marshal.load(Marshal.dump(params))
        tmp_params.delete(key)

        it "should require #{key}" do
          expect{
            nexus_artifact_type.new({ :path => '/tmp/foo' }.merge(tmp_params))
          }.to raise_error(/must be specified.+#{key}/)
        end
      end
    end

    context ':path' do
      it 'should accept valid values' do
        valid_paths.each do |path|
          resource = nexus_artifact_type.new(
            :path       => path,
            :server     => 'foo.bar.baz',
            :repository => 'test',
            :artifact   => 'thingy'
          )

          expect(resource[:path]).to eq(path)
        end
      end

      it 'should reject invalid values' do
        invalid_paths.each do |path|
          expect {
            nexus_artifact_type.new(
              :name       => path,
              :server     => 'foo.bar.baz',
              :repository => 'test',
              :artifact   => 'thingy'
            )
          }.to raise_error(/must be fully qualified/)
        end
      end
    end

    context ':ensure' do
      let(:valid_values){{
        'present' => :present,
        'absent'  => :absent,
        'latest'  => :latest,
        '1.2.3.4' => '1.2.3.4',
        true      => :present,
        false     => :absent
      }}

      it 'should accept valid values' do
        valid_values.each do |key, value|
          resource = nexus_artifact_type.new(
            :path       => '/tmp/foo',
            :ensure     => key,
            :server     => 'foo.bar.baz',
            :repository => 'test',
            :artifact   => 'thingy'
          )

          expect(resource[:ensure]).to eq(value)
        end
      end
    end

    context ':ssl_verify' do
      let(:valid_values){{
        'true'  => true,
        'false' => false,
        true    => true,
        false   => false,
        '5'     => 5,
        5       => 5
      }}

      it 'should accept valid values' do
        valid_values.each do |key, value|
          resource = nexus_artifact_type.new(
            :path       => '/tmp/foo',
            :ensure     => 'latest',
            :server     => 'foo.bar.baz',
            :repository => 'test',
            :artifact   => 'thingy',
            :ssl_verify => key
          )

          expect(resource[:ssl_verify]).to eq(value)
        end
      end

      it 'should reject invalid values' do
        expect { nexus_artifact_type.new(
          :path       => '/tmp/foo',
          :ensure     => 'latest',
          :server     => 'foo.bar.baz',
          :repository => 'test',
          :artifact   => 'thingy',
          :ssl_verify => 'bob'
        ) }.to raise_error(/Invalid value "bob"/)
      end
    end
  end
end
