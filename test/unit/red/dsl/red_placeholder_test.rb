require 'my_test_helper'
require 'red/model/red_model'

class PlaceholderTest < Test::Unit::TestCase

  def test1
    assert Red::Model::Record.placeholder?
    assert Red::Model::Record.abstract?
  end

  def test2
    assert Red::Model::Data.placeholder?
    assert Red::Model::Data.abstract?
  end

  def test3
    assert Red::Model::Machine.placeholder?
    assert Red::Model::Machine.abstract?
  end

  def test4
    assert Red::Model::Event.placeholder?
    assert Red::Model::Event.abstract?
  end
end
