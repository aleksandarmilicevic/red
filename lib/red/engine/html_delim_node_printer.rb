require 'cgi'

module Red
  module Engine

    module HtmlDelimNodePrinter
      extend self

      def print_with_html_delims(node)
        result =
          if node.children.empty?
            node.result
          else
            node.children.reduce(""){|acc, c| acc + print_with_html_delims(c)}
          end
        enclose_result(result, node)
      end

      def enclose_result(str, node)
        # str = CGI::escapeHTML(str) if node.expr? && !str.html_safe?
        if node.no_deps?
          str
        else
          " <reds_#{node.id}></reds_#{node.id}> " +
            str +
            " <rede_#{node.id}></rede_#{node.id}> "
        end
      end
    end

  end
end
