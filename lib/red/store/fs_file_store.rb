require 'red/store/file_store'
require 'fileutils'

module Red
module Store

  #===========================================================
  # File stores
  #===========================================================

  class FSFileStore < FileStore
    def initialize(conf=nil)
      @conf = conf || Red.conf.fs_file_store
      @initialized = false
    end

    def ensure_init
      unless @initialized
        @initialized = true
        @dir_path = @conf.store_folder
        if File.exists?(@dir_path)
          msg = "'store folder' location (#{@dir_path}) exists but it's not a directory"
          raise StoreError, msg unless File.directory?(@dir_path)
        else
          msg = "store folder (#{@dir_path}) doesn't exist and could not be created"
          Dir.mkdir(@dir_path) rescue raise StoreError, msg
        end
      end
    end

    def save(file_record)
      ensure_init

      src = File.absolute_path(file_record.filepath)
      raise StoreError, "source file #{src} is not a file" unless File.file?(src)
      salt = Random.rand(1000..9999)
      fname = "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_#{salt}_#{file_record.filename}"
      dest = File.absolute_path(File.join @dir_path, fname)
      FileUtils.cp src, dest rescue raise StoreError, "could not move #{src} to #{dest}"
      file_record.filepath = dest
      file_record.content = nil
    end

    def destroy(file_record)
      ensure_init

      src = File.absolute_path(file_record.filepath)
      if File.file?(src)
        File.delete(src) rescue Red.conf.log.warn("could not delete #{src}")
      end
    end

    def expand_path(file_name)
      return file_name if file_name[0] == "/"
      ensure_init
      File.absolute_path(File.join @dir_path, file_name)
    end

    def extract_file(file_record)
      ensure_init
      file_record.filepath
    end

    def read_content(file_record)
      ensure_init
      File.open(extract_file(file_record), "rb"){|f| f.read}
    end
  end

end
end
