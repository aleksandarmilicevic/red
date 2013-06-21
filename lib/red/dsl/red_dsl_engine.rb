require_relative 'red_dsl_ext.rb'

module Red
  module DslEngine

    class EventBuilder
      def initialize(options={})
        @options = options
      end

      def self.event(*args)
        new.sig(*args)
      end

      # -------------------------------------------------------------------------------------
      #
      # -------------------------------------------------------------------------------------
      def event(name, options={}, &block)

      end
    end

  end
end