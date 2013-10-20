require 'migration_test_helper'
require 'nilio'
require 'red/model/security_model'
require 'red/engine/policy_checker'

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

      @desc = "restrict access to passwords except for owning user"
      restrict User.pswd.unless do |user|
        client.user == user
      end

      @desc = "never send passwords to clients"
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

      write User.status.when do |user|
        client.user == user
      end

      restrict User.status.when do |user|
        client.user != user
      end

      restrict write User.status.unless do |user|
        client.user == user
      end

      write User.*.when do |user|
        client.user == user
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
    Red::Engine::PolicyCache.clear_meta()
    Red::Engine::PolicyCache.clear_apps()
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

  def do_check_rule(rule, arg_cases, outcome_cases)
    arg_cases.each_with_index do |args, idx|
      outcome = rule.check_condition(*args)
      if outcome_cases[idx]
        assert outcome, "expected status rule check to fail"
      else
        assert !outcome, "expected status rule check to pass"
      end
    end
  end

  def test_status_restriction
    pol = P1.instantiate(@@client1)
    status_r = pol.restrictions(User.status).first
    do_check_rule status_r, [@@user1, @@user2, @@user3], [false, false, true]

    pol = P1.instantiate(@@client2)
    status_r = pol.restrictions(User.status).first
    do_check_rule status_r, [@@user1, @@user2, @@user3], [false, false, true]
  end

  def do_test_status_restriction_idx(idx)
    pol = P1.instantiate(@@client1)
    status_r = pol.restrictions(User.status)[idx]
    do_check_rule status_r, [@@user1, @@user2, @@user3], [false, true, true]

    pol = P1.instantiate(@@client2)
    status_r = pol.restrictions(User.status)[idx]
    do_check_rule status_r, [@@user1, @@user2, @@user3], [true, false, true]
  end

  def test_status_restriction2() do_test_status_restriction_idx(1) end
  def test_status_restriction3() do_test_status_restriction_idx(2) end
  def test_status_restriction4() do_test_status_restriction_idx(3) end

  def test_filter_busy
    pol = P1.instantiate(@@client1)
    busy_r = pol.restrictions(Room.members).first
    assert !busy_r.check_filter(@@room1, @@user1)
    assert busy_r.check_filter(@@room1, @@user2)
  end

  def do_test_star_field_rule(fld, op)
    pol = P1.instantiate(@@client1)
    ur = pol.restrictions(fld).last
    assert_equal op, ur.rule.operation
    do_check_rule ur, [@@user1, @@user2, @@user3], [false, true, true]

    pol = P1.instantiate(@@client2)
    ur = pol.restrictions(fld).last
    assert_equal op, ur.rule.operation
    do_check_rule ur, [@@user1, @@user2, @@user3], [true, false, true]
  end

  def test_star_field_rule
    do_test_star_field_rule(User.f(:name), :write)
    do_test_star_field_rule(User.pswd, :write)
    do_test_star_field_rule(User.status, :write)
  end

end
