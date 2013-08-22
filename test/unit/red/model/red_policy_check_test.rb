require 'migration_test_helper'
require 'nilio'
require 'red/model/security_model'

include Red::Dsl

module R_M_TPC
  data_model do
    record User, {
      name: String,
      pswd: String,
      status: String
    }

    record Room, {
      members: (set User)
    }
  end

  machine_model do
    machine Client, {
      user: User
    }
  end

  security_model do
    policy P1 do
      principal client: Client

      # restrict access to passwords except for owning user
      restrict User.pswd.unless do |user|
        client.user == user
      end

      # never send passwords to clients
      def check_restrict_user_pswd() true end
      restrict User.pswd, :when => :check_restrict_user_pswd

      # restrict access to status messages to users who share at least
      # one chat room with the owner of that status message
      restrict User.status.when do |user|
        client.user != user &&
        Room.none? { |room|
          room.members.include?(client.user) &&
          room.members.include?(user)
        }
      end

      # filter out busy users (those who set their status to "busy")
      restrict Room.members.reject do |room, member|
        member.status == "busy"
      end
    end
  end
end

class TestPolicyCheck < MigrationTest::TestBase
  include R_M_TPC

  attr_reader :client1, :client2, :room1, :user1, :user2, :user3

  @@room1 = nil
  @@user1 = nil
  @@user2 = nil
  @@user3 = nil
  @@client1 = nil
  @@client2 = nil
  @@client3 = nil
  @@objs = nil

  def setup_class_pre_red_init
    Red.meta.restrict_to(R_M_TPC)
  end

  def setup_class_post_red_init
    @@room1 = Room.new
    @@user1 = User.new :name => "eskang", :pswd => "ek123", :status => "working"
    @@user2 = User.new :name => "jnear", :pswd => "jn123", :status => "busy"
    @@user3 = User.new :name => "singh", :pswd => "rs123", :status => "slacking"
    @@room1.members = [@@user1, @@user2]
    @@client1 = Client.new :user => @@user1
    @@client2 = Client.new :user => @@user2
    @@client3 = Client.new
    @@objs = [@@client1, @@client2, @@client3, @@room1, @@user1, @@user2, @@user3]
    save_all
  end

  def after_tests
    @@objs.each {|r| r.destroy} if @@objs
    super
  end

  def save_all
    @@objs.each {|r| r.save!}
  end

  def test_pswd_restriction
    check_pswd = proc{ |pswd_r, ok_user|
      [@@user1, @@user2, @@user3].each do |user|
        cond = pswd_r.check_condition(user)
        if user == ok_user
          assert !cond, "expected pswd rule check to pass"
        else
          assert cond, "expected pswd rule check to fail"
        end
      end
    }
    pol = P1.instantiate(@@client1)
    check_pswd[pol.restrictions(User.pswd)[0], @@user1]
    check_pswd[pol.restrictions(User.pswd)[1], nil]

    pol = P1.instantiate(@@client2)
    check_pswd[pol.restrictions(User.pswd)[0], @@user2]
    check_pswd[pol.restrictions(User.pswd)[1], nil]

    pol = P1.instantiate(@@client3)
    check_pswd[pol.restrictions(User.pswd)[0], nil]
    check_pswd[pol.restrictions(User.pswd)[1], nil]
  end

  def test_status_restriction
    pol = P1.instantiate(@@client1)
    status_r = pol.restrictions(User.status).first
    assert !status_r.check_condition(@@user1), "expected pswd rule check to pass"
    assert !status_r.check_condition(@@user2), "expected pswd rule check to fail"
    assert status_r.check_condition(@@user3), "expected pswd rule check to fail"

    pol = P1.instantiate(@@client2)
    status_r = pol.restrictions(User.status).first
    assert !status_r.check_condition(@@user1), "expected pswd rule check to pass"
    assert !status_r.check_condition(@@user2), "expected pswd rule check to fail"
    assert status_r.check_condition(@@user3), "expected pswd rule check to fail"
  end

  def test_filter_busy
    pol = P1.instantiate(@@client1)
    busy_r = pol.restrictions(Room.members).first
    assert !busy_r.check_filter(@@room1, @@user1)
    assert busy_r.check_filter(@@room1, @@user2)
  end

end
