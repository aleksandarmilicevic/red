require 'arby/resolver'
require 'red/model/red_model'

module Red
  extend self

  Resolver = Arby::CResolver.new :baseklass => Red::Model::Record
end
