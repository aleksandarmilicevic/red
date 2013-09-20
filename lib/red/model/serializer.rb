require 'active_record'
require 'red/model/red_model'
require 'red/model/red_table_util'

module Red
  module Model

    module Serializer
      extend self

      def ser_fields(record)
        record_cls = record.meta.sig_cls
        hier = record_cls.all_supersigs.reverse + [record_cls]
        fld_hash = {}
        hier.each do |r|
          r.meta.fields.each do |f|
            fld_hash[f.name] = f
          end
        end
        fld_hash.values
      end

      def ser_as_red_inspect(record)
        content = ser_as_red_json(record).map{ |k, v|
          "#{k}: #{v}"
        }.join(", ")
        "\#<#{record.red_meta.record_cls.name} #{content}>"
      end

      def ser_as_red_json(record)
        #TODO:
        json_hash = record.as_json :root => false
        json_hash.delete("created_at")
        json_hash.delete("updated_at")
        json_hash["__type__"] = record.class.name
        json_hash["__short_type__"] = record.class.relative_name
        ser_fields(record).each do |fld|
          unless fld.scalar?
            val = record.read_field(fld).map(&:id)
            json_hash[fld.name.singularize + "_ids"] = val
          end
        end
        json_hash
        # ser_fields(record).reduce({"id" => record.id}) do |ans, fld|
        #   value = record.read_field(fld)
        #   key, value = nil, nil
        #   if fld.primitive?
        #     key = fld.name
        #     val = value
        #   else
        #     fldinf = Red::Model::TableUtil.fld_table_info(fld)
        #     key = fldinf.column
        #     val = (value.nil?) ? nil : value.id
        #   end
        #   ans.merge! key => val if key
        # end
      end
    end

  end
end

# ====================================================================
# Methods:
#   * red_inspect
#   * as_red_json
# ====================================================================

module Red::Model
  class Record < ActiveRecord::Base
    def red_inspect
      Serializer.ser_as_red_inspect(self)
    end

    def as_red_json(hash={})
      json = Serializer.ser_as_red_json(self)
      if hash[:root]
        root_name = self.class.name.underscore.singularize
        json = { root_name => json }
      end
      json
    end

  end
end

class Array
  def red_inspect()
    str = map{|e| e.red_inspect}.join(", ")
    "[#{str}]"
  end

  def as_red_json(hash={})
    map{|e| e.as_red_json(hash)}
  end
end

class ActiveRecord::Relation
  def as_red_json(hash={})
    map{|e|e}.as_red_json
  end
end

class Hash
  def red_inspect()
    str = map{|k,v| "#{k.red_inspect} => #{v.red_inspect}"}.join(", ")
    "{#{str}}"
  end

  def as_red_json(hash={})
    reduce({}) do |acc,kv|
      key = kv[0].as_red_json(hash)
      value = kv[1].as_red_json(hash)
      acc[key] = value
      acc
    end
  end
end

class Object
  def red_inspect() inspect end
  def as_red_json(hash={}) as_json(hash) end
end
