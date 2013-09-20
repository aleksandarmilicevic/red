require 'active_support/inflector/inflections'

require_relative 'red_model.rb'
require_relative 'red_meta_model.rb'

module Red
  module Model

    module TableUtil

      # ==========================================================================
      # Class +FldInfo+
      #
      # @attr scalar [Boolean]           - whether the field is scalar
      # @attr primitive [Boolean]        - whether the range of the field
      #                                    is of primitive type
      # @attr type [:attr,               - attribute stored in a column in the
      #                                    same table
      #             :own_one,            - owning scalar reference, foreign key
      #                                    stored in this table, deletion propagated
      #             :own_many,           - owning set of references, foreign key
      #                                    stored in the referenced table, deletion
      #                                    propagated
      #             :ref_one,            - scalar reference, foreign key stored in
      #                                    this table, deletion not propagated
      #             :ref_many]           - set of references, join table is needed
      # @attr field [Symbol]            - name of the field in the model
      # @attr column [Symbol]           - name to use as the column name in the DB
      # @attr range_class [String]      - name of the range class
      # @attr range_base_class [String] - name of the range base (root) class
      # @attr col_type [String]         - db type for a primitive scalar field
      # @attr join_table [String]       - name of the join table in when the field
      #                                   is not scalar
      #
      # @invariant #TODO
      # ==========================================================================
      class FldInfo
        attr_accessor :scalar, :primitive, :polymorphic

        attr_accessor :type
        attr_accessor :prime_inf

        # these are always populated
        attr_accessor :field, :column, :range_class, :range_base_class

        # these are populated only if @type == :attr
        attr_accessor :col_type

        # these are popluated only if @type == :join
        attr_accessor :join_table
        attr_accessor :join_domain_field, :join_range_field
        attr_accessor :join_domain_column, :join_range_column

        def scalar?()      @scalar      end
        def primitive?()   @primitive   end
        def polymorphic?() @polymorphic end

        def attr?()              @type == :attr end
        def own_one?()           @type == :own_one end
        def ref_one?()           @type == :ref_one end
        def own_many?()          @type == :own_many end
        def ref_many?()          @type == :ref_many end
        def single_owned?()      @type == :single_owned end
        def refd_by_many?()      @type == :refd_by_many end
        def one_of_many_owned?() @type == :one_of_many_owned end
        def to_one?()            own_one?  || ref_one? || one_of_many_owned? end
        def to_many?()           own_many? || ref_many? end

        # def join?() ref_many? end

        def field()    @field.to_sym end
        def column()   @column.to_sym end
        def col_type() @col_type.to_sym end
        def join_domain_column() @join_domain_column.to_sym end
        def join_range_column()  @join_range_column.to_sym end
        def join_domain_field()  @join_domain_field.to_sym end
        def join_range_field()   @join_range_field.to_sym end
      end

      class << self

        def red_seq_pos_column_name
          'position'
        end

        # Model name for a given model class.
        #
        # @param cls [Class < Record]
        def red_model_name(cls)
          cls.name
        end

        # Table name for a given model class.
        #
        # @param cls [Class < Record]
        def red_table_name(cls)
          cls.relative_name.tableize
        end

        # Name to use when referencing the table corresponding to +cls+.
        #
        # @param cls [Class < Record]
        def red_ref_name(cls)
          cls.relative_name.underscore
        end

        # @param cls [Class < Record]
        def red_key_col_name(cls)
          red_foreign_key_name(red_ref_name(cls))
        end

        # @param fld [String, Symbol, Field]
        def red_foreign_key_name(fld)
          case fld
          when String
            fld + "_id"
          when Symbol
            red_foreign_key_name(fld.to_s)
          else
            if fld.respond_to? :name
              red_foreign_key_name(fld.name)
            else
              msg = "expected [Field, String, Symbol], got #{fld.class}"
              raise ArgumentError, msg
            end
          end
        end

        # @param src_cls [Class < Record]
        # @param fld [Field]
        def red_join_table_name(src_cls, fld)
          dst_cls = fld.type.range.cls.klass
          name = "#{src_cls.red_table_name}_#{dst_cls.red_table_name}"
          no_with_same_range = src_cls.meta.fields.none? do |f|
            f!=fld && f.type.range.cls.klass==dst_cls
          end
          unless Red.conf[:omit_field_name_in_join_table_names] && no_with_same_range
            name += "_#{fld.name}"
          end
          name
        end

        # Simply dispatches to fld_table_info_[1,2] based on the
        # number of arguments.
        def fld_table_info(*args)
          case args.size
          when 1
            fld_table_info_1(args[0])
          when 2
            fld_table_info_2(*args)
          else
            raise ArgumentError
          end
        end

        # Returns various information about a given field relevant when
        # creating a corresponding DB column or join table.
        #
        # @param record_cls [Class < Record]
        # @param fld_name [String]
        def fld_table_info_2(record_cls, fld_name)
          fld = record_cls.meta.field(fld_name)
          fld_table_info(fld)
        end

        # Returns various information about a given field relevant when
        # creating a corresponding DB column or join table.
        #
        # @param fld [Field]
        def fld_table_info_1(fld)
          ret = basic_fld_inf(fld)

          if !fld.is_inv?
            add_prime_fld_inf(fld, ret)
          else
            prime_inf = fld_table_info_1(fld.inv)
            invert(ret, prime_inf)
          end
          ret
        end

        private

        def basic_fld_inf(fld)
          range_type = fld.type.range.cls
          range_klass = range_type.klass

          ret = FldInfo.new

          ret.primitive = range_type.primitive?
          ret.polymorphic = !range_klass.red_subclasses.empty? ||
                            (range_klass.red_root != range_klass)

          ret.field = fld.name
          ret.column = fld.red_foreign_key_name
          ret.range_class = range_type.klass.red_model_name
          ret.range_base_class = range_type.klass.red_root.red_model_name

          ret
        end

        def add_prime_fld_inf(fld, ret)
          range_type = fld.type.range.cls
          range_klass = range_type.klass

          if fld.type.scalar?
            ret.scalar = true
            if range_type.primitive?
              ret.type = :attr
              ret.col_type = range_type.to_db_s
            else
              if fld.belongs_to_parent?
                # foreign key is here
                ret.type = :own_one
              else
                # foreign key is here
                ret.type = :ref_one
              end
            end
          else
            ret.scalar = false
            if fld.belongs_to_parent?
              # foreign key is on the other side
              ret.type = :own_many
              ret.column = basic_fld_inf(fld.inv).column
            else
              # foreign key is in a join table whose info is determined here
              ret.type = :ref_many
              ret.join_table = red_join_table_name(fld.parent, fld)
              if fld.parent != range_type.klass
                dom_fld = fld.parent.red_ref_name
                range_fld = range_type.klass.red_ref_name
              else
                cname = fld.parent.red_ref_name
                dom_fld = "dom_#{cname}"
                range_fld = "range_#{cname}"
              end
              ret.join_domain_field  = dom_fld
              ret.join_range_field   = range_fld
              ret.join_domain_column = red_key_col_name(dom_fld)
              ret.join_range_column  = red_key_col_name(range_fld)
              ret.column             = ret.join_domain_column
            end
          end
        end

        def invert(ret, prime_inf)
          ret.prime_inf = prime_inf
          case
          when prime_inf.attr?
            fail "Should never happen"
          when prime_inf.own_one?
            ret.type = :single_owned
            ret.scalar = true
            ret.column = prime_inf.column # because foreign key is in prime_inf
          when prime_inf.ref_one?
            ret.type = :refd_by_many
            ret.scalar = false
            ret.column = prime_inf.column # because foreign key is in prime_inf
          when prime_inf.own_many?
            ret.type = :one_of_many_owned # foreign key is here
            ret.scalar = true
          when prime_inf.ref_many?
            ret.scalar = false
            ret.type = :ref_many
            ret.join_table         = prime_inf.join_table
            ret.join_domain_field  = prime_inf.join_range_field
            ret.join_domain_column = prime_inf.join_range_column
            ret.join_range_field   = prime_inf.join_domain_field
            ret.join_range_column  = prime_inf.join_domain_column
            ret.column             = ret.join_domain_column
          end
        end

  #TODO delete below

      #   # Returns various information about a given field relevant when
      #   # creating a corresponding DB column or join table.
      #   #
      #   # @param fld [Field]
      #   def _fld_table_info_1(fld)
      #     range_type = fld.type.range.cls
      #     range_klass = range_type.klass

      #     ret = FldInfo.new

      #     ret.scalar = fld.type.scalar?
      #     ret.primitive = range_type.primitive?
      #     ret.polymorphic = !range_klass.red_subclasses.empty? ||
      #                       (range_klass.red_root != range_klass)

      #     ret.field = fld.name
      #     ret.column = fld.red_foreign_key_name
      #     ret.range_class = range_type.klass.red_model_name
      #     ret.range_base_class = range_type.klass.red_root.red_model_name

      #     if fld.type.scalar?
      #       if range_type.primitive?
      #         ret.type = :attr
      #         ret.col_type = range_type.to_db_s
      #       else
      #         if fld.belongs_to_parent?
      #           ret.type = :own_one
      #         else
      #           ret.type = :ref_one
      #         end
      #       end
      #     else
      #       if fld.belongs_to_parent?
      #         ret.type = :own_many
      #       else
      #         ret.type = :ref_many
      #         ret.join_table = red_join_table_name(fld.parent, fld)
      #         if fld.parent != range_type.klass
      #           dom_fld = fld.parent.red_ref_name
      #           range_fld = range_type.klass.red_ref_name
      #         else
      #           cname = fld.parent.red_ref_name
      #           dom_fld = "dom_#{cname}"
      #           range_fld = "range_#{cname}"
      #         end
      #         ret.join_domain_field = dom_fld
      #         ret.join_range_field = range_fld
      #         ret.join_domain_column = red_key_col_name(dom_fld)
      #         ret.join_range_column = red_key_col_name(range_fld)
      #       end
      #     end

      #     # special case for tuples: add the ownership
      #     if range_klass < Red::Model::RedTuple
      #       ret.type = case ret.type
      #                  when :ref_many; :own_many
      #                  when :ref_one; :own_one
      #                  else ret.type
      #                  end
      #     end
      #     ret
      #   end

      #   # @param col_type [ColType]
      #   # def tbl_column_info(col_type)
      #   #   ret = FldInfo.new
      #   #   ret.scalar = true
      #   #   if col_type.primitive?
      #   #     ret.primitive = true
      #   #     ret.col_type = col_type.to_db_sym
      #   #     ret.join_field = nil
      #   #     ret.ref_field = nil
      #   #   else
      #   #     ret.primitive = false
      #   #     ret.col_type = nil
      #   #     ret.join_table_name = nil
      #   #     ret.ref_table_name = col_type.klass.red_ref_name
      #   #   end
      #   #   ret
      #   # end
      end

    end

  end
end
