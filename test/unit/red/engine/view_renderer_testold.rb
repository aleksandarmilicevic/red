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

  def setup_class_pre_red_init
    Red.meta.restrict_to(R_E_VRT)
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
                                      :auto_push => true,
                                      :log => Logger.new(NilIO.instance)
  end

  def assert_objs_equal(objs, expected)
    actual = objs.map do |obj, fld_val_list|
      [obj, fld_val_list.map{|f,v| [f.name, v]}]
    end
    assert_arry_equal expected.to_a, actual
  end

  def assert_const(node, content)
    assert node.deps.objs.empty?
    assert node.deps.classes.empty?
    assert node.children.empty?
    case content
    when Regexp
      assert node.src =~ content
      assert node.result =~ content
    else
      assert_equal content.to_s, node.src
      assert_equal content.to_s, node.result
    end
  end

  def assert_rerender(assert_stuff)
    root = @manager.tree.root

    root.children.each_with_index do |n, idx|
      new_node = rerender n
      assert_not_equal new_node, n
      assert_equal new_node, root.children[idx]
      # assert_equal n.src, new_node.src
      assert_stuff.call
    end
  end

  def test0
    result = my_render :view => @@test_view, :text => "hi there"
    assert_equal "hi there", result
    root = @manager.tree.root

    assert_const root, "hi there"

  end

  def test0b
    tpl = <<-TPL
hi there <% render :text => "bro" %>
    TPL

    result = my_render :view => @@test_view, :inline => tpl.strip

    assert_stuff = lambda{
      root = @manager.tree.root
      assert_equal "hi there bro", result
      assert_equal 2, root.children.size
      assert_const root.children[0], "hi there "
      assert_const root.children[1], "bro"
      assert root.deps.objs.empty?
      assert root.deps.classes.empty?
    }

    assert_stuff.call

    # re-render inner nodes
    assert_rerender(assert_stuff)
  end

  def test1
    tpl = <<-TPL
hi there
    TPL

    result = my_render :view => @@test_view, :inline => tpl
    root = @manager.tree.root

    # renderer test

    assert_equal tpl, result
    assert root
    assert_equal 0, root.children.size
    assert root.deps.objs.empty?
    assert root.deps.classes.empty?

    # pusher test

    p = get_pusher_for_current_view
    @user1.name = "asdf"
    @room1.users = []
    save_all

    assert_arry_equal [], p.affected_nodes
    assert_arry_equal [], p.updated_nodes
  end

  def test2
    tpl = <<-TPL
hi there in <%= room1.name %>
    TPL

    result = my_render :view => @@test_view, :inline => tpl, :locals => locals()
    tree = @manager.tree
    root = tree.root

    assert_equal "hi there in g708", result.strip
    assert_equal 0, root.children.size
    assert_objs_equal root.deps.objs, room1 => [["name", "g708"]]
    assert root.deps.classes.empty?

    # pusher test
    p = get_pusher_for_current_view
    pusher_test21 p, tree
    pusher_test22 p, tree
    pusher_test23 p, tree
  end

  def pusher_test21(p, tree)
    @room1.users = []
    save_all

    assert_arry_equal [], p.affected_nodes
    assert_arry_equal [], p.updated_nodes
  end

  def pusher_test22(p, tree)
    @user1.name = ""
    @user1.save!

    assert_arry_equal [], p.affected_nodes
    assert_arry_equal [], p.updated_nodes
  end

  def pusher_test23(p, tree)
    root = tree.root
    @room1.name = "xxx"
    @room1.save!

    assert_equal "hi there in xxx", tree.root.result.strip
    assert_not_equal root, tree.root
    assert_arry_equal [root], p.affected_nodes
    assert_arry_equal [[root, tree.root]], p.updated_nodes
  end

  def test3
    tpl = <<-TPL
hi there <%= room1.users.map{|u| u.name}.join(", ") %>
    TPL

    result = my_render :view => @@test_view, :inline => tpl, :locals => locals()
    root = @manager.tree.root

    assert_equal "hi there eskang, jnear, singh", result.strip
    assert_equal 0, root.children.size
    exp = { @room1 => [["users", @room1.users]], @user1 => [["name", "eskang"]],
      @user2 => [["name", "jnear"]], @user3 => [["name", "singh"]] }
    assert_objs_equal root.deps.objs, exp
    assert root.deps.classes.empty?
  end

  def test4
    tpl = <<-TPL
