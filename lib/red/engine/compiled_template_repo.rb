require 'red/engine/template_engine'
require 'red/engine/view_tree'
require 'sdg_utils/obj/uninstantiable'

module Red
  module Engine

    # ================================================================
    #  Class +CompiledTemplateRepo+
    # ================================================================
    class CompiledTemplateRepo
      include SDGUtils::Obj::Uninstantiable

      # TODO: all methods must be SYNCHRONIZED

      @@expr_tpls = []
      def self.create(*args)
        mod, method_name = TemplateEngine.code_gen(*args)
        ViewBinding.send :include, mod
        CompiledClassTemplate.new(method_name)      
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
