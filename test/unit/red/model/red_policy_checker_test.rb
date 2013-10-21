require 'migration_test_helper'
require 'nilio'
require 'red/model/security_model'
require 'red/engine/policy_checker'

include Red::Dsl

module R_M_TPChecker
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

      # restrict access to status messages to users who share at least
      # one chat room with the owner of that status message
      restrict User.status.when do |user|
        $pera = 1
        client.user != user &&
        Room.none? { |room|
          room.members.include?(client.user) &&
          room.members.include?(user)
        }
      end

      # filter out busy users (those who set their status to "busy")
      restrict Room.members.reject do |room, member|
        member.status == "busy" && client.user != member
      end

      write User.*.when do |user|
        client.user == user
      end
    end
  end
end

class TestPolicyChecker < MigrationTest::TestBase
  include R_M_TPChecker

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
    Red.meta.restrict_to(R_M_TPChecker)
    Red.conf.policy.return_empty_for_read_violations = false
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

  def for_all_clients(*ok_clients, &block)
    for_clients_check(nil, [@@client1, @@client2, @@client3], ok_clients, &block)
  end

  def for_clients_check(check_proc, all_clients, ok_clients, &block)
    all_clients.map do |client|
      Red.boss.enable_policy_checking(client)
      val = begin
              is_ok = ok_clients.include?(client)
              if is_ok
                yield
              else
                assert_raise(Red::Model::AccessDeniedError) do
                  yield
                end
              end
            ensure
              Red.boss.disable_policy_checking
            end
      check_proc[is_ok, client, val] if check_proc
      val
    end
  end

  def check_results(*expected)
    actual = yield
    expected.each_with_index do |e, idx|
      a = actual[idx]
      case e
      when Class; assert e === a
      else;       assert_equal e, a, "arrays differ at position #{idx}"
      end
    end
  end

  def ade() Red::Model::AccessDeniedError end

  def test_pswd_restriction
    check_results("ek123", ade, ade) do for_all_clients(@@client1) { @@user1.pswd } end
    check_results(ade, "jn123", ade) do for_all_clients(@@client2) { @@user2.pswd } end
    check_results(ade, ade, ade)     do for_all_clients([])        { @@user3.pswd } end
  end

  def test_status_restriction
    check_results("working", "working", ade){
      for_all_clients(@@client1, @@client2) { @@user1.status } }
    check_results("busy", "busy", ade)      {
      for_all_clients(@@client1, @@client2) { @@user2.status } }
    check_results(ade, ade, ade)            {
      for_all_clients()                     { @@user3.status } }
  end

  def test_write_status
    sp = proc{ |u|    proc{ u.status = "done" }}
    cp = proc{ |u, v| proc{ |is_ok| assert_equal (is_ok ? "done" : v), u.status }}
    for_clients_check(cp[@@user1, "working"],  [@@client2, @@client3, @@client1],
                                               [@@client1], &sp[@@user1])
    for_clients_check(cp[@@user2, "busy"],     [@@client1, @@client3, @@client2],
                                               [@@client2], &sp[@@user2])
    for_clients_check(cp[@@user3, "slacking"], [@@client1, @@client2, @@client3],
                                               [], &sp[@@user3])
  end

  def test_filter_busy
    res = for_all_clients(@@client1, @@client2, @@client3) { @@room1.members }
    assert_arry_equal([@@user1], res[0])
    assert_arry_equal([@@user1, @@user2], res[1])
    assert_arry_equal([@@user1], res[2])
  end
end
