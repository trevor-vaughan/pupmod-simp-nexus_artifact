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
  gem 'simp-rspec-puppet-facts', ENV.fetch('SIMP_RSPEC_PUPPET_FACTS_VERSION', '~> 3.0')
  gem 'simp-rake-helpers', ENV.fetch('SIMP_RAKE_HELPERS_VERSION', ['>= 5.10.2', '< 6.0.0'])
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
  gem 'beaker', :git => 'https://github.com/puppetlabs/beaker'
  gem 'beaker-puppet', :git => 'https://github.com/puppetlabs/beaker-puppet'
  gem 'beaker-windows'
  #gem 'simp-beaker-helpers', ENV.fetch('SIMP_BEAKER_HELPERS_VERSION', ['>= 1.18.0', '< 2.0'])
  gem 'simp-beaker-helpers', :git => 'https://github.com/trevor-vaughan/rubygem-simp-beaker-helpers', :branch => 'SIMP-MAINT-fix_windows_lib'
end
