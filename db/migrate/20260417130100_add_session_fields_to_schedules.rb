class AddSessionFieldsToSchedules < ActiveRecord::Migration[6.0]
  # `scheduled_time`: horário do encontro IRL (ex.: "19:30"). Mantemos como
  # string para evitar fuso horário — o cliente envia o que mostra no relógio.
  # `campaign_name`: nome opcional da missão/arco principal. Não vira tabela
  # própria por hoje — é apenas etiqueta livre, conforme acordado.
  def change
    add_column :schedules, :scheduled_time, :string, default: nil
    add_column :schedules, :campaign_name, :string, default: nil
    add_index  :schedules, :campaign_name
  end
end
