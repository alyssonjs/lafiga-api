class AddCoinsToSheets < ActiveRecord::Migration[6.0]
  COIN_DEFAULT = { 'cp' => 0, 'sp' => 0, 'ep' => 0, 'gp' => 0, 'pp' => 0 }.freeze

  def up
    add_column :sheets, :coins, :jsonb, null: false, default: COIN_DEFAULT

    Sheet.reset_column_information
    # Garante presença de todas as denominações em fichas existentes
    Sheet.where(coins: nil).update_all(coins: COIN_DEFAULT)
    Sheet.where(coins: {}).update_all(coins: COIN_DEFAULT)
  end

  def down
    remove_column :sheets, :coins
  end
end
