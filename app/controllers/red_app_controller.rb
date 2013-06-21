require 'red/stdlib/web/machine_model'
require 'red/engine/view_manager'

class RedAppController < ActionController::Base
  protect_from_forgery

  module RedAppHelper
    def autosave_fld(record, fld_name, hash={})
      hash = hash.clone
      tag = hash.delete(:tag) || "span"
      escape_body = true
      escape_body = !!hash[:escape_body] if hash.has_key?(:escape_body)
      multiline = !!hash[:multiline]

      blder = SDGUtils::HTML::TagBuilder.new(tag)
      blder
        .body(record.read_field(fld_name))
        .attr("data-record-cls", record.class.name)
        .attr("data-record-id", record.id)
        .attr("data-field-name", fld_name)
        .attr("contenteditable", true)
        .attr("class", "red-autosave")
        .when(!multiline, :attr, "class", "singlelineedit")
        .attrs(hash)
        .build(escape_body).html_safe()
    end    

    # ===============================================================
    # Renders a specified view using the `ViewManager' so that all
    # field accesses are detected and the view is automatically
    # updated when those fields change. 
    #
    # @param hash [Hash]
    # ===============================================================
    def autoview(hash)
      vm = Red::Engine::ViewManager.new
                            
      opts = {
        :layout => false, 
      }.merge!(hash)

      locals = {
        :client => client, 
        :server => server
      }.merge!(opts[:locals] ||= {})

      opts[:locals] = locals
      view = vm.render_view(opts)
      tree = vm.view_tree()

      text = print_with_html_delims(view)

      log = Red.conf.logger
      log.debug "@@@ View tree: "
      log.debug tree.print_full_info

      Red.boss.add_client_view client, vm
      vm.start_collecting_client_updates(client) 
      # changes are pushed explicitly after each event

      text
    end
  end

  helper RedAppHelper

  include RedAppHelper

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
