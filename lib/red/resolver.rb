require 'alloy/resolver'
require 'red/model/red_model'

module Red
  extend self

  Resolver = Alloy::CResolver.new :baseklass => Red::Model::Record
end
