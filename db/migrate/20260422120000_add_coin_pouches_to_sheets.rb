# Algibeiras (multiplas carteiras) por ficha + agregado em `coins` para compat.
class AddCoinPouchesToSheets < ActiveRecord::Migration[6.0]
  COIN_KEYS = %w[cp sp ep gp pp].freeze

  def up
    add_column :sheets, :coin_pouches, :jsonb, null: true

    Sheet.reset_column_information
    say_with_time 'backfill coin_pouches from sheets.coins' do
      Sheet.find_each(batch_size: 200) do |sheet|
        next if sheet.read_attribute(:coin_pouches).present?

        c = sheet.read_attribute(:coins) || {}
        wallet = {}
        COIN_KEYS.each do |k|
          wallet[k] = [[c[k] || c[k.to_sym], 0].compact.first.to_i, 0].max
        end
        pouches = [
          {
            'id' => 'primary',
            'name' => 'Carteira',
            'cp' => wallet['cp'],
            'sp' => wallet['sp'],
            'ep' => wallet['ep'],
            'gp' => wallet['gp'],
            'pp' => wallet['pp']
          }
        ]
        sheet.update_columns(coin_pouches: pouches)
      end
    end

    change_column_default :sheets, :coin_pouches, []
    change_column_null :sheets, :coin_pouches, false
  end

  def down
    remove_column :sheets, :coin_pouches
  end
end
