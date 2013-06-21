require 'red/red'
require 'red/model/red_model'
require 'red/model/red_meta_model'

require_relative 'red_dsl_engine.rb'

module Red

  module Dsl
    include Alloy::Dsl
    extend self

    # def alloy_model(name="", &block)
    #   fail "Unsupported, use `data_model' or `machine_model"
    # end

    def data_model(name="", &block)
      mm = _model_builder_class.get_new(
        :mods_to_include => [Red::Dsl::MData])
      mm.model(:data, name, &block)
    end

    def machine_model(name="", &block)
      mm = _model_builder_class.get_new(
        :mods_to_include => [Red::Dsl::MMachine])
      mm.model(:machines, name, &block)
    end

    def event_model(name="", &block)
      mm = _model_builder_class.get_new(
        :mods_to_include => [Red::Dsl::MEvent])
      mm.model(:events, name, &block)
    end

    # ==================================================================
    # Model to be included in each +data_model+.
    # ==================================================================
    module MData
      include Alloy::Dsl::Mult
      include Alloy::Dsl::Abstract
      extend self

      def record(name, fields={}, &block)
        sb = Alloy::DslEngine::SigBuilder.new(
          :default_superclass => Red::Model::Data)
        sb.sig(name, fields, &block)
      end

      def abstract_record(name, fields={}, &block)
        record(name, fields, &block).abstract
      end
    end

    # ==================================================================
    # Model to be included in each +machine_model+.
    # ==================================================================
    module MMachine
      include Alloy::Dsl::Mult
      include Alloy::Dsl::Abstract
      extend self

      def machine(name, fields={}, &block)
        sb = Alloy::DslEngine::SigBuilder.new(
          :default_superclass => Red::Model::Machine)
        sb.sig(name, fields, &block)
      end

      def abstract_machine(name, fields={}, &block)
        machine(name, fields, &block).abstract
      end
    end

    # ==================================================================
    # Model to be included in each +event_model+.
    # ==================================================================
    module MEvent
      include Alloy::Dsl::Mult
      extend self

      def event(name, fields={}, &block)
        sb = Alloy::DslEngine::SigBuilder.new(
          :default_superclass => Red::Model::Event)
        sb.sig(name, fields, &block)
      end
    end
  end
end
