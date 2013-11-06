require 'red/model/data_model'
require 'red/model/security_model'
require 'red/model/red_model_errors'
require 'sdg_utils/caching/cache.rb'

module Red
  module Engine

    class PolicyCache
      @@meta_cache  = SDGUtils::Caching::Cache.new("meta", :fast => true)
      @@apps_cache  = SDGUtils::Caching::Cache.new("apps", :fast => true, 
                                                           :acept_nils => true)

      class << self
        def meta() @@meta_cache end
        def apps() @@apps_cache end

        def clear_meta() @@meta_cache.clear end
        def clear_apps() @@apps_cache.clear end
      end
    end

    class PolicyChecker

      # @param principal [Red::Model::Machine] principal machine
      # @param conf      [Hash]                configuration options
      def initialize(principal, conf={})
        @conf = Red.conf.policy.extend(conf)
        globals = @conf.globals || {}
        @principal   = principal
        @read_conds  = _r_conds().map{|r| r.instantiate(principal, globals)}
        @write_conds = _w_conds().map{|r| r.instantiate(principal, globals)}
        @filters     = _r_filters().map{|r| r.instantiate(principal, globals)}
        @fld_rules   = {}
      end

      def check_read(record, fld)
        fld_conds = _fld_read_conds(fld)
        return if fld_conds.empty?
        key = "read: #{fld.full_name}(#{record.id}) by #{@principal}"
        failing_rule = PolicyCache.apps.fetch(key# , @conf.no_read_cache
                                              ) {
          fld_conds.find do |rule|
            rule.check_condition(record, fld)
          end
        }
        raise_access_denied(:read, failing_rule, record, fld) if failing_rule
      end

      def check_write(record, fld, value)
        fld_conds = _fld_write_conds(fld)
        return if fld_conds.empty?
        key = "write: #{fld.full_name}(#{record.id}) by #{@principal}"
        failing_rule = PolicyCache.apps.fetch(key#, @conf.no_write_cache
                                              ) {
          fld_conds.find do |rule|
            rule.check_condition(record, fld, value)
          end
        }
        raise_access_denied(:write, failing_rule, record, fld, value) if failing_rule
      end

      def apply_filters(record, fld, value)
        # return value if is_scalar(value)
        # value = [value] if is_scalar(value)
        fld_filters = _fld_filters(fld)
        return value if fld_filters.empty?
        key = "filter `#{value.__id__}': #{fld.full_name}(#{record.id}) by #{@principal}"
        ans = PolicyCache.apps.fetch(key# , @conf.no_filter_cache
                                     ) {
          fld_filters.reduce(value) do |acc, filter|
            acc.reject{|val| filter.check_filter(record, val, fld)}
          end
        }
        ans
      end

      private

      def _fld_rule(kind, rule_repo, fld)
        key = "field_#{kind}_#{fld.full_name}"
        @fld_rules[key] ||= rule_repo.select{|rule| rule.applies_to_field(fld)}
      end

      def _fld_read_conds(fld)  _fld_rule(:read_conds,  @read_conds,  fld) end
      def _fld_write_conds(fld) _fld_rule(:write_conds, @write_conds, fld) end
      def _fld_filters(fld)     _fld_rule(:filters,     @filters,     fld) end

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
        PolicyCache.meta.fetch(what, &block)
        # PolicyCache.meta.fetch(what, @conf.no_meta_cache, &block)
      end
    end

  end
end
