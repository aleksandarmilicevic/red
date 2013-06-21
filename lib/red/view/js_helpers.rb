require 'red/red_conf'
require 'sdg_utils/html/tag_builder'

module Red
  module View

    module JsHelpers
      extend self

      def js_ns_prefix(ns)
        ns ? "#{ns}." : "var "
      end

      def js_record_prefix
        js_ns_prefix(Red.conf.js_record_ns)
      end

      def js_event_prefix
        js_ns_prefix(Red.conf.js_event_ns)
      end

      def js_name(cls)
        cls.relative_name.underscore
      end

      # @param client [WebClient, Object#auth_token]
      def push_channel_to(client)
        "/data/update/#{client.auth_token}"
      end

      def red_tags
        ch = push_channel_to Red.boss.thr(:client)
        subs = ["Red.updateReceived"]
        if Red.conf.log_java_script
          subs.unshift("Red.logMessages")
        end
        subs_str = subs.map{|e| "Red.subscribe(#{e});"}.join("\n    ")
        out = <<-EOT
  <script type="text/javascript">
    Red.fayeClient = new Faye.Client('#{Red.conf.pusher.push_server}');
    Red.subscribe = function(func) { Red.fayeClient.subscribe('#{ch}', func); }
    Red.publish = function(json) { Red.fayeClient.publish('#{ch}', json); }
    #{subs_str}
  </script>
  <meta name="client-id" content="#{Red.boss.thr(:client).id}"/>
  <meta name="server-id" content="#{Red.boss.thr(:server).id}"/>
EOT
        out.html_safe
      end

      def red_styles
        traverse_views_with {|tree| tree.styles}
      end

      def red_scripts
        traverse_views_with {|tree| tree.scripts}
      end

      def red_assets
        styles = red_styles
        scripts = red_scripts
        return "" if styles.empty? && scripts.empty?
        out = <<-EOS
  <script type="text/javascript">
    #{scripts}
  </script>

  <style media="screen" type="text/css">
    #{styles}
  </style>
EOS
        out.html_safe
      end

      # @param utype [UnaryType]
      def ember_type(utype)
        utype.cls.to_ember_s
      end

      def ar2ember_mapper
        Proc.new do |reflection_macro|
          reflection_macro = reflection_macro.to_s
          case reflection_macro
          when "has_and_belongs_to_many"; "hasMany"
          when "belongs_to"; "belongsTo"
          when "has_one"; "belongsTo"
          when "has_many"; "hasMany"
          else
            # TODO fail?
            reflection_macro.camelize(:lower)
          end
        end
      end

      private

      def traverse_views_with(&block)
        Red.boss.client_views.map{ |vm|
          block.call(vm.view_tree).map{ |file|
            vm.render_to_plain_text :partial => file
          }
        }.flatten.join("\n\n").html_safe
      end

    end

  end
end
