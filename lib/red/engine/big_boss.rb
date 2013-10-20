require 'red/engine/event_constants'
require 'red/engine/policy_checker'
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
      super()
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
      def time_it(task, task_param=nil, &block)
        if @timer
          @timer.time_it(task, task_param, &block)
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

      # at_exit {
      #   puts "timings: ---------------------"
      #   puts Red.boss.print_timings
      # }
    end

    # ------------------------------------------------
    # Global field access listener stuff
    # ------------------------------------------------

    # single instance of AccessListener
    def access_listener
      @access_listener ||= AccessListener.new
    end

    # ------------------------------------------------
    # Field access checking
    # ------------------------------------------------

    # @policy_checker [PolicyChecker]
    begin
      def enable_policy_checking(principal=curr_client())
        @policy_checker = PolicyChecker.new(principal)
      end

      def disable_policy_checking
        @policy_checker = nil
      end

      # @see Red::Engine::PolicyChecker#check_read
      def check_fld_read(*args)  run_checker{|checker| checker.check_read(*args)} end

      # @see Red::Engine::PolicyChecker#check_write
      def check_fld_write(*args) run_checker{|checker| checker.check_write(*args)} end

      # Expects that the last argument is the actual value to be
      # filtered; doesn't care about other arguments, just passes them
      # along to PolicyChecker
      #
      # @see Red::Engine::PolicyChecker#apply_filters
      def apply_filters(*args)
        return args.last unless @policy_checker
        run_checker{|checker| checker.apply_filters(*args)}
      end

      private

      def run_checker
        old_checker = @policy_checker
        @policy_checker = nil
        yield(old_checker) if old_checker
      ensure
        @policy_checker = old_checker
      end
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

      # @param notes [Array(String)]: JSON objects (notes) to push
      #                               along with any view updates
      def push_changes(notes=[])
        updated_clients = []
        time_it("[RedBoss] PushChanges") {
          clients.each do |c|
            cp = client_pusher(c)
            cp.push() and notes.each{|json| cp.push_json(json)}
          end
          # client_pushers.values.each{|pusher| pusher.push}
          # client2views.values.flatten.each {|view| view.push}
        }
      end

      def connected_clients() clients.clone end

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
