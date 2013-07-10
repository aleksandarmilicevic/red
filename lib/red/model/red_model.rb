require 'active_record'
require 'alloy/alloy_ast'
require 'alloy/alloy_ast_errors'
require 'alloy/relations/all'
require 'sdg_utils/recorder'
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

      def gen_obj_callback(ar_cb_sym)
        sym = "obj_#{ar_cb_sym}".to_sym
        rem_sym = "remove_#{sym}".to_sym
        self.send :define_method, sym do |cb_obj=nil, &block|
          cb = cb_obj || block
          fail "no callback given" unless cb
          self.class.get_callbacks_for(sym, self) << cb
        end

        self.send :define_method, rem_sym do |cb|
          self.class.get_callbacks_for(sym, self).delete cb
        end

        self.send ar_cb_sym do |rec|
          self.class.get_callbacks_for(sym, self).each{|cb|
            Proc === cb ? cb.call(rec) : cb.send(sym, rec)
          }
        end
      end
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

        def after_query_listeners
          @@after_query_listeners ||= []
        end

        def _fld_getter_proc(fld)
          if fld.transient?
            super
          else
            # defining associations will take care that super exists
            lambda {
              _fld_pre_read(fld)
              val = super()
              _fld_post_read(fld, val)
              val
            }
          end
        end

        def _fld_setter_proc(fld)
          if fld.transient?
            super
          else
            # defining associations will take care that super exists
            lambda { |val|
              _fld_pre_write(fld, val)
              super(val)
              _fld_post_write(fld, val)
            }
          end
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

      def _read_fld_value(fld)
        fail "not supposed to be used for persistent fields" if fld.persistent?
        if (self.id rescue false)
          red_meta.get_transient_value(self, fld)
        else
          super(fld)
        end
      end

      def _write_fld_value(fld, val)
        fail "not supposed to be used for persistent fields" if fld.persistent?
        if (self.id rescue false)
          red_meta.set_transient_value(self, fld, val)
        else
          super(fld, val)
        end
      end

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
    # == Class +RedRel+
    #
    #
    #-------------------------------------------------------------------
    class RedRel < Alloy::Relations::Relation
      def initialize(tuple_cls, *args)
        @tuple_cls = tuple_cls
        super(*args)
      end

      def [](idx)
        t = tuple_at(idx)
        if t.respond_to? :default_cast
          t.default_cast
        elsif t.arity == 1
          t.atom_at 0
        else
          t
        end
      end

      def []=(idx, val)
        t = tuple_at(idx)
        t.update_from(val)
        t.save!
      end

    end

    #-------------------------------------------------------------------
    # == Class +RedTuple+
    #
    # Note: It's ok to use +meta.fields+ instead of +meta.pfields+ since
    #       we know +RedTuple+ doesn't contain any transient fields.
    #-------------------------------------------------------------------
    class RedTuple < Record
      placeholder

      include Alloy::Relations::MTuple

      module Instance
        def arity
          self.class.arity
        end

        def values
          meta.fields.drop(1).map {|f| read_field(f) }
        end

        def tuple_at(idx)
          case idx
          when Integer
            read_field(meta.fields[idx+1])
          when Symbol, String
            fld = meta.field(idx.to_s)
            read_field(fld)
          when Range
            values[idx]
          else
            values[idx]
          end
        end

        def update_from(val)
          tuple = val.as_tuple
          raise Alloy::Ast::TypeError, "Arity mismatch" if tuple.arity != arity

          tuple.values.each_with_index do |obj, idx|
            write_field(meta.fields[idx+1], obj)
          end
        end

        def default_cast
          self
        end
      end

      include Instance

      # =========================================================================
      #  static stuff
      # =========================================================================

      class << self

        def for_field=(fld) meta.extra[:for_field] = fld end
        def for_field()     meta.extra[:for_field] end

        def arity
          meta.fields.size - 1
        end

        # ----------------------------------------------------
        # Assumes a cast from a relation, and returns a relation
        #
        # @return [Alloy::Relations::MRelation]
        # ----------------------------------------------------
        def cast_from_rel(val)
          return val if val.kind_of? self

          #TODO: or raise error?
          #unlikely that they will be tuples with 0 arity
          return self.new(0, []) if arity == 0

          rel = val.as_rel
          raise Alloy::Ast::TypeError, "Arity mismatch" if rel.arity != arity

          tuple_set = rel.tuples.map do |t|
            cast_from(t)
          end

          RedRel.new(self, arity, tuple_set)
        end

        # ----------------------------------------------------
        # Assumes a cast from a tuple
        #
        # @return [self]
        # ----------------------------------------------------
        def cast_from(val)
          return val if val.kind_of? self

          me = self.new
          me.update_from(val)
          me
        end

        def default_cast_rel(val)
          RedRel.new(self, arity, val.map { |e| e.as_tuple })
        end
      end
    end

    #-------------------------------------------------------------------
    # == Class +RedSeqTuple+
    #
    # Note: It's ok to use +meta.fields+ instead of +meta.pfields+ since
    #       we know +RedSeqTuple+ doesn't contain any transient fields.
    #-------------------------------------------------------------------
    class RedSeqTuple < RedTuple
      placeholder

      # -----------------------------------------------------------------
      # Assumes a cast from a relation.  Handles a special case when
      # `val' is array, in which case instead of +as_rel+,
      # +Array#as_rel_with_index+ is used.
      #
      # @return [Alloy::Relations::Relation]
      # -----------------------------------------------------------------
      def self.cast_from_rel(val)
        return val if val.kind_of? self
        case val
        when Array
          super(val.as_rel_with_index)
        else
          super(val)
        end
      end

      # ----------------------------------------------------------------
      # Assumes a cast from a tuple.  Handles a special case when
      # `val' unary only assignes the range field to it.
      #
      # @return [self]
      # ----------------------------------------------------------------
      def update_from(val)
        tuple = val.as_tuple
        if tuple.arity == 1
          write_field(meta.fields[2], tuple.atom_at(0))
        else
          super(val)
        end
      end

      def self.cast_from(val)
        return val if val.kind_of? self
        case val
        when Array
          super(0.as_tuple.tuple_product(val.as_tuple))
        else
          super(val)
        end
      end

      # ----------------------------------------------------------------
      #
      # @return [Array]
      # ----------------------------------------------------------------
      def default_cast
        #TODO what if there are more than 1 field (beside the index field)?
        read_field(meta.fields[2])
      end

    end

    #-------------------------------------------------------------------
    # == Class +Relation+
    #
    #
    #-------------------------------------------------------------------
    class Relation < Alloy::Relations::Relation
      def initialize(arity, tuples)
        super
      end

      def self.default_cast_to(val)
        #TODO
        val
      end

      #TODO remove
      # assumes a cast from a relation
      def self.cast_from(val, tuple_cls)
        return val if val.kind_of? self
        arity = tuple_cls.arity

        #TODO: or raise error?
        #unlikely that they will be tuples with 0 arity
        return self.new(0, []) if arity == 0

        rel = val.as_rel
        fld0 = tuple_cls.meta.fields[0]
        if (rel.arity == arity - 1) &&
            (val.kind_of? Array) &&
            (fld0.type.arity == 1) &&
            (fld0.type.domain.klass == Integer)
          rel = val.as_rel_with_index
        end

        raise Alloy::Ast::TypeError if rel.arity != arity

        tuple_set = rel.tuples.map { |t| tuple_cls.cast_from(t) }
        self.new(arity, tuple_set)
      end
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
