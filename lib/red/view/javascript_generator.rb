require 'red/model/red_model'
require 'red/model/red_meta_model'

module Red
module View

  class JavascriptGenerator

    class Ref
      def initialize(lit) @lit = lit end
      def to_s() @lit end
      def inspect() @lit end
    end

    class Fmt
      attr_reader :fmt, :args
      def initialize(fmt, args) @fmt = fmt; @args = args end
    end

    def translate_model_to_javascript(meta=Red.meta)
      @decl_js_classes = Set.new
      buff = ""
      buff << gen_prolog

      # relies on meta.records being top-sorted
      buff << "/* ------------- record signatures ------------- */\n\n"
      @decl_js_classes << Red::Model::Record << Red::Model::Data <<
                          Red::Model::Machine << Red::Model::Event
      (meta.records + meta.machines).each do |r|
        buff << gen_record_signature(r) << "\n"
        @decl_js_classes << r
      end

      # relies on meta.events being top-sorted
      buff << "\n/* ------------- event signatures ------------- */\n\n"
      meta.events.each do |e|
        buff << gen_event_signature(e) << "\n"
        @decl_js_classes << e
      end

      buff << "\n/* ------------- record meta ------------- */\n\n"
      meta.records.each do |r|
        buff << gen_record_meta(r) << "\n"
      end

      buff << "\n/* ------------- event meta ------------- */\n\n"
      meta.events.each do |e|
        buff << gen_event_meta(e) << "\n"
      end

      # buff << "\n/* ------------- red meta ------------- */\n\n"
      # buff << gen_red_meta(meta)

      buff << gen_epilog
      buff
    end

    def gen_record_signature(r)
      "var #{lit r} = Red.Constr.record(#{lit(r).inspect}, #{lit r.superclass});"
    end

    def gen_event_signature(e)
      "var #{lit e} = Red.Constr.event(#{lit(e).inspect}, #{lit e.superclass});"
    end

    def gen_record_meta(r)
      props_json = props_for_class_json(r)
      "#{lit r}.meta = new Red.Model.RecordMeta(#{props_json});\n"
    end

    def gen_event_meta(e)
      props_json = props_for_class_json(e)
      "#{lit e}.meta = new Red.Model.EventMeta(#{props_json});\n"
    end

    def gen_red_meta(meta)
      rec_json = to_json((meta.records + meta.machines).reduce({}) { |acc, r|
        acc.merge! r.name => r
      }, true)
      ev_json = to_json(meta.events.reduce({}) { |acc, e|
        acc.merge! e.name => e
      }, true)
      "Red.Meta.records = #{to_json_string rec_json};\n" +
      "Red.Meta.events = #{to_json_string ev_json};"
    end

    def props_for_class(cls)
      props = {:name => cls.name, :relative_name => cls.relative_name}
      props.merge! to_json(cls.meta)
    end

    def props_for_class_json(cls)
      to_json_string(props_for_class(cls))
    end

    @@tab = "  "
    def to_json_string(obj, indent="")
      case obj
      when Array
        new_indent = obj.size > 1 ? indent + @@tab : indent
        content = obj.map{|e| to_json_string(e, new_indent)}
        "[#{join_content(content, new_indent)}]"
      when Hash
        new_indent = obj.size > 1 ? indent + @@tab : indent
        content = obj.map{|k,v|
          "#{to_json_string(k)}: #{to_json_string(v, new_indent)}"
        }
        "{#{join_content(content, new_indent)}}"
      when NilClass
        "null"
      when Symbol
        obj.to_s.inspect
      when Fmt
        args = obj.args.map {|a| to_json_string(a, indent) }
        obj.fmt % args
      else
        obj.inspect
      end
    end

    def join_content(arr, indent="")
      ans = "#{arr.join(",\n#{indent+@@tab}")}"
      ans = "\n#{indent+@@tab}#{ans}\n#{indent}" if arr.size > 1
      ans
    end

    def to_json(obj, ref=false)
      case obj
      when Array; obj.map{|e| to_json(e, ref)}
      when Hash; obj.reduce({}){|a,kv| a.merge! to_json(kv[0],true)=>to_json(kv[1],ref)}
      when Class
        fail "won't expand a Class object" unless ref
        cls = obj
        if js_cls_declared? cls
          Ref.new lit(cls)
        else
          cls.name
        end
      when Alloy::Ast::SigMeta, Red::Model::EventMeta
        sig_meta = obj
        if ref
          Ref.new "#{to_json(sig_meta.sig_cls, true)}.meta"
        else
          incl = %w(sig_cls placeholder extra subsigs parentSig)
          incl += %w(from to) if Red::Model::EventMeta === obj
          h1 = instance_variables sig_meta, :include => incl
          h1.merge! :fields => to_json(sig_meta.fields),
                    :inv_fields => to_json(sig_meta.inv_fields)
        end
      when Alloy::Ast::Field
        fld = obj
        if ref
          fname = (fld.is_inv?) ? "inv_fields" : "fields"
          arr = fld.parent.meta.send fname.to_sym
          i = arr.index(fld)
          Ref.new "function(){ return #{to_json(fld.parent, true)}.meta.#{fname}[#{i}];}"
        else
          json = instance_variables fld, :except => [:impl, :expr]
          Fmt.new "new Red.Model.Field(%s)", [json]
        end
      when Alloy::Ast::AType
        atype = obj
        if atype.primitive?
          atype.to_s
        else
          fail "won't expand an AType object" unless ref
          to_json(atype.range.klass, true) rescue "********** DEPENDENT ********".inspect
        end
      else
        obj
      end
    end

    def js_cls_declared?(cls)
      @decl_js_classes.member? cls
    end

    def to_js_name(ruby_name)
      ruby_name.camelize(:lower)
    end

    def instance_variables(obj, hash={})
      include = hash[:include] || obj.instance_variables.map{|v| v[1..-1]}
      exclude = (hash[:except] || []).map{|e| e.to_s}
      (include - exclude).reduce({}) do |acc, var|
        val = obj.instance_variable_get("@" + var.to_s)
        acc.merge! to_js_name(var).to_sym => to_json(val, true)
      end
    end

    protected

    def gen_prolog() "" end
    def gen_epilog() "" end

    def lit(cls)
      if cls==Red::Model::Data || cls==Red::Model::Machine || cls==Red::Model::Record
        "Red.Model.Record"
      elsif cls == Red::Model::Event
        "Red.Model.Event"
      else
        cls.relative_name
      end
    end
  end

end
end
