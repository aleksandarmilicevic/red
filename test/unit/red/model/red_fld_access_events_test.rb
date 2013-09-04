require 'alloy/helpers/test/test_event_listener'
require 'migration_test_helper'

include Red::Dsl

module RFAE
  data_model do
    record SBase, {
      r: SBase,
    } do
      abstract

      def initialize(name)
        super()
        @name = name
      end

      def to_s
        @name.to_s
      end
    end

    record SigA < SBase, {
      i: Integer,
      s: String,
      f: Float,
      b: Bool
    } do
      def initialize(name)
        super
      end
    end
  end
end

class RedFldAccessEventsTest < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(RFAE)
  end

  def setup_class_post_red_init
    if @listener; Red.boss.unregister_listener(@listener) end
    @listener = Alloy::Helpers::Test::TestEventListener.new
    Red.boss.register_listener(:field_read, @listener)
    Red.boss.register_listener(:field_written, @listener)
  end

  def test1
    a = RFAE::SigA.new('x')
    a.i = 4
    x = a.b
    a.b = false
    x = a.b
    RFAE::SigA.new('y').b
    assert_arry_equal ["x.b -> nil", "x.b -> false", "y.b -> nil"], @listener.format_reads
    assert_arry_equal ["x.i <- 4", "x.b <- false"], @listener.format_writes
  end

end
