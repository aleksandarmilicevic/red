require 'red/engine/view_renderer'

module Red::Engine

  # ================================================================
  #  Class +ViewDependencies+
  # ================================================================
  class ViewDependencies
    # Maps record objects to field accesses (represented by an array
    # of (field, value) pairs.
    #
    # @return {RedRecord => Array(FieldMeta, Object)}
    def objs()    @objs ||= {} end

    # Returns the field-access list for a given object
    #
    # @param obj [RedRecord]
    # @return Array(FieldMeta, Object)
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
      flds = (objs[object] ||= [])
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
      fa = objs.map{ |k, v|
        "  #{k.class.name}(#{k.id})::(#{v.map{|f,fv| f.name}.join(', ')})"
      }.join("\n")
      cq = queries.map{|q| "  " + q.to_s}.join("\n")
      "Field accesses:\n#{fa}\nClasses queried:\n  #{cq}"
    end
  end

  # ================================================================
  #  Class +AccessListener+
  # ================================================================
  class AccessListener
    EVENTS = [Red::E_FIELD_READ, Red::E_FIELD_WRITTEN, Red::E_QUERY_EXECUTED]

    def initialize(hash={})
      @deps_list = Set.new
      @conf = Red.conf.access_listener.extend(hash)
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
