require 'red/engine/event_constants'
require 'red/engine/pusher'
require 'red/engine/access_listener'
require 'sdg_utils/meta_utils'
require 'sdg_utils/event/events'

module Red
module Engine

  class BigBoss
    include SDGUtils::Delegate
    include SDGUtils::Events::EventHandler

    def initialize(alloy_boss)
      super() # important to initialize monitor included by Sync
      if alloy_boss
        delegate_all SDGUtils::Events::EventProvider, :to => alloy_boss
      else
        (class << self; self end).send :include, SDGUtils::Events::EventProvider
      end
      views = lambda{client_views.values.map{|vm| vm.view_tree}}
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
      
      # @modifies `@client_views'
      # @param client [Client]
      # @param view []
      def remember_client_view(client, view)
        old = client_views[client]
        client_views[client] = view
        old
      end

      def client_view(client=nil)         
        client = thr(:client) unless client
        client_views[client] 
      end

      def client_listener(client=nil)     
        client_view(client).access_listener rescue nil 
      end

      def client_pusher(client=nil)       
        (client_view(client).pusher rescue nil) ||
          (client_pushers[client])
      end

      def client_view_manager(client=nil) 
        client_view(client).view_manager rescue nil 
      end

      def fireClientConnected(params)
        fire(Red::E_CLIENT_CONNECTED, params)
      end
      
      def has_client?(client)
        clients.member?(client)
      end

      def push_changes
        client_views.each do |cl, view| 
          if view.pusher
            view.pusher.push
          else
            Red.conf.logger.error "No pusher for client #{cl}"
          end
        end
      end

      protected      

      def clients()          @clients ||= [] end 
      def client_views()     @client_views ||= {} end
      def client_pushers()   @client_pushers ||= {} end

      # @modifies `@clients'
      def handle_client_connected(params)
        client = params[:client]
        return unless client
        debug "Client connected: #{client.inspect}."
        clients << client
        client_pushers.merge! :client => params[:pusher]
      end
    end

    # -------------------------------------------------------
    # ActiveRecord Callbacks
    #  
    # Just delegates to fire, which is already synchronized.
    # -------------------------------------------------------
    begin
      protected
      def after_create(record)  fire(Red::E_RECORD_CREATED, :record => record) end
      def after_save(record)    fire(Red::E_RECORD_SAVED, :record => record) end
      def after_destroy(record) fire(Red::E_RECORD_DESTROYED, :record => record) end
      def after_find(record)    fire(Red::E_RECORD_QUERIED, :record => record) end
      def after_update(record)  fire(Red::E_RECORD_UPDATED, :record => record) end
      def after_query(obj, method, args, result)
        fire(Red::E_QUERY_EXECUTED, :target => obj, :method => method,
                                    :args => args, :result => result)
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
