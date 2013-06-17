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
end
