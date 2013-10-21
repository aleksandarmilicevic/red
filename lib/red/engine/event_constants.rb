require 'alloy/alloy_event_constants'

module Red
  module Engine
    module EventConstants
      include Alloy::EventConstants

      E_CLIENT_CONNECTED    = :client_connected
      E_CLIENT_DISCONNECTED = :client_disconnected
      E_RECORD_CREATED      = :record_created
      E_RECORD_SAVED        = :record_saved
      E_RECORD_DESTROYED    = :record_destroyed
      E_RECORD_QUERIED      = :record_queried
      E_RECORD_UPDATED      = :record_updated
      E_QUERY_EXECUTED      = :query_executed
    end
  end
end
