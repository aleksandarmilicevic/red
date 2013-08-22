require 'migration_test_helper'

include Red::Dsl

data_model "D3" do
  record Person, {
    name: String,
    manager: Manager
  }

  record Manager < Person, {
    title: String,
  }

  record Contact, {
    person: Person,
    email: String
  }
end

class MigrationInheritanceTest < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(D3)
  end

  def test_person
    m1 = D3::Manager.new :name => "boss"
    assert m1.save!
    assert_equal 1, D3::Person.count
    pm = D3::Person.find(m1.id)
    assert_equal D3::Manager, pm.class

    p = D3::Person.new :name => "schmuck"
    m2 = D3::Manager.new :name => "boss2"
    p.manager = m2
    p.save
    assert_equal 3, D3::Person.count
    assert_equal 2, D3::Manager.count

    mgr_inv = D3::Person.meta[:manager].inv

    assert_equal p, m2.read_field(mgr_inv).first

    m2.read_field(mgr_inv) << m1
    m2.save

    assert_equal m2, m1.manager

    assert_raise ActiveRecord::AssociationTypeMismatch do
      m2.manager = p
      m2.save
    end

    # circular managers -- ok, no rules specified
    m2.manager = m1
    m2.save

    c1 = D3::Contact.new :email => "xyz", :person => p
    c2 = D3::Contact.new :email => "xyz", :person => m1
    c3 = D3::Contact.new :email => "xyz", :person => m2

    c1.save; c2.save; c3.save
    assert_equal 3, D3::Contact.count
  end

end