hi there<%= render room1.users %> bros
    TPL

    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl, :locals => locals(),
                    :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang jnear *** bros", result.strip
      assert_equal 5, root.children.size
      assert_objs_equal root.deps.objs, { @room1 => [["users", @room1.users]] }
      assert_const root.children[0], "hi there"
      assert_objs_equal root.children[1].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }
      assert_objs_equal root.children[2].deps.objs,
                        { @user2 => [["slacker", false], ["name", "jnear"]] }
      assert_objs_equal root.children[3].deps.objs,
                        { @user3 => [["slacker", true]] }
      assert_const root.children[4], /^ bros/
      assert root.deps.classes.empty?
    }

    assert_stuff.call

    # re-render inner nodes
    assert_rerender(assert_stuff)
  end

  def test4b
    tpl = <<-TPL
hi there<%= render lambda{room1.users} %> bros
    TPL

    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl, :locals => locals(),
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang jnear *** bros", result.strip
      assert_equal 3, root.children.size
      assert_objs_equal root.deps.objs, {}
      assert_const(root.children[0], "hi there")
      ch0 = root.children[1]

      assert_objs_equal ch0.deps.objs, { @room1 => [["users", @room1.users]] }
      assert_equal 3, ch0.children.size
      assert_objs_equal ch0.children[0].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }
      assert_objs_equal ch0.children[1].deps.objs,
                        { @user2 => [["slacker", false], ["name", "jnear"]] }
      assert_objs_equal ch0.children[2].deps.objs,
                        { @user3 => [["slacker", true]] }
      assert_const root.children[2], /^ bros/

      assert root.deps.classes.empty?
    }

    assert_stuff.call

    assert_rerender(assert_stuff)
  end

  def test4c
    tpl = <<-TPL
hi there<%= render lambda{user1} %> bro
    TPL

    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl, :locals => locals(),
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang bro", result.strip
      assert_equal 3, root.children.size
      assert_objs_equal root.deps.objs, {}
      assert root.deps.classes.empty?

      assert_const(root.children[0], "hi there")

      ch0 = root.children[1]
      assert_objs_equal ch0.deps.objs, {}
      assert_equal 1, ch0.children.size
      assert_objs_equal ch0.children[0].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }

      assert_const root.children[2], /^ bro/
    }

    assert_stuff.call
    assert_rerender(assert_stuff)
  end

  def test4d
    tpl = <<-TPL
hi there<%= render lambda{user1} %> bro <%= user1.slacker ? 'slacker' : 'worker' %>
    TPL

    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl, :locals => locals(),
                       :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang bro worker", result.strip
      assert_equal 3, root.children.size
      assert_objs_equal root.deps.objs,
                        { @user1 => [["slacker", false]] }

      assert root.deps.classes.empty?

      assert_const(root.children[0], "hi there")

      ch0 = root.children[1]
      assert_objs_equal ch0.deps.objs, {}
      assert_equal 1, ch0.children.size
      assert_objs_equal ch0.children[0].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }

      assert_const root.children[2], /^ bro worker/
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
    result = my_render :view => @@test_view, :inline => tpl.strip, :locals => locals(),
                    :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there eskang jnear ***", result.strip
      assert_equal 4, root.children.size
      assert_objs_equal root.deps.objs, { }
      assert_const root.children[0], "hi there"
      assert_objs_equal root.children[1].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }
      assert_objs_equal root.children[2].deps.objs,
                        { @user2 => [["slacker", false], ["name", "jnear"]] }
      assert_objs_equal root.children[3].deps.objs,
                        { @user3 => [["slacker", true]] }
      assert_arry_equal [User], root.deps.classes
    }

    assert_stuff.call

    # re-render
    assert_rerender(assert_stuff)
  end

  def test5b
    tpl = <<-TPL
