require 'erb'
require 'parser/current'
require 'red/engine/compiled_template_repo'

module Red
module Engine

  module ERBCompiler
    extend self

    # Retuns a compiler for the ERB format, i.e., a Proc which when
    # executed returns a `CompiledTemplate'.
    #
    # @result [Proc]
    def get
      lambda { |source|
        erb_out_var = "out"
        erb = ERB.new(source, nil, "%<>", erb_out_var)
        instrumented = Red::Engine::ERBCompiler.instrument_erb(erb.src, erb_out_var)
        erb.src.clear
        erb.src.concat(instrumented)
        CTE.new("ERB", Proc.new {|view_binding|
          Red.boss.time_it("Rendering ERB:\n#{erb.src}"){
            erb.result(view_binding.get_binding)
          }
        }, :ruby_code => instrumented)
      }
    end

    def instrument_erb(src, var)
      src = src.gsub(/#{var}\ =\ ''/, "#{var}=mk_out")
      ast = Parser::CurrentRuby.parse(src)

      # discover concat calls
      concat_nodes = []
      # array of (node, parent) pairs
      worklist = [[ast, nil]]
      while !worklist.empty? do
        node, parent = worklist.shift
        if cn = is_concat_node(node, var)
          while cn[:type]==:const && cnn=is_next_concat_const(parent, worklist, var) do
            cn[:end_pos] = cnn[:end_pos]
            cn[:source] = eval("#{cn[:source]} + #{cnn[:source]}").inspect
            cn[:template] = cn[:template] + cnn[:template]
            worklist.shift
          end
          concat_nodes << cn
        else
          chldrn = node.children.map{|ch| [ch, node] if Parser::AST::Node===ch}.compact
          worklist.unshift(*chldrn)
        end
      end

      # instrument src by wrapping all concat calls in `as_node'
      instr_src = ""
      last_pos = 0
      concat_nodes.sort_by! do |n|
        n[:begin_pos]
      end.each do |n|
        bpos = n[:begin_pos]
        epos = n[:end_pos]
        pre = src[last_pos...bpos]
        orig_src = src[bpos...epos]
        instr_src += pre
        instr_src += as_node_code(var, n[:type], n[:source], n[:template], orig_src)
        last_pos = epos
      end
      instr_src += src[last_pos..-1]
      instr_src
    end

    def as_node_code(var, type, source, template, original)
      varsym = var.to_sym.inspect
      if type == :const
        node = ConstNodeRepo.create(source)
        "#{var}.add_node_by_id(#{node.id})"
      else
        locals_code = """
(local_variables - [#{varsym}]).reduce({}){|acc, v| acc[v] = eval(v.to_s); acc}
        """.strip
        tpl_id = Red::Engine::CompiledTemplateRepo.for_expr(source)
        """
#{var}.as_node(#{type.inspect}, #{locals_code}, #{source.inspect}, #{tpl_id}){
  #{original}
};"""
      end
    end

    def is_next_concat_const(curr_parent, worklist, outvar)
      return false unless curr_parent.type == :begin
      return false if worklist.empty?
      node, parent = worklist[0]
      return false unless parent == curr_parent
      cn = is_concat_node(node, outvar)
      return false unless cn && cn[:type] == :const
      cn
    end

    def is_concat_node(ast_node, outvar)
      return false unless ast_node.type == :send
      return false unless (ast_node.children.size == 3 rescue false)
      return false unless (ast_node.children[0].children.size == 1 rescue false)
      return false unless ast_node.children[0].children[0] == outvar.to_sym
      return false unless ast_node.children[1] == :concat
      begin
        ch = ast_node.children[2]
        if ch.type == :str
          type = :const
          src = get_node_source(ch)
          tpl = eval(src)
        else
          src = get_node_source(ch.children[0].children[0])
          tpl = "<%= #{src} %>"
          type = :expr
        end
        return :type => type,
               :source => src,
               :template => tpl,
               :begin_pos => get_node_expr(ast_node).begin_pos,
               :end_pos => get_node_expr(ast_node).end_pos
      rescue Exception
        false
      end
    end
    
    def get_node_expr(node) node.location.expression end
    def get_node_source(node) get_node_expr(node).source end

  end

end
end
