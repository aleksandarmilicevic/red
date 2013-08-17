require 'alloy/alloy_event_constants.rb'
require 'alloy/ast/arg'
require 'alloy/ast/field'
require 'alloy/ast/fun'
require 'alloy/ast/sig_meta'
require 'alloy/utils/codegen_repo'
require 'sdg_utils/meta_utils'
require 'sdg_utils/random'

module Alloy
  module Ast

    #=========================================================================
    # == Module ASig::Static
    #=========================================================================
    module ASig

      module Builder
        protected

        # ---------------------------------------------------------
        # TODO: DOCS
        # ---------------------------------------------------------
        def fields(hash={}, &block)
          _traverse_fields hash, lambda { |name, type| field(name, type) }, &block
        end

        alias_method :persistent, :fields
        alias_method :refs, :fields

        def owns(hash={}, &block)
          _traverse_fields hash, lambda { |name, type|
            field(name, type, :owned => true)
          }, &block
        end

        def transient(hash={}, &block)
          _traverse_fields hash, lambda { |name, type|
            field(name, type, :transient => true)
          }, &block
        end

        # ---------------------------------------------------------
        # TODO: DOCS
        # ---------------------------------------------------------
        def field(*args)
          _traverse_field_args(args, lambda {|name, type, hash={}|
                                 _field(name, type, hash)})
        end

        alias_method :ref, :field

        def synth_field(name, type)
          field(name, type, :synth => true)
        end

        def abstract()    _set_abstract; self end
        def placeholder() _set_placeholder; self end

        # ---------------------------------------------------------
        # TODO: DOCS
        # ---------------------------------------------------------
        def pred(*args, &block)
          begin
            pred_opts = _to_fun_opts(*args, &block)
            pred = meta.add_pred pred_opts
            _define_method_for_fun(pred)
          rescue => ex
            raise SyntaxError.new(ex)
          end
        end

        def fun(*args, &block)
          begin
            fun_opts = _to_fun_opts(*args, &block)
            fun = meta.add_fun fun_opts
            _define_method_for_fun(fun)
          rescue => ex
            raise SyntaxError.new(ex)
          end
        end

        def invariant(&block)
          _define_method(:invariant, &block)
        end

        def method_missing(sym, *args, &block)
          return super unless @in_body
          return super unless args.empty? && block.nil?
          FunBuilder.new(sym)
        end

        private

        # if block is provided,
        #   args must contain a single symbol
        # else
        #   args should match to the +class_eval+ formal parameters
        def _define_method(*args, &block)
          old = @in_body
          @in_body = false
          begin
            if block.nil?
              class_eval *args
            else
              define_method(args[0], &block)
            end
          rescue ::SyntaxError => ex
            src = block ? block.source : args[0]
            msg = "syntax error in:\n  #{src}"
            raise SyntaxError.new(ex), msg
          ensure
            @in_body = old
          end
        end

        #------------------------------------------------------------------------
        # For a given field (name, type) creates a getter and a setter
        # (instance) method, and adds it to this sig's +meta+ instance.
        #
        # @param fld_name [String]
        # @param fld_type [AType]
        #------------------------------------------------------------------------
        def _field(name, type, hash={})
          fld = meta.add_field(name, type, hash)
          fld_accessors fld
          fld
        end

        def _fld_reader_code(fld) "@#{fld.getter_sym}" end
        def _fld_writer_code(fld, val) "@#{fld.getter_sym} = #{val}" end

        def _traverse_fields(hash, cont, &block)
          _traverse_fields_hash(hash, cont)
          unless block.nil?
            ret = block.call
            _traverse_fields_hash(ret, cont)
          end
          nil
        end

        def _traverse_fields_hash(hash, cont)
          return unless hash
          hash.each do |k,v| 
            if Array === k
              k.each{|e| cont.call(e, v)}
            else
              cont.call(k, v) 
            end
          end
        end

        def _traverse_field_args(args, cont)
          case
          when args.size == 3
            cont.call(*args)
          when args.size == 2
            if Hash === args[0] && args[0].size == 1
              cont.call(*args[0].first, args[1])
            else
              cont.call(*args)
            end
          when args.size == 1 && Hash === args[0]
            name, type = args[0].first
            cont.call(name, type, Hash[args[0].drop 1])
          else
            msg = """
Invalid field format. Valid formats:
  - field name, type, options_hash={}
  - field name_type_hash, options_hash={}; where name_type_hash.size == 1
  - field hash                           ; where name,type = hash.first
                                           options_hash = Hash[hash.drop 1]
"""
            raise ArgumentError, msg
          end
        end

        def _set_abstract
          meta.set_abstract
        end

        def _set_placeholder
          _set_abstract
          meta.set_placeholder
        end

        # -----------------------------------------------------------------------
        # This is called not during class definition.
        # -----------------------------------------------------------------------
        def _add_inv_for_field(f)
          inv_fld = meta.add_inv_field_for(f)
          fld_accessors inv_fld
          inv_fld
        end

        def _to_args(hash)
          ans = []
          _traverse_fields_hash hash, lambda {|arg_name, type|
            arg = Arg.new :name => arg_name, :type => type
            ans << arg
          }
          ans
        end

        def _to_fun_opts(*args, &block)
          block = lambda{} unless block
          fun_opts =
            case
            when args.size == 1 && Hash === args[0]
              fa = _to_args(args[0][:args])
              args[0].merge :args => fa
            when args.size == 1 && Fun === args[0]
              args[0]
            when args.size == 1 && FunBuilder === args[0]
              fb = args[0]
              { :name => fb.name,
                :args => _to_args(fb.args),
                :ret_type => fb.ret_type }
            when args.size == 2
              # expected types: String, Hash
              fun_name = args[0]
              fun_args = _to_args(args[1])
              { :name => fun_name,
                :args => fun_args[0...-1],
                :ret_type => fun_args[-1].type }
            when args.size == 3
              # expected types: String, Hash, AType
              { :name => args[0],
                :args => _to_args(args[1]),
                :ret_type => args[2] }
            else
              raise ArgumentError, """
Invalid fun format. Valid formats:
  - fun(opts [Hash])
  - fun(fun [Fun])
  - fun(name [String], full_type [Hash])
  - fun(name [String], args [Hash], ret_type [AType])
"""
            end
          fun_opts.merge!({:body => block})
        end

        def _define_method_for_fun(fun)
          proc = fun.body || proc{}
          method_body_sym = "#{fun.name}_body__#{SDGUtils::Random.salted_timestamp}".to_sym
          _define_method method_body_sym, &proc

          if fun.arity == proc.arity
            _define_method fun.name.to_sym, &proc
          else
            raise ArgumentError, "number of function (#{fun.name}) formal parameters (#{fun.arity}) doesn't match the arity of the given block (#{proc.arity})" unless proc.arity == 0
            args_str = fun.args.map(&:name).join(", ")
            arg_map_str = fun.args.map{|a| "#{a.name}: #{a.name}"}.join(", ")
            _define_method <<-RUBY, __FILE__, __LINE__+1
              def #{fun.name}(#{args_str})
                shadow_methods_while({#{arg_map_str}}) do
                  #{method_body_sym}
                end
              end
            RUBY
          end
        end

      end

      module Static
        def inherited(subclass)
          super
          fail "The +meta+ method hasn't been defined for class #{self}" unless meta
          subclass.start
          meta.add_subsig(subclass)
        end

        def created()
          require 'alloy/alloy.rb'
          Alloy.meta.sig_created(self)
        end

        def method_missing(sym, *args, &block)
          return super unless args.empty? && block.nil?
          fld = meta.field(sym) || meta.inv_field(sym)
          return super unless fld
          fld_mth = (fld.is_inv?) ? "inv_field" : "field"
          self.instance_eval <<-RUBY, __FILE__, __LINE__+1
            def #{sym}()
              meta.#{fld_mth}(#{sym.inspect})
            end
          RUBY
          fld
        end

        # @see +SigMeta#abstract?+
        # @return [TrueClass, FalseClass]
        def abstract?() meta.abstract? end

        # @see +SigMeta#placeholder?+
        # @return [TrueClass, FalseClass]
        def placeholder?() meta.placeholder? end

        # @see +SigMeta#ignore_abstract+
        # @return [Class, NilClass]
        def oldest_ancestor(ignore_abstract=false)
          meta.oldest_ancestor(ignore_abstract)
        end

        # Returns highest non-placeholder ancestor of +self+ in the
        # inheritance hierarchy or self.
        def alloy_root
          meta.oldest_ancestor(false) || self
        end

        def all_supersigs()  meta.all_supersigs end
        def all_subsigs()  meta.all_subsigs end

        #------------------------------------------------------------------------
        # Defines a getter method for a field with the given symbol +sym+
        #------------------------------------------------------------------------
        def fld_accessors(fld)
          cls = Module.new
          fld_sym = fld.getter_sym
          find_fld_src = if fld.is_inv?
                           "meta.inv_field!(#{fld_sym.inspect})"
                         else
                           "meta.field!(#{fld_sym.inspect})"
                         end
          desc = {
            :kind => :fld_accessors,
            :target => self,
            :field => fld_sym
          }
          Alloy::Utils::CodegenRepo.eval_code cls, <<-RUBY, __FILE__, __LINE__+1, desc
          def #{fld_sym}
            intercept_read(#{find_fld_src}){
              #{_fld_reader_code(fld)}
            }
          end
          def #{fld_sym}=(value)
            intercept_write(#{find_fld_src}, value){
              #{_fld_writer_code(fld, 'value')}
            }
          end
          RUBY
          cls.send :alias_method, "#{fld_sym}?".to_sym, fld_sym if fld.type.isBool?
          self.send :include, cls
        end

        def method_added(name)
          return unless @in_body
          meth = self.instance_method(name)
          fun_args = meth.parameters.map{ |mod, sym|
            Arg.new :name => sym, :type => NoType.new
          }
          meta.add_fun :name     => name,
                       :args     => fun_args,
                       :ret_type => NoType.new,
                       :body     => meth.bind(allocate).to_proc
        end

        def start()  _define_meta() end
        def finish() end
        def eval_body(&block)
          @in_body = true
          begin
            self.class_eval &block
          ensure
            @in_body = false
          end
        end

        #------------------------------------------------------------------------
        # Returns a string representation of this +Sig+ conforming to
        # the Alloy syntax
        #------------------------------------------------------------------------
        def to_alloy
          psig = superclass
          psig_str = (psig != Sig.class) ? "extends #{psig.relative_name} " : ""
          <<-EOS
sig #{relative_name} #{psig_str} {
#{meta.fields_to_alloy}

// inv fields (synthesized)
/*
#{meta.inv_fields_to_alloy}
*/
}
EOS
        end

        #------------------------------------------------------------------------
        # Defines the +meta+ method which returns some meta info
        # about this sig's fields
        #------------------------------------------------------------------------
        def _define_meta()
          meta = Alloy::Ast::SigMeta.new(self)
          define_singleton_method(:meta, lambda {meta})
        end

        #------------------------------------------------------------------------
        # Checks whether the specified hash contains exactly one
        # entry, whose key is a valid identifier, and whose value is a
        # subtype of the specified type (`expected_type')
        # ------------------------------------------------------------------------
        def _check_single_fld_hash(hash, expected_type)
          msg1 = "Hash expected, got #{hash.class} instead"
          msg2 = "Expected exactly one entry, got #{hash.length}"
          raise ArgumentError, msg1 unless hash.kind_of? Hash
          raise ArgumentError, msg2 unless hash.length == 1

          varname, type = hash.first
          msg = "`#{varname}' is not a proper identifier"
          raise ArgumentError, msg unless SDGUtils::MetaUtils.check_identifier(varname)
          Alloy::Ast::TypeChecker.check_type(expected_type, type)
        end
      end
    end

    #------------------------------------------
    # == Module ASig
    #------------------------------------------
    module ASig
      include SDGUtils::ShadowMethods

      def self.included(base)
        base.extend(Alloy::Dsl::StaticHelpers)
        base.extend(Static)
        base.send :include, Alloy::Dsl::InstanceHelpers
        base.start
      end

      def meta
        self.class.meta
      end

      def initialize(*args)
        super
        init_default_transient_values
      end

      def read_field(fld)       send Alloy::Ast::Field.getter_sym(fld) end
      def write_field(fld, val) send Alloy::Ast::Field.setter_sym(fld), val end

      protected

      include Alloy::EventConstants

      def intercept_read(fld)
        _fld_pre_read(fld)
        value = yield
        _fld_post_read(fld, value)
        value
      end

      def intercept_write(fld, value)
        _fld_pre_write(fld, value)
        yield
        _fld_post_write(fld, value)
      end

      def _fld_pre_read(fld)
        Alloy.boss.fire E_FIELD_TRY_READ, :object => self, :field => fld
        _check_fld_read_access(fld)
      end

      def _fld_pre_write(fld, val)
        Alloy.boss.fire E_FIELD_TRY_WRITE, :object => self, :field => fld, :value => val
        _check_fld_write_access(fld, val)
      end

      def _fld_post_read(fld, val)
        Alloy.boss.fire E_FIELD_READ, :object => self, :field => fld, :return => val
      end

      def _fld_post_write(fld, val)
        Alloy.boss.fire E_FIELD_WRITTEN, :object => self, :field => fld, :value => val
      end

      def init_default_transient_values
        meta.tfields.each do |tf|
          if tf.type.unary? && tf.type.range.cls.primitive?
            val = tf.type.range.cls.default_value
            self.write_field(tf, val)
          end
        end
      end

      # checks field read access and raises an error if a violation is detected
      def _check_fld_read_access(fld)
        #TODO
        true
      end

      # checks field write access and raises an error if a violation is detected
      def _check_fld_write_access(fld, value)
        #TODO
        true
      end

    end

    #================================================================
    # == Class Sig
    #================================================================
    class Sig
      include ASig
      extend ASig::Static
      extend ASig::Builder
      meta.set_placeholder
    end

    def self.create_sig(name, super_cls=Alloy::Ast::Sig)
      cls = Class.new(super_cls)
      SDGUtils::MetaUtils.assign_const(name, cls)
      cls.created if cls.respond_to? :created
      cls
    end

  end
end
