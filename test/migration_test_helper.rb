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
      setup_class_pre_red_init
      RedTestSetup.init_all
      setup_class_post_red_init
    end

    def setup_class_pre_red_init() end
    def setup_class_post_red_init() end

    #TODO: rename all invocations of these methods to invoke the above ones
    alias_method :setup_pre, :setup_class_pre_red_init
    alias_method :setup_post, :setup_class_post_red_init

    def after_tests
      teardown_pre
      Red.meta.clear_restriction
      teardown_post
    end

    def teardown_pre; end
    def teardown_post; end
  end

end
