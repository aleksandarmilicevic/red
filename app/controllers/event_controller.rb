require 'red/model/marshalling'
require 'red/model/red_model_errors'

class EventController < RedAppController
  include Red::Model::Marshalling

  protected

  def event_succeeded(event_name, ans=nil)
    success :kind => "event_completed",
            :event => {:name => event_name, :params => params[:params]},
            :msg => "Event #{event_name} successfully completed",
            :ans => ans
  end

  public

  def call(event, params)
    record = params[:object]
    return unless Red::Model::Record === record
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

    Red.boss.time_it("[EventController] Unmarhsalling") {
      unmarshal_and_set_event_params(event)
    }

    #TODO: enclose in transaction
    begin
      @updated_records = Set.new
      Red.boss.register_listener Red::E_FIELD_WRITTEN, self
      Red.boss.time_it("[EventController] Event execution") {
        execute_event(event, lambda { |ans| event_succeeded(event_name, ans)})
      }
    rescue Red::Model::EventNotCompletedError => e
      return error(e.message, 400)
    rescue Red::Model::EventPreconditionNotSatisfied => e
      trace = "#{e.message}\n#{e.backtrace.join("\n")}"
      msg = "Precondition for #{event_name} not satisfied.\n#{trace}"
      return error(e.message, msg, 412)
    rescue => e
      trace = "#{e.message}\n#{e.backtrace.join("\n")}"
      msg = "Error during execution of #{event_name} event.\n#{trace}"
      return error(e.message, msg, 500)
    ensure
      Red.boss.unregister_listener Red::E_FIELD_WRITTEN, self

      Red.boss.time_it("[EventController] Auto-save") {
        @updated_records.each do |r|
          if r.changed?
            log_debug "Auto-saving record #{r}"
            r.save
          else
            log_debug "Updated record #{r} needs no saving"
          end
        end
      }

      Red.boss.push_changes
    end
  end

  private

  def execute_event(event, cont)
    ok = event.requires
    raise Red::Model::EventPreconditionNotSatisfied, "Precondition failed" unless ok
    ans = event.ensures
    cont.call(ans)
  end

  def unmarshal_and_set_event_params(event)
    event_params = if params[:params].blank?
                     {}
                   else
                     params[:params]
                   end

    fld = nil
    val = nil
    event_params.each do |name, value|
      begin
        fld = event.meta.field(name)
        if !fld
          log_warn "invalid parameter '#{name}' for event #{event.class.name}"
        else
          val = unmarshal(value, fld.type)
          event.set_param(name, val)
        end
      rescue Red::Model::Marshalling::MarshallingError => e
        log_warn "Could not unmarshal `#{value.inspect}' for field #{fld}", e
      rescue e
        log_warn "Could not set field #{fld} to value #{val.inspect}", e
      end
    end
  end

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
