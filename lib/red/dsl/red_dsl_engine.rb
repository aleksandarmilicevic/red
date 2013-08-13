require 'red/model/security_model.rb'
require 'sdg_utils/dsl/class_builder'

module Red
  module DslEngine

    class PolicyBuilder < SDGUtils::DSL::ClassBuilder
      def initialize(options={})
        opts = { :superclass => Red::Model::Policy }
        super(opts.merge!(options))
      end
    end

  end
end
