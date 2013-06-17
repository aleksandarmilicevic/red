require 'red/engine/big_boss'
require 'red/engine/view_renderer'

module Red
  module Engine

    # ----------------------------------------------------------
    #  Class +ViewManager+
    # ----------------------------------------------------------
    class ViewManager
      attr_reader :client, :server

      def initialize(renderer_conf={})
        # @client = hash[:client]      
        # @server = hash[:server]      
        @renderer_conf = renderer_conf
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
      
      def rerender_node(node)         
        new_node = rerender_only(node)
        swap_nodes(node, new_node)
        new_node
      end
      
      def render_view(view_opts)        
        @renderer = ViewRenderer.new(@renderer_conf)
        view = @renderer.render_to_node(view_opts)
        @view_tree = @renderer.tree
        @view_tree.client = client
        view
      end

      def render_to_plain_text(view_opts)
        @renderer = ViewRenderer.new(@renderer_conf)
        view = @renderer.render_to_node(view_opts)
        view.result
      end

      def view_tree() @view_tree end      
      alias_method :tree, :view_tree

      def renderer() @renderer end #TODO: remove
    end

  end
end
