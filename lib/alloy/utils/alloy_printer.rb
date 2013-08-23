require 'alloy/alloy_ast'
require 'sdg_utils/print_utils/code_printer'

module Alloy
  module Utils

    class AlloyPrinter

      def self.export_to_als(*what)
        ap = AlloyPrinter.new
        what = Alloy.meta.models if what.empty?
        what.map{|e| ap.send :to_als, e}.join("\n")
        ap.to_s
      end

      def export_to_als(*what)
        self.class.export_to_als(*what)
      end

      def to_s
        @out.to_s
      end

      protected

      def initialize
        @out = SDGUtils::PrintUtils::CodePrinter.new :visitor => self,
                                                     :visit_method => :export_to_als
      end

      def to_als(alloy_obj)
        _fail = proc{fail "Unrecognized Alloy entity: #{alloy_obj}:#{alloy_obj.class}"}
        case alloy_obj
        when Alloy::Ast::Model; model_to_als(alloy_obj)
        when Class
          if alloy_obj < Alloy::Ast::ASig
            sig_to_als(alloy_obj)
          else
            _fail[]
          end
        when Alloy::Ast::Fun;          fun_to_als(alloy_obj)
        when Alloy::Ast::Field;        field_to_als(alloy_obj)
        when Alloy::Ast::AType;        type_to_als(alloy_obj)
        when Alloy::Ast::Arg;          arg_to_als(alloy_obj)
        when Alloy::Ast::Expr::MExpr;  expr_to_als(alloy_obj)
        else
          _fail[]
        end
      end

      def model_to_als(model)
        @out.pl "module #{model.name}"
        @out.pl
        @out.pn model.sigs, "\n"
        @out.pl unless model.all_funs.empty?
        @out.pn model.all_funs, "\n"
      end

      def sig_to_als(sig)
        psig = sig.superclass
        psig_str = (psig != Alloy::Ast::Sig) ? "extends #{psig.relative_name} " : ""
        @out.pl "sig #{sig.relative_name} #{psig_str} {"
        @out.in do
          @out.pn sig.meta.fields, ",\n"
        end
        @out.pl
        @out.pl "}"
        funs = sig.meta.all_funs
        @out.pl unless funs.empty?
        @out.pn funs, "\n"
      end

      def field_to_als(fld)
        @out.p "#{fld.name}: #{fld.type.to_alloy}"
      end

      def fun_to_als(fun)
        args = if Class === fun.owner && fun.owner.is_sig?
                 selfarg = Alloy::Ast::Arg.new :name => "self", :type => fun.owner
                 [selfarg] + fun.args
               else
                 fun.args
               end
        args_str = args.map(&method(:export_to_als)).join(", ")
        params_str = if args.empty? #&& !fun.fun? && !fun.pred?
                       ""
                     else
                       "[#{args_str}]"
                     end
        ret_str = if fun.fun?
                    ": #{fun.ret_type}"
                  else
                    ""
                  end
        kind = if fun.assertion?
                 :assert
               else
                 fun.kind
               end
        @out.pl "#{kind} #{fun.name}#{params_str}#{ret_str} {"
        @out.in do
          @out.pn [fun.sym_exe]
        end
        @out.pl "\n}"

      end

      def type_to_als(type)
        @out.p type.to_s
      end

      def arg_to_als(arg)
        @out.p "#{arg.name}: #{export_to_als arg.type}"
      end

      def expr_to_als(expr)
        expr.class.ancestors.select{|cls|
          cls < Alloy::Ast::Expr::MExpr
        }.each do |cls|
          kind = cls.relative_name.downcase
          meth = "#{kind}_to_als".to_sym
          if self.respond_to? meth
            return self.send meth, expr
          end
        end
        @out.p expr.to_s
      end

      def quantexpr_to_als(expr)
        decl_str = expr.decl.map(&method(:export_to_als)).join(", ")
        @out.pl "#{expr.kind} #{decl_str} {"
        @out.in do
          @out.pn [expr.body]
        end
        @out.pl "\n}"
      end

      def iteexpr_to_als(ite)
        @out.p "("
        @out.pn [ite.cond]
        @out.pl ") implies {"
        @out.in do
          @out.pn [ite.then_expr]
        end
        @out.pl
        @out.p "}"
        unless Alloy::Ast::Expr::BoolConst === ite.else_expr
          @out.pl " else {"
          @out.in do
            @out.pn [ite.else_expr]
          end
          @out.pl
          @out.p "}"
        end
      end

      def sigexpr_to_als(se)
        @out.p se.sig.relative_name
      end

      def unaryexpr_to_als(ue)
        @out.p("(").p(ue.op).p(" ").pn([ue.sub]).p(")")
      end

      def binaryexpr_to_als(be)
        op_str = be.op.to_s
        op_str = " #{op_str} " unless op_str == "."
        @out.pn([be.lhs]).p(op_str).pn([be.rhs])
      end

      def boolconst_to_als(bc)
        if bc.value
          ""
        else
          "1 != 0"
        end
      end
    end

  end
end
