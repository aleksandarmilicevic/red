module Red::Engine

  class CodegenRepo
    class << self
      
      @@gen_code = []
      def gen_code() @@gen_code end

      def add_method(mod, method_name, src, file=nil, line=nil)
        class_eval_code(mode, method_name, src, file, line)
      end

      # --------------------------------------------------------------
      #
      # Evaluates a source code block (`src') in the context of a
      # module (`mod'), and remembers it for future reference.
      #
      # @param mod [Module]  - module to add code to
      #
      # @param src [String]  - source code to be evaluated for module
      #                        `mod'
      #
      # @param file [String] - optional file name of the source
      #
      # @param line [String] - optional line number in the source file
      #                        source code
      #
      # @param desc [Hash]   - arbitrary hash to be stored alongside
      #
      # --------------------------------------------------------------
      def class_eval_code(mod, src, file=nil, line=nil, desc={})
        # Red.conf.log.debug "------------------------- in #{mod}"
        # Red.conf.log.debug src
        @@gen_code << {:module => mod, :code => src}.merge!(desc)
        mod.class_eval src, file, line
      end


    end
  end

end
