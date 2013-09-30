require 'sass'
require 'alloy/utils/codegen_repo'
require 'red/engine/erb_compiler'
require 'sdg_utils/meta_utils'

module Red::Engine

  module TemplateEngine
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
        if Proc === source
          fst_compiler = get_compiler(formats)
          rest_compiled = CompiledProcTemplate.new(source)
          join(fst_compiler, rest_compiled)
        elsif formats.nil? || formats.empty?
          CompiledTextTemplate.new(source)
        elsif formats.size == 1
          get_compiler(formats.first).call(source)
        else
          rest_compiled = compile(source, formats[1..-1])
          fst_compiler = get_compiler(formats.first)
          join(fst_compiler, rest_compiled)
        end
      end

      # --------------------------------------------------------
      #
      # @param fst_compiler [Proc]
      # @param rest_compiled [CompiledTemplate]
      #
      # --------------------------------------------------------
      def join(fst_compiler, rest_compiled)
        if !rest_compiled.needs_env?
          # can precompile
          rest_src = rest_compiled.execute
          fst_compiler.call(rest_src)
        elsif fst_compiler == IDEN
          rest_compiled
        else
          fst_name = fst_compiler.call("").name rescue "?"
          name = "#{fst_name}.#{rest_compiled.name}"
          CompiledCompositeTemplate.new(name, fst_compiler, rest_compiled)
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
      # `CompiledTextTemplate' `CompiledProcTemplate', or
      # `CompiledCompositeTemplate', or any instance of
      # `CompiledTemplate' returning a string value for the
      # `ruby_code' property.
      #
      # @param compiled_template [String, CompiledTextTemplate,
      #   CompiledProcTemplate, CompiledCompositeTemplate,
      #   CompiledTemplate#props[:ruby_code]]
      #
      # @return [Array(Module, String)] - a module containing all the
      #   code (generated methods) and the name of the root method
      #   (corresponding to the given compiled template).
      #
      # -------------------------------------------------------------
      def code_gen(compiled_tpl, prefix=nil, mod=Module.new)
        time = "#{Time.now.utc.strftime("%s_%L")}"
        salt = Random.rand(1000..9999)
        tpl_id = compiled_tpl.gen_method_name rescue nil
        tpl_fmt = compiled_tpl.name.downcase.gsub(/\./, "_") rescue nil
        prefix = prefix || SDGUtils::MetaUtils.check_identifier(tpl_id)
        fmt = SDGUtils::MetaUtils.check_identifier(tpl_fmt) || "tpl"

        method_name = "#{prefix}_#{fmt}_#{time}_#{salt}"
        method_body =
          case compiled_tpl
          when String
            add_compiled_tpl_method mod, method_name, <<-RUBY, __FILE__, __LINE__
def #{method_name}
  #{compiled_tpl}
end
RUBY
          when CompiledTextTemplate
            add_compiled_tpl_method mod, method_name, <<-RUBY, __FILE__, __LINE__
def #{method_name}
  #{compiled_tpl.execute.inspect}
end
RUBY
          when CompiledProcTemplate
            proc_method_name = "#{method_name}_proc"
            mod.send :define_method, "#{proc_method_name}", compiled_tpl.proc
            add_compiled_tpl_method mod, method_name, <<-RUBY, __FILE__, __LINE__
def #{method_name}
  #{proc_method_name}()
end
RUBY
          when CompiledCompositeTemplate
            fst_method_name = "#{method_name}_fst_compiler"
            mod.send :define_method, "#{fst_method_name}", compiled_tpl.fst
            m, rest_method_name = code_gen(compiled_tpl.rest, "#{prefix}_rest", mod)
            add_compiled_tpl_method mod, method_name, <<-RUBY, __FILE__, __LINE__
def #{method_name}
  rest_out = #{rest_method_name}()
  fst_compiler = #{fst_method_name}(rest_out)
  engine_divider()
  fst_compiler.execute(self)
end
RUBY
          else
            ruby_code = (compiled_tpl.props[:ruby_code] ||
                         compiled_tpl.ruby_code) rescue nil
            fail "No ':ruby_code' property found in #{compiled_tpl}" unless ruby_code
            add_compiled_tpl_method mod, method_name, <<-RUBY, __FILE__, __LINE__
def #{method_name}
  #{ruby_code}
end
RUBY
          end
        props = compiled_tpl.props rescue Hash.new
        [mod, method_name, props]
      end

      def add_compiled_tpl_method(mod, method_name, src, file=nil, line=nil)
        desc = {
          :kind => :template_method,
          :method => method_name
        }
        Alloy::Utils::CodegenRepo.eval_code mod, src, file, line, desc
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
        when Array
          formats = format
          fail "Zero-elem array" unless formats.size > 0
          fst_compiler = get_compiler(formats[0])
          if formats.size == 1
            fst_compiler
          else
            rest_compiler = get_compiler(formats[1..-1])
            lambda{|source| fst_compiler.call(rest_compiler.call(source))}
          end
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
    def needs_env?()       @needs_env end
    def name()             @name end
    def props()            @props end
    def merge_props(props) @props.merge! props end

    # @return [Object]
    def execute(env=nil) fail "" end

    def gen_method_name
      arr = [props[:view], props[:template]].compact
      if arr.empty?
        nil
      else
        File.join(arr).gsub /[\/\\\.]/, "_"
      end
    end

    def inspect
      "#{self.class.relative_name}"
    end
  end

  # =================================================================

  class CompiledTextTemplate < CompiledTemplate
    def initialize(text, name="TXT")
      super(name, false)
      @text = text
    end

    def execute(env=nil) @text end
  end

  # =================================================================

  class CompiledProcTemplate < CompiledTemplate
    attr_reader :proc
    def initialize(proc, name="PROC")
      super(name, true)
      fail "not a no-arg proc" unless Proc === proc && proc.arity == 0
      @proc = proc
    end

    def execute(env=nil) @proc.call end
  end

  # =================================================================

  class CompiledCompositeTemplate < CompiledTemplate
    attr_reader :fst, :rest

    # @param fst [Proc] - compiler
    # @param rest [CompiledTemplate] - compiled
    def initialize(name, fst, rest)
      super(name, true)
      @fst = fst
      @rest = rest
    end

    def execute(env)
      rest_out = @rest.execute(env)
      fst_compiled = @fst.call(rest_out)
      #TODO: don't hardcode this call to engine_divider
      env.engine_divider() #rescue nil
      fst_compiled.execute(env)
    end
  end

  # =================================================================

  class CompiledClassTemplate < CompiledTemplate
    def initialize(method_name, name=method_name, props={}, &block)
      super(name, true, props, &block)
      @method_name = method_name.to_sym
    end

    def execute(env) env.send @method_name end
  end

  # =================================================================

  class CTE < CompiledTemplate
    def initialize(name, engine, props={}, &block)
      fail "not a proc" unless Proc === engine
      super(name, engine.arity != 0, props, &block)
      @engine = engine
    end

    def execute(env) call_proc(@engine, env) end

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
