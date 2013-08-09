require 'red/model/security_model.rb'
require_relative 'red_dsl_ext.rb'

module Red
  module DslEngine

    class PolicyBuilder
      def initialize(options={})
        @options = options
      end

      def build(name, &block)
        @policy = Red::Model::Policy.new(name)
        if block
          self.instance_eval block
        end
      end
    end

  end
end
