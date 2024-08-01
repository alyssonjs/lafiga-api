class CreateGroups < ActiveRecord::Migration[6.0]
  def change
    create_table :groups do |t|
      t.string :name
      t.integer :season, default: 0  # Usando 0 como valor padrão para o enum
      t.integer :day, null: false
      t.integer :year
      t.text :description

      t.timestamps
    end

    # Adiciona uma restrição para o campo `day` para garantir que o valor esteja entre 1 e 120
    change_column :groups, :day, :integer, null: false
  end
end
