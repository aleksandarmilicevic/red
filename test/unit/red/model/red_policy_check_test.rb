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

      # filter out anonymous users (those who have not sent anything)
      restrict Room.members.reject do |room, member|
        !room.messages.sender.include?(member) &&
        client.user != member
      end
    end
  end
end

class TestPolicyCheck < MigrationTest::TestBase
  include R_M_TPC

  attr_reader :client1, :client2, :room1, :user1, :user2, :user3

  def setup_pre
    Red.meta.restrict_to(R_M_TPC)
    # Red.boss.start
  end

  def setup_test
    @room1 = Room.new
    @user1 = User.new :name => "eskang", :pswd => "ek123", :status => "working"
    @user2 = User.new :name => "jnear", :pswd => "jn123", :status => "working"
    @user3 = User.new :name => "singh", :pswd => "rs123", :status => "slacking"
    @room1.members = [@user1, @user2, @user3]
    @client1 = Client.new :user => @user1
    @client2 = Client.new :user => @user2
    @objs = [@client1, @client2, @room1, @user1, @user2, @user3]
    save_all
  end

  def teardown
    @objs.each {|r| r.destroy} if @objs
  end

  def save_all
    @objs.each {|r| r.save!}
  end

  def test_restriction1
    pol = P1.instantiate(@client1)
    r = pol.restrictions(User.pswd)[0]
    assert !r.check_condition(@user1), "expected restriction check to fail"
  end
end
