require 'alloy/alloy'
require 'red/engine/event_constants'
require 'red/model/serializer'
require 'sdg_utils/test_and_set'

module Red
  extend self

  include Red::Engine::EventConstants

  class CMain
    include TestAndSet

    def initialize
      reset_fields
    end

    def conf
      require 'red/red_conf'
      @conf ||= Red::default_conf
      @conf
    end

    def configure(&block)
      block.call(conf)
    end

    def meta
      require 'red/model/red_meta_model'
      @meta ||= Red::Model::MetaModel.new
    end

    def boss
      require 'red/engine/big_boss'
      @boss ||= Red::Engine::BigBoss.new(Alloy.boss)
    end

    def initializer
      require 'red/initializer'
      @initializer ||= Red::CInitializer.new
    end

    def reset
      #meta.reset
      reset_fields
    end

    def reset_fields
      @assoc_defined = false
      @fields_expanded = false
      @conf = nil #Red::default_conf
    end
  end

  def red; @@red ||= Red::CMain.new end
  alias_method :main, :red

  def initialize!
    initializer.init_all
  end

  def reset
    Alloy.reset
    red.reset
  end

  extend SDGUtils::Delegate
  delegate :meta, :boss, :conf, :configure, :set_default, :initializer, :test_and_set,
           :to => lambda{red}, :proc => true

end
