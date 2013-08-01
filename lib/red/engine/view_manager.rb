require 'red/engine/big_boss'
require 'red/engine/view_renderer'
require 'red/engine/access_listener'
require 'red/engine/rendering_cache'

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
        if new_node.equal?(node)
          node
        # elsif node.result == new_node.result
        #   disconnect_deps_listeners(new_node)
        #   node
        else
          disconnect_deps_listeners(node)
          swap_nodes(node, new_node)
          connect_deps_to_pusher(new_node, @pusher)
          new_node
        end
      end

      def rerender_only(node)
        curr_view = (view_tree.render_options[:view] rescue nil)
        conf = @renderer_conf.merge :current_view => curr_view
        @renderer = ViewRenderer.new(conf)
        @renderer.rerender_node(node)
      end

      def swap_nodes(node, new_node)
        return if node.const?
        new_node.id = node.id
        if node.parent
          node.parent.set_child(node.index_in_parent, new_node)
        else
          @view_tree.set_root(new_node)
        end
      end

      def renderer() @renderer end #TODO: remove

      # -----------------------------------------

      def start_auto_updating_client(client, hash=nil)
        start_listening(client, to_pusher(client, true, hash))
      end

      def start_collecting_client_updates(client, hash=nil)
        start_listening(client, to_pusher(client, false, hash))
      end

      def start_listening(client, pusher=nil)
        @client = client
        @pusher = pusher || Red.boss.client_pusher(client)
        unless @pusher
          fail "no pusher for client #{client}"
        end
        connect_deps_to_pusher(view_tree.root, @pusher)
      end

      def push
        fail "Auto-updating has not been started. " +
             "Call `start_auto_updating_first'" unless pusher
        pusher.push
      end

      def finalize
        pusher.finalize if pusher
        disconnect_deps_listeners(view_tree.root) if view_tree
      end

      def pusher
        @pusher
      end

      def clear_renderer_cache
        RenderingCache.clear_all
      end

      protected

      def to_pusher(client, auto_push, hash)
        case hash
        when Pusher; hash
        when NilClass; nil
        when Hash
          Red::Engine::Pusher.new({
            :client    => client,
            :listen    => true,
            :auto_push => auto_push,
            :manager   => self
          }.merge!(hash))
        end
      end

      def debug(msg)
        Red.conf.log.debug "[ViewManager] #{msg}"
      end

      def disconnect_deps_listeners(root_node)
        root_node.yield_all_nodes do |node|
          # puts "\n **************************************** "
          # puts "       FINALIZING #{node.id}                "
          # puts " **************************************** \n"
          node.deps.finalize
        end
      end

      def connect_deps_to_pusher(root_node, pusher)
        return unless pusher
        manager = self
        rerender_lambda = lambda{
          #TODO see if it speeds things up if this is compiled
          self.reload_all  #TODO not the most efficient thing to do
          manager.rerender_node(self)
        }
        ev = [Red::Engine::ViewDependencies::E_DEPS_CHANGED]
        root_node.yield_all_nodes do |node|
          unless node.no_deps?
            node.define_singleton_method :rerender, rerender_lambda
            node.deps.register_listener(ev) {|e, args|
              event, record = args
              pusher.add_affected_node(node, record)
            }
          end
        end
      end

    end

  end
end
