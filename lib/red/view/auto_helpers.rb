require 'red/engine/view_manager'
require 'red/engine/html_delim_node_printer'
require 'sdg_utils/html/tag_builder'

module Red
module View

  module AutoHelpers
    def autosave_fld(record, fld_name, hash={})
      fail "no record is provided" unless record
      av = hash[:autoview]
      av = true if av.nil?
      if av
        hc = hash.clone
        hc[:autoview] = false
        autoview :inline => "<%= autosave_fld record, fld_name, hash %>",
                 :locals => {:record => record, :fld_name => fld_name, :hash => hc}
      else
        hash = hash.clone
        hash[:params] = {
          :target => record,
          :fieldName => fld_name,
          :saveTarget => true
        }
        hash[:body] ||= record.read_field(fld_name) || hash[:default]
        autotrigger(RedLib::Crud::LinkToRecord, "fieldValue", hash)
      end
    end

    def autotrigger(event, fld_name, hash={})
      av = hash[:autoview]
      av = true if av.nil?
      if av
        hc = hash.clone
        hc[:autoview] = false
        autoview :inline => "<%= autotrigger event, fld_name, hash %>",
                 :locals => {:event => event, :fld_name => fld_name, :hash => hc}
      else
        event_cls = (Red::Model::Event > event) ? event : event.class
        fail "not an event: #{event.inspect}" unless Red::Model::Event > event

        hash = hash.clone
        tag = hash.delete(:tag) || "span"
        body = hash.delete(:body) || ""
        escape_body = true
        escape_body = !!hash.delete(:escape_body) if hash.has_key?(:escape_body)
        multiline = !!hash.delete(:multiline)
        event_params = hash.delete(:params) || {}

        blder = SDGUtils::HTML::TagBuilder.new(tag)
        blder
          .body(body)
          .attr("data-event-name", event.relative_name)
          .attr("data-field-name", fld_name)
          .attr("contenteditable", true)
          .attr("class", "red-autotrigger")
          .when(!multiline, :attr, "class", "singlelineedit")

        event_params.each do |key, value|
          value_str = value.to_s
          if value.kind_of? Red::Model::Record
            value_str = "${Red.Meta.createRecord('#{value.class.name}', #{value.id})}"
          end
          blder.attr("data-param-#{key}", value_str)
        end

        blder
          .attrs(hash)
          .build(escape_body).html_safe()
      end
    end

    def file_location(file_record)
      file_record
    end

    # ===============================================================
    # Renders a specified view using the `ViewManager' so that all
    # field accesses are detected and the view is automatically
    # updated when those fields change.
    #
    # @param hash [Hash]
    # ===============================================================
    def autoview(hash)
      vm = render_autoview(hash)
      print_autoview(vm)
      # h1 = (Proc === hash) ? hash.call : hash.clone
      # hi = h1[:inline]; h1[:inline] = hi.call if Proc === hi
      # t1 = time_it("Rails render"){controller.render_to_string(h1).html_safe}
      # vm = time_it("Red render"){render_autoview(hash)}
      # time_it("Red print"){print_autoview(vm)}
    end

    # ===============================================================
    # @param expr [String, NilClass]
    # @param block [Proc]
    # ===============================================================
    def autoexpr(expr=nil, &block)
      case expr
      when Symbol, String
        autoview :inline => "<%=#{expr}%>"
      when NilClass, Proc
        proc = expr || block
        fail "no expression given" unless proc
        autoview :text => proc
      end
    end

    def widget(name, locals={})
      @@widget_id = @@widget_id + 1
      render :partial => "widget",
             :locals => { :widget_name => name,
                          :widget_id => @@widget_id,
                          :locals => locals }
    end

    private

    # ===============================================================
    # @param hash [Hash]
    # @return [ViewManager]
    # ===============================================================
    def render_autoview(hash)
      vm = Red::Engine::ViewManager.new

      ctrl = Red.boss.thr(:controller)
      helpers = ctrl.class.send :_helpers

      opts = {
        :layout => false,
        :view_binding => ctrl.send(:binding),
        :helpers => helpers
      } #.merge!(hash)

      locals = {
        :client => client,
        :server => server
      } #.merge!(opts[:locals] ||= {})

      opts[:locals] = locals

      render_opts = case hash
                    when Hash
                      merge_opts(opts, locals, hash)
                    when Proc
                      lambda{ merge_opts(opts, locals, hash.call) }
                    end
      vm.render_view(render_opts)
      vm
    end

    def merge_opts(default_opts, default_locals, user_opts)
      ans = {}.merge! default_opts
      ans.merge! user_opts
      ans[:locals] = default_locals.merge(user_opts[:locals] || {})
      ans
    end

    # ===============================================================
    # @param view_manager [Red::Engine::ViewManager]
    # @return [String]
    # ===============================================================
    def print_autoview(view_manager)
      tree = view_manager.tree

      text = Red::Engine::HtmlDelimNodePrinter.print_with_html_delims(tree.root)

      time_it("Flushing full info tree") {
        log = Red.conf.logger
        log.debug "@@@ View tree: "
        log.debug tree.print_full_info
      }

      Red.boss.add_client_view client, view_manager
      view_manager.start_collecting_client_updates(client)
      # changes are pushed explicitly after each event

      text.html_safe
    end

    def time_it(task, &block)
      Red.boss.time_it("[Autoview] #{task}", &block)
    end
  end

end
end
