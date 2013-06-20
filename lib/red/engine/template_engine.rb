require 'sass'
require 'parser/current'

module Red::Engine

  module ERBCompiler
    extend self

    # Retusn a Proc which when executed returns a `CompiledTemplate'.
    #
    # @result [Proc]
    def get
      lambda { |source|
        erb_out_var = "out"
        erb = ERB.new(source, nil, "%<>", erb_out_var)          
        instrumented = instrument_erb(erb.src, erb_out_var)
        erb.src.clear
        erb.src.concat(instrumented)
        CompiledTemplate.new("ERB", lambda{|bndg| erb.result(bndg)})
      }
    end

    private

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
          # node.children.each{ |ch| worklist << [ch,node] if Parser::AST::Node === ch }
          worklist = node.children.map{ |ch| [ch, node] if Parser::AST::Node === ch }.compact + worklist
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
      locals_code = """
(local_variables - [#{varsym}]).reduce({}){|acc, v| acc.merge v => eval(v.to_s)}
        """.strip
      """
#{var}.as_node(#{type.inspect}, #{locals_code}, #{source.inspect}){
  #{original}
};"""
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
          src = ch.src.expression.to_source
          tpl = eval(src)
        else
          src = ch.children[0].children[0].src.expression.to_source
          tpl = "<%= #{src} %>"
          type = :expr
        end
        return :type => type, 
               :source => src,
               :template => tpl,
               :begin_pos => ast_node.src.expression.begin_pos, 
               :end_pos => ast_node.src.expression.end_pos 
      rescue Exception
        false
      end
    end
  end

  # ==============================================

  class TemplateEngine
    class << self

      # Formats should be in the order of compilation, i.e., if
      # `formats == %w(.erb .scss .css)', then the ERB compiler
      # is invoked first, next is invoked SCSS, and finally CSS.
      #
      # @param source [String]
      # @param formats [Array]
      # @result [CompiledTemplate]
      def compile(source, formats=[])
        if formats.nil? || formats.empty?
          CompiledTemplate.new("TXT", lambda{source})
        elsif formats.size == 1
          get_compiler(formats.first).call(source)
        else
          rest = compile(source, formats[1..-1])
          fst = get_compiler(formats.first)
          if rest.engine.arity == 0
            # can precompile
            rest_src = rest.execute
            fst.call(rest_src)
          elsif fst == IDEN
            rest
          else
            fst_name = fst.call("").name 
            CompiledTemplate.new("#{fst_name}.#{rest.name}", lambda { |*env| 
                                   rest_src = rest.execute(*env)
                                   fst_compiler = fst.call(rest_src)
                                   env.first.eval "engine_divider()" #rescue nil
                                   fst_compiler.execute(*env) 
                                 })
          end
        end
      end
      
      # Returns a 1-arg lambda which when executed on a given source
      # string returns an instance of the `CompiledTemplate' class.
      #
      # @result [Proc]

      IDEN = lambda{|source| CompiledTemplate.new("TXT", lambda{source})}

      def get_compiler(format)
        case format
        when ".erb"
          ERBCompiler.get
        when ".scss", ".sass"
          lambda { |source|
            engine = Sass::Engine.new(source, :syntax => format[1..-1].to_sym)
            CompiledTemplate.new(format[1..-1].upcase, lambda{engine.render})
          }
        else
          IDEN
        end
      end
    end
  end

  # ==============================================

  class CompiledTemplate
    # Takes a proc which is the execute method of this compiled template
    # @param engine [Proc]
    def initialize(name, engine) 
      fail "not a proc" unless Proc === engine
      @name = name
      @arity = engine.arity
      @engine = engine
    end
    def engine() @engine end
    def arity()  @arity end
    def name()   @name end
    def execute(*env)     
      if @engine.arity == 0 
        @engine.call 
      else
        fail "expected arity: #{@engine.arity}, actual: 0" if env.empty?
        @engine.call(*env) 
      end
    end
  end


  
end
