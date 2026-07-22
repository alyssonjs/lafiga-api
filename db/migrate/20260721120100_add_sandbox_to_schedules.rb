class AddSandboxToSchedules < ActiveRecord::Migration[6.0]
  # `sandbox` marca sessões-fantasma de teste do DM: só o criador as vê, ficam
  # fora das listagens de player e NÃO ocupam o "slot único" (grupo/data ou
  # criador/data) das sessões reais — assim o DM pode abrir várias para testar
  # combate sem colidir com a agenda real.
  def change
    add_column :schedules, :sandbox, :boolean, null: false, default: false unless column_exists?(:schedules, :sandbox)
    unless index_exists?(:schedules, :sandbox, name: 'index_schedules_on_sandbox_true')
      add_index :schedules, :sandbox, where: '(sandbox = true)', name: 'index_schedules_on_sandbox_true'
    end
    # NOTA: a reconciliação dos índices de "slot único" (excluir sandbox) foi
    # movida para 20260723120000_reconcile_schedule_open_slot_indexes. A versão
    # anterior desta migração fazia `remove_index 'idx_schedules_active_per_*'`,
    # que CRASHAVA em bancos (prod/main) onde esses índices foram renomeados para
    # `idx_schedules_open_per_*`. A reconciliação é defensiva (DROP IF EXISTS).
  end
end
