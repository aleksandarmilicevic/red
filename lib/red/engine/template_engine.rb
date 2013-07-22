require 'sass'
require 'red/engine/erb_compiler'

module Red::Engine

  class TemplateEngine
    class << self

      # --------------------------------------------------------
      #
      # Formats should be in the order of compilation, i.e., if
      # `formats == %w(.css .scss .erb)', then the CSS compiler
      # is invoked first, next is invoked SCSS, and finally ERB.
      #
      # @param source [String]
      # @param formats [Array]
      # @return [CompiledTemplate]
      #
      # --------------------------------------------------------
      def compile(source, formats=[])
        formats = [formats].flatten.compact
        if formats.nil? || formats.empty?
          CompiledTextTemplate.new(source)
        elsif formats.size == 1
          get_compiler(formats.first).call(source)
        else
          rest = compile(source, formats[1..-1])
          fst = get_compiler(formats.first)
          if !rest.needs_env?
            # can precompile
            rest_src = rest.execute
            fst.call(rest_src)
          elsif fst == IDEN
            rest
          else
            fst_name = fst.call("").name rescue "?"
            CompiledCompositeTemplate.new("#{fst_name}.#{rest.name}", fst, rest)
          end
        end
      end

      # -------------------------------------------------------------
      #
      # Takes an instance of `CompiledTemplate' and translates it into
      # Ruby source code.  Since the compiled template may be a
      # composite template (instance of `CompositeCompiledTemplate'),
      # the result may contain multiple method, so the return value of
      # this call is an array containing at its first position (index
      # 0) a module (where all those methods are generated) and at its
      # second position (index 1) name of the root method
      # (corresponding to the given compiled template). 
      #
      # The input parameter must be an instance of either
      # `CompiledTextTemplate' or `CompiledCompositeTemplate', or any
      # instance of `CompiledTemplate' returning a string value for
      # the `ruby_code' property.
      #
      # @param compiled_template [CompiledTextTemplate,
      #   CompiledCompositeTemplate, CompiledTemplate#props[:ruby_code]]
      #
      # @return [Array(Module, String)] - a module containing all the
      #   code (generated methods) and the name of the root method
      #   (corresponding to the given compiled template).
      #
      # -------------------------------------------------------------
      def code_gen(compiled_tpl, prefix=nil, mod=Module.new)
        time = "#{Time.now.utc.strftime("%s_%L")}"
        salt = Random.rand(1000..9999)
        prefix = 
          (prefix or 
          (fn = compiled_tpl.props[:filename] and fn.to_s.underscore rescue nil) or
          "tpl")
        method_name = "#{prefix}_#{time}_#{salt}"
        method_body = 
          case compiled_tpl
          when CompiledTextTemplate
            compiled_tpl.render.inspect       
          when CompiledCompositeTemplate
            fst_method_name = "#{method_name}_fst_compiler"
            mod.send :define_method, "#{fst_method_name}", compiled_tpl.fst
            m, rest_method_name = code_gen(compiled_tpl.rest, "#{prefix}_rest", mod)
"""
  rest_out = #{rest_method_name}()
  fst_compiler = #{fst_method_name}(rest_out)
  engine_divider()
  fst_compiler.render(self)
"""
          else
            ruby_code = (compiled_tpl.props[:ruby_code] || 
                         compiled_tpl.ruby_code) rescue nil
            fail "No ':ruby_code' property found in #{compiled_tpl}" unless ruby_code
            ruby_code
          end
        mod.class_eval <<-RUBY, __FILE__, __LINE__
def #{method_name}
  #{method_body}
end
RUBY
        puts "-------------------------"
        puts "def #{method_name}\n  #{method_body}\nend"
        puts "-------------------------\n"
        [mod, method_name]
      end
      
      IDEN = lambda{|source| CompiledTextTemplate.new(source)}

      # --------------------------------------------------------
      #
      # Returns a 1-arg lambda which when executed on a given source
      # string returns an instance of the `CompiledTemplate' class.
      #
      # @return [Proc]
      #
      # --------------------------------------------------------
      def get_compiler(format)
        case format
        when ".erb"
          ERBCompiler.get
        when ".scss", ".sass"
          fmt = format[1..-1]
          lambda { |source|
            engine = Sass::Engine.new(source, :syntax => fmt.to_sym)
            CompiledTextTemplate.new(engine.render, fmt.upcase)
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
    def initialize(name, needs_env, props={}, &block)
      @name = name
      @needs_env = needs_env
      @props = props.clone
      self.instance_eval &block if block
    end
    def needs_env?() @needs_env end
    def name()       @name end
    def props()      @props end

    # @return [Object]
    def execute(*env) fail "" end

    # @return [String]
    def render(*env) fail "" end

  end

  # =================================================================

  class CompiledTextTemplate < CompiledTemplate
    def initialize(text, name="TXT")
      super(name, false)
      @text = text
    end

    def execute(*env) @text end
    def render(*env) @text end
  end

  # =================================================================

  class CompiledCompositeTemplate < CompiledTemplate
    attr_reader :fst, :rest

    # @param fst [Proc]
    # @param fst [CompiledTemplate]
    def initialize(name, fst, rest)
      super(name, true)
      @fst = fst
      @rest = rest
    end

    def exe(meth, *env)
      rest_out = @rest.render(*env)
      fst_compiler = @fst.call(rest_out)
      #TODO: don't hardcode this call to engine_divider
      env.first.engine_divider() #rescue nil 
      fst_compiler.send meth, *env
    end

    def render(*env) exe(:render, *env); end
    def execute(*env) exe(:execute, *env); end
  end

  # =================================================================

  class CompiledClassTemplate < CompiledTemplate
    def initialize(method_name, name=method_name, props={}, &block)
      super(name, true, props, &block)
      @method_name = method_name.to_sym
    end

    def execute(obj) obj.send @method_name end
    def render(obj) execute(obj).to_s end
  end

  # =================================================================

  class CTE < CompiledTemplate
    def initialize(name, engine, props={}, &block)
      fail "not a proc" unless Proc === engine
      super(name, engine.arity != 0, props, &block)
      @engine = engine
    end

    def render(*env) call_proc(@engine, *env); end
    def execute(*env) call_proc(@engine, *env); nil end

    protected

    def call_proc(proc, *args)
      if proc.arity == 0
        proc.call
      else
        fail "expected arity: #{@engine.arity}, actual: 0" if args.empty?
        proc.call(*args)
      end
    end
  end

end
