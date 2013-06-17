require_relative 'red_dsl_test_helper.rb'
require 'unit/alloy/dsl/alloy_dsl_sig_test_tmpl.rb'

tmpl = get_test_template('RedDslRecordTest', 'Red::Dsl::data_model', 'Red::Dsl::MData.record', 'Red::Model::Data')
eval tmpl