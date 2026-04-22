class AddHighlightsToSchedules < ActiveRecord::Migration[6.0]
  # Highlights da sessão (eventos marcantes que alimentam a Timeline do Hub).
  # Estrutura esperada por elemento:
  #   { "text": "Texto do feito", "type": "combat|narrative|discovery|social" }
  #
  # Mantemos como JSONB para evolução simples (autoria, timestamps por highlight,
  # personagem associado etc.) sem migrar uma tabela dedicada agora.
  def change
    add_column :schedules, :highlights, :jsonb, default: [], null: false
    add_index  :schedules, :highlights, using: :gin
  end
end
