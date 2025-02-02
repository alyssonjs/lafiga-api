class ChangeGroupIdToReferenceGroupInSchedule < ActiveRecord::Migration[6.0]
  def change
    remove_column :schedules, :group_id, :integer 
    add_reference :schedules, :group, foreign_key: true
  end
end
