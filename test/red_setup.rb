require 'migration_helper'
require 'sdg_utils/db/db_helper'

module RedTestSetup
  include SDGUtils::DB::DBHelpers
  include MigrationHelper

  extend self

  def red_init
    Red.reset
    Red.initializer.resolve_fields
    Red.initializer.expand_fields
    Red.initializer.init_inv_fields
    Red.initializer.add_associations
    Red.initializer.eval_sig_bodies
  end

  def init_all
    db_setup
    red_init
    db_drop
    db_migrate
  end

end
