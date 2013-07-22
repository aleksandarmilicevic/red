require 'red/engine/access_listener'
require 'red/engine/view_tree'
require 'red/engine/template_engine'
require 'sdg_utils/config'
require 'sdg_utils/caching/cache.rb'

module Red
  module Engine

    class ViewError < StandardError
    end

    # ================================================================
    #  Class +ViewRenderer+
    # ================================================================
    class ViewRenderer

      def default_opts
        @@default_opts ||= SDGUtils::Config.new(nil, {
          :event_server => Red.boss,
          :view_finder => lambda{ViewFinder.new},
          :access_listener => Red.boss.access_listener,
          :current_view => nil,
          :no_template_cache? => false,
          :no_file_cache? => false,
          :no_content_cache? => true
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

      # ------------------------------------------------------------
      #  buffer methods (called by the template engine)
      # ------------------------------------------------------------

      # @param type [String]
      # @param source [String]
      def as_node(type, locals_map, source, tpl=nil)
        node = start_node(type, source)
        node.locals_map = locals_map
        begin
          node.compiled_tpl = tpl ||
            lambda{_compile_content(node.to_erb_template, [".erb"])}
          yield
        ensure
          end_node(node)
        end
      end

      def add_node(node)
        curr_node().add_child(node)
      end

      def add_node_by_id(node_id)
        add_node(ConstNodeRepo.find(node_id))
      end

      def render_template(compiled_template, bndg)
        _render_template(compiled_template, bndg)
      end

      def concat(str)
        require 'cgi'
        cn = curr_node
        (str = CGI::escapeHTML(str) if cn.expr? && !str.html_safe?) rescue nil
        cn.output.concat(str)
      end

      def force_encoding(enc)
        cn = curr_node
        Red.boss.time_it("Force encoding") {
          cn.result.force_encoding(enc)
        } if cn == @tree.root
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
                 opts = { :inline => "#{node.to_erb_template}",
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
        hash = time_it("Normalizing") { _normalize(hash) }
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
        cn.render_options = hash.clone unless Proc === cn.render_options
        if hash[:nothing]
        elsif proc = hash[:recurse]
          cn.render_options = proc
          my_render(proc.call)
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
          case content
          when String
            tpl = _compile_content(content, hash[:formats] || [".erb"])
            _render_template tpl, hash
          when Proc
            text = content.call
            curr_node.output = text
          else
            fail "unknown content kind #{content}:#{content.class}"
          end

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
          path = time_it("Finding template: #{hash[:template]}") {
            find_template_file(hash)
          }
          if path.nil?
            raise_not_found_error(view, template, view_finder)
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

      def _render_template(tpl, binding_or_hash)
        b = case binding_or_hash
            when Binding
              binding_or_hash
            when Hash
              read_binding_from(binding_or_hash)
            else
              arg = "#{binding_or_hash}:#{binding_or_hash.class}"
              fail "illegal argument: #{arg} is neither Binding nor Hash"
            end
        time_it("Rendering") {
          top_node = curr_node
          top_node.compiled_tpl = tpl unless top_node.compiled_tpl
          ans = time_it("executing template #{tpl.name}"){tpl.execute(b, self)}
          case ans
          when String
            top_node.output = ans # if top_node.children.empty?
          when NilClass
            # nothing (the execution created a view tree using the `as_node' function
          else
            fail "unknown template execution result"
          end
        }
      end

      def _partially_render_template(tpl)
        pevb = PartEvalViewBinding.new
        b = pevb.get_binding
        ans = tpl.execute(b, self)
        pevb.as_node :const, {}, ans.inspect if String === ans

        puts "============================"
        CTE.new("CompiledTree", lambda { |bndg, renderer|
                  puts "--------------------------------"
                  pevb.root.children.each do |n|
                    if n.const?
                      renderer.add_node(n)
                    else
                      n.compiled_tpl = TemplateEngine.compile(n.to_erb_template, ".erb")
                      renderer.as_node(n.type, n.locals_map, n.src) {
                        ans = bndg.eval n.src
                        renderer.concat(ans) if String === ans
                      }
                    end
                  end
                  nil
                }) do
        end
      end

      @@content_tpl_cache = SDGUtils::Caching::Cache.new("content")
      def _compile_content(content, formats)
        tpl = time_it("Compiling") {
          @@content_tpl_cache.fetch(formats.join("")+content, @conf.no_content_cache?) {
            TemplateEngine.compile(content, formats)
          }
        }

        # try run the compiler with an empty binding to obtain a partial tree
        # tpl2 = _partially_render_template(tpl) # rescue nil

        # tpl2 || tpl
      end

      @@file_tpl_cache = SDGUtils::Caching::Cache.new("file")
      def _compile_file(path, hash)
        raise ViewError, "Not a file: #{file}" unless path.file?
        curr_node.extras[:pathname] = path
        ext = hash[:object] ? " for obj: #{hash[:object]}:#{hash[:object].class}" : ""
        formats = hash[:formats] || path_formats(path)
        @@file_tpl_cache.fetch(path.realpath.to_s + formats.join(""),
                               @conf.no_file_cache?) {
          time_it("Reading file: #{path}") {
            trace "### #{_indent}Rendering file #{path}#{ext}"
            _compile_content(path.read, formats)
          }
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

      @@template_cache = SDGUtils::Caching::Cache.new("template")
      def find_template_file(hash)
        view = hash[:view]
        template = hash[:template]
        view_cannon = "#{view}/#{template}"
        @@template_cache.fetch(view_cannon, @conf.no_template_cache?) {
          view_finder = @conf.view_finder
          parent_dir = curr_node.parent.extras[:pathname].dirname rescue nil
          path = nil
          ([template] + hash[:hierarchy]).each do |tmpl|
            path = view_finder.find_in_folder(parent_dir, tmpl) rescue nil
            break if path
            path = view_finder.find_view(view, tmpl, hash[:partial])
            break if path
          end
          path
        }
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
        locals = hash[:locals] || {}
        locals = locals.merge(curr_node.locals_map) if curr_node
        obj = ViewBinding.new(self, parent, hash[:helpers])
        obj._add_getters(locals)
        obj
      end

      def time_it(task, &block)
        Red.boss.time_it("[ViewRenderer] #{task}", &block)
      end

    end

    # ----------------------------------------------------------
    #  Class +ViewFinder+
    # ----------------------------------------------------------
    class ViewFinder
      def candidates() @candidates ||= [] end

      def partialize(template)
        path = template.split("/")
        path.last.insert(0, "_")
        File.join(path)
      end

      def find_view(view, template, is_partial)
        views = [view, ""]
        templates = is_partial ? [partialize(template), template]
                               : [template, view]
        file = find_view_file views, templates
        if !file.nil?
          {:pathname => file}
        else
          nil
        end
      end

      def find_in_folder(dir, template, is_partial)
        templates = is_partial ? [partialize(template), template]
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
        candidates << no_ext.to_s
        no_ext.file? and return no_ext

        any_ext = dir.join(template_name + ".*")
        candidates << any_ext.to_s
        cands = Dir[any_ext]

        if cands.empty?
          return nil
        else
          return Pathname.new(cands.first)
        end
      end
    end

  end
end
