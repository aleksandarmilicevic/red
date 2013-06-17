require 'migration_test_helper'
require 'nilio'
require 'red/engine/view_manager'

include Red::Dsl

module R_E_VRT
  data_model do
    record User, {
      name: String,
      slacker: Boolean
    }
    
    record Room, {
      name: String,
      users: (set User)
    }
  end
end

class TestViewRendererSimple < MigrationTest::TestBase
  include R_E_VRT
  
  attr_reader :room1, :user1, :user2, :user3
  attr_reader :widget_id, :widget_color

  def setup_pre
    Red.meta.restrict_to(R_E_VRT)  
    Red.boss.start
  end

  @@test_view = "test_view"

  def setup_test
    @room1 = Room.new :name => "g708"
    @user1 = User.new :name => "eskang", :slacker => false
    @user2 = User.new :name => "jnear", :slacker => false
    @user3 = User.new :name => "singh", :slacker => true
    @room1.users = [@user1, @user2, @user3]
    @objs = [@room1, @user1, @user2, @user3]
    save_all
    @room1_id = @room1.id

    @widget_id = 42
    @widget_color = 'green'
  end
  
  def teardown
    @objs.each {|r| r.destroy}
    @pusher.finalize if @pusher
  end

  def locals
    @locals ||= 
      begin
        methods = {:render => method(:render).to_proc}
        vars = instance_variables.reduce({}) do |acc, v|
          acc.merge v => instance_variable_get(v)
        end
        consts = self.class.constants(true).reduce({}) do |acc, c|
          acc.merge c => self.class.const_get(c)
        end
        methods.merge!(vars).merge!(consts)
      end
  end
  
  def my_render(hash)
    @manager = Red::Engine::ViewManager.new :view_finder => hash.delete(:view_finder)
    @manager.render_view({:formats =>[".erb", ".txt"]}.merge!(hash)).result
  end

  def rerender(node)
    @manager.rerender_node(node)
  end

  def render(*args)
    @manager.renderer.render(*args)
  end

  def save_all
    @objs.each {|r| r.save!} 
  end

  def get_finder(str=nil, expected_view=@@test_view, &block)
    proc = if str 
             lambda{ |view, template, p| 
               view == expected_view ? {:inline => str} : nil
             } 
           else 
             block
           end
    obj = Object.new
    obj.define_singleton_method :find_view, proc
    obj
  end
  
  def get_finder2(tpls, expected_view=@@test_view)
    obj = Object.new
    obj.define_singleton_method :find_view, lambda { |view, template, p|
      if tpls.key?(template.to_sym)
        view == expected_view ? {:inline => tpls[template.to_sym]} : nil
      else
        nil
      end
    }
    obj
  end

  def get_pusher_for_current_view
    @pusher = Red::Engine::Pusher.new :event_server => Red.boss, 
                                      :views => [@manager.tree],
                                      :manager => @manager,
                                      :push_changes => false, 
                                      :auto_push => true
  end

  def assert_objs_equal(objs, expected)
    actual = objs.map do |obj, fld_val_list|
      [obj, fld_val_list.map{|f,v| [f.name, v]}]
    end
    assert_arry_equal expected.to_a, actual
  end

  def assert_no_deps(node)
    msg = "empty dependencies expected, found:\n#{node.deps}"
    assert node.deps.objs.empty?, msg
    assert node.deps.classes.empty?, msg
  end
  
  def assert_const(node, result)
    assert_no_deps(node)    
    assert_expr(node, result)
  end
  
  def assert_expr(node, result, src=nil)
    assert node.children.empty?, "didn't expect any children in an expr node, found #{node.children.size}"
    assert_matches result, node.output, "output doesn't match expected result"
    assert_matches result, node.result, "result doesn't match expected result"
    if src
      assert_matches src, node.src, "source doesn't match expected source"
    end
  end

  def assert_rerender(assert_stuff)
    root = @manager.tree.root
    for idx in 0..root.children.size-1
      n = root.children[idx]
      new_node = rerender n
      assert_equal n.type, new_node.type
      assert_not_equal new_node, n unless n.const?
      assert_equal new_node, root.children[idx]
      # assert_equal n.src, new_node.src
      assert_stuff.call
    end
  end

  def test0
    result = my_render :view => @@test_view, :text => "hi there"
    assert_equal "hi there", result
    root = @manager.tree.root
    assert_no_deps root
    assert_equal 1, root.children.size
    assert_const root.children[0], "hi there"
  end

  def test0b
    tpl = <<-TPL
