require 'unit/alloy/alloy_test_helper.rb'
require 'red/dsl/red_dsl'
require 'red_setup'

include Red::Dsl

data_model "X" do
  record Person, {
    name: String,
    manager: Person,
    home: "Y::House"
  }
end

data_model "Y" do
  record House do
    persistent {{
      peoples: (set X::Person)
    }}

    transient {{
      selected: Bool
    }}
  end
end

RedTestSetup.red_init

class RedDslFldTest < Test::Unit::TestCase
  include AlloyTestUtils

  def test_sigs_defined
    sig_test_helper('X::Person', Red::Model::Record)
    sig_test_helper('Y::House', Red::Model::Record)
  end

  def test_fld_accessors_defined
    %w(manager home).each { |f| assert_accessors_defined(X::Person, f) }
    %w(peoples selected).each { |f| assert_accessors_defined(Y::House, f) }
  end

  # def test_inv_fld_accessors_defined
    # inv_fld_acc_helper(Users::SBase, %w(f0 g1 f4 f5))
    # inv_fld_acc_helper(Users::SigA, %w(f1 f2 f3 f6 g3))
    # inv_fld_acc_helper(Users::SigB, %w(x))
  # end

end
