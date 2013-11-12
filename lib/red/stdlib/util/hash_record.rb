module RedLib
module Util

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
    record HashEntryRecord, {
      key: String,
      value: String
    }

    record HashRecord [
      entries: (set RedLib::Util::HashEntryRecord) | [:owned => true]
    ] do

      def entry(key)
        entries.where("key = ?", key).first
      end

      def get(key)
        e = self.entry(key)
        e ? e.value : nil
      end

      def put(key, value)
        e = self.entry(key)
        unless e
          e = RedLib::Util::HashEntryRecord.new :key => key
          self.entries << e
          self.save!
        end
        e.value = value
        e.save!
      end

      alias_method :set, :put

    end
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
    event HashPut do
      params {{
          hash: RedLib::Util::HashRecord,
          key: String,
          value: String
        }}

      requires {
        check_all_present
      }

      ensures {
        hash.put(key, value)
      }
    end

    event AddToHashField do
      params {{
          target: Red::Model::Record,
          fieldName: String,
          key: String,
          value: String
        }}

      requires {
        check_all_present
      }

      ensures {
        hash = target.read_field(fieldName)
        unless hash
          hash = RedLib::Util::HashRecord.new
          target.write_field(fieldName, hash)
          target.save!
        end
        hash.put(key, value)
      }
    end
  end

end
end
