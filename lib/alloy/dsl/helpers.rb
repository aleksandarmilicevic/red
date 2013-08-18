require 'alloy/dsl/abstract_helper'
require 'alloy/dsl/fun_helper'
require 'alloy/dsl/mult_helper'

module Alloy
  module Dsl

    module StaticHelpers
      include MultHelper
      extend self
    end

    #TODO: doesn't work for ActiveRecord::Relation
    module InstanceHelpers
      require 'alloy/relations/relation_ext.rb'
      def no(col)   col.as_rel.no? end
      def some(col) col.as_rel.some? end
      def one(col)  col.as_rel.one? end
      def lone(col) col.as_rel.lone? end
    end

  end
end
