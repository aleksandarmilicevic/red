require 'red/stdlib/web/machine_model'
require 'red/engine/view_manager'
require 'red/engine/rendering_cache'
require 'red/engine/policy_checker'
require 'red/view/auto_helpers'
require 'red/model/marshalling'
require 'red/model/red_model_errors'

class RedAppController < ActionController::Base
  protect_from_forgery

  include Red::Model::Marshalling
  include Red::View::AutoHelpers

  helper Red::View::AutoHelpers

  before_filter :bf_invalidate_session_client
  before_filter :bf_init_server_once
  before_filter :bf_notify_red_boss
  before_filter :bf_clear_autoviews
  before_filter :bf_invalidate_caches
  around_filter :arf_time_request
  after_filter  :aff_push_changes

  layout Red.conf.view.default_layout

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

      # add the online method to clients
      # vf = Alloy::Ast::Field.new :name => :online,
      #                            :type => @@client_cls,
      #                            :parent => @@client_cls,
      #                            :transient => true
      # @@client_cls.send :define_singleton_method, :online do
      #   Red::Model::RelationWrapper.wrap(nil, vf, Red.boss.connected_clients)
      # end

      #TODO: cleanup expired clients

      @@server_cls.destroy_all
      @@server = @@server_cls.create!

      Red.boss.set_thr :server => @@server
    end
  end

  # ---------------------------------------------------------------------

  def client
    @session_client ||=
      begin
        clnt = session[:client]
        if clnt.nil?
          session[:client] ||= clnt = @@client_cls.new
          clnt.auth_token = SecureRandom.hex(32)
          clnt.save! #TODO: make sure no other client has the same token?
        else
          clnt.reload # or even clnt = @@client_cls.find(clnt.id())
        end
        unless Red.boss.has_client?(clnt)
          Red.boss.fireClientConnected :client => clnt
        end
        clnt
      end
  end

  def server
    @@server
  end

  protected

  def error(short, long=nil, status_code=412)
    long = "#{long.message}\n#{long.backtrace.join("\n")}" if Exception === long
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

  # @see BigBoss#with_enabled_policy_checking
  def with_enabled_policy_checking(*args)
    Red.boss.with_enabled_policy_checking(*args) do
      yield
    end
  end

  # @param payload_json [Hash]
  def get_status_json(payload_json)
    { :type => "status_message", :payload => payload_json }
  end

  def push_status(json)
    pusher = Red.boss.client_pusher
    pusher.push_json(get_status_json(json)) if pusher
  end

  def bf_init_server_once
    RedAppController.init_server
    RedAppController.skip_before_filter :init_server_once
  end

  def bf_notify_red_boss
    Red.boss.set_thr :request => request, :session => session,
                     :client => client(), :controller => self
  end

  def bf_invalidate_session_client
    @session_client = nil
  end

  def bf_invalidate_caches
    if Red.conf.renderer.invalidate_caches_between_requests && !self.class.async?
      Red.conf.log.debug "[RedAppController] clearing rendering caches before #{self}"
      Red::Engine::RenderingCache.clear_all()
    end
    if Red.conf.policy.invalidate_meta_cache_between_requests
      Red.conf.log.debug "[RedAppController] clearing policy meta cache before #{self}"
      Red::Engine::PolicyCache.clear_meta()
    end
    if Red.conf.policy.invalidate_apps_cache_between_requests
      Red.conf.log.debug "[RedAppController] clearing policy apps cache before #{self}"
      Red::Engine::PolicyCache.clear_apps()
    end
  end

  def bf_clear_autoviews
    unless self.class.async?
      Red.conf.log.debug "[RedAppController] clearing autoviews in controller #{self}"
      Red.boss.clear_client_views
    else
      msg = "[RedAppController] NOT clearing autoviews for ASYNC controller #{self}"
      Red.conf.log.debug msg
    end
  end

  def aff_push_changes
    Red.boss.push_changes
  end

  def arf_time_request
    task = "[RedAppController] #{request.method} #{self.class.name}.#{params[:action]}"
    Red.boss.reset_timer
    Red.boss.time_it(task){yield}
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    Red.conf.logger.debug Red.boss.print_timings
    Red.conf.logger.debug "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  end

end
