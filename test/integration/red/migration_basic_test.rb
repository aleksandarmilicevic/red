require 'migration_test_helper'

include Red::Dsl

data_model "D1" do
  record Person, {
    name: String,
    #nicknames: (set String),
    age: Integer,
    spouse: Person,
    cellphone: Phone,
    other_phones: (set Phone)
  }

  record Phone, {
    num: Integer,
  }

  record Trans do
    transient {{
      i: Integer,
      s: String,
      f: Float,
      b: Bool
    }}
  end
end

class MigrationBasicTest < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(D1)
  end

  def test_person
    # require 'pry'
    # binding.pry

    p = D1::Person.new
    p.name = "x"
    p.age = 23
    p.spouse = D1::Person.new :name => "y", :age => 22
    p.cellphone = D1::Phone.new
    p.cellphone.num = 123
    ph1, ph2, ph3 = [D1::Phone.new, D1::Phone.new, D1::Phone.new]
    p.other_phones = [ph1, ph2, ph3]
    p.other_phones[0].num = 234
    p.other_phones[1].num = 345
    ph3.num = 456
    p.spouse.other_phones = [ph3]

    assert p.save!
    assert_equal 2, D1::Person.count
    assert_equal 4, D1::Phone.count

    spouse_inv = D1::Person.meta[:spouse].inv
    cellphone_inv = D1::Person.meta[:cellphone].inv
    ophones_inv = D1::Person.meta[:other_phones].inv

    assert_equal p, p.spouse.read_field(spouse_inv)[0]
    assert_equal p, D1::Person.find(p.spouse.id).read_field(spouse_inv)[0]
    assert_equal p, D1::Phone.find(p.cellphone).read_field(cellphone_inv)[0]

    assert_arry_equal [p], ph1.read_field(ophones_inv)
    assert_arry_equal [p], ph2.read_field(ophones_inv)
    assert_set_equal [p, p.spouse], ph3.read_field(ophones_inv)

    pp = D1::Person.find(p.id)
    assert_equal p.name, pp.name
    assert_equal p.age, pp.age
    assert_equal p.cellphone.num, pp.cellphone.num

    #assert_equal 4, D1::PersonOtherPhoneJM.count

    phones = [p.cellphone] + p.other_phones
    sp = p.spouse

    p.destroy
    assert_equal 1, D1::Person.count
    assert_equal 4, D1::Phone.count
    #assert_equal 1, D1::PersonOtherPhoneJM.count

    phones.each {|ph| assert ph.destroy}
    assert_equal 1, D1::Person.count
    assert_equal 0, D1::Phone.count
    #assert_equal 0, D1::PersonOtherPhoneJM.count

    sp.destroy
    assert_equal 0, D1::Person.count
    assert_equal 0, D1::Phone.count
    #assert_equal 0, D1::PersonOtherPhoneJM.count

  end

  def test_trans
    t = D1::Trans.new
    assert_default_values t
    t.save!
    assert_default_values t

    tt = D1::Trans.all[0]
    assert_default_values tt

    tt = D1::Trans.find(t.id)
    assert_default_values tt
  end

  def assert_default_values(t)
    assert_equal 0, t.i
    assert_equal 0.0, t.f
    assert_equal "", t.s
    assert_equal false, t.b
    assert_equal false, t.b?
  end

end
