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

  class Pusher
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
      __reset_saved_fields
      start_listening if @conf.listen
    end

    def start_listening() end
    def stop_listening() end
    def finalize() end

    def push_client
      @push_client ||= Faye::Client.new(@conf.push_server)
    end

    def affected_nodes
      @affected_nodes ||= Set.new
    end

    def add_affected_node(node, record=nil)
      if record.nil? || check_deps(node.deps, record)
        affected_nodes << node
        push if @conf.auto_push
      end
    end

    # @return [TrueClass, FalseClass]: whether anything was pushed to the client
    def push()
      updated_nodes = push_views
      return !updated_nodes.empty?
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

    def push_views
      an = affected_nodes
      @affected_nodes = Set.new
      @_affected_nodes += an.to_a
      un = []
      Red.boss.time_it("[Pusher] Updating views") {
        un = update_views(an) if @conf.update_views
      }
      @_updated_nodes += un.clone # TODO: for testing only

      if @conf.push_changes
        Red.boss.time_it("[Pusher] Pushing changes") { push_view_changes(un) }
        un
      else
        []
      end
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
          new_node = Red.boss.time_it("[Pusher] rerendering node"){
            Red.boss.with_enabled_policy_checking(@conf.client) {
              dn.rerender()
            }
          }
          unless new_node.equal?(dn)
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

    def check_record_deps(deps, record)
      deps.obj(record).each do |field, old_value|
        new_value = record.read_field(field)
        if new_value != old_value
          debug "    field '#{field.name}' changed from '#{old_value}' to '#{new_value}'"
          return true
        end
      end
      return false
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
      msg = "[Pusher] Checking dependencies #{deps.to_s.inspect} for record #{record}"
      Red.boss.time_it(msg) {
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
