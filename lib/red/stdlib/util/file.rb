module RedLib
module Util

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
    record FileRecord, {
      content: Blob,
      content_type: String,
      filename: String,
      filepath: String,
      size: Integer
    } do
      def self.isFile?() true end

      before_save lambda{store.save(self)}
      after_destroy lambda{store.destroy(self)}

      def extract_file() store.extract_file(self) end
      def read_content() store.read_content(self) end

      private

      def store() Red.conf.file_store end

    end
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
  end

end
end
