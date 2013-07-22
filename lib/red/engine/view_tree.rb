require 'red/view/view_helpers'
require 'sdg_utils/assertions'
require 'sdg_utils/print_utils/tree_printer'

module Red
  module Engine

    # ================================================================
    #  Class +ViewBinding+
    # ---------------------------------------------------------------
    #
    # Used for bindings when evaluating expressions inside templates
    # (which is actually delegated to an off-the-shelf template
    # engine).
    # ================================================================
    class ViewBinding
      include Red::View::ViewHelpers
      include ActionView::Helpers if defined? ActionView::Helpers
      include ActionView::Context if defined? ActionView::Context

      @@widget_id = 0

      def parent() @parent end

      def initialize(renderer, parent=nil, helpers=[])
        @renderer = renderer
        @parent = parent
        @user_inst_vars = {}
        @locals = {}
        singleton_cls = class << self; self end
        [helpers].flatten.compact.each do |mod|
          singleton_cls.send :include, mod
        end
        _prepare_context if defined? ActionView::Context
      end

      def gravatar_for(user, hash={})
        '<img src="https://secure.gravatar.com/avatar/52263f4f0ad7eefd3464de854f4828f2?s=32" alt="aleksandar milicevic"></img>'
      end

      def user_inst_vars() @user_inst_vars ||= {} end
      def locals()         @locals ||= {} end

      def render(*args) @renderer.render(*args) end
      def mk_out()      @renderer end

      def engine_divider()
        @renderer.send :_collapseTopNode
      end

      def style(name)          @renderer.tree.styles << name; "" end
      def script(name)         @renderer.tree.scripts << name; "" end
      def styles()             @styles  ||= Set.new end
      def scripts()            @scripts ||= Set.new end
      def get_binding()        @last_binding ||= binding() end
      def _add_getters(hash)
        singl_cls = (class << self; self end)
        cls = self.class
        @locals = {}
        # copy instance variables from parent
        if ViewBinding === @parent
          @locals.merge! @parent.locals
        end
        @locals.merge! hash if hash
        @locals.each do |k, v|
          if k.to_s =~ /^[A-Z]/
            # constant
            cls.send :remove_const, k if cls.const_defined?(k, false)
            cls.const_set(k, v)
          else
            # method or variable
            body = (Proc === v) ? v : lambda{v}
            name = (k[0] == '@') ? k[1..-1] : k
            define_singleton_method(name.to_sym, body)
            if k[0] == '@'
              instance_variable_set(k, v)
              @user_inst_vars.merge! k => v
            end
          end
        end
      end

      def method_missing(sym, *args)
        case @parent
        when NilClass
          super
        when Binding
          if args.empty?
            @parent.eval sym.to_s
          else
            mth = @parent.eval "method :#{sym}"
            mth ? mth.call(*args) : super
          end
        else
          @parent.send sym, *args
        end
      end
    end

    # ================================================================
    #  Class +Query+
    # ================================================================
    class Query
      attr_accessor :target, :method, :args, :result
      def initialize(target, method, args, result)
        @target = target
        @method = method
        @args = args
        @result = result
      end
      def to_s
        "#{target}.#{method}(#{args.reduce(""){|acc, e| acc + e.to_s}})"
      end
    end

    # ================================================================
    #  Class +ViewInfoTree+
    # ================================================================
    class ViewInfoTree
      attr_reader :root, :render_options, :root_binding
      attr_accessor :client

      def initialize(root_binding, render_options={})
        @root_binding = root_binding
        @render_options = render_options
      end

      def styles()  @styles  ||= Set.new end
      def scripts() @scripts ||= Set.new end

      def set_root(node)
        @root = node
        node.parent_tree = self
        node.parent = nil
      end

      def print_full_info(depth=1)  @root ? @root.print_full_info(depth) : "" end
      def print_short_info(depth=1) @root ? @root.print_short_info(depth) : "" end

      def to_s
        "#{self.class.name}(@root = #{@root})"
      end
    end

    # ================================================================
    #  Class +ConstNodeRepo+
    # ================================================================
    class ConstNodeRepo
      @@repo = {}
      class << self
        def create(source)
          node = ViewInfoNode.create_const()
          node.src = source
          node.output = eval "#{source}"
          node.freeze
          @@repo[node.id] = node
          node
        end

        def find(id) @@repo[id] end
        def find!(id) find(id) || fail("const node(#{id}) not found") end

      end
    end

    # ================================================================
    #  Class +ViewInfoNode+
    # ================================================================
    class ViewInfoNode
      include SDGUtils::Assertions

      attr_reader :type, :children, :extras, :deps
      attr_accessor :id, :src, :output, :render_options, :compiled_tpl
      attr_accessor :parent_tree, :parent, :index_in_parent
      attr_accessor :locals_map

      @@id = 0

      def self.create_const() ViewInfoNode.new(:const) end
      def self.create_expr()  ViewInfoNode.new(:expr) end
      def self.create_tree()  ViewInfoNode.new(:tree) end

      def self.create(type)
        case type
        when :const; create_const
        when :expr;  create_expr
        when :tree;  create_tree
        else fail "Unknown type: #{type}"
        end
      end

      def const?() @type == :const end
      def expr?() @type == :expr end
      def tree?() @type == :tree end

      def retype_to_tree() @type = :tree end

      def view_binding()
        render_options[:view_binding] if Hash === render_options
      end

      def to_erb_template
        return nil unless src
        if const?
          eval(src)
        else
          "<%= #{src} %>"
        end
      end

      private

      def initialize(type)
        @type = type
        @children = []
        @extras = {}
        @render_options = {}
        @locals_map = {}
        @src = ""
        @output = ""
        @deps = ViewDependencies.new
        @parent = nil
        @index_in_parent = -1
        @id = (@@id += 1)
        if const?
          [:parent, :parent_tree, :index_in_parent].each do |sym|
            self.define_singleton_method sym do
              fail "const nodes can be shares so they don't have parent pointers"
            end
            self.define_singleton_method "#{sym}=".to_sym do |val|
              # don't fail, just refuse to set values
            end
          end
        end
      end

      def dbg_out
        "\n#{print_short_info}"
      end

      public

      def output=(str)
        fail "can't set output to a non-leaf node" unless @children.empty? || str.empty?
        @output = str
      end

      # Recursively finds all children
      def all_children()
        ans = []
        children.each do |ch|
          ans << ch
          ans += ch.all_children
        end
        ans
      end

      def yield_all_nodes(&block)
        yield(self)
        children.each{|ch| ch.yield_all_nodes(&block)}
      end

      def reset_children() @children = [] end
      def reset_output()   @output = "" end

      def add_child(node)
        assert tree?, "can't add child to #{@type.inspect} node"
        assert output.empty?, "can't add child when output is set: #{dbg_out}"
        node.parent = self
        node.index_in_parent = @children.size
        @children << node
      end

      def set_child(at, node)
        assert tree?, "can't set child to #{@type.inspect} node"
        assert output.empty?, "can't set child when output is set #{dbg_out}"
        if Array === node
          set_children(at, node)
        else
          set_children(at, [node])
        end
      end

      def set_children(at, nodes)
        return if nodes.nil? || nodes.empty?
        assert tree?, "can't set children to #{@type.inspect} node"
        assert output.empty?, "can't set children when output is set #{dbg_out}"
        front = at == 0 ? [] : @children[0..(at-1)]
        back = @children[(at+1)..-1] || []
        @children = front + nodes + back
        for i in at..(@children.size - 1) do
          node = @children[i]
          node.parent = self
          node.index_in_parent = i
        end
      end

      def result
        if children.empty?
          @output || ""
        else
          @children.reduce(""){|acc, c| acc + c.result}
        end
      end

      def replace_with(node)
        if parent
          parent.set_child(index_in_parent, node)
        else
          parent_tree.set_root(node)
        end
      end

      def synth?
        !!extras[:synth]
      end

      def no_deps?
        deps.empty?
      end

      def clear_deps
        deps = ViewDependencies.new
      end

      def reload_all
        deps.objs.each do |obj, fld|
          obj.reload
        end
      end

      def short_info()
        deps_str = @deps.to_s.split("\n").map{|e| "  " + e}.join("\n")
        [
         "Id: #{id}",
         "Type: #{type}",
         "File: #{extras[:pathname]}",
         "Object: #{extras[:object]}",
         "Src: #{src[0..60].inspect}",
         # "Compiled template: #{compiled_tpl.props if compiled_tpl}",
         "Compiled template: #{compiled_tpl.class}",
         "Output: #{output[0..60].inspect}",
         "Children: #{children.size}",
         "Deps(#{deps.__id__}):",
         "#{deps_str}".split("\n"),
        ].flatten
      end

      def print_short_info()
        short_info.join("\n")
      end

      TREE_PRINTER = SDGUtils::PrintUtils::TreePrinter.new({
        :indent_size  => 2,
        :print_root   => true,
        :children_sep => "\n",
        :box         => {
                          :width => :tight
                        },
        :printer      => lambda {|node| node.short_info},
        :descender    => lambda {|node| node.children.select{|c| !c.synth?}},
      })

      def print_full_info(depth=1)
        TREE_PRINTER.print_tree(self, 1)
      end

      def to_s
        "#{self.class.name}(#{id})"
      end

    end

  end
end