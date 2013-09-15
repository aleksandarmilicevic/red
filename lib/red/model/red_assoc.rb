require 'sdg_utils/recorder'

require 'red/red_conf'
require 'red/model/relations'
require 'red/model/red_table_util'
require 'red/model/red_meta_model'

module Red
  module Model

    module Assoc
      extend self

      def expand_fields
        Red.meta.base_records.each { |r| add_impl_fields(r) }
      end

      def define_associations(hash={})
        log_debug "\nAdding associations:"
        Red.meta.base_records.each do |r|
          table_name = (r.oldest_ancestor || r).red_table_name
          r.send :table_name=, table_name.to_sym

          r.meta.pfields.each do |f|
            if f.has_impl?
              add_delegators(f)
            else
              add_associations(f)
            end
          end
          r.meta.inv_fields.each do |invf|
            if invf.inv.has_impl?
              add_inv_delegators(invf)
            else
              add_associations(invf)
            end
          end
          log "\n"
        end
      end

      protected

      # ---------------------------------------------------------------------
      # "Expand fields" stuff
      # ---------------------------------------------------------------------

      # @param record [Class < Record]
      def add_impl_fields(record)
        impl_fld_namer = Red.conf.impl_field_namer
        impl_cls_namer = Red.conf.impl_class_namer
        record.meta.pfields.each do |f|
          type = if f.type.seq?
                   Integer * f.type.remove_multiplicity
                 else
                   f.type
                 end
          unless type.unary?
            tuple_cls_name = impl_cls_namer.call(f)
            super_cls = if f.type.seq?
                          Red::Model::RedSeqTuple
                        else
                          Red::Model::RedTuple
                        end
            tuple_cls = Red::Model.create_record(tuple_cls_name, super_cls)
            tuple_cls.for_field = f
            add_tuple_fields(tuple_cls, record * type)
            log_debug "[expand_fields] #{f} expanded to #{type} via #{tuple_cls}"
            f.set_impl(lambda{tuple_cls.meta.fields[0].inv})
          end
        end
      end

      # @param tuple_cls [Class < RedTuple]
      # @param atype [AType]
      def add_tuple_fields(tuple_cls, atype)
        idx = 0
        atype.each do |utype|
          if utype.seq?
            tuple_cls.field tuple_fld_name(Integer, idx), Integer
            idx += 1
          end
          tuple_cls.send :field, tuple_fld_name(utype.klass, idx), utype.klass
          idx += 1
        end
      end

      def tuple_fld_name(cls, position)
        "#{cls.relative_name}_#{position}".underscore.to_sym
      end

      # ---------------------------------------------------------------------
      # "Add associations" stuff
      #
      # TODO: check if generated associations will override methods from
      #       ActiveRecord::Base (e.g., if there is a field called "connection"
      # ---------------------------------------------------------------------

      # @param fld [Field]
      def add_delegators(fld)
        return if fld.is_inv?
        # define getter
        fld.parent.send :define_method, fld.getter_sym, lambda {
          val = read_field(fld.impl)
          range_class = fld.impl.type.range.klass
          fldinf = Red::Model::TableUtil.fld_table_info(fld.impl)
          if fldinf.scalar?
            val.default_cast
          else
            # expecting val to be an array, so map default cast onto each elem
            range_class.default_cast_rel(val)
          end
        }

        # define setter
        fld.parent.send :define_method, fld.setter_sym, lambda { |val|
          range_class = fld.impl.type.range.klass
          fldinf = Red::Model::TableUtil.fld_table_info(fld.impl)
          val2 = if fldinf.scalar?
                   range_class.cast_from(val)
                 else
                   range_class.cast_from_rel(val).tuples
                 end
          write_field(fld.impl, val2)
        }
      end

      # @param fld [Field]
      def add_inv_delegators(inv_fld)
      end

      # @param fld [Field]
      def add_associations(fld)
        fldinf = Red::Model::TableUtil.fld_table_info(fld)
        opts = { :class_name => fldinf.range_class,
                 :foreign_key => fldinf.column }
        if fldinf.prime_inf && !fldinf.ref_many?
          opts.merge! :inverse_of => fldinf.prime_inf.field
        end
        if fld.type.range.klass < Red::Model::RedTuple
          opts.merge! :dependent => :destroy
        end

        record = wrap(fld.parent)
        case
        when fldinf.attr?              # ATTR
          record.send :attr_accessible, fldinf.field
        when fldinf.own_one?           # OWN_ONE: foreign key is here
          record.send :belongs_to, fldinf.field, opts.merge(:dependent => :destroy)
        when fldinf.ref_one?           # REF_ONE: foreign key is here
          record.send :belongs_to, fldinf.field, opts
        when fldinf.single_owned?      # SINGLE_OWNED: foreign key is on the other side
          record.send :has_one, fldinf.field, opts
        when fldinf.refd_by_many?      # REFD_BY_MANY: foreign key is on the other side
          record.send :has_many, fldinf.field, opts
        when fldinf.one_of_many_owned? # ONE_OF_MANY_OWNED: foreign key is here
          record.send :belongs_to, fldinf.field, opts
        when fldinf.own_many?          # OWN_MANY: foreign key is on the other side
          # TODO: :order => ''
          record.send :has_many, fldinf.field, opts.merge(:dependent => :destroy)
        when fldinf.ref_many?          # REF_MANY: foreign key is in a join table
          record.send :has_and_belongs_to_many, fldinf.field,
            opts.merge(:association_foreign_key => fldinf.join_range_column,
                       :join_table => fldinf.join_table)
        else
          fail "Internal error: unknown FieldInfo.type: #{fldinf.type}"
        end
      end

      private

      def wrap(obj)
        buff = Object.new
        buff.instance_variable_set "@target", obj
        def buff.<<(str)
          Alloy::Utils::CodegenRepo.record_code(str, @target, :kind => :assoc)
          SDGUtils::IO::LoggerIO.new(Red.conf.logger) << str
        end
        rec = SDGUtils::Recorder.new(:var => obj.to_s, :buffer => buff)
        SDGUtils::RecorderDelegator.new(obj, :recorder => rec)
      end

      def log(str)
        Red.conf.logger << str
      end

      def log_debug(str)
        Red.conf.logger.debug str
      end
    end

  end
end

