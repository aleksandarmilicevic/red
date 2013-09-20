require 'alloy/dsl/sig_builder'
require 'red/model/red_model'
require 'red/model/event_model'
require 'sdg_utils/delegator'
require 'sdg_utils/meta_utils'
require 'sdg_utils/random'

module Red
  module Model

    #-------------------------------------------------------------------
    # == Class +Rule+
    #
    # Rule
    #-------------------------------------------------------------------
    class Rule
      CONDITIONS = [:when, :unless]
      FILTERS    = [:select, :include, :reject, :exclude]

      attr_reader :field, :policy, :condition, :filter
      def initialize(field, policy, condition, filter)
        @field = field
        @policy = policy
        @condition = condition
        @filter = filter
      end

      def has_condition?()   !!_method(@condition) end
      def has_filter?()      !!_method(@filter) end
      def condition_kind()   _kind(@condition) end
      def filter_kind()      _kind(@filter) end
      def condition_method() _method(@condition) end
      def filter_method()    _method(@filter) end

      def self.cond(kind, method=nil)   kind ? {kind: kind, method: method} : nil end
      def self.filter(kind, method=nil) self.cond(kind, method) end

      def bind(policy)
        BoundRule.new(policy, self)
      end

      private

      def _kind(hash)   hash ? hash[:kind] : nil end
      def _method(hash) hash ? hash[:method] : nil end
    end

    #-------------------------------------------------------------------
    # == Class +BoundRule+
    #
    # Rule bound to a concrete policy instance
    #-------------------------------------------------------------------
    class BoundRule
      attr_reader :policy

      def initialize(policy, rule)
        @policy = policy
        @rule = rule
      end

      def check_condition(*args)
        if @rule.has_condition?
          check(@rule.condition_kind, @rule.condition_method, *args)
        else
          nil
        end
      end

      def check_filter(*args)
        if @rule.has_filter?
          check(@rule.filter_kind, @rule.filter_method, *args)
        else
          nil
        end
      end

      private

      def check(kind, method, *args)
        Red.boss.time_it("checking rule") do
          meth, meth_args = Red.boss.time_it("getting arity", method) do
            meth = @policy.send :method, method.to_sym
            meth_args = args[0...meth.arity]
            [meth, meth_args]
          end
          ans = Red.boss.time_it("executing rule method", method) do
            @policy.send method.to_sym, *meth_args
          end
          case kind
          # conditions
          when :when; ans
          when :unless; !ans
          # filters
          when :select, :include; !ans
          when :reject, :exclude; ans
          else fail "unknown condition kind: #{kind}"
          end
        end
      end

    end

    #-------------------------------------------------------------------
    # == Class +PolicyMeta+
    #
    # Meta information about policies.
    #-------------------------------------------------------------------
    class PolicyMeta < Alloy::Ast::SigMeta
      attr_accessor :principal

      def initialize(*args)
        super
        @field_restrictions = {}
      end

      def restrictions(field=nil)
        __restrictions(field).clone
      end

      def add_restriction(rule)
        __restrictions(rule.field) << rule
      end

      def freeze
        super
        @field_restrictions.freeze
      end

      private

      def __restrictions(field)
        if field
          @field_restrictions[field] ||= []
        else
          @field_restrictions.values.flatten
        end
      end

    end

    # ===========================================================
    # == Module +PolicyDslApi+
    # ===========================================================
    module PolicyDslApi
      include Alloy::Dsl::SigDslApi
      include Alloy::Dsl::FunHelper

      def principal(hash)
        _check_single_fld_hash(hash, Red::Model::Machine)
        transient(hash)
        meta.principal = meta.field(hash.keys.first)
      end

      def restrict(*args, &block)
        opts =
          case
          when args.size == 1 && Hash === args[0]; args[0]
          when args.size == 2; {:field => args.first}.merge! args[1]
          else raise ArgumentError, "expected hash or a field and a hash"
          end
        opts = __normalize_opts(opts)
        fld = opts[:field]
        cond = opts[:condition]
        filter = opts[:filter]
        if block
          msg = "both :condition and :filter, and block given"
          raise ArgumentError, msg if cond && filter
          poli = cond || filter
          raise ArgumentError, "both :method and block given" if poli[:method]
          salt = SDGUtils::Random.salted_timestamp
          method_name = :"restrict_#{fld.to_iden}_#{poli[:kind]}_#{salt}"
          pred(method_name, &block)
          poli[:method] = method_name
        end
        rule = Rule.new(fld, self, cond, filter)
        meta.add_restriction(rule)
      end

      protected

      def __created()
        super
        Red.meta.add_policy(self)
      end

      def __finish
        meta.freeze
        instance_eval <<-RUBY, __FILE__, __LINE__+1
          def principal() meta.principal end
        RUBY
      end

      private

      def __normalize_opts(opts)
        fld = opts[:field]
        raise ArgumentError, "field not specified" unless fld
        msg = "expected `Field', got #{fld}:#{fld.class}"
        raise ArgumentError, msg unless Alloy::Ast::Field === fld

        cond_keys = opts.keys.select{|e| Rule::CONDITIONS.member? e}
        filter_keys = opts.keys.select{|e| Rule::FILTERS.member? e}
        msg = "more than one %s specified: %s"
        raise ArgumentError, msg % ["condition", cond_keys] if cond_keys.size > 1
        raise ArgumentError, msg % ["filter", filter_keys] if filter_keys.size > 1

        cond_key = cond_keys[0]
        filter_key = filter_keys[0]
        cond = opts[:condition]
        filter = opts[:filter]
        msg = "both :%s and :%s keys given; use either one or the other form"
        raise ArgumentError, msg % [:condition, cond_key] if cond && cond_key
        raise ArgumentError, msg % [:filter, filter_key] if filter && filter_key

        cond ||= Rule.cond(cond_key, opts[cond_key])
        filter ||= Rule.filter(filter_key, opts[filter_key])

        raise ArgumentError, "no condition specified" unless cond || filter

        { :field => fld }.
          merge!(cond ?   {:condition => cond} : {}).
          merge!(filter ? {:filter => filter}  : {})
      end
    end

    module PolicyStatic
      include Alloy::Ast::ASig::Static

      def instantiate(principal)
        self.new(principal)
      end

      def restrictions(*args) meta.restrictions(*args) end

      protected

      #------------------------------------------------------------------------
      # Defines the +meta+ method which returns some meta info
      # about this events's params and from/to designations.
      #------------------------------------------------------------------------
      def _define_meta()
        #TODO codegen
        meta = PolicyMeta.new(self)
        define_singleton_method(:meta, lambda {meta})
      end
    end

    #-------------------------------------------------------------------
    # == Class +Policy+
    #
    # Base class for all policies.
    #-------------------------------------------------------------------
    class Policy
      include Alloy::Ast::ASig
      extend PolicyStatic
      extend PolicyDslApi

      attr_reader :principal

      def initialize(principal)
        write_field(meta.principal, principal)
        @principal = principal
      end

      def restrictions(*args)
        self.class.restrictions(*args).map { |rule|
          rule.bind(self)
        }
      end
    end

    #-------------------------------------------------------------------
    # == Module +FieldRuleExt+
    #
    # Extensions for the Field class that adds methods for
    # generating policy conditions and filters.
    # -------------------------------------------------------------------
    module FieldRuleExt
      private

      def self.gen_cond(conds, filters)
        conds.each do |cond|
          self.module_eval <<-RUBY, __FILE__, __LINE__+1
def #{cond}
  {:field => self, :condition => #{Rule.cond(cond).inspect}}
end
RUBY
        end
        filters.each do |filter|
          self.module_eval <<-RUBY, __FILE__, __LINE__+1
def #{filter}
  {:field => self, :filter => #{Rule.filter(filter).inspect}}
end
RUBY
        end
      end

      gen_cond Rule::CONDITIONS, Rule::FILTERS
    end
    Alloy::Ast::Field.send :include, FieldRuleExt

  end
end
