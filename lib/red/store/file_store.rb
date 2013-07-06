module Red
module Store

  #===========================================================
  # File stores
  #===========================================================

  class StoreError < StandardError
  end

  class FileStore
    def save(file_record)         fail "must override" end
    def destroy(file_record)         fail "must override" end
    def extract_file(file_record) fail "must override" end
    def read_content(file_record) fail "must override"  end
  end

end
end
