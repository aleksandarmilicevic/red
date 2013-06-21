require 'red/view/view_helpers'
require 'red/engine/access_listener'
require 'red/engine/template_engine'
require 'sdg_utils/config'
require 'sdg_utils/assertions'
require 'sdg_utils/caching/cache.rb'
require 'sdg_utils/print_utils/tree_printer'

module Red
  module Engine

    class ViewError < StandardError
    end

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

      @@widget_id = 0

      def parent() @parent end

      def initialize(renderer, parent=nil)
        @renderer = renderer
        @parent = parent
        @user_inst_vars = {}
      end

      def user_inst_vars() @user_inst_vars ||= {} end

      def render(*args) @renderer.render(*args) end
      def mk_out()      @renderer end

      def engine_divider()
        @renderer.send :_collapseTopNode
      end

      def widget(name, locals={})
        @@widget_id = @@widget_id + 1
        render :partial => "widget",
               :locals => { :widget_name => name,
                            :widget_id => @@widget_id,
                            :locals => locals }
      end

      def style(name)          @renderer.tree.styles << name; "" end
      def script(name)         @renderer.tree.scripts << name; "" end
      def styles()             @styles  ||= Set.new end
      def scripts()            @scripts ||= Set.new end
      def get_binding()        @last_binding ||= binding() end
      def _add_getters(hash)
        singl_cls = (class << self; self end)
        cls = self.class
        hash.each do |k, v|
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
        # also copy instance variables from parent
        if ViewBinding === @parent
          @parent.user_inst_vars.each do |k, v|
            instance_variable_set(k, v)
            @user_inst_vars.merge! k => v
            define_singleton_method(k[1..-1].to_sym, lambda{v})
          end
        end
      end

      def method_missing(sym, *args)
        case @parent
        when NilClass
          super
        when Binding
          @parent.eval "#{sym.to_s}(#{args.map{|a|a.to_s}.join(',')})"
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
        render_options[:view_binding] if render_options
      end

      def template
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
      end

      def dbg_out
        "\n#{print_short_info}"
      end

      public

      def output=(str)
        unless @children.empty? || str.empty?
          fail ""
        end
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
         "Output: #{output[0..60].inspect}",
         "Children: #{children.size}",
         "Deps:",
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

      # TAB1 = "|  "
      # TAB2 = "`--"
      # def _indent(depth, t1, t2)
      #   (0..depth-1).reduce("") {|acc,i| acc + (i == depth-1 ? t2 : t1)}
      # end

      # def print_short_info(depth=1)
      #   ind_str = _indent(depth, TAB1, TAB2)
      #   ind_str2 = _indent(depth, TAB1, TAB1)
      #   deps_str = @deps.to_s.split("\n").map{|e| ind_str2 + "  " + e}.join("\n")
      #   "#{ind_str}Id: #{id}\n" +
      #   "#{ind_str}Type: #{type}\n" +
      #   "#{ind_str}File: #{extras[:pathname]}\n" +
      #   "#{ind_str}Object: #{extras[:object]}\n" +
      #   "#{ind_str}Src: #{src[0..60].inspect}\n" +
      #   "#{ind_str}Output: #{output[0..60].inspect}\n" +
      #   "#{ind_str}Children: #{children.size}\n" +
      #   "#{ind_str}Deps:\n#{deps_str}\n"
      # end

      # def print_full_info(depth=1)
      #   children_str = @children.select{|c|
      #                    !c.synth?
      #                  }.map{|c|
      #                    c.print_full_info(depth+1)
      #                  }.join("\n")
      #   print_short_info(depth) + "\n" + "#{children_str}"
      # end

      def to_s
        "#{self.class.name}(#{id})"
      end

    end

    # ================================================================
    #  Class +ViewRenderer+
    # ================================================================
    class ViewRenderer

      def default_opts
        @@default_opts ||= SDGUtils::Config.new(nil, {
          :event_server => Red.boss,
          :view_finder => ViewFinder.new,
          :access_listener => Red.boss.access_listener,
          :current_view => nil,
        })
      end

      def initialize(hash={})
        @stack = []
        @conf = default_opts.extend(hash)
        @rendering = false
      end

      def curr_node
        (@stack.empty?) ? nil : @stack.last
      end

      def tree
        @tree  # _render_view sets this attribute
      end

      # # ------------------------------------------------------------
      # #  Event handling methods
      # # ------------------------------------------------------------

      # def call(event, par)
      #   case event
      #   when Red::E_FIELD_READ
      #     curr_node.deps.field_accessed(par[:object], par[:field], par[:return])
      #   when Red::E_FIELD_WRITTEN
      #     curr_node.deps.field_accessed(par[:object], par[:field], par[:value])
      #   when Red::E_QUERY_EXECUTED
      #     curr_node.deps.handle_query_executed(par[:target], par[:method],
      #                                          par[:args], par[:result])
      #   else
      #     fail "unexpected event type: #{event}"
      #   end
      # end

      # ------------------------------------------------------------
      #  buffer methods (called by the template engine)
      # ------------------------------------------------------------

      # @param type [String]
      # @param source [String]
      def as_node(type, locals_map, source)
        node = start_node(type, source)
        node.locals_map = locals_map
        begin
          node.compiled_tpl = lambda{_compile_content(node.template, [".erb"])}
          yield
        ensure
          end_node(node)
        end
      end

      def concat(str)
        curr_node.output.concat(str)
      end

      def force_encoding(enc)
        curr_node.result.force_encoding(enc)
      end

      # ------------------------------------------------------------

      # @param node [ViewInfoNode]
      # @result [ViewInfoNode]
      def rerender_node(node)
        return node if node.const?

        vb = begin
               parent_binding = node.parent.view_binding if node.parent
               node.view_binding || parent_binding
             end

        root = case
               when tpl=node.compiled_tpl
                 tpl = (Proc === tpl ? tpl.call : tpl)
                 opts = { :compiled_tpl => tpl,
                          :view_binding => vb }
                 ans = render_to_node opts
                 ans.compiled_tpl = tpl
                 ans
               when !node.src.empty?
                 opts = { :inline => "#{node.template}",
                          :view_binding => vb }
                 render_to_node opts
               else
                 render_to_node node.render_options
               end

        root.src = node.src
        if node.parent.nil?
          root
        else
          fail "Expected exactly 1 child" unless root.children.size == 1
          root.children[0]
        end
      end

      def render_to_node(*args)
        my_render(*args)
        return @tree.root
      end

      def render(*args)
        my_render(*args)
        ""
      end

      def my_render(hash)
        hash = _normalize(hash)
        case
        when !@rendering
          _around_root(hash) { _render(hash) }
        else
          _render(hash)
        end
        ""
      end

      protected

      def trace(str)     Red.conf.logger.debug str end
      def trace_hit(ch)  trace "++++++++ #{ch.name} cache HIT: #{ch.hits}" end
      def trace_miss(ch) trace "-------- #{ch.name} cache MISS: #{ch.misses}" end

      def _around_root(hash)
        @rendering = true
        @tree = ViewInfoTree.new(hash[:view_binding].get_binding, hash)
        root_node = start_node(:tree)
        deps_lambda = lambda{curr_node.deps}
        @conf.access_listener.register_deps(deps_lambda)
        begin
          yield
        ensure
          @conf.access_listener.unregister_deps(deps_lambda)
          end_node(root_node)
          fail "expected empty stack after root node was removed" unless @stack.empty?
          @rendering = false
        end
      end

      def _render(hash)
        cn = curr_node
        cn.retype_to_tree
        cn.render_options = hash.clone
        if hash[:nothing]
        elsif proc = hash[:recurse]
          my_render(proc.call())
        elsif hash[:collection]
          _process_collection(hash.delete(:collection), hash)
        else
          _process(hash)
        end
      end

      def _process_collection(col, hash)
        col.each do |obj|
          node = start_node(:tree)
          begin
            my_render(hash.merge :object => obj, :normalized => false)
          ensure
            end_node(node)
          end
        end
      end

      def _process(hash)
        case
        when hash.key?(:compiled_tpl)
        # === compiled template
          _render_template hash[:compiled_tpl], hash

        # === nothing
        when hash.key?(:nothing)
          tpl = _compile_content("", [".txt"])
          _render_template tpl, hash

        # === plain text
        when text = hash.delete(:text)
          tpl = _compile_content(text, hash[:formats] || [".txt"])
          _render_template tpl, hash

        # === inline template (default format .erb)
        when content = hash.delete(:inline)
          tpl = _compile_content(content, hash[:formats] || [".erb"])
          _render_template tpl, hash

        # === Pathname pointing to file template
        when path = hash.delete(:pathname)
          tpl = _compile_file(path, hash)
          _render_template tpl, hash

        # === String pointing to file template
        when file = hash.delete(:file)
          opts = {:pathname => Pathname.new(file)}.merge(hash)
          _process opts

        # === template name, uses a convention to look up the actual file
        when hash.key?(:template)
          view = hash[:view]
          template = hash[:template]
          view_finder = @conf.view_finder
          parent_dir = curr_node.parent.extras[:pathname].dirname rescue nil
          path = nil
          ([template] + hash[:hierarchy]).each do |tmpl|
            path = view_finder.find_in_folder(dir, tmpl) rescue nil
            break if path
            path = view_finder.find_view(view, tmpl, hash[:partial])
            break if path
          end
          if path.nil?
            raise_not_found_error(view, template, @conf.view_finder)
          else
            _process hash.merge(path)
          end
        # === Unknown
        else
          raise ViewError "Nothing specified" # OR render :nothing ?
        end
      end

      # Returns the list of file formats of this file in reverse order.
      #
      # Example:
      #   path = "dir/file.txt.erb"
      #   result = [".erb", ".txt"]
      #
      # @result [Array(String)]
      # @param path [Pathname]
      def path_formats(path)
        path.basename.to_s.split(".")[1..-1].map{|e| ".#{e}"}
      end

      def read_binding_from(hash)
        hash[:__binding__] || hash[:view_binding].get_binding()
      end

      def _render_template(tpl, hash)
        top_node = curr_node
        b = read_binding_from(hash)
        top_node.compiled_tpl = tpl unless top_node.compiled_tpl
        text = tpl.execute(b)
        if top_node.children.empty?
          top_node.output = text
        end
      end

      @@content_tpl_cache = SDGUtils::Caching::Cache.new("content", :fake => true)

      def _compile_content(content, formats)
        @@content_tpl_cache.on_hit { |cache|
          trace_hit(cache)
        }.on_miss { |cache|
          trace_miss(cache)
        }.fetch(formats.join("") + content) {
          TemplateEngine.compile(content, formats)
        }
      end

      @@file_tpl_cache = SDGUtils::Caching::Cache.new("file")

      def _compile_file(path, hash)
        raise ViewError, "Not a file: #{file}" unless path.file?
        curr_node.extras[:pathname] = path
        ext = hash[:object] ? " for obj: #{hash[:object]}:#{hash[:object].class}" : ""
        formats = hash[:formats] || path_formats(path)
        @@file_tpl_cache.on_hit { |cache|
          trace_hit(cache)
        }.on_miss { |cache|
          trace_miss(cache)
          trace "### #{_indent}Rendering file #{path}#{ext}"
        }.fetch(path.realpath.to_s + formats.join("")) {
          _compile_content(path.read, formats)
        }
      end

      def _collapseTopNode
        top_node = curr_node
        top_node.all_children.map{|e| e.deps}.each{|d| top_node.deps.merge!(d)}
        top_node.reset_children
        top_node.reset_output
      end

      def current_view()
        @conf.current_view || (@tree.render_options[:view] rescue nil)
      end

      def raise_not_found_error(view, template, view_finder)
        err_msg = "Template `#{template}' for view `#{view}' not found.\n"
        if view_finder.respond_to? :candidates
          cand = view_finder.candidates.join("\n  ")
          err_msg += "Candidates checked:\n  #{cand}"
        end
        raise ViewError, err_msg
      end

      TAB1 = "|  "
      TAB2 = "`--"
      def _indent()
        (0..depth-2).reduce("") {|acc,i| acc + (i == depth-2 ? TAB2 : TAB1)}
      end

      def depth
        @stack.size
      end

      def start_node(type, src="")
        new_node = ViewInfoNode.create(type)
        new_node.src = src
        if @stack.empty?
          @tree.set_root(new_node)
        else
          curr_node().add_child(new_node)
        end
        @stack.push(new_node)
        new_node
      end

      def end_node(expected=nil)
        node = @stack.pop
        fail "stack corrupted" unless expected.nil? || expected === node
        node
      end

      def _normalize(hash)
        case hash
        when :nothing, NilClass
          _normalize :nothing => true
        when Symbol, String
          if @rendering
            _normalize :partial => true, :template => "primitive", :object => hash
          else
            _normalize :template => hash.to_s
          end
        when Proc
          _normalize :recurse => hash
        when Hash
          if hash[:normalized]
            return hash.merge :view => current_view(),
                              :view_binding => get_view_binding_obj(hash)
          end
          view = hash[:view] || current_view() || "application"
          tmpl = hash[:template] || "main"
          partial = hash[:partial]
          is_partial = !!partial

          if is_partial && (partial != is_partial)
            # meaning that hash[:partial] is not a bool, but presumably string
            tmpl = partial
          end

          # -------------------------------------------------------------------
          #  extract type hierarchy if an object is given
          # -------------------------------------------------------------------
          obj = hash[:object]
          hier = if Red::Model::Record === obj
                   record_cls = obj.class
                   types = [record_cls] + record_cls.all_supersigs
                   types.map{|r| r.relative_name.underscore}
                 else
                   []
                 end

          locals = {}.merge!(hash[:locals] || {})

          # -------------------------------------------------------------------
          #  if object is specified, add local variables pointing to it
          # -------------------------------------------------------------------
          if obj
            to_var = lambda{|str|
              return nil unless str
              str = str.to_sym
              ok = Object.new.send(:define_singleton_method, str, lambda{}) rescue false
              ok ? str : nil
            }
            var_name = hash[:as] || to_var.call(hash[:template]) || "it"
            ([var_name] + hier).each do |hname|
              locals.merge! hname => obj
            end
          end

          # -------------------------------------------------------------------

          ans = hash.merge :normalized => true,
                           :view => view,
                           :template => tmpl,
                           :partial => is_partial,
                           :locals => locals,
                           :layout=> false,
                           :hierarchy => hier
          ans.merge! :view_binding => get_view_binding_obj(ans)
          ans
        when Red::Model::Record
          _normalize :partial => true, :object => hash
        else
          if hash.kind_of?(Array) || hash.kind_of?(ActiveRecord::Relation)
            if hash.size == 1
              _normalize :partial => true, :object => hash[0]
            else
              _normalize :partial => true, :collection => hash
            end
          else
            _normalize :partial => true, :template => "primitive", :object => hash
          end
        end
      end

      def get_view_binding_obj(hash)
        parent = hash[:view_binding] || (curr_node.parent.view_binding rescue nil)
        obj = ViewBinding.new(self, parent)
        locals = hash[:locals] || {}
        locals = locals.merge(curr_node.locals_map) if curr_node
        obj._add_getters(locals)
        obj
      end

    end

    # ----------------------------------------------------------
    #  Class +ViewFinder+
    # ----------------------------------------------------------
    class ViewFinder
      def candidates() @candidates ||= [] end

      def find_view(view, template, is_partial)
        @candidates = []
        views = [view, ""]
        templates = is_partial ? ["_#{template}", template]
                               : [template, view]
        file = find_view_file views, templates
        if !file.nil?
          {:pathname => file}
        else
          nil
        end
      end

      def find_in_folder(dir, template, is_partial)
        templates = is_partial ? ["_#{template}", template]
                               : [template]
        templates.each do |t|
          file = check_file(dir, t)
          return file unless file.nil?
        end
        nil
      end

      private

      # @param prefixes [Array(String)]
      # @param template_names [Array(String)]
      # @return [Pathname]
      def find_view_file(prefixes, template_names)
        root = Red.conf.root
        root = Pathname.new(root) if String === root
        @candidates = []
        view_paths = Red.conf.view_paths
        view_paths.each do |view|
          prefixes.each do |prefix|
            dir = root.join(view, prefix)
            template_names.each do |template_name|
              file = check_file(dir, template_name)
              return file unless file.nil?
            end
          end
        end
        nil
      end

      # @param dir [Pathname]
      # @param template_name [String]
      # @return [Pathname, nil]
      def check_file(dir, template_name)
        return nil unless dir.directory?

        no_ext = dir.join(template_name)
        @candidates << no_ext.to_s
        no_ext.file? and return no_ext

        any_ext = dir.join(template_name + ".*")
        @candidates << any_ext.to_s
        candidates = Dir[any_ext]

        if candidates.empty?
          return nil
        else
          return Pathname.new(candidates.first)
        end
      end
    end

  end
end
