class CreateDiaryEntries < ActiveRecord::Migration[6.0]
  def change
    create_table :diary_entries do |t|
      t.references :character, null: false, foreign_key: true, index: true
      t.references :schedule, null: true, foreign_key: true, index: true
      t.string  :title, null: false, default: ''
      t.text    :content, null: false, default: ''
      t.string  :font_family, null: false, default: 'Caveat'
      t.integer :font_size, null: false, default: 16
      t.string  :text_color, null: false, default: '#3e2723'
      t.string  :page_color, null: false, default: '#f5e6d3'

      t.timestamps
    end

    add_index :diary_entries, [:character_id, :updated_at]
  end
end
