require_relative 'red_dsl_test_helper.rb'
require 'red/red'

module XTestPolicyModel
  data_model do
    record User, {
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

      @desc = "hide password"
      def check_restrict_user_pswd(user, pswd)
        client.user != user
      end
      restrict User.pswd, :when => :check_restrict_user_pswd

      @desc = "hide password 2"
      restrict User.pswd.unless do |user, pswd|
        client.user == user
      end

      @desc = "status to comrades"
      restrict User.status.when do |user, status|
        client.user != user &&
        Room.none? { |room|
          room.members.include?(client.user) &&
          room.members.include?(user)
        }
      end

      @desc = "filter members"
      restrict Room.members.reject do |room, member|
        !room.messages.sender.include?(member) &&
        client.user != member
      end
    end
  end
end

class TestPolicyModel < Test::Unit::TestCase
  include RedDslTestUtils
  include SDGUtils::Testing::Assertions
  include SDGUtils::Testing::SmartSetup

  def setup_class
    Red.meta.restrict_to(XTestPolicyModel)
    Red.initializer.init_all_but_rails_no_freeze
  end

  def test_policy_created
    assert((p = XTestPolicyModel::P1 rescue false), "policy class not created")
    assert_equal 1, Red.meta.policies.size
    pol = Red.meta.policies[0]
    assert_equal "XTestPolicyModel::P1", pol.name
    assert_equal pol, Red.meta.policy("XTestPolicyModel::P1")
    assert_equal pol, XTestPolicyModel::P1
  end

  def test_policy_props
    pol = XTestPolicyModel::P1
    assert_equal XTestPolicyModel::Client, pol.principal.type.range.klass
    assert_equal 4, pol.restrictions.size
    assert_equal 2, pol.restrictions(XTestPolicyModel::User.pswd).size
    assert_equal 1, pol.restrictions(XTestPolicyModel::User.status).size
    assert_equal 1, pol.restrictions(XTestPolicyModel::Room.members).size
  end

  def test_rule_props
    pol = XTestPolicyModel::P1
    begin
      r, _ = pol.restrictions(XTestPolicyModel::User.pswd)
      assert_equal pol, r.policy
      assert r.has_condition?
      assert !r.has_filter?
      assert_equal :when, r.condition
      assert_equal :check_restrict_user_pswd, r.method
      assert_equal "hide password", r.desc
    end
    begin
      _, r = pol.restrictions(XTestPolicyModel::User.pswd)
      assert_equal pol, r.policy
      assert r.has_condition?
      assert !r.has_filter?
      assert_equal :unless, r.condition
      assert_starts_with "restrict_XTestPolicyModel__User_pswd_unless",r.method
      assert_equal "hide password 2", r.desc
    end
    begin
      r = pol.restrictions(XTestPolicyModel::User.status).first
      assert_equal pol, r.policy
      assert r.has_condition?
      assert !r.has_filter?
      assert_equal :when, r.condition
      assert_starts_with "restrict_XTestPolicyModel__User_status_when",r.method
      assert_equal "status to comrades", r.desc
    end
    begin
      r = pol.restrictions(XTestPolicyModel::Room.members).first
      assert_equal pol, r.policy
      assert !r.has_condition?
      assert r.has_filter?
      assert_equal :reject, r.filter
      assert_starts_with "restrict_XTestPolicyModel__Room_members_reject",r.method
      assert_equal "filter members", r.desc
    end
  end

  def do_test_invalid_policy_opts(*args, &block)
    assert_raise(ArgumentError) do
      Alloy.conf.do_with :defer_body_eval => false do
        security_model do
          policy :P do
            principal c: XTestPolicyModel::Client
            restrict *args, &block
          end
        end
      end
    end
  end

  def test_restrict_invalid_no_opts
    ex = do_test_invalid_policy_opts
    assert ex.message.start_with?("expected hash or a field and a hash"), ex.message
  end

  def test_restrict_invalid_not_hash
    ex = do_test_invalid_policy_opts XTestPolicyModel::User
    assert ex.message.start_with?("expected hash or a field and a hash"), ex.message
  end

  def test_restrict_invalid_not_field
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User
    assert ex.message.start_with?("expected `Field' got"), ex.message
  end

  def test_restrict_invalid_no_field
    ex = do_test_invalid_policy_opts :dffield => XTestPolicyModel::User.pswd
    assert_equal "field not specified", ex.message
  end

  def test_restrict_invalid_mult_cond
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd,
                                     :when => "", :unless => ""
    assert ex.message.start_with?("more than one condition specified"), ex.message
  end

  def test_restrict_invalid_mult_filter
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd,
                                     :select => "", :reject => ""
    assert ex.message.start_with?("more than one filter specified"), ex.message
  end

  def test_restrict_invalid_double_cond
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd,
                                     :when => "", :condition => {}
    assert ex.message.start_with?("both :condition and :when keys given"), ex.message
  end

  def test_restrict_invalid_double_filter
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd,
                                     :select => "", :filter => {}
    assert ex.message.start_with?("both :filter and :select keys given"), ex.message
  end

  def test_restrict_invalid_both_cond_filter
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd,
                                     :select => "", :when => "" do end
    assert_equal "can't add block, rule has method", ex.message
  end

  def test_restrict_invalid_no_cond_filter
    ex = do_test_invalid_policy_opts :field => XTestPolicyModel::User.pswd
    assert_equal "no condition specified", ex.message
  end

end
