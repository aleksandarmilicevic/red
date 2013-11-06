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

    class ColInfo
      attr_reader :kind, :col_name, :fld_name, :type, :opts
      def initialize(hash={})
        hash.each do |k, v|
          self.class.send :attr_reader, k
          instance_variable_set "@#{k}".to_sym, v
        end
      end
    end

    #----------------------------------------
    # Class +MigrationGenerator+
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
          @name += "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}" if append_timestamp
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
          @from_scratch = !!hash[:from_scratch]
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
          end
          if @migrations.empty?
            puts "Your DB schema is up to date, no migrations created.\n"
          else
            puts "\nRun `rake db:migrate' to apply generated migrations.\n"
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
          if anc=r.oldest_ancestor
            log "Skipping class #{r}, will use #{anc} instead."
          elsif @from_scratch || !_table_exists?(r.red_table_name)
            gen_create_table r
          else
            gen_update_table r
          end
        end

        # Checks if the existing table needs to be updated for the
        # given record +r+.
        #
        # @param r [Record]
        def gen_update_table(r)
          # suppress_messages do
          #   #TODO: implement
          # end
          table_name = r.red_table_name.to_sym
          cols = get_columns_for_record(r)

          # remove all columns that don't exist anymore
          obsolete_cols = _columns(table_name).reject {|c|
            ["id", "created_at", "updated_at"].member? c.name.to_s
          }.select {|c|
            cols.none? { |col_info| col_info.col_name.to_s == c.name.to_s }
          }

          # add new columns that don't already exist
          updated_cols = []
          new_cols = []
          cols.each do |col|
            if col.kind == :join
              gen_create_join_table(col.fld, col.fld_info)
            else
              # if it doesn't already exist, add it
              unless _column_exists?(table_name, col.col_name, col.type, col.opts)
                if _column_exists?(table_name, col.col_name)
                  updated_cols << col
                else
                  new_cols << col
                end
              end
            end
          end

          exe_update(table_name, obsolete_cols, updated_cols, new_cols)
        end

        # @param table_name [String]
        # @param obsolete_cols [Array(ActiveRecord::ConnectionAdapters::Column)]
        # @param updated_cols [Array(ColInfo)]
        # @param new_cols [Array(ColInfo)]
        def exe_update(table_name, obsolete_cols, updated_cols, new_cols)
          rec = new_change_recorder
          unless obsolete_cols.empty? && updated_cols.empty? && new_cols.empty?
            __print(rec, "    # ------------------------------:\n")
            __print(rec, "    # migration for table #{table_name} \n")
            __print(rec, "    # ------------------------------:\n")
          end

          unless obsolete_cols.empty?
            __print(rec, "\n    # obsolete columns:\n")
            obsolete_cols.each do |c|
              rec.remove_column table_name, c.name.to_sym
            end
          end

          unless updated_cols.empty?
            __print(rec, "\n    # updated columns:\n")
            updated_cols.each { |col|
              remove_col(rec, table_name, col)
              add_col(rec, table_name, col)
            }
          end

          unless new_cols.empty?
            __print(rec, "\n    # new columns:\n")
            new_cols.each { |col| add_col(rec, table_name, col) }
          end
        end

        def remove_col(rec, table_name, col)
          rec.remove_column table_name, col.col_name
        end

        def add_col(rec, table_name, col)
          if col.opts
            rec.add_column table_name, col.col_name, col.type, col.opts
          else
            rec.add_column table_name, col.col_name, col.type
          end
          if :ref === col.kind
            rec.add_index table_name, col.col_name
          end
        end

        # Generates a +create_table+ command for a given record +r+.
        #
        # @param r [Record]
        def gen_create_table(r)
          cols = get_columns_for_record(r)
          rec = new_change_recorder
          rec.create_table r.red_table_name.to_sym do |t|
            cols.each do |col|
              case col.kind
              when :attr
                t.column col.col_name, col.type
              when :ref
                if col.opts
                  t.references col.fld_name, col.opts
                else
                  t.references col.fld_name
                end
              when :join
                gen_create_join_table(col.fld, col.fld_info)
              else
                fail "Unexpected ColInfo kind: #{col.kind}"
              end
            end
            __print(t, "\n")
            t.timestamps
          end
        end

        # @param r [Record]
        def get_columns_for_record(r)
          sigs = [r.red_root] + r.red_root.all_subsigs
          fields = sigs.map {|rr| rr.meta.pfields}.flatten

          inv_fields = sigs.map { |rr|
            rr.meta.inv_fields
          }.flatten.find_all { |invf|
            fldinf = Red::Model::TableUtil.fld_table_info(invf.inv)
            fldinf.own_many?
          }

          cols = (fields + inv_fields).map { |f|
            cols_for_field(f)
          }.flatten

          unless r.meta.subsigs.empty?
            type_col = ColInfo.new :kind => :attr, :col_name => :type, :type => :string
            cols << type_col
          end

          cols
        end

        # Handles a given field of the given record
        #
        # @param fld [Field]
        # @result [Array(ColInfo), ColInfo]
        def cols_for_field(fld)
          return [] if fld.has_impl?
          begin
            fld_info = Red::Model::TableUtil.fld_table_info(fld)
            if fld_info.attr?
              ColInfo.new :kind => :attr,
                          :col_name => fld_info.field,
                          :fld_name => fld_info.field,
                          :type => fld_info.col_type
            elsif fld_info.to_one?
              c1 = ColInfo.new :kind => :ref,
                               :col_name => fld_info.column,
                               :fld_name => fld_info.field,
                               :type => :integer
              if fld_info.polymorphic?
                c2 = ColInfo.new :kind => :attr,
                                 :col_name => "#{fld_info.field}_type".to_sym,
                                 :type => :string
                [c1, c2]
              else
                c1
              end
            elsif fld_info.own_many?
              # nothing to add here, foreign key goes in the other table
              []
            elsif fld_info.ref_many?
              ColInfo.new :kind => :join, :fld => fld, :fld_info => fld_info
            else
              fail "Internal error: fld_table_info returned inconsistent info: " +
                   "#{fld_info.inspect}"
            end
          rescue Exception => e
            raise FieldError.new(e), "Error handling field #{fld}."
          end
        end

        # Generates a join table for a given field
        #
        # @param record [Record]
        # @param fld [Field]
        # @param fld_info [FldInfo]
        def gen_create_join_table(fld, fld_info)
          return if _table_exists? fld_info.join_table.to_sym
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

        def new_change_recorder()
          _self_if_standalone ||
            begin
              unless @change_migration
                @change_migration = MigrationRecorder.new("UpdateTables", true)
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

        def __print(recorder, text)
          unless @exe
            recorder.__print(text)
          end
        end

        def _self_if_standalone
          if @exe
            self
          end
        end

        def _table_exists?(name)
          return false if @from_scratch
          suppress_messages do
            table_exists? name
          end
        end

        def _column_exists?(table, col, type=nil, opts=nil)
          return false if @from_scratch
          suppress_messages do
            args = [table, col, type, opts].compact
            column_exists?(*args)
          end
        end

        def _columns(table)
          suppress_messages do
            columns(table)
          end
        end
      end

      def create_migration(hash={})
        # TODO: how to get args from cmdline
        begin
          mig = Migration.new hash #.merge{:from_scratch => true}
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
