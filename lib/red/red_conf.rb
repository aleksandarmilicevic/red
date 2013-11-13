require 'alloy/alloy_conf'
require 'red/store/fs_file_store'
require 'sdg_utils/config'
require 'sdg_utils/io'
require 'socket'
require 'nilio'
require 'logger'

module Red

  def self.default_view_deps_conf
    SDGUtils::Config.new do |c|
      c.log            = lambda{Red.conf.logger} # Logger.new(NilIO.instance) #
    end
  end

  def self.default_access_listener_conf
    SDGUtils::Config.new do |c|
      c.event_server   = lambda{Red.boss}
      c.log            = Logger.new(NilIO.instance)
    end
  end

  def self.default_pusher_conf
    SDGUtils::Config.new do |c|
      c.event_server   = lambda{Red.boss}
      c.views          = []
      c.deps           = nil
      c.manager        = nil #must be set by the caller
      c.client         = nil
      c.push_server    = "http://localhost:9292/faye"
      c.push_client_js = "http://localhost:9292/faye.js"
      c.listen         = true
      c.check_views    = true
      c.update_views   = true
      c.push_changes   = true
      c.auto_push      = false
      c.events         = [Red::E_RECORD_SAVED, Red::E_RECORD_DESTROYED,
                          Red::E_RECORD_QUERIED]
      c.log            = lambda{Red.conf.logger}
    end
  end

  def self.default_alloy_conf
    SDGUtils::PushConfig.new(Alloy.conf) do |c|
      c.inv_field_namer = lambda { |fld| "_" + fld.name }
      c.defer_body_eval = false
      #c.logger = SDGUtils::IO::LoggerIO.new(Rails.logger)
      # :inv_field_namer => lambda { |fld|
      #     begin
      #       owner_fld = "owner_#{fld.parent.red_ref_name}"
      #       default_name = "#{fld.name}_of_#{fld.parent.red_table_name}"
      #       if fld.belongs_to_parent? && !fld.type.range.klass.meta.field(owner_fld)
      #         owner_fld
      #       else
      #         default_name
      #       end
      #     rescue
      #       default_name
      #     end
      #  },
    end
  end

  def self.default_fs_file_store_conf
    SDGUtils::Config.new do |c|
      c.store_folder   = lambda{Rails.root.join("db").join("#{Rails.env}_file_store")}
    end
  end

  def self.default_renderer_conf
    SDGUtils::Config.new do |c|
      c.event_server                       = lambda{Red.boss}
      c.view_finder                        = lambda{Red::Engine::ViewFinder.new}
      c.access_listener                    = lambda{Red.boss.access_listener}
      c.current_view                       = nil
      c.no_template_cache                  = false
      c.no_file_cache                      = false
      c.no_content_cache                   = true
      c.invalidate_caches_between_requests = false
    end
  end

  def self.default_view_conf
    SDGUtils::Config.new do |c|
      c.autoviews          = true
      c.default_layout     = "red_app"
    end
  end

  def self.default_policy_conf
    SDGUtils::Config.new do |c|
      c.globals                                 = {}
      c.return_empty_for_read_violations        = true
      c.no_meta_cache                           = false
      c.no_read_cache                           = false
      c.no_write_cache                          = false
      c.no_filter_cache                         = false
      c.invalidate_meta_cache_between_requests  = false
      c.invalidate_apps_cache_between_requests  = true
    end
  end

  def self.default_conf
    SDGUtils::Config.new do |c|
      c.impl_field_namer = lambda { |fld| "#{fld.name}_REL" }
      c.impl_class_namer = lambda { |fld| "#{fld.parent.name}#{fld.name.classify}Tuple" }
      c.omit_field_name_in_join_table_names = false
      c.app_name        = lambda {Rails.root.to_s.split('/').last.underscore}
      c.js_record_ns    = "jRed"
      c.js_event_ns     = "jRed"
      c.root            = '.'
      c.view_paths      = ["app/views"]
      c.alloy           = default_alloy_conf
      c.pusher          = default_pusher_conf
      c.renderer        = default_renderer_conf
      c.access_listener = default_access_listener_conf
      c.view_deps       = default_view_deps_conf
      c.fs_file_store   = default_fs_file_store_conf
      c.file_store      = Red::Store::FSFileStore.new(c.fs_file_store)
      c.logger          = lambda{c.alloy.logger}
      c.log             = lambda{c.alloy.logger}
      c.log_java_script = true
      c.autoviews       = true
      c.automigrate     = false
      c.view            = default_view_conf
      c.policy          = default_policy_conf
    end
  end
end