hi there <%= render :text => "bro" %>
    TPL
    
    result = my_render :view => @@test_view, :inline => tpl.strip
    
    assert_stuff = lambda{
      root = @manager.tree.root
      assert_equal "hi there bro", result
      assert_no_deps root
      assert_equal 2, root.children.size
      assert_const root.children[0], "hi there "
      assert_expr root.children[1], "bro", 'render :text => "bro"'
    }

    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test1
    tpl = <<-TPL
hi there
    TPL
    
    result = my_render :view => @@test_view, :inline => tpl
    
    assert_stuff = lambda{
      root = @manager.tree.root

      assert_equal tpl, result    
      assert_no_deps root
      assert_equal 1, root.children.size
    
      assert_const root.children[0], tpl
    }

    assert_stuff.call
    assert_rerender(assert_stuff)
        
    # pusher test

    p = get_pusher_for_current_view
    @user1.name = "asdf"
    @room1.users = []
    save_all
    
    assert_arry_equal [], p._affected_nodes
    assert_arry_equal [], p._updated_nodes
  end
  
  def test2
    tpl = <<-TPL
hi there in <%= room1.name %>   
    TPL
    
    result = my_render :view => @@test_view, :inline => tpl.strip, :locals => locals()
    
    assert_stuff = lambda{
      tree = @manager.tree
      root = tree.root

      assert_equal "hi there in g708", result.strip
      assert_no_deps root
      assert_equal 2, root.children.size 
    
      assert_const root.children[0], "hi there in "
    
      ch1 = root.children[1]
      assert_expr ch1, "g708", 'room1.name'
      assert_objs_equal ch1.deps.objs, room1 => [["name", "g708"]]
      assert ch1.deps.classes.empty?
    }

    assert_stuff.call
    assert_rerender(assert_stuff)

    # pusher test
    p = get_pusher_for_current_view
    begin
      pusher_test21 p, @manager.tree
      pusher_test22 p, @manager.tree
      pusher_test23 p, @manager.tree
      pusher_test24 p, @manager.tree
    ensure
      p.stop_listening
    end
  end
  
  def pusher_test21(p, tree)
    p.__reset_saved_fields
    @room1.users = []
    save_all
    
    assert_arry_equal [], p._affected_nodes
    assert_arry_equal [], p._updated_nodes    
  end

  def pusher_test22(p, tree)
    p.__reset_saved_fields
    @user1.name = ""
    @user1.save!
    
    assert_arry_equal [], p._affected_nodes
    assert_arry_equal [], p._updated_nodes    
  end

  def pusher_test23(p, tree)
    p.__reset_saved_fields
    root = tree.root
    ch1old = root.children[1]
    
    @room1.name = "xxx"
    @room1.save!
       
    ch1 = root.children[1]
       
    assert_equal "hi there in xxx", tree.root.result.strip
    assert_not_equal ch1, ch1old
    assert_arry_equal [ch1old], p._affected_nodes
    assert_arry_equal [[ch1old, ch1]], p._updated_nodes
  end
  
  def pusher_test24(p, tree)
    p.__reset_saved_fields
    root = tree.root
    ch1old = root.children[1]
    
    @room1.name = "aaa"
    @room1.save!
       
    ch1 = root.children[1]
       
    assert_equal "hi there in aaa", tree.root.result.strip
    assert_not_equal ch1, ch1old
    assert_arry_equal [ch1old], p._affected_nodes
    assert_arry_equal [[ch1old, ch1]], p._updated_nodes
  end

  def test3
    tpl = <<-TPL
