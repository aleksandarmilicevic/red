require 'migration_test_helper'

include Red::Dsl

module M4
  machine_model do
    machine Client
    machine Server
  end

  event_model do
    event E1 do

    end

    event E2 do
      from x: Client
      to y: Server
    end
  end
end

class TestRedEventSimple < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(M4)
  end

  def test1
    assert M4::E1.meta.from, "`from' field not defined"
    assert_equal "from", M4::E1.meta.from.name, "wrong default name for the `from' field"
    assert M4::E1.meta.to, "`to' field not defined"
    assert_equal "to", M4::E1.meta.to.name, "wrong default name for the `to' field"
    assert_equal 2, M4::E1.meta.fields.size
    assert_set_equal %w(to from), M4::E1.meta.fields.map {|f| f.name}

    c = M4::Client.new
    e = M4::E1.new
    e.to = c
    e.from = c
    assert_equal c, e.to
    assert_equal c, e.from
  end

  def test2
    assert M4::E2.meta.from, "`from' field not defined"
    assert_equal "x", M4::E2.meta.from.name, "wrong name for the `from' field"
    assert M4::E2.meta.to, "`to' field not defined"
    assert_equal "y", M4::E2.meta.to.name, "wrong name for the `to' field"
    assert_equal 2, M4::E2.meta.fields.size
    assert_set_equal %w(x y), M4::E2.meta.fields.map {|f| f.name}

    c = M4::Client.new
    s = M4::Client.new
    e = M4::E2.new
    e.to = s
    e.from = c

    assert_equal s, e.to
    assert_equal c, e.from
  end

end
