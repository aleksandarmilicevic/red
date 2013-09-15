require 'alloy/alloy_dsl'
require 'red/red'
require 'red/dsl/red_dsl_engine'
require 'red/model/red_model'
require 'red/model/red_meta_model'
require 'sdg_utils/dsl/instance_builder'
require 'sdg_utils/dsl/module_builder'

module Red

  module Dsl
    include Alloy::Dsl
    extend self

    # def alloy_model(name="", &block)
    #   fail "Unsupported, use `data_model' or `machine_model"
    # end

    def data_model(name="", &block)
      Alloy::Dsl::ModelBuilder.new({
        :mods_to_include => [Red::Dsl::MData],
        :return          => :builder
      }).model(:data, name, &block)
    end

    def machine_model(name="", &block)
      Alloy::Dsl::ModelBuilder.new({
        :mods_to_include => [Red::Dsl::MMachine],
        :return          => :builder
      }).model(:machines, name, &block)
    end

    def event_model(name="", &block)
      Alloy::Dsl::ModelBuilder.new({
        :mods_to_include => [Red::Dsl::MEvent],
        :return          => :builder
      }).model(:events, name, &block)
    end

    def security_model(name="", &block)
      Alloy::Dsl::ModelBuilder.new({
        :mods_to_include => [Red::Dsl::MSecurity],
        :return          => :builder
      }).model(:events, name, &block)
    end

    # ==================================================================
    # Model to be included in each +data_model+.
    # ==================================================================
    module MData
      include Alloy::Dsl::ModelDslApi
      extend self

      def record(name, fields={}, &block)
        Alloy::Dsl::SigBuilder.new({
          :superclass => Red::Model::Data,
          :return     => :builder
        }).sig(name, fields, &block)
      end
    end

    # ==================================================================
    # Model to be included in each +machine_model+.
    # ==================================================================
    module MMachine
      include Alloy::Dsl::ModelDslApi
      extend self

      def machine(name, fields={}, &block)
        Alloy::Dsl::SigBuilder.new({
          :superclass => Red::Model::Machine,
          :return     => :builder
        }).sig(name, fields, &block)
      end
    end

    # ==================================================================
    # Model to be included in each +event_model+.
    # ==================================================================
    module MEvent
      include Alloy::Dsl::ModelDslApi
      extend self

      def event(name, fields={}, &block)
        sb = Alloy::Dsl::SigBuilder.new({
          :superclass => Red::Model::Event,
          :return     => :builder
        }).sig(name, fields, &block)
      end
    end

    # ==================================================================
    # Model to be included in each +security_model+.
    # ==================================================================
    module MSecurity
      include Alloy::Dsl::ModelDslApi
      extend self

      def policy(name, &block)
        # opts = {
        #   :parent_class         => Red::Model::Policy,
        #   :include_builder_mods => [Red::Model::Policy::Builder],
        #   :expand_name          => true,
        #   :create_const         => true
        # }
        # blder = SDGUtils::DSL::InstanceBuilder.new opts
        # policy = blder.build(name, {}, &block)
        # Red.meta.policy_created(policy)
        # policy

        sb = Alloy::Dsl::SigBuilder.new({
          :superclass => Red::Model::Policy,
          :return     => :builder
        }).sig(name, {}, &block)
      end
    end

  end
end
