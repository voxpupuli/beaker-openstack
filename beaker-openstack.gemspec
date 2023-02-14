# -*- encoding: utf-8 -*-
$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'beaker-openstack/version'

Gem::Specification.new do |s|
  s.name        = "beaker-openstack"
  s.version     = BeakerOpenstack::VERSION
  s.authors     = 'Vox Pupuli'
  s.email       = 'voxpupuli@groups.io'
  s.homepage    = 'https://github.com/voxpupuli/beaker-openstack'
  s.summary     = %q{Beaker DSL Extension Helpers!}
  s.description = %q{For use for the Beaker acceptance testing tool}
  s.license     = 'Apache2'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # Testing dependencies
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rspec-its'
  s.add_development_dependency 'fakefs', '~> 2.4'
  s.add_development_dependency 'rake', '>= 12.3.3'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'pry', '~> 0.10'

  # Documentation dependencies
  s.add_development_dependency 'yard'
  s.add_development_dependency 'markdown'
  s.add_development_dependency 'thin'

  # Run time dependencies
  s.add_runtime_dependency 'stringify-hash', '~> 0.0.0'
  s.add_runtime_dependency 'fog-openstack', '~> 1.0.0'

end