hi there<%= render lambda{User.all} %>
    TPL

    user_tpl = <<-UTPL
 <%= (!user.slacker?) ? user.name : "***" %>
    UTPL
    result = my_render :view => @@test_view, :inline => tpl.strip, :locals => locals(),
                    :view_finder => get_finder(" " + user_tpl.strip)

    assert_stuff = lambda {
      root = @manager.tree.root

      assert_equal "hi there eskang jnear ***", result.strip
      assert_equal 2, root.children.size
      assert_objs_equal root.deps.objs, { }
      assert_const root.children[0], "hi there"
      ch0 = root.children[1]
      assert_equal 3, ch0.children.size
      assert_objs_equal ch0.deps.objs, { }
      assert_objs_equal ch0.children[0].deps.objs,
                        { @user1 => [["slacker", false], ["name", "eskang"]] }
      assert_objs_equal ch0.children[1].deps.objs,
                        { @user2 => [["slacker", false], ["name", "jnear"]] }
      assert_objs_equal ch0.children[2].deps.objs,
                        { @user3 => [["slacker", true]] }
      assert root.deps.classes.empty?
      assert_arry_equal [User], ch0.deps.classes
    }

    assert_stuff.call

    # re-render
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

    result = my_render :view => @@test_view, :inline => tpl.strip,
                    :locals => locals(),
                    :view_finder => get_finder2({:user => user_tpl.strip,
                                                 :room => room_tpl.strip})

    assert_stuff = lambda {
      root = @manager.tree.root
      assert_equal "hi there slackers: singh\nrooms: g708", result.strip
      assert_equal 4, root.children.size
      assert_objs_equal root.deps.objs, { }
      assert_const root.children[0], "hi there slackers: "
      assert_const root.children[2], "\nrooms: "
      assert_objs_equal root.children[1].deps.objs,
                        { @user3 => [["name", "singh"]] }
      assert_objs_equal root.children[3].deps.objs,
                        { @room1 => [["name", "g708"]] }
      assert_arry_equal [User, Room], root.deps.classes
    }

    assert_stuff.call

    # re-render
    assert_rerender(assert_stuff)
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

    result = my_render :view => @@test_view, :inline => tpl.strip,
                    :locals => locals(),
                    :view_finder => get_finder2({:user => user_tpl.strip,
                                                 :room => room_tpl.strip})

    assert_stuff = lambda{
      root = @manager.tree.root
      assert_equal "hi there slackers: singh\nrooms: g708", result.strip
      assert_equal 4, root.children.size
      assert_objs_equal root.deps.objs, { }
      assert_const root.children[0], "hi there slackers: "
      assert_const root.children[2], "\nrooms: "
      ch0 = root.children[1]
      ch1 = root.children[3]
      assert_equal 1, ch0.children.size
      assert_objs_equal ch0.deps.objs, { }
      assert_objs_equal ch0.children[0].deps.objs,
                        { @user3 => [["name", "singh"]] }
      assert_equal 1, ch1.children.size
      assert_objs_equal ch1.deps.objs, { }
      assert_objs_equal ch1.children[0].deps.objs,
                        { @room1 => [["name", "g708"]] }

      assert root.deps.classes.empty?
      assert_arry_equal [User], ch0.deps.classes
      assert_arry_equal [Room], ch1.deps.classes
    }
    assert_stuff.call

    # re-render
    assert_rerender(assert_stuff)
  end

  def test7
    tpl = <<-TPL
#widget-<%= widget_id %> {
  <%= render :partial => 'mycss' %>
}
    TPL

    mycss = <<-CSSTPL
.cl1 { color: <%= widget_color %>; }
.cl2 { color: red; }
    CSSTPL

    result = my_render :view => @@test_view, :inline => tpl.strip,
                    :formats => [".erb", ".scss", ".css"],
                    :locals => locals(),
                    :view_finder => get_finder2({:mycss => mycss.strip})

    assert_stuff = lambda{
      root = @manager.tree.root
      puts result.strip
      # assert_equal "hi there slackers: singh\nrooms: g708", result.strip
      # assert_equal 4, root.children.size
      # assert_objs_equal root.deps.objs, { }
      # assert_const root.children[0], "hi there slackers: "
      # assert_const root.children[2], "\nrooms: "
      # ch0 = root.children[1]
      # ch1 = root.children[3]
      # assert_equal 1, ch0.children.size
      # assert_objs_equal ch0.deps.objs, { }
      # assert_objs_equal ch0.children[0].deps.objs,
      #                   { @user3 => [["name", "singh"]] }
      # assert_equal 1, ch1.children.size
      # assert_objs_equal ch1.deps.objs, { }
      # assert_objs_equal ch1.children[0].deps.objs,
      #                   { @room1 => [["name", "g708"]] }

      # assert root.deps.classes.empty?
      # assert_arry_equal [User], ch0.deps.classes
      # assert_arry_equal [Room], ch1.deps.classes
    }
    assert_stuff.call

    # re-render
    assert_rerender(assert_stuff)
  end

end
