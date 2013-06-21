require 'alloy/alloy_ast'
require 'alloy/alloy_meta'
require 'alloy/alloy_ast_errors'
require 'alloy/alloy'
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
      include Alloy::Model::MMUtils
      extend SDGUtils::Delegate

      delegate :register_listener, :fire, :unregister_listener, :to => Alloy.meta

      def initialize
        reset
      end

      def reset
        @base_records = []
        @records = []
        @machines = []
        @events = []
        @cache = {}
        @restriction_mod = nil
      end

      def base_records; _base_records end
      def records;      _records end
      def machines;     _machines end
      def events;       _events end

      def base_record_created(rklass) add_to(@base_records, rklass) end
      def record_created(rklass)      add_to(@records, rklass) end
      def machine_created(mklass)     add_to(@machines, mklass) end
      def event_created(eklass)       add_to(@events, eklass) end

      def get_base_record(name) _cache(_base_records, name) end
      def get_record(name)      _cache(_records, name) end
      def get_machine(name)     _cache(_machines, name) end
      def get_event(name)       _cache(_events, name) end

      alias_method :base_record, :get_base_record
      alias_method :record, :get_record
      alias_method :machine, :get_machine
      alias_method :event, :get_event

      def find_base_record(name); _search_by_name(_base_records, name) end
      def find_record(name);      _search_by_name(_records, name) end
      def find_machine(name);     _search_by_name(_machines, name) end
      def find_event(name);       _search_by_name(_events, name) end

      def restrict_to(mod)
        @restriction_mod = mod
        Alloy.meta.restrict_to(mod)
      end

      private

      def add_to(col, val)
        col << val unless val.placeholder?
      end

      def _base_records; _restrict @base_records end
      def _records;      _restrict @records end
      def _machines;     _restrict @machines end
      def _events;       _restrict @events end

    end

  end
end
