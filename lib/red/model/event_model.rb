require 'alloy/alloy_ast'
require 'alloy/dsl/sig_builder'
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

    #============================================================
    # == Class +EventDslApi+
    #
    # Adds some dsl API methods
    #============================================================
    module EventDslApi
      include Alloy::Dsl::SigDslApi

      protected

      def from(hash)
        _check_single_fld_hash(hash, Red::Model::Machine)
        params(hash)
        meta.from = meta.field(hash.keys.first)
      end

      def to(hash)
        _check_single_fld_hash(hash, Red::Model::Machine)
        params(hash)
        meta.to = meta.field(hash.keys.first)
      end

      alias_method :params, :transient

      def param(*args)
        _traverse_field_args(args, lambda{|name, type, hash={}|
                             _field(name, type, hash.merge({:transient => true}))})
      end

      def requires(&blk)     _define_method(:requires, &blk) end
      def ensures(&blk)      _define_method(:ensures, &blk) end
      def success_note(&blk) _define_method(:success_note, &blk) end
      def error_note(&blk)   _define_method(:error_note, &blk) end

      def __created
        super
        Red.meta.add_event(self)
      end

      def __finish
        _sanity_check()
      end

      def _sanity_check
        from({from: Machine}) unless meta.from
        to({to: Machine})     unless meta.to
        requires(&lambda{ true }) unless method_defined? :requires
        ensures(&lambda{})        unless method_defined? :ensures
      end
    end

    #============================================================
    # == Module +EventClassMethods+
    #
    #============================================================
    module EventStatic
      include Alloy::Ast::ASig::Static

      protected

      #------------------------------------------------------------------------
      # Defines the +meta+ method which returns some meta info
      # about this events's params and from/to designations.
      #------------------------------------------------------------------------
      def _define_meta()
        #TODO codegen
        meta = EventMeta.new(self)
        define_singleton_method(:meta, lambda {meta})
      end
    end

    #-------------------------------------------------------------------
    # == Class +Event+
    #
    # Base class for all classes from the event-model.
    #-------------------------------------------------------------------
    class Event
      include Alloy::Ast::ASig
      extend EventStatic
      extend EventDslApi

      placeholder

      def initialize(hash={})
        super rescue nil
        @notes = []
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

      def notes() (@notes || []).clone end

      def check_present(*param_names)
        param_names.each do |param_name|
          obj = get_param(param_name)
          msg ||= "param #{param_name} must not be nil"
          check !obj.nil?, msg
        end
      end

      def check_all_present
        check_present(*meta.params.map(&:name))
      end

      def success(msg)
        add_note(:success, msg)
      end

      def error(msg)
        fail msg
      end

      def execute
        succeeded = false

        ok = requires()
        raise Red::Model::EventPreconditionNotSatisfied, "Precondition failed" unless ok
        ensures()

        succeeded = true
        suc_note = success_note() and add_note(:success, suc_note)
      ensure
        !succeeded and er_note = error_note() and  add_note(:error, er_note)
      end

      protected

      # don't track field accesses for policies
      def intercept_read(fld)       yield end
      def intercept_write(fld, val) yield end

      def success_note() nil end
      def error_note()   nil end

      def add_note(kind, msg)
        @notes << [kind, msg]
      end
    end

  end
end
