require 'red/engine/event_constants'
require 'red/engine/pusher'
require 'red/engine/access_listener'
require 'sdg_utils/meta_utils'
require 'sdg_utils/event/events'
require 'sdg_utils/timing/timer'

module Red
module Engine

  class BigBoss
    include SDGUtils::Delegate
    include SDGUtils::Events::EventHandler

    def initialize(alloy_boss)
      super() # important to initialize monitor included by Sync
      reset_timer()
      if alloy_boss
        delegate_all SDGUtils::Events::EventProvider, :to => alloy_boss
      else
        (class << self; self end).send :include, SDGUtils::Events::EventProvider
      end
      self.register_listener(Red::E_CLIENT_CONNECTED, self)
    end

    def start
      debug "Big Boss started"
      access_listener.start_listening
    end

    def stop
      debug "Big Boss stopped"
      access_listener.stop_listening
    end

    # ------------------------------------------------
    # Timing and benchmarking stuff
    # ------------------------------------------------

    begin
      def time_it(task, &block)
        if @timer
          @timer.time_it(task, &block)
        else
          yield
        end
      end

      def reset_timer
       @timer = SDGUtils::Timing::Timer.new
      end

      def print_timings
        return "" unless @timer
        @timer.print + "\n\n" + @timer.summary.map{|k,v| "#{k} = #{v*1000}ms"}.join("\n")
      end
    end

    # ------------------------------------------------
    # Global field access listener stuff
    # ------------------------------------------------

    # single instance of AccessListener
    def access_listener
      @access_listener ||= AccessListener.new
    end

    # ------------------------------------------------
    # Thread-local stuff, doesn't need synchronizing.
    # ------------------------------------------------
    begin
      def set_thr(hash)  hash.each {|k,v| Thread.current[k] = v} end
      def thr(sym)       Thread.current[sym] end
      def thr=(sym, val) Thread.current[sym] = val end
    end

    # ------------------------------------------------
    # Managing clients
    # ------------------------------------------------
    begin
      def curr_client() thr(:client) end

      # @param client [Client]
      # @param view [ViewManager]
      def add_client_view(client, view)
        client_views(client) << view
      end

      def clear_client_views(client=curr_client)
        client_views(client).each{|view| view.finalize}
        client_views(client).clear
      end

      # @result [Array(ViewManager)]
      def client_views(client=curr_client)
        client2views[client] ||= []
      end

      def client_pusher(client=curr_client)
        client_pushers[client] ||= Red::Engine::Pusher.new :client => client,
                                                           :listen => false
      end

       def fireClientConnected(params)
        fire(Red::E_CLIENT_CONNECTED, params)
      end

      def has_client?(client)
        clients.member?(client)
      end

      def push_changes
        time_it("[RedBoss] PushChanges") {
          clients.each do |c|
            client_pusher(c).push
          end
          # client_pushers.values.each{|pusher| pusher.push}
          # client2views.values.flatten.each {|view| view.push}
        }
      end

      protected

      def clients()          @clients ||= [] end
      def client2views()     @client2views ||= {} end
      def client_pushers()   @client_pushers ||= {} end

      def handle_client_connected(params)
        client = params[:client]
        return unless client
        debug "Client connected: #{client.inspect}."
        clients << client
        client_pushers.merge! client => params[:pusher]
      end
    end

    # -------------------------------------------------------
    # ActiveRecord Callbacks
    #
    # Just delegates to fire, which is already synchronized.
    # -------------------------------------------------------
    begin
      protected
      def after_create(record)  fire(Red::E_RECORD_CREATED, :record => record); true end
      def after_save(record)    fire(Red::E_RECORD_SAVED, :record => record); true end
      def after_destroy(record) fire(Red::E_RECORD_DESTROYED,:record => record); true end
      def after_find(record)    fire(Red::E_RECORD_QUERIED, :record => record); true end
      def after_update(record)  fire(Red::E_RECORD_UPDATED, :record => record); true end
      def after_query(obj, method, args, result)
        fire(Red::E_QUERY_EXECUTED, :target => obj, :method => method,
                                    :args => args, :result => result)
        true
      end

    end

    protected

    def debug(msg)
      Red.conf.logger.debug "[BigBoss] #{msg}"
    end

    # Disallow arbitrary fire
    def fire(*)
      super
    end

  end

end
end
