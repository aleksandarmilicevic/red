require 'red/model/marshalling'
require 'red/model/red_model_errors'

class EventController < RedAppController
  include Red::Model::Marshalling

  private 

  def error(short, long=nil, status_code)
    Rails.logger.warn "[ERROR] #{short}. #{long}" 
    short = long unless short
    json = {:kind => "error", :msg => short, :status => status_code} 
    push_status(json)
    render :json => json, :status => status_code
  end

  def success(event_name, event_params, ans=nil)
    json = {:kind => "event_completed", 
            :event => {:name => event_name, :params => event_params}, 
            :msg => "Event #{event_name} successfully completed", 
            :ans => ans}
    push_status(json)
    render :json => json
  end
  
  def push_status(json)
    pusher = Red.boss.client_pusher
    pusher.push_json(:type => "status_message", :payload => json) if pusher
  end

  public

  def call(event, params) 
    record = params[:object]
    log_debug "Detected an update on record #{record} during execution of #{@curr_event}"
    @updated_records << record
  end
  
  def index
    event_name = params[:event]
    return error("event name not specified") unless event_name

    event_cls = Red.meta.find_event(event_name)
    return error("event #{event_name} not found") unless event_cls

    @curr_event = event = event_cls.new
    event.from = client()
    event.to = server()

    event_params = if params[:params].blank?
                     {}
                   else
                     params[:params]
                   end

    fld = nil
    val = nil
    event_params.each do |name, value| 
      begin 
        fld = event_cls.meta.field(name)
        val = unmarshal(value, fld.type)
        event.set_param(name, val) 
      rescue Red::Model::Marshalling::MarshallingError => e
        log_warn "Could not unmarshal `#{value.inspect}' for field #{fld}", e
      rescue e
        log_warn "Could not set field #{fld} to value #{val.inspect}", e
      end
    end

    #TODO: enclose in transaction    
    begin
      @updated_records = []
      Red.boss.register_listener Red::E_FIELD_WRITTEN, self
      ok = event.requires
      raise Red::Model::EventPreconditionNotSatisfied unless ok
      ans = event.ensures
      return success(event_name, event_params, ans)
    rescue Red::Model::EventNotCompletedError => e
      return error(e.message, 400)
    rescue Red::Model::EventPreconditionNotSatisfied => e
      msg = "Precondition for #{event_name} not satisfied"
      return error(e.message, msg, 412)
    rescue => e
      trace = "#{e.message}\n#{e.backtrace.join("\n")}"
      msg = "Error during execution of #{event_name} event.\n#{trace}"
      return error(e.message, msg, 500)
    ensure
      Red.boss.unregister_listener Red::E_FIELD_WRITTEN, self
      @updated_records.each do |r|
        if r.changed?
          log_debug "Auto-saving record #{r}"
          r.save!
        else
          log_debug "Updated record #{r} needs no saving"
        end
      end 
      Red.boss.push_changes
    end   
  end

  private 

  def log_debug(str, e=nil) log :debug, str, e end
  def log_warn(str, e=nil)  log :warn, str, e end

  def log(level, str, e=nil)
    Red.conf.logger.send level, "[EventController] #{str}"
    if e 
      Red.conf.logger.send level, e.message
      Red.conf.logger.send level, e.backtrace.join("  \n") 
    end
  end
  
end
