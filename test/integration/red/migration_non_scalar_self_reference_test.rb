require 'migration_test_helper'

include Red::Dsl

data_model "D2" do
  record Person, {
    name: String,
    spouse: Person,
    children: (set Person)
  }
end

class MigrationSelfRefTest < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(D2)
  end

  def test_person
    p = D2::Person.new
    p.name = "x"
    c1 = D2::Person.new(:name => "c1")
    c2 = D2::Person.new(:name => "c2")
    p.children = [c1, c2]

    assert p.save!
    assert_equal 3, D2::Person.count

    children_inv = D2::Person.meta[:children].inv
    spouse_inv = D2::Person.meta[:spouse].inv

    assert_equal p, D2::Person.find(c1.id).read_field(children_inv)[0]
    assert_equal p, D2::Person.find(p.children[0].id).read_field(children_inv)[0]
    assert_equal p, D2::Person.find(c2.id).read_field(children_inv)[0]
    assert_equal p, D2::Person.find(p.children[1].id).read_field(children_inv)[0]

    s = D2::Person.new :name => "s"
    p.spouse = s
    s.children = [c1, c2]
    p.save

    assert_equal p, p.spouse.read_field(spouse_inv)[0]
    assert_equal p, D2::Person.find(p.spouse.id).read_field(spouse_inv)[0]

    s = D2::Person.find(s.id)
    assert_equal c1, s.children[0]
    assert_equal c2, s.children[1]

    assert_set_equal [p, s], c1.read_field(children_inv)
    assert_set_equal [p, s], c2.read_field(children_inv)

    p.destroy; assert_equal 3, D2::Person.count
    s.destroy; assert_equal 2, D2::Person.count
    assert_equal 0, c1.reload.read_field(children_inv).size
    assert_equal 0, c2.reload.read_field(children_inv).size
    c1.destroy
    c2.destroy
    assert_equal 0, D2::Person.count
  end

end
