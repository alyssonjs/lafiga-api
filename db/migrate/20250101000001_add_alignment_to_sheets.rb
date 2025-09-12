class AddAlignmentToSheets < ActiveRecord::Migration[6.0]
  def change
    add_reference :sheets, :alignment, null: true, foreign_key: true
    add_index :sheets, :alignment_id
  end
end


