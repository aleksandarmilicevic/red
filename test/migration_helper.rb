require 'generators/red/migrate/migrate_generator'

module MigrationHelper
  def db_migrate(conn=@conn)
    mg = Red::Generators::MigrateGenerator.new
    # print to log first
    mg.create_migration :logger => Red.conf.logger
    # actually execute
    mg.create_migration :exe => true
  end
end