module Red::Engine

  class CodegenRepo
    class << self

      @@gen_methods = []
      def gen_methods() @@gen_methods end

      def add_method(mod, method_name, src, file=nil, line=nil)
        # Red.conf.log.debug "------------------------- in #{mod}"
        # Red.conf.log.debug src
        @@gen_methods << {:module => mod, :method_name => method_name, :code => src}
        mod.class_eval src, file, line
      end


    end
  end

end
