require 'red/stdlib/web/machine_model'
require 'red/engine/view_manager'
require 'red/view/auto_helpers'
require 'red/model/marshalling'
require 'red/model/red_model_errors'

class RedAppController < ActionController::Base
  protect_from_forgery

  include Red::Model::Marshalling
  include Red::View::AutoHelpers

  helper Red::View::AutoHelpers

  before_filter :init_server_once
  before_filter :notify_red_boss
  before_filter :clear_autoviews
  around_filter :time_request
  after_filter  :push_changes

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
    def async() @async = true end
    def async?() !!@async end

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
        return res.last
        # TODOOO
        fail "More than one WebServer specification found: #{res.map{|m| m.name}}"
      end
    end

    @@server_initialized = false
    def init_server
      Red.conf.log.debug("*** Server already initialized") and return if @@server_initialized

      @@server_initialized = true
      @@server_cls = try_read_machine_from_conf(:server_machine) ||
                     try_find_machine(RedLib::Web::WebServer) ||
                     fail("No web server machine spec found")
      @@client_cls = try_read_machine_from_conf(:client_machine) ||
                     try_find_machine(RedLib::Web::WebClient) ||
                     fail("No web client machine spec found")

      Rails.logger.debug "Using server machine: #{@@server_cls}"
      Rails.logger.debug "Using client machine: #{@@client_cls}"

      #TODO: cleanup expired clients

      @@server_cls.destroy_all
      @@server = @@server_cls.create!
    end
  end

  # ---------------------------------------------------------------------

  def client
    client = session[:client]
    if client.nil?
      session[:client] ||= client = @@client_cls.new
      client.auth_token = SecureRandom.hex(32)
      client.save! #TODO: make sure no other client has the same token?
    end
    unless Red.boss.has_client?(client)
      Red.boss.fireClientConnected :client => client
    end
    session[:client]
  end

  def server
    @@server
  end

  protected

  def init_server_once
    RedAppController.init_server
    RedAppController.skip_before_filter :init_server_once
  end

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

  def notify_red_boss
    Red.boss.set_thr :request => request, :session => session,
                     :client => client, :server => server, :controller => self
  end

  def clear_autoviews
    unless self.class.async?
      Red.conf.log.debug "[RedAppController] clearing autoviews in controller #{self}"
      Red.boss.clear_client_views
    else
      msg = "[RedAppController] NOT clearing autoviews for ASYNC controller #{self}"
      Red.conf.log.debug msg
    end
  end

  def push_changes
    Red.boss.push_changes
  end

  private

  def time_request
    task = "[RedAppController] #{request.method} #{self.class.name}.#{params[:action]}"
    Red.boss.reset_timer
    Red.boss.time_it(task){yield}
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    Red.conf.logger.debug Red.boss.print_timings
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  end

end
