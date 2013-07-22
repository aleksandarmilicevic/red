require 'sass'
require 'red/engine/erb_compiler'

module Red::Engine

  class TemplateEngine
    class << self

      # Formats should be in the order of compilation, i.e., if
      # `formats == %w(.css .scss .erb)', then the CSS compiler
      # is invoked first, next is invoked SCSS, and finally ERB.
      #
      # @param source [String]
      # @param formats [Array]
      # @return [CompiledTemplate]
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
            CTE.new("#{fst_name}.#{rest.name}", lambda{|meth, *env|
              rest_src = rest.render(*env)
              fst_compiler = fst.call(rest_src)
              env.first.eval "engine_divider()" #rescue nil
              fst_compiler.send meth, *env
            }) do
              def execute(*env) @engine.call(:execute, *env) end
              def render(*env) @engine.call(:render, *env) end
            end
          end
        end
      end

      IDEN = lambda{|source| CompiledTextTemplate.new(source)}

      # Returns a 1-arg lambda which when executed on a given source
      # string returns an instance of the `CompiledTemplate' class.
      #
      # @return [Proc]
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
