require 'red/model/marshalling'
require 'red/model/red_model_errors'

class EventController < RedAppController
  include Red::Model::Marshalling

  async

  protected

  def event_succeeded(ev, event_name, ans=nil)
    # success :kind => "event_completed",
    #         :event => {:name => event_name, :params => params[:params]},
    #         :msg => "Event #{event_name} successfully completed",
    #         :ans => ans.as_red_json
    success :kind => "event_completed", :event => {:name => event_name}
  end

  public

  def last_event() @last_event end

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

    #TODO: remove this!!
    # begin
    #   event.from.user = current_user
    #   event.from.save!
    # rescue
    # end

    Red.boss.time_it("[EventController] Unmarshalling") {
      unmarshal_and_set_event_params(event)
    }

    #TODO: enclose in transaction
    begin
      @updated_records = Set.new
      Red.boss.register_listener Red::E_FIELD_WRITTEN, self
      Red.boss.time_it("[EventController] Event execution") {
        execute_event(event, lambda { |ev, ans| event_succeeded(ev, event_name, ans)})
      }
    rescue Red::Model::EventNotCompletedError => e
      return error(e.message, 400)
    rescue Red::Model::EventPreconditionNotSatisfied => e
      msg = "Precondition for #{event_name} not satisfied: #{e.message}"
      return error(msg, e, 412)
    rescue Red::Model::AccessDeniedError => e
      rule = e.failing_rule.unbind
      msg = rule.desc() || e.message
      return error("Access denied: " + msg, e, 412)
    rescue => e
      msg = "Error during execution of #{event_name} event: #{e.message}"
      return error(msg, e, 500)
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
    end
  end

  protected

  def aff_push_changes
    notes = (@last_event ? @last_event.notes : []).map do |kv|
      get_status_json :kind => kv[0], :msg => kv[1], :status => 200
    end
    Red.boss.push_changes(notes)
  end

  private

  def execute_event(event, cont)
    @last_event = event
    Red.boss.enable_policy_checking
    ans = event.execute
    cont.call(event, ans)
  ensure
    Red.boss.disable_policy_checking
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
          value = to_record_hash(params[name]) if fld.type.isFile?
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

  def to_record_hash(uploaded_file)
    return nil unless uploaded_file
    {
      :__type__     => "RedLib::Util::FileRecord",
      :content_type => uploaded_file.content_type,
      :filename     => uploaded_file.original_filename,
      :filepath     => File.absolute_path(uploaded_file.tempfile.path),
      :size         => uploaded_file.size
    }
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