hi there <%= room1.users.map{|u| u.name}.join(", ") %>   
    TPL
    
    result = my_render :view => @@test_view, :inline => tpl.strip, :locals => locals()
    
    assert_stuff = lambda{
      root = @manager.tree.root

      assert_equal "hi there eskang, jnear, singh", result.strip
      assert_no_deps root
      assert_equal 2, root.children.size 

      assert_const root.children[0], "hi there "
      assert_expr root.children[1], 
                  'eskang, jnear, singh', 
                  'room1.users.map{|u| u.name}.join(", ")'
      exp = { @room1 => [["users", @room1.users]], 
              @user1 => [["name", "eskang"]],
              @user2 => [["name", "jnear"]], 
              @user3 => [["name", "singh"]] }
      assert_objs_equal root.children[1].deps.objs, exp
      assert root.children[1].deps.classes.empty?
    }

    assert_stuff.call
    assert_rerender(assert_stuff)    
  end

  def assert_eskang(n)
    assert_no_deps n
    assert_const n.children[0], " "
    assert_expr n.children[1], "eskang", '(!user.slacker?) ? user.name : "***"'
    assert_objs_equal n.children[1].deps.objs, 
                      { @user1 => [["slacker", false], ["name", "eskang"]] }
  end

  def assert_jnear(n)
    assert_no_deps n
    assert_const n.children[0], " "
    assert_expr n.children[1], "jnear", '(!user.slacker?) ? user.name : "***"'           
    assert_objs_equal n.children[1].deps.objs, 
                      { @user2 => [["slacker", false], ["name", "jnear"]] }
  end

  def assert_rishabh(n)
    assert_no_deps n
    assert_const n.children[0], " "
    assert_expr n.children[1], "***", '(!user.slacker?) ? user.name : "***"'
    assert_objs_equal n.children[1].deps.objs, 
                      { @user3 => [["slacker", true]] }
  end

  def assert_stuff4(result) lambda {
    root = @manager.tree.root
    assert_equal "hi there eskang jnear *** bros", result.strip
    assert_no_deps root
    assert_equal 3, root.children.size
    
    assert_const root.children[0], "hi there"
    assert_const root.children[2], /^ bros/
    
    ch1 = root.children[1]      
    assert_objs_equal ch1.deps.objs, { @room1 => [["users", @room1.users]] }
    
    assert_eskang  ch1.children[0]
    assert_jnear   ch1.children[1]
    assert_rishabh ch1.children[2]
  } end

  def do_test4(tpl, user_tpl)
    result = my_render :view => @@test_view, 
                       :inline => tpl.strip, 
                       :locals => locals(), 
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = assert_stuff4(result)
    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test4
    tpl = <<-TPL
hi there<%= render room1.users %> bros  
    TPL
    
    user_tpl = <<-UTPL
<%= (!user.slacker?) ? user.name : "***" %>
    UTPL

    do_test4(tpl, user_tpl)
  end

  def test4b
    tpl = <<-TPL
hi there<%= render lambda{room1.users} %> bros
    TPL
    
    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL

    do_test4(tpl, user_tpl)
  end

  def test4c
    tpl = <<-TPL
hi there<%= render user1 %> bro
    TPL
    
    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl, :locals => locals(), 
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang bro", result.strip
      assert_no_deps root
      assert_equal 3, root.children.size
      
      assert_const root.children[0], "hi there"
      assert_const root.children[2], /^ bro/
      
      assert_eskang root.children[1]
    }
    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test4d
    tpl = <<-TPL
hi there<%= render user1 %> bro <%= user1.slacker ? 'slacker' : 'worker' %>
    TPL
    
    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl.strip, :locals => locals(), 
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang bro worker", result.strip
      assert_no_deps root
      assert_equal 4, root.children.size
      
      assert_const root.children[0], "hi there"
      assert_const root.children[2], " bro "
      
      n = root.children[1]      
      assert_eskang n

      n = root.children[3]      
      assert_expr n, "worker", "user1.slacker ? 'slacker' : 'worker'"
      assert_objs_equal n.deps.objs, 
                         { @user1 => [["slacker", false]] }
    }

    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def do_test5(tpl, user_tpl)
    result = my_render :view => @@test_view, 
                       :inline => tpl.strip, 
                       :locals => locals(), 
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang jnear ***", result.strip
      assert_no_deps root
      assert_equal 2, root.children.size
      
      assert_const root.children[0], "hi there"
    
      ch1 = root.children[1]      
      assert_arry_equal [User], ch1.deps.classes
      assert_objs_equal ch1.deps.objs, {}
    
      assert_eskang  ch1.children[0]
      assert_jnear   ch1.children[1]
      assert_rishabh ch1.children[2]
    }
    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test5
    tpl = <<-TPL
