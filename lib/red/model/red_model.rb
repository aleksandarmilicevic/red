require 'active_record'
require 'alloy/alloy_ast'
require 'alloy/alloy_ast_errors'
require 'sdg_utils/recorder'
require 'sdg_utils/proxy'
require 'red/red'

require_relative 'red_meta_model'
require_relative 'red_model_ext'
require_relative 'red_model_errors'
require_relative 'red_table_util'

module Red
  module Model

    class RedMeta
      attr_reader :record_cls
      attr_reader :js_events

      def initialize(record_cls)
        @record_cls = record_cls
        @js_events = {}
        @trans_values = {}
        @rec = nil
      end

      def recorder
        @rec ||= SDGUtils::MethodRecorder.new(@record_cls, &method(:add_js_event))
      end

      def add_js_event(name, proc)
        @js_events.merge! name.to_s => proc
      end

      def js_event(name)
        @js_events[name.to_s]
      end

      def transient_values(obj)
        @trans_values[obj.id] ||= {}
      end

      def get_transient_value(obj, fld)
        transient_values(obj)[fld.name]
      end

      def set_transient_value(obj, fld, val)
        transient_values(obj)[fld.name] = val
      end
    end

    module ObjCallbacks
      def get_callbacks_for(sym, obj)
        inst_var = "@#{sym}_obj_callbacks"
        type_callbacks = instance_variable_get(inst_var)
        unless type_callbacks
          type_callbacks = {}
          instance_variable_set(inst_var, type_callbacks)
        end
        fail "unsaved record used: #{obj}" unless obj.id
        type_callbacks[obj.id] ||= []
      end

      # ---------------------------------------------------------------------
      #
      # Example:
      #   ar_cb_sym = :after_save
      #
      # Defines the following instance methods:
      #   def obj_after_save(callback=nil, &block) ... end
      #   def remove_after_save(callback) ... end
      #
      # Defines the following class methods:
      #   def self.trigger_after_save(*args) <notify all aliases of `self'> end
      #
      # Invokes (unless opts[:not_activerecord_cb]):
      #   self.class.after_save do |*args| <notify all aliases of `self'> end
      #
      # ---------------------------------------------------------------------
      def gen_obj_callback(ar_cb_sym, opts={})
        sym = "obj_#{ar_cb_sym}".to_sym
        rem_sym = "remove_#{sym}".to_sym
        trigger_sym = "trigger_#{ar_cb_sym}".to_sym

        self.class_eval <<-RUBY, __FILE__, __LINE__+1
