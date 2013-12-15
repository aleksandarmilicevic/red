require 'red/red_conf'
require 'red/engine/view_renderer'
require 'red/engine/html_delim_node_printer'
require 'red/view/js_helpers'
require 'sdg_utils/event/events'
require 'sdg_utils/config'
require 'faye'
require 'logger'

module Red
module Engine

  class PusherChecker
    include SDGUtils::Events::EventHandler
    include Red::Engine::HtmlDelimNodePrinter

    attr_reader :_affected_nodes, :_updated_nodes
    def __reset_saved_fields()
      @_affected_nodes = []
      @_updated_nodes = []
    end

    def initialize(hash={})
      @conf = Red.conf.pusher.extend(hash)
      msg = "Listen=true but no event server specified"
      raise ArgumentError, msg  if (@conf.listen && !@conf.event_server)
      @_affected_nodes = []
      @_updated_nodes = []
      start_listening if @conf.listen
    end

    def start_listening
      debug "listening for data model changes"
      @conf.event_server.register_listener(@conf.events, self)
    end

    def stop_listening
      debug "not listening for data model changes anymore"
      @conf.event_server.unregister_listener(@conf.events, self)
    end

    def finalize
      if @conf.listen && @conf.event_server && @conf.events
        @conf.event_server.unregister_listener(@conf.events, self)
      end
    end

    def push_client
      @push_client ||= Faye::Client.new(@conf.push_server)
    end

    def push
      # send_updates # this is for the Ember stuff only
      refresh_views
    end

    # -------------------------------------------------------
    # Monitoring for changes and pushing updates to clients
    # -------------------------------------------------------
    # TODO: move to a separate thread
    # TODO: batch

    def handle_record_saved(params)
      record = params[:record]
      debug "detected record #{record} saved"
      buffer << record
      push if @conf.auto_push
    end

    def handle_record_destroyed(params)
      warn "TODO: implement handle_record_destroyed(#{params.inspect})"
    end

    def handle_record_queried(params)
      warn "TODO: implement handle_record_queried(#{params.inspect})"
    end

    def push_json(hash)
      begin
        client = @conf.client
        channel = Red::View::JsHelpers.push_channel_to(client)
        push_client.publish(channel, hash)
      rescue => e
        debug "Failed to push update to #{client}"
        debug e.message
        debug e.backtrace.join("\n")
      end
    end

    private

    def buffer() @buffer ||= Set.new end

    # def traverse_result(res, &block)
    #   case res
    #   when Red::Model::Record
    #     block.call(res)
    #   when Array
    #     res.each{|e| traverse_result(e, &block)}
    #   else
    #     if res.kind_of?(ActiveRecord::Relation)
    #       res.each{|e| traverse_result(e, &block)}
    #     else
    #       @conf.log.warn("Unknown result type: #{res.class}")
    #     end
    #   end
    # end

    # def send_updates
    #   #TODO: refresh dependencies
    #   deps = @conf.deps
    #   return unless deps && !deps.empty?
    #   updated_records = Set.new
    #   buffer.each {|r| updated_records << r if check_record_deps(deps, r)}
    #   buffer.clear #TODO: should be atomic with prev
    #   affected_queries(deps).each do |q, res|
    #     traverse_result(res) {|rec| updated_records << rec}
    #     q.result = res
    #   end
    #   push_record_update(updated_records.to_a) unless updated_records.empty?
    # end

    # def push_record_update(mod_records)
    #   result = mod_records.map do |rec|
    #     debug "enquing record update: #{rec}"
    #     { :record_type => rec.class.name,
    #       :json => rec.as_red_json({:root => true}) }
    #   end
    #   push_json :type => "record_update",
    #             :payload => result
    # end

    def refresh_views
      updated_records = buffer.clone
      buffer.clear #TODO: should be atomic with prev

      affected_nodes = Set.new
      Red.boss.time_it("[Pusher] Discovering affected nodes") {
        updated_records.each do |mod_record|
          an = @conf.check_views ? discover_affected_nodes(mod_record) : []
          affected_nodes += an
        end
      }
      @_affected_nodes += affected_nodes.to_a # TODO: for testing only

      un = []
      Red.boss.time_it("[Pusher] Updating views") {
        un = update_views(affected_nodes) if @conf.update_views
      }
      @_updated_nodes += un.clone # TODO: for testing only

      Red.boss.time_it("[Pusher] Pushing changes") {
        push_view_changes(un) if @conf.push_changes
      }
    end

    # Go through each view (+ViewInfoTree+), check all of its
    # dependencies, and see which nodes are affected by the change
    # made to the +record+ object.
    #
    # Returns a list of +(ViewInfoTree, Array(ViewInfoNode))+ pairs,
    # namely, for each tree gives a list of its affected nodes.
    #
    # @return Array(ViewInfoNode)
    def discover_affected_nodes(record)
      affected_nodes = []
      debug "  checking views"
      @conf.views.each do |view|
        case view
        when Red::Engine::ViewInfoTree
          view_tree = view
          dirty_nodes = traverse_view_tree(view_tree, record)
          affected_nodes += dirty_nodes
        when Red::Engine::ViewInfoNode
          view_node = view
          affected_nodes << view_node if check_deps(view_node.deps, record)
        else
          raise ArgumentError, "unknown view type: #{view.class}"
        end
      end
      unless affected_nodes.empty?
        debug "    client has dirty nodes"
      end
      affected_nodes
    end

    # Re-renders a given list of nodes. Updates the nodes and the
    # tree.  Returns a list of changes.
    #
    # @param nodes [Array(ViewInfoTree, Array(ViewInfoNode))]
    # @return [Array(ViewInfoTree, ViewInfoNode, ViewInfoNode)]
    def update_views(dirty_nodes)
      updated_nodes = []
      dirty_nodes.each do |dn|
        begin
          #TODO not the most efficient thing to do
          Red.boss.time_it("[Pusher] Reloading all"){
            dn.reload_all
          }
          new_node = Red.boss.time_it("[Pusher] rerendering node"){
            @conf.manager.rerender_node(dn)
          }
          if dn.result != new_node.result
            updated_nodes << [dn, new_node]
          else
            info = dn.print_short_info
            debug "Node was dirty, but the result is the same: \n#{info}"
          end
        rescue => e
          debug "Failed to re-render node #{dn.print_short_info}"
          debug e.message
          debug e.backtrace.join("\n")
        end
      end
      updated_nodes
    end

    def push_view_changes(stale_nodes)
      stale_nodes.each do |old_node, new_node|
        result = print_with_html_delims(new_node)
        debug "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        debug "pushing update for node #{old_node.id}"
        debug "update size (in characters): #{result.size}"
        push_json :type => "node_update",
                  :payload => {:node_id => old_node.id, :inner_html => result}
      end
    end

    def traverse_view_tree(tree, updated_record)
      worklist = tree.root ? [tree.root] : []
      nodes_to_refresh = []
      while !worklist.empty?
        node = worklist.shift()
        if check_deps(node.deps, updated_record)
          nodes_to_refresh << node
        else
          node.children.reverse_each {|n| worklist.unshift(n)}
        end
      end
      nodes_to_refresh
    end

    def check_record_deps(deps, record)
      return !deps.obj(record).empty?
      # deps.obj(record).each do |field, old_value|
      #   new_value = record.read_field(field)
      #   if new_value != old_value
      #     debug "    field '#{field.name}' changed from '#{old_value}' to '#{new_value}'"
      #     return true
      #   end
      # end
      # return false
    end

    def affected_queries(deps)
      ret = []
      deps.queries.each do |q|
        new_result = q.target.send q.method, *q.args
        old_val = q.result.red_inspect
        new_val = new_result.red_inspect
        if old_val != new_val
          debug "    result of query #{q} changed from '#{old_val}' to '#{new_val}'"
          ret << [q, new_result]
        end
      end
      return ret
    end

    def check_deps(deps, record)      
      return false if deps.empty?
      Red.boss.time_it("[Pusher] Checking dependencies #{deps.to_s.inspect} for record #{record}") {
        Red.boss.time_it("[Pusher] Checking field dependencies") {
          check_record_deps(deps, record)
        } ||
        Red.boss.time_it("[Pusher] Checking queries") {
          !affected_queries(deps).empty?
        }
      }
    end

    private

    def pref()     "[Pusher(#{@conf.client})]" end
    def debug(msg) @conf.log.debug "#{pref} #{msg}" end
    def warn(msg)  @conf.log.warn "#{pref} #{msg}" end

    def fail_to_connect(url)
      warn "could not connect to push server at #{push_server}"
      nil
    end
  end

end
end

=begin
    def push_view_changes(stale_nodes)
      stale_nodes.each do |old_node, new_node|
        channel = Red::View::JsHelpers.push_channel_to(view_tree.client)
        begin
          # vm = Red.boss.client_views[@conf.client]
          # full = vm.render_view
          rr = @conf.renderer
          full = rr.render view_tree.root.render_options
          @conf.log.debug "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
          @conf.log.debug full
          push_client.publish(channel, :html => full)
        rescue => e
          @conf.log.debug "Failed to push update to client #{view_tree.client}"
          @conf.log.debug e.message
          @conf.log.debug e.backtrace.join("\n")
        end
      end
    end
=end

