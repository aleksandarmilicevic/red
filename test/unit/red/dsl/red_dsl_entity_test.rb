require_relative 'red_dsl_test_helper.rb'
require 'arby/helpers/test/dsl_helpers'
require 'arby/helpers/test/dsl_sig_test_tmpl'

tmpl = Arby::Helpers::Test::DslSigTestTmpl.get_test_template('RedDslMachineTest',
                                                              'Red::Dsl::machine_model',
                                                              'Red::Dsl::MMachine.machine',
                                                              'Red::Model::Machine')
eval tmpl
