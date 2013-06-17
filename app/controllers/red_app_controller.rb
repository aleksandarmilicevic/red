require 'red/stdlib/web/machine_model'

class RedAppController < ActionController::Base
  protect_from_forgery

  helper :all

  before_filter :notify_red_boss

  # ---------------------------------------------------------------------
  #  SERVER INITIALIZATION
  #
  # Executes once when server starts:
  #   - figures out client and server machines
  #   - initializes server machine
  # ---------------------------------------------------------------------

  class << self
    def try_read_machine_from_conf(prop)
      begin
        machine_cls_name = Red.conf[prop]
        Red.meta.get_machine(machine_cls_name)
      rescue 
        false
      end
    end

    def try_find_machine(parent)
      res = Red.meta.machines.find_all do |m| 
        !m.meta.abstract? && m.meta.all_supersigs.member?(parent)
      end
      if res.size == 1
        res[0]
      elsif res.empty?
        false
      else
        fail "More than one WebServer specification found: #{res.map{|m| m.name}}" 
      end
    end

    def init_server
      @@server_cls = try_read_machine_from_conf(:server_machine) ||
                     try_find_machine(RedLib::Web::WebServer) || 
                     fail("No web server machine spec found")
      @@client_cls = try_read_machine_from_conf(:client_machine) ||
                     try_find_machine(RedLib::Web::WebClient) ||
                     fail("No web client machine spec found")

      Rails.logger.debug "Using server machine: #{@@server_cls}"
      Rails.logger.debug "Using client machine: #{@@client_cls}"

      #TODO: cleanup expired clients

      @@server_cls.delete_all
      @@server = @@server_cls.create!
    end
  end

  init_server

  # ---------------------------------------------------------------------
  
  def client
    client = session[:client]
    if client.nil?
      session[:client] ||= client = @@client_cls.new
      client.auth_token = SecureRandom.hex(32)
      client.save! #TODO: make sure no other client has the same token?      
    end    
    unless Red.boss.has_client?(client)
      pusher = Red::Engine::Pusher.new :client => client, :listen => false
      Red.boss.fireClientConnected :client => client, :pusher => pusher
    end      
    session[:client]
  end
  
  def server
    @@server
  end

  def notify_red_boss
    Red.boss.set_thr :request => request, :session => session, 
                     :client => client, :server => server, :controller => self
  end

end
