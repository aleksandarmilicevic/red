require 'red/model/red_table_util'

class Class

  def red_model_name
    Red::Model::TableUtil.red_model_name(self)
  end

  def red_table_name
    Red::Model::TableUtil.red_table_name(self)
  end

  def red_ref_name
    Red::Model::TableUtil.red_ref_name(self)
  end

  def red_key_col_name
    Red::Model::TableUtil.red_key_col_name(self)
  end

  def red_root
    self
  end

  def red_subclasses
    []
  end
end

# ====================================================================

module Alloy
  module Ast
    class Field
      def red_foreign_key_name
        Red::Model::TableUtil.red_foreign_key_name(self)
      end
    end
  end
end
