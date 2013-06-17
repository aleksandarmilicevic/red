require 'my_test_helper'
require 'red/dsl/red_dsl'

include Red::Dsl

data_model "XX" do 
  record Person do
    js.click() {
      "hi"
    }
  end
end


class RedJsTest < Test::Unit::TestCase
  def test1
    assert_equal 1, XX::Person.red_meta.js_events.size
    assert XX::Person.instance_method :click
  end
      
end
