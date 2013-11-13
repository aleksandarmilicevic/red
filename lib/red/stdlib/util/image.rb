require 'red/stdlib/util/file'

module RedLib
module Util

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
    record ImageRecord [
      width:    Integer,
      height:   Integer,
      img_type: String,
      file:     FileRecord | [:owned => true]
    ] do

      def self.from_file_record(file_record)
        img = ImageRecord.new
        img.file = file_record
        img.try_infer_metadata
        img
      end

      def self.from_file_path(file_path, content_type=nil)
        from_file_record FileRecord.from_file(file_path, content_type)
      end

      @@static_images = {}
      def self.public(name, content_type=nil)
        @@static_images[name] ||= from_file_record(FileRecord.public(name, content_type))
      end

      delegate :url, :filename, :filepath, :size, :content, :content_type, :to => :file

      def aspect_ratio
        return 1 unless width && height
        return width if height == 0
        (1.0*width)/height
      end

      def try_infer_metadata
        begin
          require 'image_size'
          is = ImageSize.new(file.read_content)
          self.width = is.get_width
          self.height = is.get_height
          self.img_type = is.get_type
          true
        rescue Exception => e
          width = -1
          height = -1
          puts e.message
          puts e.backtrace.join("\n")
          false
        end
      end
    end
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
  end

end
end
