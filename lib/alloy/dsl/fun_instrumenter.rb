require 'sdg_utils/lambda/sourcerer'

module Alloy
  module Dsl

    class FunInstrumenter
      include SDGUtils::Lambda::Sourcerer

      def initialize(proc)
        @proc = proc
      end

      def instrument
        ast = parse_proc(@proc)
        orig_src = read_src(ast)
        instr_src = reprint(ast) do |node, parent, anno|
          new_src =
            case node.type
            when :if
              cond_src = compute_src(node.children[0], anno)
              then_src = compute_src(node.children[1], anno)
              else_src = compute_src(node.children[2], anno)
              "Alloy::Ast::Expr::ITEExpr.new(" +
                "#{cond_src}, " +
                "proc{#{then_src}}, " +
                "proc{#{else_src}})"
            when :and, :or
              lhs_src = compute_src(node.children[0], anno)
              rhs_src = compute_src(node.children[1], anno)
              "Alloy::Ast::Expr::BinaryExpr.#{node.type}(" +
                "proc{#{lhs_src}}, " +
                "proc{#{rhs_src}})"
            else
              nil
            end
          anno[node.__id__].src = new_src if new_src
        end
        [orig_src, instr_src]
      end
    end

  end
end
