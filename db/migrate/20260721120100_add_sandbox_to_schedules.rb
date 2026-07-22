class AddSandboxToSchedules < ActiveRecord::Migration[6.0]
  # `sandbox` marca sessões-fantasma de teste do DM: só o criador as vê, ficam
  # fora das listagens de player e NÃO ocupam o "slot único" (grupo/data ou
  # criador/data) das sessões reais — assim o DM pode abrir várias para testar
  # combate sem colidir com a agenda real.
  def change
    add_column :schedules, :sandbox, :boolean, null: false, default: false
    add_index :schedules, :sandbox, where: '(sandbox = true)', name: 'index_schedules_on_sandbox_true'

    # Recriar os índices parciais únicos excluindo sandbox do slot único.
    remove_index :schedules, name: 'idx_schedules_active_per_group_date'
    add_index :schedules, %i[group_id date_dimension_id],
              unique: true,
              where: '((group_id IS NOT NULL) AND (status <> 4) AND (sandbox = false))',
              name: 'idx_schedules_active_per_group_date'

    remove_index :schedules, name: 'idx_schedules_active_per_creator_date'
    add_index :schedules, %i[created_by_user_id date_dimension_id],
              unique: true,
              where: '((created_by_user_id IS NOT NULL) AND (status <> 4) AND (sandbox = false))',
              name: 'idx_schedules_active_per_creator_date'
  end
end
