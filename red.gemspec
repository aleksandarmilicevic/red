require 'rubygems'

Gem::Specification.new do |s|
  s.name = "red"
  s.author = "Aleksandar Milicevic"
  s.email = "aleks@csail.mit.edu"
  s.version = "0.0.1"
  s.summary = "RED - Ruby Event Driven"
  s.description = "Model-based, event-driven, programming paradigm for cloud-based systems."
  s.files = Dir['lib/**/*.rb']
  s.require_paths = ["lib"]

  s.add_runtime_dependency "arby"
  s.add_runtime_dependency "rails", ["3.2.9"]
  s.add_runtime_dependency "activerecord", ["3.2.9"]
  s.add_runtime_dependency "activemodel", ["3.2.9"]
  s.add_runtime_dependency "faye"
  s.add_runtime_dependency "sass"
  s.add_runtime_dependency "sqlite3"
  s.add_runtime_dependency "browser-timezone-rails"
end
