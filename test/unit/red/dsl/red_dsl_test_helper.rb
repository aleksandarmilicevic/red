require 'my_test_helper.rb'

require 'red/red'
require 'red/dsl/red_dsl.rb'
require 'unit/alloy/alloy_test_helper.rb'

include Red::Dsl

module RedDslTestUtils
  include AlloyTestUtils

  def data_test_helper(data_cls_str)
    assert_nothing_raised do
      sig_cls = eval "#{sig_cls_str}"
      sig_cls.new
    end
    assert sig_cls < Red::DslEngine::Data
  end

  def create_data_model(name)
    mod = Red::Dsl::data_model(name)
    assert_module_helper(mod, name)
  end

  def create_machine_model(name)
    mod = Red::Dsl::machine_model(name)
    assert_module_helper(mod, name)
  end
end
