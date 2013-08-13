require 'alloy/alloy_ast'
require 'alloy/alloy_ast_errors'
require 'red/model/red_meta_model'

module Red
  module Model

    #-------------------------------------------------------------------
    # == Class +EventMeta+
    #
    # Meta information about events.
    #-------------------------------------------------------------------
    class EventMeta < Alloy::Ast::SigMeta
      attr_accessor :from, :to

      def params(include_inherited=true)
        my_params = fields - [to, from]
        if include_inherited && parent_sig < Event
          my_params += parent_sig.meta.params(true)
        end
        my_params
      end
    end

    #-------------------------------------------------------------------
    # == Module +EventClassMethods+
    #
    #-------------------------------------------------------------------
    module EventClassMethods
      include Alloy::Ast::ASig::Static

      def created()
        super
        Red.meta.event_created(self)
      end

      def from(hash)
        _check_to_from_hash(hash)
        params(hash)
        meta.from = meta.field(hash.keys.first)
      end

      def to(hash)
        _check_to_from_hash(hash)
        params(hash)
        meta.to = meta.field(hash.keys.first)
      end

      alias_method :params, :transient

      def param(*args)
        _traverse_field_args(args, lambda{|name, type, hash={}|
                             _field(name, type, hash.merge({:transient => true}))})
      end

      def requires(&block)
        define_method(:requires, &block)
      end

      def ensures(&block)
        define_method(:ensures, &block)
      end

      def finish
        _sanity_check()
      end

      protected

      #------------------------------------------------------------------------
      # Defines the +meta+ method which returns some meta info
      # about this events's params and from/to designations.
      #------------------------------------------------------------------------
      def _define_meta()
        meta = EventMeta.new(self)
        define_singleton_method(:meta, lambda {meta})
      end

      def _sanity_check
        # raise MalformedEventError, "`from' machine not defined for event `#{name}'"\
        #   unless @from_fld
        # raise MalformedEventError, "`to' machine not defined for event `#{name}'"\
        #   unless @to_fld
        from({from: Machine}) unless meta.from
        to({to: Machine}) unless meta.to
        define_method(:requires, lambda{ true }) unless method_defined? :requires
        define_method(:ensures, lambda{}) unless method_defined? :ensures
      end

      def _check_to_from_hash(hash)
        msg1 = "Hash expected, got #{hash.class} instead"
        msg2 = "Expected exactly one entry, got #{hash.length}"
        raise ArgumentError, msg1 unless hash.kind_of? Hash
        raise ArgumentError, msg2 unless hash.length == 1
        Alloy::Ast::TypeChecker.check_type(Red::Model::Machine, hash.values.first)
      end
    end

    #-------------------------------------------------------------------
    # == Class +Event+
    #
    # Base class for all classes from the event-model.
    #-------------------------------------------------------------------
    class Event
      include Alloy::Ast::ASig
      extend EventClassMethods

      placeholder

      def initialize(hash={})
        super rescue nil
        hash.each do |k, v|
          set_param(k, v)
        end
      end

      def from()         read_field(meta.from) end
      def from=(machine) write_field(meta.from, machine) end
      def to()           read_field(meta.to) end
      def to=(machine)   write_field(meta.to, machine) end

      def params()
        meta.params.reduce({}) do |acc, fld|
          acc.merge! fld.name => read_field(fld)
        end
      end

      def set_param(name, value)
        #TODO check name
        write_field meta.field(name), value
      end

      def get_param(name)
        #TODO check name
        read_field meta.field(name)
      end

      def incomplete(msg)
        raise EventNotCompletedError, msg
      end

      def check_precondition(cond, msg)
        raise EventPreconditionNotSatisfied, msg unless cond
        true
      end

      alias_method :check, :check_precondition

      def check_present(*param_names)
        param_names.each do |param_name|
          obj = get_param(param_name)
          msg ||= "param #{param_name} must not be nil"
          check !obj.nil?, msg
        end
      end

      def check_all_present
        check_present(*meta.params.map{|fld| fld.name})
      end

      def error(msg)
        fail msg
      end

      def execute
        ok = requires()
        raise Red::Model::EventPreconditionNotSatisfied, "Precondition failed" unless ok
        ensures()
      end
    end

  end
end
