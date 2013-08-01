require 'my_test_helper'
require 'red/red'
require 'red/dsl/red_dsl'
require 'red/initializer'

module MigrationTest
  class TestBase < Test::Unit::TestCase
    include SDGUtils::Testing::SmartSetup
    include SDGUtils::Testing::Assertions
    include RedTestSetup

    def setup_class
      setup_pre
      RedTestSetup.init_all
      setup_post
    end

    def setup_pre; end
    def setup_post; end

    def teardown
      teardown_pre
      Red.meta.clear_restriction
      teardown_post
    end

    def teardown_pre; end
    def teardown_post; end
  end

end