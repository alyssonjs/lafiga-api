class AddExperiencePointsToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :experience_points, :integer, default: 0, null: false
    add_index  :sheets, :experience_points
  end
end
