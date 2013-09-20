require 'sdg_utils/event/events'
require 'red/engine/view_renderer'

module Red::Engine

  # ================================================================
  #  Class +ViewDependencies+
  # ================================================================
  class ViewDependencies
    include SDGUtils::Events::EventProvider

    E_DEPS_CHANGED = :deps_changed

    def initialize(conf={})
      @conf = Red.conf.view_deps.extend(conf)
    end

    # Maps record objects to field accesses (represented by an array
    # of (field, value) pairs.
    #
    # @return {RedRecord => Array(Field, Object)}
    def objs()    @objs ||= {} end

    # Returns the field-access list for a given object
    #
    # @param obj [RedRecord]
    # @return Array(Field, Object)
    def obj(obj)  objs[obj] || [] end

    # Returns a list of queried +RedRecord+ classes.
    #
    # @return Array(RedRecord.class)
    def classes()
      result = Set.new
      queries.each {|q| result.add(q.target)}
      result.to_a
    end

    # Returns a list of find queries
    #
    # @return Array(RedRecord.class, Array(Object), ActiveRecord::Relation)
    def queries() @queries ||= [] end

    def empty?
      objs.empty? && queries.empty?
    end

    def merge!(that)
      that.objs.each do |record, fv|
        fv.each do |field, value|
          field_accessed(record, field, value)
        end
      end
      queries.concat(that.queries)
    end

    def field_accessed(object, field, value)
      value = value.clone rescue value
      flds = obj!(object)
      unless flds.find {|f, v| f == field && v == value}
        flds << [field, value]
      end
    end

    # @param args [Array] is either [Query] or [target, method, args, result]
    def handle_query_executed(*args)
      query = args.size == 1 ? args[0] : Query.new(*args)
      queries << query
      nil
    end

    # def record_queried(record)
    #   classes << record.class unless classes.member?(record.class)
    # end

    def to_s
      to_s_short
    end

    def to_s_long
      fa = objs.map{ |k, v|
        "  #{k.class.name}(#{k.id})::(#{v.map{|f,fv| f.name}.join(', ')})"
      }.join("\n")
      cq = queries.map{|q| "  " + q.to_s}.join("\n")
      "Field accesses:\n#{fa}\nClasses queried:\n  #{cq}"
    end

    def to_s_short
      fa = objs.map{ |k, v|
        "#{k.class.name}(#{k.id})::(#{v.map{|f,fv| f.name}.join(', ')})"
      }.join(";")
      cq = queries.map{|q| "  " + q.to_s}.join(";")
      "F: #{fa}. Q: #{cq}"
    end

    def finalize
      debug "finalizing" unless empty?
      clear_listeners
      already_listening.each do |rec|
        rec.remove_obj_after_save self
        rec.remove_obj_after_destroy self
      end
      already_listening.clear
    end

    protected

    def my_fire(ev, record)
      cnt = event_listeners.size
      debug "detected #{ev} for #{record}; firing :deps_changed to #{cnt} listeners"
      fire E_DEPS_CHANGED, [ev, record]
    end

    def obj_after_save(record)    my_fire :after_save, record; true end
    def obj_after_elem_appended(obj, fld, value)

    end
    def obj_after_destroy(record) my_fire :after_destroy, record; true end

    # Returns existing, or creates an empty field-access list for a
    # given object.  If a new list is created, it also registers
    # itself to listen for record saved events.
    #
    # @param obj [RedRecord]
    # @return Array(Field, Object)
    def obj!(obj)
      if objs.key? obj
        objs[obj]
      else
        ans = objs[obj] ||= []
        if already_listening.add?(obj)
          obj.obj_after_save(self)
          # obj.obj_after_elem_appended(self)
          # obj.obj_after_destroy(self)
          debug "listening for #{obj} save and destroy"
        end
        ans
      end
    end

    def already_listening
      @already_listening ||= Set.new
    end

    def debug(msg)
      @conf.log.debug "[ViewDeps(#{__id__}): #{self.to_s_short}] #{msg}"
    end

  end

  # ================================================================
  #  Class +AccessListener+
  # ================================================================
  class AccessListener
    EVENTS = [Red::E_FIELD_READ, Red::E_FIELD_WRITTEN, Red::E_QUERY_EXECUTED]

    def initialize(conf={})
      @deps_list = Set.new
      @conf = Red.conf.access_listener.extend(conf)
    end

    def start_listening
      debug "listening for field accesses"
      @conf.event_server.register_listener(EVENTS, self)
    end

    def stop_listening
      debug "not listening for field accesses"
      @conf.event_server.unregister_listener(EVENTS, self)
    end

    def finalize
      @conf.event_server.unregister_listener(EVENTS, self)
    end

    # ---------------------------------------------------------------------------
    # TODO: should be synchronized

    # @param view_deps [ViewDependencies]
    def register_deps(view_deps)   @deps_list << view_deps; nil end

    # @param view_deps [ViewDependencies]
    def unregister_deps(view_deps) @deps_list.delete(view_deps); nil end

    # Event handler
    def call(event, par)
      obj, fld, ret, val = par[:object], par[:field], par[:return], par[:value]

      unless @deps_list.empty?
        debug "notifying #{@deps_list.size} deps about event #{event}"
      end

      case event
      when Red::E_FIELD_READ
        debug "field read: #{obj}.#{fld.name}"
        for_each_deps{|d| d.field_accessed(obj, fld, ret)}
      when Red::E_FIELD_WRITTEN
        debug "field written: #{obj}.#{fld.name}"
        for_each_deps{|d| d.field_accessed(obj, fld, val)}
      when Red::E_QUERY_EXECUTED
        target, meth, args, res = par[:target], par[:method], par[:args], par[:result]
        query = Query.new(target, meth, args, res)
        debug "query executed: #{query}"
        for_each_deps{|d| d.handle_query_executed(query)}
      else
        fail "unexpected event type: #{event}"
      end
    end

    # ---------------------------------------------------------------------------

    private

    def for_each_deps
      @deps_list.each do |deps|
        d = Proc === deps ? deps.call : deps
        yield d
      end
    end

    def pref()     "[AccessListener]" end
    def debug(msg) @conf.log.debug "#{pref} #{msg}" end
  end

end
