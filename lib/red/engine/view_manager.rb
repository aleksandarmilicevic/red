require 'red/engine/big_boss'
require 'red/engine/view_renderer'

module Red
  module Engine

    # ----------------------------------------------------------
    #  Class +ViewManager+
    # ----------------------------------------------------------
    class ViewManager
      def initialize(renderer_conf={})
        @renderer_conf = renderer_conf
      end

      def render_view(view_opts)
        @renderer = ViewRenderer.new(@renderer_conf)
        node = @renderer.render_to_node(view_opts)
        @view_tree = @renderer.tree
        node
      end

      def view_tree() @view_tree end
      alias_method :tree, :view_tree

      def render_to_plain_text(view_opts)
        @renderer = ViewRenderer.new(@renderer_conf)
        view = @renderer.render_to_node(view_opts)
        view.result
      end

      def rerender_node(node)
        new_node = rerender_only(node)
        swap_nodes(node, new_node)
        new_node
      end

      def rerender_only(node)
        curr_view = (view_tree.render_options[:view] rescue nil)
        conf = @renderer_conf.merge :current_view => curr_view
        @renderer = ViewRenderer.new(conf)
        @renderer.rerender_node(node) #render_to_node node.render_options
      end

      def swap_nodes(node, new_node)
        new_node.id = node.id
        if node.parent
          node.parent.set_child(node.index_in_parent, new_node)
        else
          @view_tree.set_root(new_node)
        end
      end

      def renderer() @renderer end #TODO: remove

      # -----------------------------------------

      def start_auto_updating_client(client, hash={})
        start_listening(client, true, hash)
      end

      def start_collecting_client_updates(client, hash={})
        start_listening(client, false, hash)
      end

      def start_listening(client, auto_push, hash={})
        @client = client
        @pusher = Red::Engine::Pusher.new({
          :client    => client,
          :views     => lambda{[view_tree()]},
          :listen    => true,
          :auto_push => auto_push,
          :manager   => self
        }.merge!(hash))
      end

      def push()
        fail "Auto-updating has not been started. " +
             "Call `start_auto_updating_first'" unless pusher
        pusher.push
      end

      def finalize()
        pusher.stop_listening if pusher
      end

      def pusher()
        @pusher
      end

    end

  end
end