hi there<%= render User.all %> 
    TPL
    
    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL

    do_test5(tpl, user_tpl)
  end

  def test5b
    tpl = <<-TPL
hi there<%= render lambda{User.all} %>   
    TPL
    
    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL

    do_test5(tpl, user_tpl)
  end
  
  def do_test6(tpl, user_tpl, room_tpl)
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :locals => locals(), 
                    :view_finder => get_finder2({:user => user_tpl.strip, 
                                                 :room => room_tpl.strip})

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there slackers: singh\nrooms: g708", result.strip
      assert_no_deps root
      
      assert_equal 4, root.children.size 
      assert_const root.children[0], "hi there slackers: "
      assert_const root.children[2], "\nrooms: "

      ch1 = root.children[1]
      ch3 = root.children[3]
      assert_arry_equal [User], ch1.deps.classes
      assert_arry_equal [Room], ch3.deps.classes

      un = ch1.children[0]
      assert_expr un, "singh", "user.name"
      assert_objs_equal un.deps.objs, 
                        { @user3 => [["name", "singh"]] }


      rn = ch3.children[0]
      assert_expr rn, "g708", "room.name"
      assert_objs_equal rn.deps.objs, 
                        { @room1 => [["name", "g708"]] }
    }

    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test6
    tpl = <<-TPL
hi there slackers: <%= render User.where(:slacker => true) %>
rooms: <%= render Room.find(@room1_id) %>
    TPL
    
    user_tpl = <<-UTPL
<%= user.name %>
    UTPL
    
    room_tpl = <<-RTPL
<%= room.name %>
    RTPL

    do_test6(tpl, user_tpl, room_tpl)
  end

  def test6b
    tpl = <<-TPL
hi there slackers: <%= render lambda{User.where(:slacker => true)} %>
rooms: <%= render lambda{Room.find(@room1_id)} %>     
    TPL
    
    user_tpl = <<-UTPL
<%= user.name %>
    UTPL
    
    room_tpl = <<-RTPL
<%= room.name %>
    RTPL
    
    do_test6(tpl, user_tpl, room_tpl)
  end

  def do_test7(tpl, mycss)    
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :formats => [".erb", ".scss", ".css"],
                    :locals => locals(), 
                    :view_finder => get_finder2({:mycss => mycss.strip})
   
    assert_stuff = lambda{       
      root = @manager.tree.root
      expected = "#widget-g708 .cl1 { color: green; } #widget-g708 .cl2 { color: red; }"
      assert_equal_ignore_whitespace expected, result
      assert root.children.empty?
      assert_objs_equal root.deps.objs, { @room1 => [["name", "g708"]] }
    }
    assert_stuff.call
    
    # re-render
    assert_rerender(assert_stuff)
  end
  
  def test7
    tpl = <<-TPL
#widget-<%= room1.name %> {
  <%= render :partial => 'mycss' %>
}
    TPL
    
    mycss = <<-CSSTPL
.cl1 { color: <%= widget_color %>; }
.cl2 { color: red; }
    CSSTPL
  
    do_test7(tpl, mycss)
  end
  
  def test7b
    tpl = <<-TPL
#widget-<%= room1.name %> {
  <%= render lambda{{:partial => 'mycss'}} %>
}
    TPL
    
    mycss = <<-CSSTPL
