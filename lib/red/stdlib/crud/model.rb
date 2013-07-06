module RedLib
module Crud

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do

    # ----------------------------------------------------------------
    # Takes a record class name and creates and saves an instance of
    # that record.
    #
    # @param className [String] - record class name
    # ----------------------------------------------------------------
    event CreateRecord do
      param className: String
      param saveRecord: Boolean, :default => true

      ensures {
        cls = Red.meta.get_record(className)
        incomplete "Record class #{cls} not found" unless cls
        incomplete "Can't create a machine" if cls.kind_of?(Red::Model::Machine)
        if saveRecord
          cls.create!
        else
          cls.new
        end
      }
    end

    # ----------------------------------------------------------------
    # Takes a record class name, creates and saves an instance of that
    # record, and then links it to the designated field of the target
    # record.
    #
    # @param className [String] - record class of which and instance
    #                             is to be created.
    #
    # @param target [Record]    - target record which the newly created
    #                             record instance will be linked to.
    #
    # @param fieldName [String] - field name of the target record to
    #                             which the newly created record
    #                             instance will be assigne.
    #
    # ----------------------------------------------------------------
    event CreateRecordAndLink < CreateRecord do
      params {{
          target: Red::Model::Record,
          fieldName: String
        }}

      requires {
        super()
        check_all_present
      }

      ensures {
        new_record = super()
        ev = LinkToRecord.new :target => target,
                              :fieldName => fieldName,
                              :fieldValue => new_record
        ev.execute
        new_record
      }
    end

    # ----------------------------------------------------------------
    # Takes a target record, its field name and an object to assign to
    # that field.
    #
    # @param target [Record]    - target record which the given object
    #                             will be linked to.
    #
    # @param fieldName [String] - field name of the target record to
    #                             which the newly created record
    #                             instance will be assigne.
    #
    # @param fieldValue [Object] - value to assign to the target field.
    #
    # ----------------------------------------------------------------
    event LinkToRecord do
      params {{
          target: Red::Model::Record,
          fieldName: String,
          fieldValue: lambda{|ev| ev.target.meta.field(fieldName).type},
        }}

      param saveTarget: Boolean, :default => true

      requires {
        check_present :target, :fieldName
      }

      ensures {
        fld = target.meta.field(fieldName)
        incomplete "Field #{fieldName} not found in class #{target.class}" unless fld
        if fld.scalar?
          target.write_field(fld, fieldValue)
        else
          target.read_field(fld) << fieldValue
        end
        target.save! if saveTarget
        target
      }

      protected

      def write_error(target, fld, value)
        error "couldn't write field #{target}.#{fld.name}"
      end

    end

    # ----------------------------------------------------------------
    # Takes a target record and a hash of fieldName-fieldValue pairs,
    # and updates the field of the target record with the values from
    # the hash.
    #
    # @param target [Record]    - target record to be updated.
    #
    # @param params [Hash(String, Object)] - fields and updated values.
    #
    # ----------------------------------------------------------------
    event UpdateRecord do
      params {{
          target: Red::Model::Record,
          params: Hash
        }}
      param saveTarget: Boolean, :default => true

      requires {
        check_all_present
      }

      ensures {
        params.each do |key, value|
          ev = LinkToRecord.new(:target => target, :fieldName => key,
                                :fieldValue => value, :saveTarget => false)
          ev.execute
        end
        target.save! if saveTarget
        target
      }
    end

    # ----------------------------------------------------------------
    # Takes a target record and deletes it from the database.
    #
    # @param target [Record]    - target record to be deleted.
    # ----------------------------------------------------------------
    event DeleteRecord do
      params {{
          target: Red::Model::Record
        }}

      requires {
        check_all_present
      }

      ensures {
        target.destroy
      }
    end

    # ----------------------------------------------------------------
    # Takes a set of records and deletes them from the database.
    #
    # @param target [Array(Record)]    - target records to be deleted.
    # ----------------------------------------------------------------
    event DeleteRecords do
      params {{
          targets: (set Red::Model::Record)
        }}

      requires {
        !targets.nil?
      }

      ensures {
        targets.each{|r| DeleteRecord.new(:target => r).execute}
      }
    end
  end

end
end
