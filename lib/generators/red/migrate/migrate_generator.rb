require 'red/red'
require 'rails/generators'
require 'red/model/red_table_util'
require 'sdg_utils/recorder'
require 'sdg_utils/errors'
require 'fileutils'
require 'date'

module Red
  module Generators

    class FieldError < SDGUtils::Errors::ErrorWithCause
    end

    #----------------------------------------
    # Class +MigrationRecorder+
    #----------------------------------------
    class MigrateGenerator < Rails::Generators::Base

      #----------------------------------------
      # Class +MigrationRecorder+
      #
      # @attr name [String]
      # @attr recorders [{Symbol => Array[Recorder]]
      #----------------------------------------
      class MigrationRecorder
        def initialize(name, append_timestamp=false)
          @name = name
          @name += "_#{Time.now.utc.strftime("%Y%m%d%H%M%S")}" if append_timestamp
          @recorders = {}
        end

        def name
          @name
        end

        def change; new_rec :change end
        def up;     new_rec :up end
        def down;   new_rec :down end

        def to_s
          buff = "class #{@name} < ActiveRecord::Migration\n"
          buff << @recorders.map {|sym, rec|
            "  def #{sym}\n#{rec.map{|e| e.to_s}.join("\n")}  end\n"
          }.join("\n")
          buff << "end\n"
          buff
        end

        private

        def new_rec sym
          rec = SDGUtils::Recorder.new :indent    => "    ",
                                       :block_var => "t"
          (@recorders[sym] ||= []) << rec
          rec
        end
      end

      #----------------------------------------
      # Class +Migration+
      #----------------------------------------
      class Migration < ActiveRecord::Migration

        def initialize(hash={})
          @migrations = []
          @change_migration = nil
          @up_down_migration = nil
          @exe = !!hash[:exe]
          @logger = hash[:logger]
        end

        def start
          Red.meta.base_records.each do |r|
            check_record r
          end
        end

        def finish
          if @logger
            print_to_log
          else
            print_to_file
          end
        end

        def print_to_log
          @migrations.each do |m|
            @logger.debug "Migration file:\n#{m.to_s}"
          end
        end

        def print_to_file
          @migrations.each do |m|
            num = next_migration_number(0)
            name = Rails.root.join("db", "migrate", "#{num}_#{m.name.underscore}.rb")
            FileUtils.mkdir_p File.dirname(name)
            mig_file = File.open(name, "w+") do |f|
              f.write m.to_s
            end
            puts " ** Migration created: #{name}"
            if @migrations.empty?
              puts "Your DB schema is up to date, no migrations created.\n"
            else
              puts "\nRun `rake db:migrate' to apply generated migrations.\n"
            end
          end
        end

        private

        def log(msg)
          if @logger
            @logger.debug msg
          end
        end

        # Checks if the schema needs to be updated for the given
        # record +r+.
        #
        # @param r [Record]
        def check_record(r)
          if _my_table_exists? r.red_table_name
            check_update r
          else
            gen_create_table r
          end
        end

        # Checks if the existing table needs to be updated for the
        # given record +r+.
        #
        # @param r [Record]
        def check_update(r)
          suppress_messages do
            #TODO: implement
          end
        end

        # Generates a +create_table+ command for a given record +r+.
        #
        # @param r [Record]
        def gen_create_table(r)
          if anc=r.oldest_ancestor
            log "Skipping class #{r}, will use #{anc} instead."
          else
            rec = new_change_recorder
            rec.create_table r.red_table_name.to_sym do |t|
              sigs = [r.red_root] + r.red_root.all_subsigs
              fields = sigs.map {|rr| rr.meta.fields}.flatten
              fields.each do |f|
                handle_field(t, f)
              end
              inv_fields = sigs.map {|rr| rr.meta.inv_fields}.flatten
              inv_fields.find_all do |invf|
                fldinf = Red::Model::TableUtil.fld_table_info(invf.inv)
                fldinf.own_many?
              end.each do |invf|
                handle_field(t, invf)
              end

              unless r.meta.subsigs.empty?
                t.column :type, :string
              end
              t.__newline unless @exe
              t.timestamps
            end
          end
        end

        # Generates a join table for a given field
        #
        # @param record [Record]
        # @param fld [FieldMeta]
        # @param fld_info [FldInfo]
        def gen_create_join_table(fld, fld_info)
          rec = new_change_recorder
          opts = if fld.type.range.cls.primitive?
                   {}
                 else
                   {:id => false}
                 end
          #TODO: work only for binary fields
          fail "Only binary fields supported" if fld.type.arity > 1
          rec.create_table fld_info.join_table.to_sym, opts do |t|
            t.column fld_info.join_domain_column, :int
            t.column fld_info.join_range_column, :int
            if fld.type.seq?
              t.column Red::Model::TableUtil.red_seq_pos_column_name.to_sym, :int
            end
          end
        end

        # Handles a given field of the given record
        #
        # @param tbl
        # @param fld_name [Symbol]
        # @param r [Record]
        def handle_field(tbl, fld)
          return if fld.has_impl?
          begin
            fld_info = Red::Model::TableUtil.fld_table_info(fld)
            if fld_info.attr?
              tbl.column fld_info.field, fld_info.col_type
            elsif fld_info.to_one?
              opts = if fld_info.polymorphic?
                       {:polymorphic => true} #{:default => fld_info.range_class}
                     else
                       {}
                     end
              tbl.references fld_info.field, opts
            elsif fld_info.own_many?
              # nothing to add here, foreign key goes in the other table
            elsif fld_info.ref_many?
              gen_create_join_table(fld, fld_info)
            else
              fail "Internal error: fld_table_info returned inconsistent info: " +
                   "#{fld_info.inspect}"
            end
          rescue Exception => e
            raise FieldError.new(e), "Error handling field #{fld}."
          end
        end

        def new_change_recorder
          _self_if_standalone ||
            begin
              unless @change_migration
                @change_migration = MigrationRecorder.new("CreateMissingTables")
                @migrations << @change_migration
              end
              @change_migration.change
            end
        end

        def new_migration_recorder(*args)
          _self_if_standalone ||
            begin
              mgr = MigrationRecorder.new(*args)
              @migrations << mgr
              mgr
            end
        end

        def _self_if_standalone
          if @exe
            self
          end
        end

        def _my_table_exists?(name)
          suppress_messages do
            table_exists? name
          end
        end

      end

      def create_migration(hash={})
        begin
          mig = Migration.new(hash)
          mig.start
          mig.finish
        rescue Exception => e
          puts "ERROR"
          puts e.to_s
          puts ""
          puts "BACKTRACE:"
          puts e.backtrace
        end
      end
    end

  end
end
