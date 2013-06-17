require_relative 'red_dsl_test_helper.rb'
require 'unit/alloy/dsl/alloy_dsl_sig_test_tmpl.rb'

tmpl = get_test_template('RedDslMachineTest', 'Red::Dsl::machine_model', 'Red::Dsl::MMachine.machine', 'Red::Model::Machine')
eval tmpl
