require 'migration_test_helper'

include Red::Dsl

machine_model "D5" do
  machine Base, {
    bbb: Base,
    sss: String
  } do
    abstract
  end

  machine M < Base
end

class MigrationInheritanceAccessorsTest < MigrationTest::TestBase

  def setup_class_pre_red_init
    Red.meta.restrict_to(D5)
  end

  def test1
    m1 = D5::M.new
    m2 = D5::M.new
    assert m1.save!
    assert m2.save!
    m1.bbb = m2
    assert m1.save!
    m1.reload
    assert_equal m2, m1.bbb
    assert m1.destroy
    assert m2.destroy
  end

  def test2
    m1 = D5::M.new
    assert m1.save!
    m1.sss = "aaa"
    assert m1.save!
    m1.reload
    assert_equal "aaa", m1.sss
    assert m1.destroy
  end
end
