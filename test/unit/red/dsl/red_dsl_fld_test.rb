require 'my_test_helper'
require 'alloy/helpers/test/dsl_helpers'
require 'red/dsl/red_dsl'
require 'red_setup'
require 'sdg_utils/testing/smart_setup'

include Red::Dsl

module R_D_RDFT
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
end

class RedDslFldTest < Test::Unit::TestCase
  include Alloy::Helpers::Test::DslHelpers
  include SDGUtils::Testing::SmartSetup
  include R_D_RDFT

  def setup_class
    Red.meta.restrict_to(R_D_RDFT)
    RedTestSetup.red_init
  end

  def test_sigs_defined
    sig_test_helper('R_D_RDFT::X::Person', Red::Model::Record)
    sig_test_helper('R_D_RDFT::Y::House', Red::Model::Record)
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
