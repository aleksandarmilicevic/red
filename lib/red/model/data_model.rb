require 'active_record'
require 'alloy/alloy_ast'
require 'alloy/alloy_ast_errors'
require 'alloy/utils/codegen_repo'
require 'sdg_utils/proxy'
require 'sdg_utils/delegator'

module Red
  module Model

    #-------------------------------------------------------------------
    # == Module +ObjCallbacks+
    #
    #-------------------------------------------------------------------
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

        desc = {
          :kind => :record_obj_callbacks,
          :callback => ar_cb_sym
        }
        Alloy::Utils::CodegenRepo.eval_code self, <<-RUBY, __FILE__, __LINE__+1, desc
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
    end

    #============================================================
    # == Module +RecordBuilder+
    #
    # Includes ASig::Builder and overrides some private methods
    # to customize processing of fields.
    #============================================================
    module RecordBuilder
      include Alloy::Ast::ASig::Builder

      private

      def _field(*args)
        fld = super
        attr_accessible fld.getter_sym if fld.transient?
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
    end

    #============================================================
    # == Module +RecordStatic+
    #
    # Static (class) methods for the Record class
    #============================================================
    module RecordStatic
      include Alloy::Ast::ASig::Static

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
      extend Red::Model::RecordStatic
      extend Red::Model::RecordBuilder

      gen_obj_callback :after_save
      gen_obj_callback :after_destroy
      gen_obj_callback :after_elem_appended, :not_activerecord_cb => true

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
  end
end
