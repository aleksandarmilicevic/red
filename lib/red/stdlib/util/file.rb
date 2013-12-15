module RedLib
module Util

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
    record FileRecord, {
      content:      Blob,
      content_type: String,
      filename:     String,
      filepath:     String,
      size:         Integer
    } do
      def self.isFile?() true end

      def self.from_file(file_path, content_type=nil)
        path = store.expand_path(file_path)
        raise ArgumentError, "not a file: #{path}" unless File.file?(path)
        fr = FileRecord.new
        fr.filepath     = path
        fr.filename     = File.basename(path)
        fr.size         = File.size(path)
        fr.content_type = content_type
        fr
      end

      @@static_files = {}
      def self.public(name, content_type=nil)
        @@static_files[name] ||= begin
                                   path = Rails.root.join("public").join(name).to_s
                                   fr = from_file(path, content_type)
                                   fr.define_singleton_method :url do |*_| "/#{name}" end
                                   fr
                                 end
      end

      def url(*_)         "/fetchFile?id=#{self.id}" end

      before_save   lambda{store.save(self)}
      after_destroy lambda{store.destroy(self)}

      def extract_file() store.extract_file(self) end
      def read_content() store.read_content(self) end

      def read_metadata

      end

      private

      def self.store() Red.conf.file_store end
      def store()      self.class.store() end

    end
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
  end

end
end
