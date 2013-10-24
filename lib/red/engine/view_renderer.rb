require 'red/engine/access_listener'
require 'red/engine/view_tree'
require 'red/engine/rendering_cache'
require 'red/engine/template_engine'
require 'red/engine/compiled_template_repo'
require 'sdg_utils/config'
require 'sdg_utils/meta_utils'

module Red
  module Engine

    class ViewError < StandardError
    end

    # ================================================================
    #  Class +ViewRenderer+
    # ================================================================
    class ViewRenderer

      def default_opts
        Red.conf.renderer
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
      def as_node(type, locals_map, source, tpl_id=nil)
        node = start_node(type, source)
        node.locals_map = locals_map
        begin
          node.compiled_tpl =
            CompiledTemplateRepo.find(tpl_id) if tpl_id
            # tpl || _to_compiled_class_template(source, "expr")
            # lambda{_compile_content(node.to_erb_template, [".erb"])}
          result = yield
          _concat result
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

      def concat(str) str end

      def _concat(str)
        require 'cgi'
        cn = curr_node
        if str && cn.no_output?
          (str = CGI::escapeHTML(str) unless cn.const? || str.html_safe?) rescue nil
          cn.output = str.to_s
        end
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
                 tpl = tpl.call if Proc === tpl
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
        root
        # if node.parent.nil?
        #   root
        # else
        #   fail "Expected exactly 1 child" unless root.children.size == 1
        #   root.children[0]
        # end
      end

      def render_to_node(*args)
        my_render(*args)
        return @tree.root
      end

      def render(*args)
        my_render(*args)
      end

      def my_render(hash)
        hash = time_it("Normalizing") { _normalize(hash) }
        case
        when !@rendering
          _around_root(hash) { _render(hash) }
        else
          _render(hash)
        end
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
        ans = col.each do |obj|
          node = start_node(:tree)
          begin
            my_render(hash.merge :object => obj, :normalized => false)
          ensure
            end_node(node)
          end
        end
        ans.empty?() ? nil: ans
      end

      def _process(hash)
        tpl = time_it("fetching template") {
          _compile_template(hash)
        }
        raise_not_found_error(hash[:view], hash[:template]) unless tpl
        time_it("rendering template") {
          _render_template tpl, hash
        }
      end

      # @return [CompiledTemplate]
      def _compile_template(hash)
        case
        when hash.key?(:compiled_tpl)
        # === compiled template
          hash[:compiled_tpl]

        # === nothing
        when hash.key?(:nothing)
          _compile_content_with_view_props("", [".txt"], hash)

        # === plain text
        when text = hash.delete(:text)
          _compile_content_with_view_props(text, hash[:formats] || [".txt"], hash)

        # === inline template (default format .erb)
        when content = hash.delete(:inline)
          _compile_content_with_view_props(content, hash[:formats] || [".erb"], hash)

        # === Pathname pointing to file template
        when path = hash.delete(:pathname)
          _compile_file(path, hash)

        # === String pointing to file template
        when file = hash.delete(:file)
          opts = {:pathname => Pathname.new(file)}.merge!(hash)
          _compile_template opts

        # === template name, uses a convention to look up the actual file
        else
          search_and_compile_template(hash)
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

      def _render_template(tpl, hash)
        top_node = curr_node
        top_node.compiled_tpl = tpl unless top_node.compiled_tpl
        top_node.view_binding = hash[:view_binding]
        text = tpl.execute(top_node.view_binding)
        _concat text if text
        # if text && top_node.children.empty?
        #   top_node.output = text
        # end
      end

      def _compile_content_with_view_props(content, formats, hash, props={})
        props = {:view => hash[:view], :template => hash[:template]}.merge!(props)
        _compile_content(content, formats, props)
      end

      def _compile_content(content, formats, props={})
        key = @conf.no_content_cache ? "" : "#{formats.join('')}:#{content}"
        RenderingCache.content.fetch(key, @conf.no_content_cache) {
          time_it("compiling and generating code") {
            tpl = TemplateEngine.compile(content, formats)
            tpl.merge_props props
            if tpl.needs_env?
              tpl = CompiledTemplateRepo.create(tpl)
            end
            tpl
          }
        }
      end

      def _compile_file(path, hash)
        raise ViewError, "Not a file: #{file}" unless path.file?
        formats = hash[:formats] || path_formats(path)
        RenderingCache.file.fetch("#{path}#{formats.join('')}", @conf.no_file_cache) {
          time_it("Reading file: #{path}") {
            obj = hash[:object]
            ext = obj ? " for obj: #{obj}:#{obj.class}" : ""
            trace "### #{_indent}Rendering file #{path}#{ext}"
            _compile_content_with_view_props path.read, formats, hash, :pathname => path
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

      def search_and_compile_template(hash)
        view = hash[:view]
        tpl_candidates = hash[:hierarchy]
        view_cannon = "#{view}/[#{tpl_candidates.join(';')}]"
        RenderingCache.template.fetch(view_cannon, @conf.no_template_cache) {
          opts = time_it("Finding templated: #{view_cannon}") {
            search_template_file(view, tpl_candidates, !!hash[:partial])
          }
          opts and _compile_template(hash.merge(opts))
        }
      end

      def search_template_file(view, tpl_candidates, is_partial)
        @view_finder = @conf.view_finder
        parent_dir = curr_node.compiled_tpl.props[:pathname].dirname rescue nil
        path = nil
        tpl_candidates.each do |tmpl|
          path = @view_finder.find_in_folder(parent_dir, tmpl, is_partial) rescue nil
          break if path
          path = @view_finder.find_view(view, tmpl, is_partial)
          break if path
        end
        path
      end

      def raise_not_found_error(view, template)
        err_msg = "Template `#{template}' for view `#{view}' not found.\n"
        if @view_finder && @view_finder.respond_to?(:candidates)
          cand = @view_finder.candidates.join("\n  ")
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
          _normalize :template => hash.to_s
          # if @rendering
          #   _normalize :partial => true, :template => "primitive", :object => hash
          # else
          # end
        when Proc
          _normalize :recurse => hash
        when Hash
          if hash[:normalized]
            return hash.merge :view => current_view(),
                              :view_binding => get_view_binding_obj(hash)
          end
          view = hash[:view] || current_view() || "application"
          tmpl = hash[:template]
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
          hier = if tmpl
                   [tmpl]
                 elsif Red::Model::Record === obj
                   record_cls = obj.class
                   types = [record_cls] + record_cls.all_supersigs
                   types.map{|r| r.relative_name.underscore}
                 else
                   ["index", "main"]
                 end

          locals = {}.merge!(hash[:locals] || {})

          # -------------------------------------------------------------------
          #  if object is specified, add local variables pointing to it
          # -------------------------------------------------------------------
          if obj
            tpl_identifier = SDGUtils::MetaUtils.check_identifier(hash[:template])
            var_name = hash[:as] || tpl_identifier || "it"
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
        cn = curr_node
        parent = hash[:view_binding] ||
                 (cn.view_binding if cn) ||
                 (cn.parent.view_binding if cn && cn.parent)
        locals = hash[:locals] || {}
        locals = locals.merge(cn.locals_map) if cn
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
        find_view_file views, templates
      end

      def find_in_folder(dir, template, is_partial)
        templates = is_partial ? [partialize(template), template]
                               : [template]
        templates.each do |t|
          file = check_file(dir, t)
          file and return file
        end
        nil
      end

      private

      # @param prefixes [Array(String)]
      # @param template_names [Array(String)]
      # @return [Hash, nil]
      def find_view_file(prefixes, template_names)
        root = Red.conf.root
        root = Pathname.new(root) if String === root
        view_paths = Red.conf.view_paths
        view_paths.each do |view|
          prefixes.each do |prefix|
            dir = root.join(view, prefix)
            template_names.each do |template_name|
              file = check_file(dir, template_name)
              file and return file.merge!({:view => prefix, :template => template_name})
            end
          end
        end
        nil
      end

      # @param dir [Pathname]
      # @param template_name [String]
      # @return [Hash, nil]
      def check_file(dir, template_name)
        return nil unless dir.directory?

        no_ext = dir.join(template_name)
        candidates << no_ext.to_s
        no_ext.file? and return no_ext

        any_ext = dir.join(template_name + ".*[^~]")
        candidates << any_ext.to_s
        cands = Dir[any_ext]

        if cands.empty?
          return nil
        else
          {:pathname => Pathname.new(cands.first)}
        end
      end
    end

  end
end
