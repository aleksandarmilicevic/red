require 'alloy/dsl/sig_builder'
require 'red/model/red_model'
require 'red/model/event_model'
require 'sdg_utils/proxy'
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
      OP_READ, OP_WRITE, OP_BOTH = :read, :write, :both
      OPERATIONS                 = [OP_READ, OP_WRITE, OP_BOTH]

      COND_WHEN, COND_UNLESS     = :when, :unless
      CONDITIONS                 = [COND_WHEN, COND_UNLESS]

      F_SEL, F_INC, F_REJ, F_EXC = :select, :include, :reject, :exclude
      FILTERS                    = [F_SEL, F_INC, F_REJ, F_EXC]

      attr_accessor :policy

      def initialize(policy)
        @policy        = policy
        @operation     = OP_BOTH
        @negated       = false

        raise ArgumentError, "policy not given" unless @policy
      end

      def freeze
        super
        raise ArgumentError, "Field checker not a Proc" unless Proc === @field_checker
        raise ArgumentError, "both :condition and :filter given" if @condition && @filter
      end

      # @param principal [Red::Model::Machine]
      # @param globals   [Hash<String, Object>]
      def instantiate(principal, globals={})
        self.bind(@policy.instantiate(principal, globals))
        # BoundRule.new(@policy.instantiate(principal, globals), self)
      end

      def desc(*args)          get_set(:desc, *args) end
      def operation(*args)     get_set(:operation, *args) end
      def condition(*args)     get_set(:condition, *args) end
      def filter(*args)        get_set(:filter, *args) end
      def field(*args)         get_set(:field, *args) end
      def field_checker(*args) get_set(:field_checker, *args) end
      def method(*args)        get_set(:method, *args) end
      def negate()             get_set(:negated, !negated?) end
      def negated?()           !!get_set(:negated) end

      def applies_for_read()  [OP_READ, OP_BOTH].member?(@operation) end
      def applies_for_write() [OP_WRITE, OP_BOTH].member?(@operation) end

      def applies_to_field(f) field_checker()[f] end

      def has_desc?()        !!@desc end
      def has_method?()      !!@method end
      def has_condition?()   !!@condition end
      def has_filter?()      !!@filter end
      def condition_kind()   @condition end
      def filter_kind()      @filter end

      def bind(policy)
        msg = "wrong kind of policy: expected #{@policy}, got #{policy.class}"
        raise ArgumentError, msg unless @policy === policy
        BoundRule.new(policy, self)
      end

      def unbind() self end

      private

      def get_set(prop, *args)
        if args.empty?
          self.instance_variable_get "@#{prop}"
        elsif args.size == 1
          self.instance_variable_set "@#{prop}", args.first
          self
        else
          fail "At most 1 arg accepted"
        end
      end
    end

    #-------------------------------------------------------------------
    # == Class +BoundRule+
    #
    # Rule bound to a concrete policy instance
    #-------------------------------------------------------------------
    class BoundRule < SDGUtils::Proxy
      attr_reader :policy, :rule

      def initialize(policy, rule)
        super(rule)
        @policy = policy
        @rule = rule
      end

      # Returns whether the rule is matched.  In terms of policies, who
      # only have restriction rule, if a rule is matched (the return value
      # of this method is +true+, access is forbidden.
      def check_condition(*args)
        if @rule.has_condition? && @rule.has_method?
          check(@rule.negated?, @rule.condition, @rule.method, *args)
        else
          fail "Either no condition or no method in #{@rule}"
        end
      end

      def check_filter(*args)
        if @rule.has_filter?
          check(@rule.negated?, @rule.filter, @rule.method, *args)
        else
          fail "Either no filter or no method in #{@rule}"
        end
      end

      def unbind() @rule end

      private

      def check(negate, kind, method, *args)
        Red.boss.time_it("checking rule") do
          meth = @policy.send :method, method.to_sym
          meth_args = args[0...meth.arity]
          meth_return = Red.boss.time_it("executing rule method", method) do
            @policy.send method.to_sym, *meth_args
          end
          ans = case kind
                  # conditions
                when :when; meth_return
                when :unless; !meth_return
                  # filters
                when :select, :include; !meth_return
                when :reject, :exclude; meth_return
                else fail "unknown condition kind: #{kind}"
                end
          negate ? !ans : ans
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
        @field_restrictions = []
        @globals            = []
      end

      # @param field [Alloy::Ast::Field, NilClass]
      def restrictions(field=nil)
        if field.nil?
          @field_restrictions.clone
        else
          ans = []
          @field_restrictions.each do |rule|
            ans << rule if rule.applies_to_field(field)
          end
          ans
        end
      end

      def global_var_names()
        @globals.clone
      end

      def add_globals(str_arr)
        @globals += str_arr
      end

      def add_restriction(rule)
        @field_restrictions << rule
        rule
      end

      def remove_restriction(rule)
        @field_restrictions -= [rule]
      end

      def freeze
        super
        @field_restrictions.freeze
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

      def global(hash)
        transient(hash)
        meta.add_globals(hash.keys)
      end

      def rw(*args, &block)
        rule = to_rule({operation: Rule::OP_BOTH}, *args)
        add_rule_block(rule, block) if block
        meta.add_restriction(rule.negate())
      end

      def read(*args, &block)
        rule = to_rule({operation: Rule::OP_READ}, *args)
        add_rule_block(rule, block) if block
        meta.add_restriction(rule.negate())
      end

      def write(*args, &block)
        rule = to_rule({operation: Rule::OP_WRITE}, *args)
        add_rule_block(rule, block) if block
        meta.add_restriction(rule.negate())
      end

      def restrict(*args, &block)
        rule = if args.size == 1 && Rule === args.first
                 meta.remove_restriction(args.first)
                 args.first.negate()
               else
                 to_rule({operation: Rule::OP_BOTH}, *args)
               end
        add_rule_block(rule, block) if block
        meta.add_restriction(rule)
      end

      protected

      def to_rule(def_opts, *args)
        desc = @desc; @desc = nil
        user_opts =
          case
          when args.size == 1 && Hash === args[0]
            args[0]
          when args.size == 1 && RuleBuilder === args[0]
            args[0].export_props
          when args.size == 2 && RuleBuilder === args[0] && Hash === args[1]
            args[0].export_props.merge!(args[1])
          when args.size == 2 && Alloy::Ast::Field === args[0] && Hash === args[1]
            {:field => args[0]}.merge!(args[1])
          else
            msg = "expected hash or a field and a hash, got #{args.map(&:class)}"
            raise ArgumentError, msg
          end
        opts = __normalize_opts(def_opts.merge(user_opts))
        Rule.new(self).
          desc(desc).
          operation(opts[:operation]).
          field(opts[:field]).
          field_checker(opts[:field_proc]).
          condition(opts[:condition]).
          filter(opts[:filter]).
          method(opts[:method])
      end

      def add_rule_block(rule, block)
        fld_iden = rule.field() ? rule.field().to_iden : "fld_proc"
        cond = rule.condition || rule.filter || ""
        raise ArgumentError, "can't add block, rule has method" if rule.has_method?
        salt = SDGUtils::Random.salted_timestamp
        method_name = :"restrict_#{fld_iden}_#{cond}_#{salt}"
        pred(method_name, &block)
        rule.method(method_name)
        rule
      end

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
        op       = opts[:operation]
        raise ArgumentError, "operation not specified" unless op

        fld      = opts[:field]
        fld_proc = opts[:field_proc]
        raise ArgumentError, "field not specified" unless fld || fld_proc

        msg = "expected `Field' got #{fld.class}"
        raise ArgumentError, msg unless fld.nil? || Alloy::Ast::Field === fld

        fld_proc ||= proc{|f| f == fld}
        raise ArgumentError, "expected `Proc' got #{fld.class}" unless Proc === fld_proc

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

        cond   ||= cond_key
        filter ||= filter_key
        method = opts[cond_key] || opts[filter_key]

        raise ArgumentError, "no condition specified" unless cond || filter

        { :operation => op,
          :field => fld,
          :field_proc => fld_proc }.
          merge!(method ? {:method    => method} : {}).
          merge!(cond   ? {:condition => cond}   : {}).
          merge!(filter ? {:filter    => filter} : {})
      end
    end

    module PolicyStatic
      include Alloy::Ast::ASig::Static

      def instantiate(principal, globals={})
        self.new(principal, globals)
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

      def initialize(principal, globals={})
        @principal = principal
        @globals   = globals
        write_field(meta.principal, principal)
        globals.each do |fname, fvalue|
          fld=meta().field(fname) and write_field(fld, fvalue)
        end
      end

      def restrictions(*args)
        self.class.restrictions(*args).map { |rule|
          rule.bind(self)
        }
      end

      protected

      # don't track field accesses for policies
      def intercept_read(fld)       yield end
      def intercept_write(fld, val) yield end
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
  {:field => self, :condition => #{cond.inspect}}
end
RUBY
        end
        filters.each do |filter|
          self.module_eval <<-RUBY, __FILE__, __LINE__+1
def #{filter}
  {:field => self, :filter => #{filter.inspect}}
end
RUBY
        end
      end

      gen_cond Rule::CONDITIONS, Rule::FILTERS
    end
    Alloy::Ast::Field.send :include, FieldRuleExt

    #-------------------------------------------------------------------
    # == Class +RuleBuilder+
    #
    # Rule
    #-------------------------------------------------------------------
    class RuleBuilder
      def initialize(hash={})
        @props = hash.clone
      end

      def export_props()     @props.clone end

      def operation(arg=nil) get_set(:operation, arg) end
      def condition(arg=nil) get_set(:condition, arg) end
      def filter(arg=nil)    get_set(:filter, arg) end
      def field(arg=nil)     get_set(:field, arg) end

      def self.gen_cond(conds, filters)
        conds.each do |cond|
          self.module_eval <<-RUBY, __FILE__, __LINE__+1
def #{cond}
  condition(#{cond.inspect})
end
RUBY
        end
        filters.each do |filter|
          self.module_eval <<-RUBY, __FILE__, __LINE__+1
def #{filter}
  filter(#{filter.inspect})
end
RUBY
        end
      end

      gen_cond Rule::CONDITIONS, Rule::FILTERS

      private

      def get_set(prop, arg=nil)
        if arg.nil?
          @props[prop]
        else
          @props[prop] = arg
          self
        end
      end

    end


  end
end
