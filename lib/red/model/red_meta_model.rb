require 'arby/arby_ast'
require 'arby/arby_meta'
require 'arby/arby'
require 'sdg_utils/meta_utils'

module Red
  module Model

    #-------------------------------------------------------------------
    # == Class +MetaModel+
    #
    # @attr records  [Array] - list of record classes
    # @attr machines [Array] - list of machine classes
    # @attr events   [Array] - list of event class
    #-------------------------------------------------------------------
    class MetaModel
      include Arby::Model::MMUtils
      extend SDGUtils::Delegate

      delegate :register_listener, :fire, :unregister_listener, :to => Arby.meta

      def initialize
        reset
      end

      def reset
        @base_records = []
        @records = []
        @machines = []
        @events = []
        @policies = []
        @cache = {}
        @restriction_mod = nil
      end

      attr_searchable :base_record, :record, :machine, :event, :policy

      def restrict_to(mod)
        @restriction_mod = mod
        Arby.meta.restrict_to(mod)
      end

      def record_or_machine(name)
        record(name) || machine(name)
      end

      private

      def _add_to(col, val)
        col << val unless val.respond_to?("placeholder?".to_sym) && val.placeholder?
      end
    end

  end
end
