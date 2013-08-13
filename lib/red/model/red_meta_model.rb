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
        @policies = []
        @cache = {}
        @restriction_mod = nil
      end

      protected

      # Returns plural of the given noun by
      #  (1) replacing the trailing 'y' with 'ies', if `word'
      #      ends with 'y',
      #  (2) appending 'es', if `word' ends with 's'
      #  (3) appending 's', otherwise
      def self.pl(word)
        word = word.to_s
        if word[-1] == "y"
          word[0...-1] + "ies"
        elsif word[-1] == "s"
          word + "es"
        else
          word + "s"
        end
      end

      # Generates several methods for each symbol in `whats'.  For
      # example, if whats == [:record] it generates:
      #
      #   private
      #   def _records()          _restrict @records end
      #
      #   public
      #   def records()           _records end
      #   def record_created(obj) add_to(@records, obj) end
      #   def get_record(name)    _cache(_records, name) end
      #   def find_record(name)   _search_by_name(_records, name) end
      #
      #   alias_method :record, :get_record
      def self.gen(*whats)
        whats.each do |what|
          self.class_eval <<-RUBY, __FILE__, __LINE__+1
            private
            def _#{pl what}()        _restrict @#{pl what} end

            public
            def #{pl what}()         _#{pl what} end
            def #{what}_created(obj) add_to(@#{pl what}, obj) end
            def get_#{what}(name)    _cache(_#{pl what}, name) end
            def find_#{what}(name);  _search_by_name(_#{pl what}, name) end

            alias_method :#{what}, :get_#{what}
          RUBY
        end
      end

      public

      gen :base_record, :record, :machine, :event, :policy

      def restrict_to(mod)
        @restriction_mod = mod
        Alloy.meta.restrict_to(mod)
      end

      private

      def add_to(col, val)
        col << val unless val.respond_to?("placeholder?".to_sym) && val.placeholder?
      end
    end

  end
end