def #{sym}(callback=nil, &block)
  cb = callback || block
  fail 'no callback given' unless cb
  self.class.get_callbacks_for(#{sym.inspect}, self) << cb
end

def #{rem_sym}(callback)
  self.class.get_callbacks_for(#{sym.inspect}, self).delete callback
end

def self.#{trigger_sym}(record, *args)
  record.class.get_callbacks_for(#{sym.inspect}, record).each do |cb|
    Proc === cb ? cb.call(record, *args) : cb.send(#{sym.inspect}, record, *args)
  end
end
RUBY
        unless opts[:not_activerecord_cb]
          self.send ar_cb_sym, lambda{|*args| self.class.send trigger_sym, self, *args}
        end
      end

    #   def gen_obj_callback(ar_cb_sym, opts={})
    #     sym = "obj_#{ar_cb_sym}".to_sym
    #     rem_sym = "remove_#{sym}".to_sym
    #     trigger_sym = "trigger_#{ar_cb_sym}".to_sym
    #     self.send :define_method, sym do |cb_obj=nil, &block|
    #       cb = cb_obj || block
    #       fail "no callback given" unless cb
    #       self.class.get_callbacks_for(sym, self) << cb
    #     end

    #     self.send :define_method, rem_sym do |cb|
    #       self.class.get_callbacks_for(sym, self).delete cb
    #     end

    #     proc = Proc.new{|*args|
    #       args = [self] if args.size == 0
    #       rec = args[0]
    #       rec.class.get_callbacks_for(sym, rec).each do |cb|
    #         Proc === cb ? cb.call(*args) : cb.send(sym, *args)
    #       end
    #     }
    #     if opts[:not_activerecord_cb]
    #       self.class.send :define_method, trigger_sym, proc
    #     else
    #       self.send ar_cb_sym, proc
    #     end
    #   end
    end

    #-------------------------------------------------------------------
    # == Class +Record+
    #
    # Base class for all persistent model object in Red.
    #-------------------------------------------------------------------
    class Record < ActiveRecord::Base
      include Alloy::Ast::ASig
      extend Red::Model::ObjCallbacks

      gen_obj_callback :after_save
      gen_obj_callback :after_destroy
      gen_obj_callback :after_elem_appended, :not_activerecord_cb => true

      class << self
        def allocate
          obj = super
          obj.send :init_default_transient_values
          obj
        end

        def created()
          super
          Red.meta.base_record_created(self)
        end

        def after_query(obj)
          #TODO: cover other cases (e.g., when obj is a symbols)
          after_query_listeners << obj
        end

        def find(*args)  res = super; fire_after_query(self, :find, args, res) end
        def all(*args)   res = super; fire_after_query(self, :all, args, res) end
        def where(*args) res = super; fire_after_query(self, :where, args, res) end

        # def scoped
        #   obj = super
        #   me = self
        #   first_time_flag = false
        #   puts "@@@@@@@@@@@@@"
        #   SDGUtils::AroundProxy.new(obj) do |name, args, block, cont|
        #     result = cont.call
        #     unless @first_time_flag
        #       @first_time_flag = true
        #       puts "intercepted message `#{name}' for cls #{me.name}"
        #       fire_after_query(me, name, args, result)
        #     end
        #     result
        #   end
        # end

        def fire_after_query(target, method, args, result)
          after_query_listeners.each do |l|
            l.after_query(target, method, args, result)
          end
          result
        end

        def red_root() alloy_root end
        def red_subclasses() meta.subsigs end

        def start
          super
          _define_red_meta()
        end

        def js()
          red_meta.recorder
        end

        protected

        def _field(*args)
          fld = super
          if fld.transient?
            attr_accessible fld.getter_sym
          end
        end

        def _fld_reader_code(fld)      (fld.persistent?) ? "super" : super end
        def _fld_writer_code(fld, val) (fld.persistent?) ? "super" : super end

        def after_query_listeners
          @@after_query_listeners ||= []
        end

        def _set_placeholder
          super
          # tell active record to ignore this class
          self.abstract_class = true
        end

        #------------------------------------------------------------------------
        # Defines the +meta+ method which returns some meta info
        # about this sig's fields
        #------------------------------------------------------------------------
        def _define_red_meta()
          red_meta = RedMeta.new(self)
          define_singleton_method(:red_meta, lambda {red_meta})
        end
      end

      placeholder

      boss_proxy = SDGUtils::Delegator.new(lambda{Red.boss})

      around_save :with_transient_values
      after_create      boss_proxy
      after_save        boss_proxy
      after_destroy     boss_proxy
      # after_find       boss_proxy
      after_update      boss_proxy
      after_query       boss_proxy

      def red_meta
        self.class.red_meta
      end

      def to_s
        "#{self.class.name}(#{id})"
      end

      protected

      def with_transient_values
        hash = save_transient_values
        yield
        hash.each { |fld, val| self.write_field(fld, val) }
      end      

      #TODO: REM and move transient
      # def _read_fld_value(fld)
      #   fail "not supposed to be used for persistent fields" if fld.persistent?
      #   if (self.id rescue false)
      #     red_meta.get_transient_value(self, fld)
      #   else
      #     super(fld)
      #   end
      # end
      # def _write_fld_value(fld, val)
      #   fail "not supposed to be used for persistent fields" if fld.persistent?
      #   if (self.id rescue false)
      #     red_meta.set_transient_value(self, fld, val)
      #   else
      #     super(fld, val)
      #   end
      # end

      def save_transient_values
        meta.tfields.reduce({}) do |acc, tf|
          acc[tf] = self.read_field(tf)
          acc
        end
      end
    end

    #-------------------------------------------------------------------
    # == Class +Data+
    #
    # Base class for classes from the data-model, excluding machines.
    #-------------------------------------------------------------------
    class Data < Record
      placeholder

      def self.created()
        super
        Red.meta.record_created(self)
      end
    end

    #-------------------------------------------------------------------
    # == Class +Machine+
    #
    # Base class for machine classes.
    #-------------------------------------------------------------------
    class Machine < Record
      placeholder

      def self.created()
        super
        Red.meta.machine_created(self)
      end
    end

    #-------------------------------------------------------------------
    # == Class +RedJoinModel+
    #
    # Used for classes generated on the fly to represent join models for
    # many to many associations.
    #-------------------------------------------------------------------
    class RedJoinModel < Record
      placeholder
    end

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

    module EventInstanceMethods
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

    #-------------------------------------------------------------------
    # == Class +Event+
    #
    # Base class for all classes from the event-model.
    #-------------------------------------------------------------------
    class Event
      include Alloy::Ast::ASig
      include EventInstanceMethods
      placeholder

      class << self
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
    end

  end
end
