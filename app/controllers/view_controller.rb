require 'red/engine/view_manager'
require 'red/engine/html_delim_node_printer'

class ViewController < RedAppController
  include Red::Engine::HtmlDelimNodePrinter

  def start
    Red.boss.clear_client_views

    view_name = params[:view] || "welcome"
    template_name = params[:template] || "home"

    red_render :view => view_name, :template => template_name
  end

end
