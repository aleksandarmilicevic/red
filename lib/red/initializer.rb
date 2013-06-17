require 'alloy/initializer'
require 'red/resolver'
require 'red/red_conf'
require 'red/model/red_assoc'

module Red

  # =================================================================
  # Class +CInitializer+
  #
  # Performs various initialization tasks. 
  #
  # Options:
  #   :resolver  - resolver to use, defaults to +Red::Resolver+
  #   :baseklass - base class for types for which to add inverse
  #                fields, defaults to +Red::Model::Record+.
  # =================================================================
  class CInitializer
    @@required  = false

    def initialize
      @alloy_initializer = Alloy::CInitializer.new :resolver => Red::Resolver,
                                                   :baseklass => Red::Model::Record
    end

    def init_all
      require_models
      init_all_but_rails
      Red.boss.start
    end

    def init_all_but_rails
      init_all_but_rails_no_freeze
      deep_freeze
    end
    
    def init_all_but_rails_no_freeze
      configure_alloy
      resolve_fields
      expand_fields
      init_inv_fields
      add_associations
    end

    def configure_alloy
      # just copy everything from Red.conf to Alloy.conf
      #Red.conf.each {|k,v| Alloy.conf[k] = v}
    end

    # ----------------------------------------------------------------
    # Finds and requires all Red models 
    # ----------------------------------------------------------------
    def require_models
      return if @@required
      @@required = true
      #TODO: make these folders configurable    
      (Dir[Rails.root.join("app", "models", "{**/*.rb}")] +
       Dir[Rails.root.join("app", "events", "{**/*.rb}")]).each do |d|
        require d.to_s
      end
    end
    
    def resolve_fields(force=false)
      @alloy_initializer.resolve_fields(force)
    end
    
    def expand_fields(force=true)
      return unless force || Red.test_and_set(:fields_expanded)
      # @alloy_initializer.init_inv_fields(force)
      Red::Model::Assoc.expand_fields
    end
    
    def init_inv_fields(force=false)
      @alloy_initializer.init_inv_fields(force)
    end

    def add_associations(force=false)
      return unless force || Red.test_and_set(:assoc_defined)
      Red::Model::Assoc.define_associations
    end

    def deep_freeze
      @alloy_initializer.deep_freeze
      Red.conf.freeze
    end
  end

end
