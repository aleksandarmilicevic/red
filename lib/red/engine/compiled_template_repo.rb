require 'red/engine/template_engine'
require 'red/engine/view_tree'

module Red
  module Engine

    # ================================================================
    #  Class +CompiledTemplateRepo+
    # ================================================================
    module CompiledTemplateRepo

      # TODO: all methods must be SYNCHRONIZED

      @@expr_tpls = []
      def self.create(*args)
        mod, method_name, props = TemplateEngine.code_gen(*args)
        ViewBinding.send :include, mod
        CompiledClassTemplate.new(method_name, method_name, props)
      end

      def self.for_expr(source)
        tpl_idx = @@expr_tpls.size
        tpl = self.create(source, "__expr_#{tpl_idx}")
        @@expr_tpls.push tpl
        tpl_idx
      end

      def self.find(idx) @@expr_tpls[idx] end
      def self.find!(id) self.find(id) or fail("template (#{id}) not found") end
    end

  end
end