.cl1 { color: <%= widget_color %>; }
.cl2 { color: red; }
    CSSTPL
  
    do_test7(tpl, mycss)
  end
  
  def do_test8(tpl, room_tpl, ch1_check)    
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :formats => [".scss", ".erb", ".css"],
                    :locals => locals(),
                    :view_finder => get_finder2({:room => room_tpl.strip})
   
    assert_stuff = lambda{       
      root = @manager.tree.root
      expected = '#widget-xxx .cl1 { color: "g708"; } #widget-xxx .cl2 { color: red; }'
      assert_equal_ignore_whitespace expected, result
      assert_no_deps root
      assert_equal 3, root.children.size
      assert_const root.children[0], /#widget-xxx .cl1\s+{\s+color:\s+"/
      assert_const root.children[2], /"; }\s+#widget-xxx\s+.cl2\s+{\s+color: red; }\s*/
      ch1_check.call(root.children[1])
    }
    assert_stuff.call
    assert_rerender(assert_stuff)
  end
  
  def test8
    tpl = <<-TPL
#widget-xxx {
  .cl1 { color: "<%= room1.name %>"; }
  .cl2 { color: red; }
}
    TPL
  
    do_test8(tpl, "", lambda {|ch1|
      assert_expr ch1, 'g708', 'room1.name'
      assert_objs_equal ch1.deps.objs, { @room1 => [["name", "g708"]] }
    })
  end

  def test8b
    tpl = <<-TPL
#widget-xxx {
  .cl1 { color: "<%= render room1 %>"; }
  .cl2 { color: red; }
}
    TPL
    
    room_tpl = <<-RTPL
<%= room.name %>
    RTPL
      
    do_test8(tpl, room_tpl, lambda {|ch1|
      assert_no_deps ch1
      assert_equal 1, ch1.children.size
      assert_expr ch1.children[0], 'g708', 'room.name'
      assert_objs_equal ch1.children[0].deps.objs, { @room1 => [["name", "g708"]] }
    })
  end
  
  def test9
    tpl = <<-TPL
pre <%= render :partial => "\#{room1.name}" %> post
    TPL
    
    g708 = <<-XXX
***
    XXX
    
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :formats => [".erb", ".txt"],
                    :locals => locals(),
                    :view_finder => get_finder2({:g708 => g708.strip})
   
    assert_stuff = lambda{       
      root = @manager.tree.root
      expected = 'pre *** post'
      assert_equal expected, result
      assert_no_deps root
      assert_equal 3, root.children.size
      assert_const root.children[0], "pre "
      assert_const root.children[2], " post"
      assert_objs_equal root.children[1].deps.objs, { @room1 => [["name", "g708"]] }
    }
   
    assert_stuff.call
    assert_rerender(assert_stuff)
  end
  
  def do_test10(tpl, expected)
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :formats => [".erb", ".txt"],
                    :locals => locals()
    check_test10_stuff(expected, result, "g708")
  end

  def check_test10_stuff(expected, result, room_name)
    assert_stuff = lambda{       
      root = @manager.tree.root
      assert_matches expected, result
      assert_objs_equal root.deps.objs, { @room1 => [["name", room_name]] }
      assert_equal 1, root.children.size
      assert_const root.children[0], expected
    }
   
    assert_stuff.call
    assert_rerender(assert_stuff)
  end
  
  def test10
    tpl = <<-TPL
% if room1.name.size > 3
    room name is greater than 3
% else
    room name is not greater than 3
% end
    TPL

    do_test10(tpl, /room name is greater than 3/)

    p = get_pusher_for_current_view
    begin
      pusher_test_10_1(p)
      pusher_test_10_2(p)
    ensure
      p.stop_listening
    end
  end

  def pusher_test_10_1(p)
    p.__reset_saved_fields
    old_root = @manager.tree.root
    @room1.name = "abdsdfj"
    save_all

    assert_arry_equal [old_root], p._affected_nodes
    assert_arry_equal [], p._updated_nodes
    # assert_not_equal old_root, @manager.tree.root
    check_test10_stuff(/room name is greater than 3/, @manager.tree.root.result, "abdsdfj")
  end

  def pusher_test_10_2(p)
    p.__reset_saved_fields
    old_root = @manager.tree.root
    @room1.name = "a"
    save_all

    assert_arry_equal [old_root], p._affected_nodes
    assert_arry_equal [[old_root, @manager.tree.root]], p._updated_nodes
    assert_not_equal old_root, @manager.tree.root
    check_test10_stuff(/room name is not greater than 3/, @manager.tree.root.result, "a")
  end

  def test10b
    tpl = <<-TPL
