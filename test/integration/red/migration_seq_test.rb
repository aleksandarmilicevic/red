require 'migration_test_helper'

include Red::Dsl

data_model "D4" do
  record Person, {
    name: String, 
    contacts: (seq Contact)
  }
  
  record Contact, {
    email: String
  }
end

class MigrationSeqTest < MigrationTest::TestBase
  def setup_pre
    Red.meta.restrict_to(D4)  
  end
  
  def test1
    c1 = D4::Contact.new :email => "e1"
    c1.save!
    c2 = D4::Contact.new :email => "e2"
    c2.save!
    
    assert_equal 2, D4::Contact.count
    
    p = D4::Person.new :name => "xyz"
       
    p.contacts = [c2, c1]
    p.save
    
    assert_equal 1, D4::Person.count
    
    pp = D4::Person.find(p.id)
    assert_equal 2, pp.contacts.size
    assert_equal c2, pp.contacts[0]
    assert_equal c1, pp.contacts[1]
        
    p.contacts = [c1, c2, c1]    
    p.save!
    
    p.reload
    pp = D4::Person.find(p.id)
    [p, pp].each do |x|
      assert_equal 3, x.contacts.size
      assert_equal c1, x.contacts[0]
      assert_equal c2, x.contacts[1]
      assert_equal c1, x.contacts[2]
    end
    assert_equal 2, D4::Contact.count
    assert_equal 3, D4::PersonContactTuple.count
    
    c1.destroy
    assert_equal 1, D4::Person.count
    assert_equal 1, D4::Contact.count
    assert_equal 1, D4::PersonContactTuple.count
    
    p.reload #TODO make it work even without reload? 
              #TODO update the position field in the corresponding tuple to 0
    assert_equal 1, p.contacts.size
    assert_equal c2, p.contacts[0]
    puts D4::PersonContactTuple.all.inspect
    #FIXME
    #assert_equal 0, D4::PersonContactTuple.where(:person_0_id => pp.id, :contact_2_id => c2.id).first.integer_1
     
    c3 = D4::Contact.new :email => "e3"
    #p.contacts << c3
    p.contacts[0] = c3
    p.save!
    
    assert_equal 1, p.contacts.size
    assert_equal c3, pp.contacts[0]
    assert_equal 1, D4::Person.count
    assert_equal 2, D4::Contact.count
    assert_equal 2, D4::PersonContactTuple.count
    
  end
end