require 'red/model/data_model'
require 'red/model/security_model'
require 'red/model/red_model_errors'
require 'sdg_utils/caching/cache.rb'

module Red
  module Engine

    class PolicyCache
      # @@policies    = nil
      # @@rules       = nil
      # @@read_rules  = nil
      # @@write_rules = nil

      @@meta_cache  = SDGUtils::Caching::Cache.new("meta")
      @@apps_cache  = SDGUtils::Caching::Cache.new("apps")

      # @@read_cache  = SDGUtils::Caching::Cache.new("read")
      # @@write_cache = SDGUtils::Caching::Cache.new("write")

      class << self
        # def policies()    @@policies    ||= Red.meta.policies end
        # def rules()       @@rules       ||= policies().map(&:restrictions).flatten end
        # def read_rules()  @@read_rules  ||= rules().select(&:applies_for_read) end
        # def write_rules() @@write_rules ||= rules().select(&:applies_for_write) end

        def meta() @@meta_cache end
        def apps() @@apps_cache end
      end
    end

    class PolicyChecker

      # @param principal [Red::Model::Machine] principal machine
      # @param conf      [Hash]                configuration options
      def initialize(principal, conf={})
        @conf = Red.conf.policy.extend(conf)
        @principal   = principal
        @read_conds  = _r_conds().map{|r| r.instantiate(principal)}
        @write_conds = _w_conds().map{|r| r.instantiate(principal)}
        @filters     = _r_filters().map{|r| r.instantiate(principal)}
      end

      def check_read(record, fld)
        key = "read: #{fld.full_name}(#{record.id}) by #{@principal}"
        failing_rule = PolicyCache.apps.fetch(key, @conf.no_read_cache) {
          @read_conds.find do |rule|
            rule.applies_to_field(fld) && rule.check_condition(record, fld)
          end
        }
        raise_access_denied(:read, failing_rule, record, fld) if failing_rule
      end

      def check_write(record, fld, value)
        key = "write: #{fld.full_name}(#{record.id}) by #{@principal}"
        failing_rule = PolicyCache.apps.fetch(key, @conf.no_write_cache) {
          @write_conds.find do |rule|
            rule.applies_to_field(fld) && rule.check_condition(record, fld, value)
          end
        }
        raise_access_denied(:write, failing_rule, record, fld, value) if failing_rule
      end

      def apply_filters(record, fld, value)
        key = "filter `#{value.__id__}': #{fld.full_name}(#{record.id}) by #{@principal}"
        PolicyCache.apps.fetch(key, @conf.no_filter_cache) {
          fld_filters = @filters.select{ |rule| rule.applies_to_field(fld) }
          if fld_filters.empty? || is_scalar(value)
            value
          else
            fld_filters.reduce(value) do |acc, filter|
              acc.reject{|val| filter.check_filter(record, val, fld)}
            end
          end
        }
      end

      private

      def is_scalar(value)
        return !value.kind_of?(Array)
      end

      def raise_access_denied(kind, rule, *payload)
        raise Red::Model::AccessDeniedError.new(kind, rule, *payload)
      end

      def _policies()  _meta(:policies) { Red.meta.policies                       } end
      def _rules()     _meta(:rules)    { _policies().map(&:restrictions).flatten } end
      def _r_rules()   _meta(:r_rules)  { _rules().select(&:applies_for_read)     } end
      def _r_conds()   _meta(:r_conds)  { _r_rules().select(&:has_condition?)     } end
      def _r_filters() _meta(:r_filters){ _r_rules().select(&:has_filter?)        } end
      def _w_rules()   _meta(:w_rules)  { _rules().select(&:applies_for_write)    } end
      def _w_conds()   _meta(:w_conds)  { _w_rules().select(&:has_condition?)     } end
      def _w_filters() _meta(:w_filters){ _w_rules().select(&:has_filter?)        } end

      def _meta(what, &block)
        PolicyCache.meta.fetch(what, @conf.no_meta_cache, &block)
      end
    end

  end
end
