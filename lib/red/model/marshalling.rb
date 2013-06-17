module Red
  module Model

    module Marshalling
      extend self

      class MarshallingError < StandardError
      end

      def unmarshall(obj)
        case obj
        when Array
          obj.map {|e| unmarshall(e)}
        when Hash
          if obj.delete(:is_record)
            unmarshal_hash_to_record(obj)
          else
            obj.reduce({}) do |acc, keyval|
              ukey = unmarshall(keyval[0])
              uval = unmarshall(keyval[1])
              acc.merge({ukey => uval})
            end
          end
        else
          obj
        end
      end

      def unmarshal_hash_to_record(hash)
        type = hash.delete("type")
        raise MarshallingError, ":type key not found" unless type

        rec_cls = Red.meta.find_record(type)
        raise MarshallingError, "record class #{type} not found" unless type
        
        id = hash.delete("id")
        if !id.nil?
          rec_cls.find(Integer(id)) #return
        else
          rec = rec_cls.new
          hash.each do |k,v|
            fld = rec_cls.meta.field(k)
            if fld
              val = unmarshall(v)
              if fld.type.range.cls.primitive? && val.kind_of?(String)
                val = fld.type.range.cls.from_str(val)
              end
              rec.write(field(fld, val))
            end
          end
          rec #return
        end
      end    
    end

  end
end
