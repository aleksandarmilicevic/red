module Red
  module Model

    #------------------------------------------------------------------------
    # == Class +TypeError+
    #
    # Raised if there is something wrong with an event, e.g., +to+ or +from+
    # designation is missing, etc.
    #------------------------------------------------------------------------
    class MalformedEventError < StandardError
    end
    
    class EventNotCompletedError < StandardError
    end

    class EventPreconditionNotSatisfied < StandardError
    end
  end
end
    
