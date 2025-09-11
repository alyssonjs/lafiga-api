class AddAbilitiesAndHpToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :str, :integer
    add_column :sheets, :dex, :integer
    add_column :sheets, :con, :integer
    add_column :sheets, :int, :integer
    add_column :sheets, :wis, :integer
    add_column :sheets, :cha, :integer

    add_column :sheets, :hp_max, :integer, default: 0, null: false
    add_column :sheets, :hp_current, :integer, default: 0, null: false
    add_column :sheets, :temp_hp, :integer, default: 0, null: false
  end
end