% if room1.name[2..-1].size > 3
    room name* is greater than 3
% else
    room name* is not greater than 3
% end
    TPL

    do_test10(tpl, /room name\* is not greater than 3/)
  end

  def do_test11(tpl, user_tpl, room_tpl)
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                       :formats => [".erb", ".txt"],
                       :locals => locals(),
                       :view_finder => get_finder2({:user => user_tpl.strip, 
                                                    :room => room_tpl.strip})

    assert_stuff = lambda{       
      root = @manager.tree.root
      assert_matches(/\s*_eskang_\s*_jnear_\s*_\*\*\*_\s*/, result)
      # assert_objs_equal root.deps.objs, { @room1 => [["name", "g708"]] }
      # assert_equal 1, root.children.size
      # assert_const root.children[0], expected
    }
   
    assert_stuff.call
    assert_rerender(assert_stuff)
  end
  
  def do_test11(tpl, user_tpl, room_tpl)
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                       :formats => [".erb", ".txt"],
                       :locals => locals(),
                       :view_finder => get_finder2({:user => user_tpl.strip, 
                                                    :room => room_tpl.strip})

    assert_stuff = lambda{       
      root = @manager.tree.root
      assert_matches(/\s*_eskang_\s*_jnear_\s*_\*\*\*_\s*/, result)
      # assert_objs_equal root.deps.objs, { @room1 => [["name", "g708"]] }
      # assert_equal 1, root.children.size
      # assert_const root.children[0], expected
    }
   
    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test11
    tpl = <<-TPL
<% room1.users.each do |u| %>
  <%= render u %>
<% end %>
    TPL

    utpl = <<-UTPL
<% if user.slacker %>
  _***_
<% else %>
  _<%= user.name %>_
<% end %>
    UTPL

    do_test11(tpl, utpl, "")
  end

  def do_test12(tpl, branch_result, branch_check)
    result = my_render :view => @@test_view, :inline => tpl.strip, 
                    :formats => [".erb", ".txt"],
                    :locals => locals()
   
    assert_stuff = lambda{       
      root = @manager.tree.root
      assert_matches(/pre\s*#{branch_result}\s*post/, result)
      assert_objs_equal root.deps.objs, { @room1 => [["name", "g708"]] }
      assert_equal 5, root.children.size
      assert_const root.children[0], /pre\s*/
      branch_check.call(root)
      assert_const root.children[4], "post"
    }
   
    assert_stuff.call
    assert_rerender(assert_stuff)
  end
  
  def test12
    tpl = <<-TPL
pre
% if room1.name.size > 3
    room name is <%= room1.name %>.
% else
    room has <%= room1.users.size %> users.
% end
post
    TPL
    
    branch_check = lambda{ |root|
      assert_const root.children[1], /\s*room name is /
      assert_expr root.children[2], "g708", 'room1.name'
      assert_objs_equal root.children[2].deps.objs, { @room1 => [["name", "g708"]] }      
      assert_const root.children[3], /.\s*/
    }

    do_test12(tpl, "room name is g708\.", branch_check)
  end

  def test12b
    tpl = <<-TPL
pre
% if room1.name[2..-1].size > 3
    room name is <%= room1.name %>.
% else
    room has <%= room1.users.size %> users.
% end
post
    TPL
    
    branch_check = lambda{ |root|
      assert_const root.children[1], /\s*room has /
      assert_expr root.children[2], "3", 'room1.users.size'
      assert_objs_equal root.children[2].deps.objs, { @room1 => [["users", room1.users]] }      
      assert_const root.children[3], / users.\s*/
    }

    do_test12(tpl, "room has 3 users.", branch_check)
  end
end
