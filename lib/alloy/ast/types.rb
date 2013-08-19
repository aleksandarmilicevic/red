require 'date'
require 'sdg_utils/lambda/proc'

module Alloy
  module Ast

    #------------------------------------------
    # == Module AType
    #------------------------------------------
    module AType
      include Enumerable

      @@DEFAULT_MULT = :lone

      def self.get(obj)
        case obj
        when Proc; DependentType.new(obj)
        when AType; obj
        else
          UnaryType.new(obj)
        end
      end

      def self.included(base)
        base.extend(SDGUtils::Lambda::Class2Proc)
      end

      def to_ruby_type
        map(&:klass)
      end

      def ==(other)
        return false unless AType === other
        to_ruby_type == other.to_ruby_type
      end

      def hash
        to_ruby_type.hash
      end

      def instantiated?() true end

      def arity()      fail "must override" end
      def column!(idx) fail "must override" end

      def unary?() arity == 1 end
      def binary?() arity == 2 end
      def ternary?() arity == 3 end

      def primitive?() false end
      def isInt?()     false end
      def isFloat?()   false end
      def isString?()  false end
      def isText?()    false end
      def isDate?()    false end
      def isTime?()    false end
      def isBool?()    false end
      def isBlob?()    false end
      def isFile?()    false end

      # @return [Symbol]
      def multiplicity() @@DEFAULT_MULT end
      def remove_multiplicity() self end

      def scalar?
        case multiplicity
        when :one, :lone
          true
        else
          false
        end
      end

      def seq?;  multiplicity == :seq end
      def set?;  multiplicity == :set end
      def one?;  multiplicity == :one end
      def lone?; multiplicity == :lone end

      # Returns a +UnaryType+ at the given position.
      #
      # @param idx [Integer] - position, must be in [0..arity)
      # @return [UnaryType]
      def column(idx)
        raise ArgumentError, "index out of scope, idx=#{idx}, arity=#{arity}" \
          if idx < 0 || idx >= arity
        column!(idx)
      end

      def domain; column!(0) end
      def range; column!(arity - 1) end

      def full_range
        drop(1).reduce(nil) do |acc, utype|
          acc ? ProductType.new(acc, utype) : utype
        end
      end

      def inv
        reduce(nil) do |acc, utype|
          acc ? ProductType.new(utype, acc) : utype
        end
      end

      def each
        for idx in 0..arity-1
           yield column!(idx)
        end
      end

      def *(rhs)
        case rhs
        when AType
          ProductType.new(self, rhs)
        when Class
          ProductType.new(self, UnaryType.new(rhs))
        when Symbol
          ProductType.new(self, UnaryType.new(rhs))
        else
          raise NoMethodError, "undefined multiplication of AType and #{rhs.class.name}"
        end
      end

      def to_alloy
        case self
        when UnaryType
          self.cls.to_s.relative_name
        when ProductType
          if self.rhs.arity > 1
            "#{lhs.to_alloy} -> (#{rhs.to_alloy})"
          else
            "#{lhs.to_alloy} -> #{rhs.to_alloy}"
          end
        when ModType
          if @type.arity > 1
            "#{@mult} (#{@type.to_alloy})"
          else
            "#{@mult} #{@type.to_alloy}"
          end
        end
      end
    end

    class DependentType
      include SDGUtils::Delegate
      include AType

      def initialize(proc, inst=nil)
        @proc = proc
        @inst = inst
        if inst
          delegate :arity, :column!, :to => lambda{@proc.call(inst)}
        else
          class << self
            def arity()      0 end
            def column!(idx) fail "Dependent type not instantiated" end
          end
        end
      end

      def instantiate(inst)
        DependentType.new(@type, inst)
      end

      def instantiated?() !@inst.nil? end
      def my_proc() @proc end
      def my_inst() @inst end
    end

    #------------------------------------------
    # == Class UnaryType
    #
    # @attr_reader cls [ColType]
    #------------------------------------------
    class UnaryType
      include AType

      #TODO: rename to something more sensical
      attr_reader :cls

      #----------------------------------------------------------
      # == Class +ColType+
      #
      # @attr_reader src [Object]  - whatever source was used to
      #                              create this this +ColType+
      # @attr_reader klass [Class] - corresponding +Class+
      #----------------------------------------------------------
      class ColType
        attr_reader :src, :klass

        def initialize(src)
          @src = src
          @klass = nil
        end

        def self.inherited(subclass)
          subclass.instance_eval do
            def initialize(src)
              super
            end
          end
        end

        class PrimitiveColType < ColType
        end

        def self.prim(kls, def_val)
          cls = Class.new(PrimitiveColType)
          cls.send(:define_singleton_method, :klass, lambda{kls})
          cls.send(:define_method, :klass, lambda{kls})
          cls.send(:define_method, :default_value, lambda{def_val})
          cls
        end

        class IntColType           < prim(Integer, 0); end
        class FloatColType         < prim(Float, 0.0); end
        class StringColType        < prim(String, ""); end
        class TextColType          < prim(String, ""); end
        class BoolColType          < prim(Integer, false); end
        class DateColType          < prim(Date, nil); end
        class TimeColType          < prim(Time, nil); end
        class BlobColType          < prim(Array, nil); end
        class RefColType           < ColType
          def klass; src end
        end

        class UnresolvedRefColType < ColType
          attr_reader :mod
          def initialize(src, mod)
            super(src)
            @mod = mod
            @klass = nil
          end
          def klass
            msg  = "`klass' method not available for #{self}:#{self.class}.\n"
            msg += "Did you forget run Red::Initializer.resolve_fields?"
            fail msg
          end
        end

        @@built_in_types = {
          :Int     => IntColType.new(:Int),
          :Integer => IntColType.new(:Integer),
          :Float   => FloatColType.new(:Float),
          :String  => StringColType.new(:String),
          :Text    => TextColType.new(:Text),
          :Bool    => BoolColType.new(:Bool),
          :Boolean => BoolColType.new(:Boolean),
          :Date    => DateColType.new(:Date),
          :Time    => TimeColType.new(:Time),
          :Blob    => BlobColType.new(:Blob),
        }

        def self.get(sym)
          case sym
          when NilClass
            raise TypeError, "nil is not a valid type"
          when ColType
            sym
          when Class
            if sym == Integer
              IntColType.new(sym)
            elsif sym == Float
              FloatColType.new(sym)
            elsif sym == String
              StringColType.new(sym)
            elsif sym == Date
              DateColType.new(sym)
            elsif sym == Time
              TimeColType.new(sym)
            else
              RefColType.new(sym)
            end
          when String
            self.get(sym.to_sym)
          when Symbol
            builtin = @@built_in_types[sym]
            mgr = Alloy::Dsl::ModelBuilder.get
            builtin ||= UnresolvedRefColType.new(sym, mgr.scope_module)
          else
            raise TypeError, "`#{sym}' must be Class or Symbol or String, instead it is #{sym.class}"
          end
        end

        def primitive?
          kind_of? PrimitiveColType
        end

        # Returns string representing corresponding database type
        # supported by +ActiveRecord+.
        def to_db_s
          case self
          when IntColType;     "integer"
          when FloatColType;   "float"
          when StringColType;  "string"
          when TextColType;    "text"
          when DateColType;    "date"
          when TimeColType;    "time"
          when BoolColType;    "boolean"
          when BlobColType;    "binary"
          else
            @src.to_s.relative_name
          end
        end

        def to_ember_s
          case self
          when IntColType, FloatColType;    "number"
          when StringColType, TextColType;  "string"
          when DateColType, TimeColType;    "date"
          when BoolColType;                 "boolean"
          else
            #TODO fail?
            "string"
          end
        end

        def from_str(str)
          case self
          when IntColType;    Integer(str)
          when FloatColType;  Float(str)
          when StringColType; str
          when TextColType;   str
          when DateColType;   nil #TODO
          when TimeColType;   nil #TODO
          when BoolColType;   str == "true" ? true : (str == "false" ? false : nil)
          when BlobColType;   nil #TODO
          else
            nil
          end
        end

        # Returns the database type converted to +Symbol+.
        def to_db_sym
          to_db_s.to_sym
        end

        def to_s
          case self
          when IntColType; "Int"
          when StringColType; "String"
          when TextColType; "Text"
          when DateColType; "Date"
          else
            @src.to_s #TODO
          end
        end
      end

      def initialize(cls)
        @cls = ColType.get(cls)
        unless @cls.instance_of? ColType::UnresolvedRefColType
          freeze
        end
      end

      # Allowed to call this method only once, only to
      # update an unresolved type
      def update_cls(cls)
        @cls = ColType.get(cls)
        freeze
      end

      def klass()      @cls.klass end
      def arity()      1 end
      def column!(idx) self end

      def primitive?() @cls.primitive? end
      def isInt?()     scalar? && ColType::IntColType === @cls end
      def isFloat?()   scalar? && ColType::FloatColType === @cls end
      def isString?()  scalar? && ColType::StringColType === @cls end
      def isText?()    scalar? && ColType::TextColType === @cls end
      def isDate?()    scalar? && ColType::DateColType === @cls end
      def isTime?()    scalar? && ColType::TimeColType === @cls end
      def isBool?()    scalar? && ColType::BoolColType === @cls end
      def isBlob?()    scalar? && ColType::BlobColType === @cls end
      def isFile?()    scalar? && (klass.isFile?() rescue false) end

      def to_s
        @cls.to_s
      end
    end

    #------------------------------------------
    # == Class ProductType
    #------------------------------------------
    class ProductType
      include AType

      attr_reader :lhs, :rhs

      def self.new(lhs, rhs)
        return check_sub(rhs) if lhs.nil?
        return check_sub(lhs) if rhs.nil?
        super(lhs, rhs)
      end

      # @param lhs [AType]
      # @param rhs [AType]
      def initialize(lhs, rhs)
        check_sub(lhs)
        check_sub(rhs)
        @lhs = lhs
        @rhs = rhs
        freeze
      end

      def arity
        lhs.arity + rhs.arity
      end

      def column!(idx)
        if idx < lhs.arity
          lhs.column!(idx)
        else
          rhs.column!(idx-lhs.arity)
        end
      end

      def to_s
        if rhs.arity > 1
          "#{lhs.to_s} -> (#{rhs.to_s})"
        else
          "#{lhs.to_s} -> #{rhs.to_s}"
        end
      end

      private

      def self.check_sub(type)
        msg = "AType expected, got #{type.class}"
        raise ArgumentError, msg unless type.kind_of?(AType)
        type
      end

      def check_sub(x) self.class.check_sub(x) end
    end

    # ======================================================
    # == Class +NoType+
    # ======================================================
    class NoType
      include AType

      INSTANCE = allocate

      def arity() 0 end
      def klass() NilClass end

      def new() INSTANCE end
    end

    # ======================================================
    # == Class +ModType+
    #
    # Wraps another type and adds a multiplicity modifier
    # ======================================================
    class ModType
      include AType

      attr_reader :mult, :type

      # @param type [AType]
      # @param mult [Symbol]
      def initialize(type, mult)
        @type = type
        @mult = mult
        freeze
      end

      def arity()               @type.arity end
      def column!(idx)          @type.column!(idx) end
      def multiplicity()        @mult end
      def remove_multiplicity() @type end

      def to_s
        if @type.arity > 1
          "#{@mult} (#{@type.to_s})"
        else
          "#{@mult} #{@type.to_s}"
        end
      end
    end

    #-----------------------------------------------------
    # == Class +TypeChecker+
    #-----------------------------------------------------
    class TypeChecker
      def self.check_type(expected, actual)
        actual <= expected #TODO: incomplete
      end
    end

  end
end
