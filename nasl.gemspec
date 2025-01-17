# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'nasl/version'

Gem::Specification.new do |s|
  s.name        = 'nasl'
  s.version     = Nasl::VERSION
  s.authors     = ['Mak Kolybabi']
  s.email       = ['mak@kolybabi.com']
  s.homepage    = 'http://github.com/mogigoma/nasl'
  s.summary     = %q{A parser for the Nessus Attack Scripting Language.}

  s.rubyforge_project = 'nasl'

  s.files         = `git ls-files`.split("\n") + ['lib/nasl/grammar.tab.rb']

  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_development_dependency 'rake'

  s.add_runtime_dependency 'builder'
  s.add_runtime_dependency 'racc'
  s.add_runtime_dependency 'rainbow'
end
