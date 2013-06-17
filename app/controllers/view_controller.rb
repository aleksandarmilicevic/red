require 'red/engine/view_manager'
require 'red/engine/html_delim_node_printer'

class ViewController < RedAppController
  include Red::Engine::HtmlDelimNodePrinter  

  def start
    view_name = params[:view] || "welcome"
    template_name = params[:template] || "home"
    
    @vm = Red::Engine::ViewManager.new
                                 
    view = @vm.render_view :view => view_name, 
                           :template => template_name,
                           :layout => false,
                           :locals => { :client => client,
                                        :server => server }
    tree = @vm.view_tree()

    text = print_with_html_delims(view)

    log = Red.conf.logger
    log.debug "@@@ View tree: "
    log.debug tree.print_full_info

    old = Red.boss.remember_client_view client, self
    old.pusher.stop_listening if old && old.pusher

    ret = render :text => text, :layout => true

    @pusher = Red::Engine::Pusher.new :client => client, 
                :views => lambda{[@vm.view_tree()]}, 
                :listen => false,
                :manager => @vm
  
    @pusher.start_listening 
    ret
  end

  def pusher() @pusher end
  def view_manager() @vm end

end
