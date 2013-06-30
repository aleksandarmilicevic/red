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

    record HashRecord do 
      field entries: (set HashEntryRecord), :owned => true, :default => []
    end
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
  end

end
end
