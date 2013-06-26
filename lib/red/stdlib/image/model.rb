module RedLib
module Image

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
    record Image, {
      content: Blob, 
      content_type: String,
      size: Integer,
      width: Integer, 
      height: Integer
    }
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
  end

end
end
