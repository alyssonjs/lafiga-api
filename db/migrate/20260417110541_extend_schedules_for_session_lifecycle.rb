class ExtendSchedulesForSessionLifecycle < ActiveRecord::Migration[6.0]
  # Adiciona campos para registrar o ciclo de vida de uma sessão de RPG:
  #   summary   -> resumo escrito após a sessão (visível no diário do Hub)
  #   description -> briefing/objetivo definido na agenda
  #   xp_awarded -> XP distribuído a TODOS os personagens ao concluir
  #   started_at / ended_at -> marcam quando a sessão começou e terminou
  #
  # Mantemos os valores existentes do enum status (`reserved=0`, `waiting=1`)
  # e estendemos com `in_progress=2`, `completed=3`, `cancelled=4`. Isso evita
  # quebrar seeds e código que usa `status: :waiting` na criação.
  def change
    change_table :schedules, bulk: true do |t|
      t.text     :description
      t.text     :summary
      t.integer  :xp_awarded, default: 0, null: false
      t.datetime :started_at
      t.datetime :ended_at
    end

    add_index :schedules, :status
  end
end
