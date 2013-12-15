require 'sdg_utils/errors'

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

    class AccessDeniedError < StandardError # SDGUtils::Errors::ErrorWithCause
      attr_reader :op, :failing_rule, :payload
      def initialize(op, failing_rule, *payload)
        super()
        @op           = op
        @failing_rule = failing_rule
        @payload      = payload
      end

      def message()
        "#{op} failed because of rule #{failing_rule.method}\n" +
          "record: #{payload[0]}, field: #{payload[1]}"
      end
    end

  end
end

