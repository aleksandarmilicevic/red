module Red
  module Routing

    module MapperExt
      VALID_ON_OPTIONS       =	[:new, :collection, :member]
      RESOURCE_OPTIONS       =	[:as, :controller, :path, :only, :except, :param, :concerns]
      CANONICAL_ACTIONS      =	[:index, :create, :new, :show, :edit, :update, :destroy]
      RESOURCE_METHOD_SCOPES =	[:collection, :member, :new]
      RESOURCE_SCOPES        =	[:resource, :resources]

      def sproc(proc_src)
        str = "proc{#{proc_src}}"
        prc = eval str
        prc.define_singleton_method :inspect do str end
        prc
      end

      def redresource(*resources, &block) _redresource(true, *resources, &block) end
      def redresources(*resources, &block) _redresource(false, *resources, &block) end

      private

      def _redresource(is_singleton, *resources, &block)
        hash = resources.extract_options!
        resources = [nil] if resources.empty?
        resources.each do |url|
          opts = normalize(is_singleton, url, hash)
          common_opts = opts[:other].merge({
            :controller => opts[:controller],
            :resource   => opts[:url]
          })
          opts[:actions].each do |act|
            common_opts_act = common_opts.merge :action => act
            idseg = is_singleton ? "" : "/:id"
            case act
            when :index   then get    "/#{opts[:url]}",              common_opts_act unless is_singleton
            when :new     then get    "/#{opts[:url]}/new",          common_opts_act
            when :create  then post   "/#{opts[:url]}",              common_opts_act
            when :show    then get    "/#{opts[:url]}#{idseg}",      common_opts_act
            when :edit    then get    "/#{opts[:url]}#{idseg}/edit", common_opts_act
            when :update  then put    "/#{opts[:url]}#{idseg}",      common_opts_act
            when :destroy then delete "/#{opts[:url]}#{idseg}",      common_opts_act
            end
          end
        end
      end

      def to_sym_arr(arr)
        Array(arr).map(&:to_sym)
      end

      def normalize(is_singleton, url_path, hash)
        hash = hash.dup
        actions = if hash.key?(:only)
                    to_sym_arr(hash.delete(:only))
                  elsif hash.key?(:except)
                    CANONICAL_ACTIONS - to_sym_arr(hash.delete(:except))
                  else
                    CANONICAL_ACTIONS
                  end

        klass = if hash.key?(:klass)
                  hash.delete :klass
                elsif hash.key?(:record_cls)
                  hash.delete :record_cls
                else
                  nil
                end
        klass = Red.meta.record_or_machine(klass.classify) if klass.is_a?(String)

        url = url_path || if klass
                            res_from_cls = klass.relative_name.underscore
                            is_singleton ? res_from_cls.singularize : res_from_cls.pluralize
                          end

        ctrl = if hash.key?(:controller)
                 hash.delete :controller
               elsif hash.key?(:to)
                 to = hash.delete :to
                 idx = to.index("#") || to.lenght
                 to[0...idx]
               else
                 "red_rest"
               end

        { :url        => url,
          :klass      => klass,
          :controller => ctrl,
          :actions    => actions,
          :other      => hash }
      end

    end

  end
end
