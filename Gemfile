# ------------------------------------------------------------------------------
# NOTE: SIMP Puppet rake tasks support ruby 2.1.9
# ------------------------------------------------------------------------------
gem_sources = ENV.fetch('GEM_SERVERS','https://rubygems.org').split(/[, ]+/)

gem_sources.each { |gem_source| source gem_source }

ENV['PUPPET_VERSION'] ||= ENV['PDK_PUPPET_VERSION']
ENV['PUPPET_VERSION'] ||= '~> 5.5'

group :test do
  gem 'rake'
  gem 'puppet'
  gem 'rspec'
  gem 'rspec-puppet'
  gem 'hiera-puppet-helper'
  gem 'puppetlabs_spec_helper'
  gem 'metadata-json-lint'
  gem 'puppet-strings'
  gem 'puppet-lint-empty_string-check',   :require => false
  gem 'puppet-lint-trailing_comma-check', :require => false
  gem 'simp-rspec-puppet-facts', ENV.fetch('SIMP_RSPEC_PUPPET_FACTS_VERSION', '~> 2.2')
  gem 'simp-rake-helpers', ENV.fetch('SIMP_RAKE_HELPERS_VERSION', '~> 5.9')
  gem 'facterdb'
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'rubocop-i18n'
end

group :development do
  gem 'pry'
  gem 'pry-doc'
  gem 'puppet-resource_api', require: false
end

group :system_tests do
  gem 'beaker'
  gem 'beaker-rspec'
  gem 'beaker-vagrant', :git => 'https://github.com/puppetlabs/beaker-vagrant'
  gem 'beaker-windows'
  gem 'beaker-puppet', :git => 'https://github.com/trevor-vaughan/beaker-puppet', :branch => 'windows_paths'
  gem 'simp-beaker-helpers', ENV.fetch('SIMP_BEAKER_HELPERS_VERSION', ['>= 1.14.6', '< 2.0'])
end
