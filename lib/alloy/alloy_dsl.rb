require 'sdg_utils/meta_utils.rb'

require_relative 'alloy_dsl_engine.rb'

module Alloy

  # ------------------------------------------------------------------
  # == Module +Dsl+
  #
  # Included in all user defined (via the +AlloyDsl::Dsl#alloy_model+
  # method) Alloy models.
  # ------------------------------------------------------------------
  module Dsl
    extend self

    # ------------------------------------------------------
    # Methods for constructing expressions.
    # ------------------------------------------------------
    module Mult
      extend self
      def lone(*sig) Alloy::DslEngine::ModBuilder.mult(:lone, *sig) end
      def one(*sig)  Alloy::DslEngine::ModBuilder.mult(:one, *sig) end
      def set(*sig)  Alloy::DslEngine::ModBuilder.mult(:set, *sig) end
      def seq(*sig)  Alloy::DslEngine::ModBuilder.mult(:seq, *sig) end
    end

    module Abstract
      # def abstract(sig_cls=nil, &block)
      #   unless sig_cls
      #     fail "neither class nor block provided" unless block
      #     sig_cls = block.call
      #   end
      #   fail "not a sig but #{sig_cls}" unless (sig_cls.is_sig? rescue false)
      #   sig_cls.meta.set_abstract
      # end
      def abstract(sig_cls=nil, &block)
        if sig_cls
          sig_cls.meta.set_abstract
          sig_cls.class_evaluate(block) if block
        elsif block
          old_abstract = @abstract_alloy_block || false
          @abstract_alloy_block = true
          begin
            block.call
          ensure
            @abstract_alloy_block = old_abstract
          end
        else
          fail "neither class nor block provided"
        end
      end
    end

    module StaticHelpers
      include Mult
      extend self
    end

    #TODO: doesn't work for ActiveRecord::Relation
    module InstanceHelpers
      require 'alloy/relations/relation_ext.rb'
      def no(col)   col.as_rel.no? end
      def some(col) col.as_rel.some? end
      def one(col)  col.as_rel.one? end
      def lone(col) col.as_rel.lone? end
    end

    # ----------------------------------------------------------------
    # Model to be included in each +alloy_model+.
    # ----------------------------------------------------------------
    module Model
      include Mult
      include Abstract
      extend self
      # --------------------------------------------------------------
      # Creates a new class, subclass of either Alloy::Ast::Sig or a
      # user supplied super class, creates a constant with a given
      # +name+ in the callers namespace and assigns the created class
      # to it.
      # --------------------------------------------------------------
      def sig(name, fields={}, &block)
        ans = Alloy::DslEngine::SigBuilder.sig(name, fields, &block)
        ans.abstract if @abstract_alloy_block
        ans
      end

      def abstract_sig(name, fields={}, &block)
        sig(name, fields, &block).abstract
      end
    end

    # ----------------------------------------------------------------
    # Creates a modules named +name+ and then executes +&block+ using
    # +module_eval+.  All Alloy sigs must be created inside an "alloy
    # model" block.  Inside of this module, all undefined constants
    # are automatically converted to symbols.
    # ----------------------------------------------------------------
    def alloy_model(name="", &block)
      Alloy::DslEngine::ModelBuilder.new.model(:alloy, name, &block)
    end

    # ----------------------------------------------------------------
    # Different aliases for the +alloy_model+ method.
    # ----------------------------------------------------------------
    alias_method :alloy_module, :alloy_model

  end

end

require_relative 'alloy_dsl_ext.rb'
