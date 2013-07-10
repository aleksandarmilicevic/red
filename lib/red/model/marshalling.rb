require 'sdg_utils/errors'

module Red
  module Model

    module Marshalling
      extend self

      class MarshallingError < SDGUtils::Errors::ErrorWithCause
      end

      # Converts string to boolean.  Returns `true' if and only if the
      # string is equal to "true" or "yes".
      def to_bool(str)
        str == 'true' || str == 'yes'
      end

      # Takes an object and tries to unmarshal it to the same type.
      # The only exception is that when the object is a Hash with
      # a key "is_record" set to "true", then it tries to unmarshal
      # it to a Record.
      #
      # @param obj [Object]
      def unmarshal_guess_type(obj)
        case obj
        when Array
          unmarshal_to_array(obj)
        when Hash
          if obj.delete("is_record")
            unmarshal_to_record(obj)
          else
            unmarshal_to_hash(obj)
          end
        else
          obj
        end
      end

      # TODO how do we serialize higher-arity types?
      #
      # Takes an object and an Alloy type (`AType') and tries to
      # unmarshal the object to match that type.
      #
      # For non-scalar types the object is unmarshalled to an `Array'.
      # For binary types the object is unmarshalled to a `Hash'.
      #
      # @param obj [Object]
      # @param obj [AType]
      def unmarshal(obj, atype=nil)
        return nil if obj.nil?
        case
        when atype.nil?
          unmarshal_guess_type(obj)
        when !atype.scalar?
          unmarshal_to_array(obj, atype.remove_multiplicity)
        when atype.unary?
          unmarshal_unary(obj, atype)
        when atype.binary?
          unmarshal_to_hash(obj, atype.column!(0), atype.column!(1))
        else
          unmarshal_guess_type(obj)
          # raise MarshallingError.new, "Higher-arity type: #{atype}"
        end
      end

      # Takes an object and an Alloy type and tries to unmarshal the
      # object either to a primitive value or a record.
      #
      # If `utype' is primitive, it attempts to convert `obj' to that
      # type.  Otherwise, it calls `unmarshal_to_record'.
      #
      # @param obj [Object]
      # @param utype [UnaryType]
      def unmarshal_unary(obj, utype)
        if utype.primitive?
          if obj.class == utype.klass
            obj
          else
            utype.cls.from_str(obj.to_s)
          end
        else
          klass = utype.klass
          case
          when klass <= Array
            unmarshal_to_array(obj)
          when klass <= Hash
            unmarshal_to_hash(obj)
          when klass <= Red::Model::Record
            unmarshal_to_record(obj, klass)
          when klass == Object
            obj
          else
            raise MarshallingError.new, "Unsupported unary class type: #{klass}"
          end
        end
      end

      # Takes an object and two Alloy types (for lhs and rhs) and
      # tries to unmarshal the object to a Hash mapping elements of
      # `lhs_type' to elements of `rhs_type'.
      #
      # Besides hashes, it can also convert an array if lhs_type is
      # indeed Integer.
      #
      # @param obj [Object]
      # @param lhs_utype [UnaryType]
      # @param rhs_utype [UnaryType]
      def unmarshal_to_hash(obj, lhs_utype=nil, rhs_utype=nil)
        case obj
        when Hash
          hash = obj
          hash.reduce({}) do |acc, keyval|
            ukey = unmarshal(keyval[0], lhs_utype)
            uval = unmarshal(keyval[1], rhs_utype)
            acc.merge!({ukey => uval})
          end
        when Array
          msg = "Unmarhsalling array to hash when lhs is not Int (lhs type: #{lhs_type})"
          raise MarshallingError.new, msg if lhs_utype && !lhs.isInt?
          arry = obj
          arry.reduce({}) do |acc, elem|
            acc.merge! acc.size => unmarshal(elem, rhs_utype)
          end
        else
          raise MarshallingError.new, "Unmarshalling #{obj.class} to Hash"
        end
      end

      # Takes an object and an Alloy type and tries to unmarshal the
      # object to an array of elements of `elem_utype' type.
      #
      # If `utype' is primitive, it attempts to convert `obj' to that
      # type.  Otherwise, it calls `unmarshal_to_record'.
      #
      # @param obj [Object]
      # @param elem_utype [UnaryType]
      def unmarshal_to_array(obj, elem_utype=nil)
        case obj
        when Array; obj.map {|e| unmarshal(e, elem_utype)}
        when Hash
          hash = obj
          (0...hash.size).map do |idx|
            val = hash[idx] || hash["#{idx}"]
            unmarshal(val, elem_utype)
          end
        else
          raise MarshallingError.new, "can't unmarhsal #{obj.inspect} to Array"
        end
      end

      # Takes an object and a Record class and tries to unmarshal the
      # object to an instance of that record class
      #
      # If `obj' is an `Integer', it tries to find a record of
      # `rec_cls' class with that id.
      #
      # If `obj' is a `String' of a `Symbol', it tries to convert it
      # to Integer and find a record with that id.
      #
      # If `obj' is a `Hash', if the hash contains the "id" key, it
      # just finds a record with that id.  Otherwise, it creates a new
      # record and assignes properties from the hash to its field
      # values.  If `rec_cls' is not specified, it will look for it in
      # the hash under the "__type__" key.
      #
      # @param obj [Object]
      # @param rec_cls [Class < Record]
      def unmarshal_to_record(obj, rec_cls=nil)
        case obj
        when Red::Model::Record
          obj
        when Integer
          id = obj
          msg = "Unmarshalling integer to Record without knowing the record class"
          raise MarshallingError.new, msg unless rec_cls
          begin
            rec_cls.find(id)
          rescue Exception => e
            raise MarshallingError.new(e), "Couldn't find record #{rec_cls.name}(#{id})"
          end
        when String, Symbol
          id = Integer(obj.to_s) rescue nil
          raise MarshallingError.new, "cannot convert #{obj} to integer" unless id
          unmarshal_to_record(id, rec_cls)
        when Hash
          hash = obj.clone

          type = hash.delete("__type__")
          rec_cls = pick_type(rec_cls, type)

          id = hash.delete("id")
          if !id.nil?
            unmarshal_to_record(id, rec_cls)
          else
            # raise MarshallingError.new, "no record id is provided"
            rec = rec_cls.new
            hash.each do |k,v|
              fld = rec_cls.meta.field(k)
              if fld
                val = unmarshal(v, fld.type)
                rec.write_field(fld, val)
              end
            end
            rec
          end
        end
      end

      private

      # Picks the more specific one
      def pick_type(rec_cls, cls_name)
        cls_from_name = Red.meta.find_record(cls_name)
        if rec_cls.nil?
          raise MarshallingError.new, "record #{cls_name} not found" unless cls_from_name
          cls_from_name
        else
          if cls_from_name.nil?
            rec_cls
          else
            msg = "actual type (#{cls_from_name}) not subclass of expected (#{rec_cls})"
            raise MarshallingError.new, msg unless cls_from_name <= rec_cls
            if cls_from_name < rec_cls
              cls_from_name
            else
              rec_cls
            end
          end
        end
      end
    end

  end
end
