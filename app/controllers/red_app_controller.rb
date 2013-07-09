require 'red/stdlib/web/machine_model'
require 'red/engine/view_manager'
require 'red/view/auto_helpers'
require 'red/model/marshalling'
require 'red/model/red_model_errors'

class RedAppController < ActionController::Base
  protect_from_forgery

  include Red::Model::Marshalling

  helper Red::View::AutoHelpers

  before_filter :notify_red_boss
  around_filter :time_it

  # ---------------------------------------------------------------------
  #  SERVER INITIALIZATION
  #
  # Executes once when server starts:
  #   - figures out client and server machines
  #   - initializes server machine
  # ---------------------------------------------------------------------

  def autosave_fld(*)
    "hi"
  end

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

  protected

  def error(short, long=nil, status_code=412)
    Rails.logger.warn "[ERROR] #{short}. #{long}"
    short = long unless short
    json = {:kind => "error", :msg => short, :status => status_code}
    push_status(json)
    render :json => json, :status => status_code
  end

  def success(hash={})
    hash = {:msg => hash} if String === hash
    json = {:kind => "success", :status => 200}.merge!(hash)
    push_status(json)
    respond_to do |format|
      format.json { render :json => json }
      format.html { render :text => "hi" }
    end
  end

  def push_status(json)
    pusher = Red.boss.client_pusher
    pusher.push_json(:type => "status_message", :payload => json) if pusher
  end

  def to_bool(str)
    str == 'true' || str == 'yes'
  end

  def notify_red_boss
    Red.boss.set_thr :request => request, :session => session,
                     :client => client, :server => server, :controller => self
  end

  def time_it
    task = "[RedAppController] #{request.method} #{self.class.name}.#{params[:action]}"
    Red.boss.reset_timer
    Red.boss.time_it(task){yield}
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    Red.conf.logger.debug Red.boss.print_timings
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  end

end
