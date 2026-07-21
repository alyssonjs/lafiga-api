class AddKindToBugReports < ActiveRecord::Migration[6.0]
  # `kind` distingue relato de bug (0, default) de solicitação de melhoria do DM
  # (1). Uma pipeline única para a IA triar ambos a partir da mesma tabela.
  def change
    add_column :bug_reports, :kind, :integer, null: false, default: 0
    add_index :bug_reports, :kind
  end
end
