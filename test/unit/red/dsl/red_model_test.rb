require_relative 'red_dsl_test_helper.rb'
require 'sdg_utils/testing/smart_setup'
require 'sdg_utils/testing/assertions'

module X
  data_model "DY" do
    record D
  end
  machine_model "EY"
end

class TestRedDataModel < Test::Unit::TestCase
  include SDGUtils::Testing::SmartSetup
  include RedDslTestUtils
  include SDGUtils::Testing::Assertions

  def setup_class
    Red.meta.restrict_to(X)
  end

  def test1() create_data_model "MyDModel1" end
  def test2() create_data_model :MyDModel2 end
  def test3() create_data_model "MyEModel1" end
  def test4() create_data_model :MyEModel2 end

  def test_create_in_a_module
    assert_module_helper X::DY, "X::DY"
    assert_module_helper X::EY, "X::EY"
  end

  def test_invalid_name
    assert_raise(NameError) do
      create_data_model "My Model"
    end
    assert_raise(NameError) do
      create_machine_model "My Model"
    end
  end

  def test_already_defined
    blder = data_model("MyModel1")
    assert_seq_equal [MyModel1], blder.return_result(:array)
    blder = machine_model("MyModel1")
    assert_seq_equal [MyModel1], blder.return_result(:array)
  end

end
