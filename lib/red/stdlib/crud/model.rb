module RedLib
module Crud

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
    event CreateRecord do
      params {{
          className: String,
        }}

      ensures {
        cls = Red.meta.get_record(className)
        incomplete "Record class #{cls} not found" unless cls
        incomplete "Can't create a machine" if cls.kind_of?(Red::Model::Machine)
        cls.create!
      }
    end

    event CreateRecordAndLink < CreateRecord do
      params {{
          target: Red::Model::Record,
          fieldName: String
        }}

      requires { 
        super()
        msg = "Target object must be a Record but it's #{target.class}"
        check Red::Model::Record === target, msg
      }

      ensures {
        new_record = super()
        fld = target.meta.field(fieldName)
        incomplete "Field #{fieldName} not found in class #{record.class}" unless fld
        if fld.scalar?
          target.write_field(fld, new_record)
        else
          target.read_field(fld) << new_record
        end
        target.save!
        new_record
      }
    end

    event UpdateRecord do
      params {{
          target: Red::Model::Record,
          params: Hash
        }}

      requires {
        !target.nil? and
        !params.nil?
      }

      ensures {
        params.each do |key, value|
          fld = target.meta.field(key)
          incomplete "No field named `#{key}' in #{target.class}" unless fld
          target.write_field fld, value rescue write_error(target, fld, value)
        end
        target.save!
      }

      def write_error(target, fld, value)
        error "couldn't write field #{target}.#{fld.name}"
      end
    end

    event DeleteRecord do
      params {{
          target: Red::Model::Record
        }}

      requires {
        !target.nil?
      }

      ensures {
        target.destroy
      }
    end

    event DeleteRecords do
      params {{
          targets: (set Red::Model::Record)
        }}

      requires {
        !targets.nil?
      }

      ensures {
        targets.each{|r| r.destroy}
      }
    end
  end

end
end
