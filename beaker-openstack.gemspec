# frozen_string_literal: true

# Use require_relative for the version file and avoid unshifting to $LOAD_PATH manually
require_relative 'lib/beaker-openstack/version'

Gem::Specification.new do |s|
  s.name        = "beaker-openstack"
  s.version     = BeakerOpenstack::VERSION
  s.authors     = ['Vox Pupuli']
  s.email       = ['voxpupuli@groups.io']
  s.homepage    = 'https://github.com/voxpupuli/beaker-openstack'
  s.summary     = 'Beaker hypervisor support for OpenStack'
  s.description = 'Provides OpenStack hypervisor implementation for the Beaker acceptance testing tool.'
  s.license     = 'Apache-2.0'

  # Modern file list logic using standard Ruby Dir for environments without git
  s.files         = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  s.require_paths = ["lib"]

  # Metadata for better visibility on RubyGems.org
  s.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'changelog_uri'     => 'https://github.com',
    'source_code_uri'   => 'https://github.com/voxpupuli/beaker-openstack',
    'bug_tracker_uri'   => 'https://github.com'
  }

  # Ruby compatibility: Dropped EoL 2.4/2.5/2.6 support in version 2.0.0
  s.required_ruby_version = '>= 2.7', '< 5'

  # Runtime dependencies
  s.add_runtime_dependency 'stringify-hash', '~> 0.0.0'
  s.add_runtime_dependency 'fog-openstack', '~> 1.0'
  # Updated for modern Beaker compatibility (Beaker 6.x and 7.x)
  s.add_runtime_dependency 'beaker', '>= 5.6', '< 8'

  # Testing & Development dependencies
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rspec-its'
  s.add_development_dependency 'fakefs', '>= 2.4', '< 4'
  s.add_development_dependency 'irb'
  s.add_development_dependency 'rake', '>= 12.3.3'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'pry', '~> 0.10'
  s.add_development_dependency 'yard'
end
