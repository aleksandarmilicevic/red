require 'sdg_utils/caching/cache.rb'

module Red
  module Engine

    class RenderingCache
      @@content_cache  = SDGUtils::Caching::Cache.new("content")
      @@file_cache     = SDGUtils::Caching::Cache.new("file")
      @@template_cache = SDGUtils::Caching::Cache.new("template")

      class << self
        def content()  @@content_cache end
        def file()     @@file_cache end
        def template() @@template_cache end

        def clear_all
          @@content_cache.clear
          @@file_cache.clear
          @@template_cache.clear
        end
      end
    end

  end
end
