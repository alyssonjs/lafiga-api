class AddApiIndexToRacesAndSubRaces < ActiveRecord::Migration[6.0]
  def up
    add_column :races, :api_index, :string
    add_column :sub_races, :api_index, :string

    add_index :races, :api_index, unique: true
    add_index :sub_races, [:race_id, :api_index], unique: true

    # Backfill from names if blank
    say_with_time 'Backfilling api_index for races and sub_races' do
      Race.reset_column_information
      SubRace.reset_column_information

      Race.find_each do |r|
        r.update_columns(api_index: (r.api_index.presence || r.name.to_s.parameterize(separator: '_')))
      end
      SubRace.find_each do |sr|
        sr.update_columns(api_index: (sr.api_index.presence || sr.name.to_s.parameterize(separator: '_')))
      end
    end
  end

  def down
    remove_index :sub_races, column: [:race_id, :api_index] rescue nil
    remove_index :races, :api_index rescue nil
    remove_column :sub_races, :api_index
    remove_column :races, :api_index
  end
end

