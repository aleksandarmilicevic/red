require 'alloy/alloy'
require 'alloy/relations/all'
require 'alloy/alloy_event_constants'
require 'red/model/red_model'
require 'sdg_utils/proxy'

module Red
  module Model

    class SetProxy < SDGUtils::Proxy
      def initialize(owner, field, value)
        super(value)
        @owner = owner
        @field = field
        @target = value
      end

      def arity() 1 end
      def tuples() @target.to_a end
      def unwrap() @target end

      def << (elem)
        @target << elem
        if Red::Model::Record === @owner
          @owner.class.trigger_after_elem_appended(@owner, @field, elem)
        end
      end
    end

    class RelationWrapper
      def self.wrap(owner, field, value)
        unless field.primitive?
          SetProxy.new(owner, field, value)
        else
          value
        end
      end
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
    class RedTuple < Red::Model::Record
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

  end
end
