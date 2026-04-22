module Combat
  # Inicia (ou reinicia) o combate de uma sessão. Encapsula:
  #   1. find_or_create do CombatState 1:1 do Schedule
  #   2. CombatState#begin! (idempotente)
  #   3. Sincronização HP Sheet → Combatant para todos os PCs presentes
  #
  # G27 — Sincronização HP Sheet → Combatant
  # ----------------------------------------
  # Quando o combate começa, copiamos `sheet.hp_current/hp_max/temp_hp` para
  # cada `combat_combatant` do tipo Character. Isso garante que a UI do
  # tracker já mostra HP fresco, e libera o combatant para flutuar HP de
  # combate sem mexer na Sheet (que continua representando "fora de combate").
  #
  # Decisões:
  #   - Apenas Combatants criados ANTES do begin! são sincronizados aqui.
  #     Combatants adicionados mid-combate sincronizam HP no momento da criação
  #     (CombatCombatantsController#create vai copiar do Sheet).
  #   - Se a Sheet não existir, mantém os valores atuais do combatant (sem
  #     sobrescrever pra zero).
  class StartService
    prepend SimpleCommand

    def initialize(schedule:, current_user: nil)
      @schedule = schedule
      @current_user = current_user
    end

    def call
      return errors.add(:schedule, 'inexistente') && nil if @schedule.nil?

      cs = ActiveRecord::Base.transaction do
        cs_inner = CombatState.find_or_create_by!(schedule: @schedule)
        cs_inner.begin!

        # Suprime eventos por-combatant durante o sync HP — vamos disparar
        # um único state_changed agregado no fim.
        Combat::Broadcaster.silently { sync_pc_hp_into_combatants(cs_inner) }

        cs_inner
      end

      Combat::Broadcaster.state_changed(cs.reload)
      cs
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { |m| errors.add(:base, m) }
      nil
    end

    private

    def sync_pc_hp_into_combatants(cs)
      cs.combat_combatants.where(combatable_type: 'Character').includes(combatable: :sheet).each do |combatant|
        sheet = combatant.combatable&.sheet
        next unless sheet

        combatant.update!(
          hp_current: sheet.hp_current.to_i,
          hp_max:     sheet.hp_max.to_i,
          temp_hp:    sheet.temp_hp.to_i,
        )
      end
    end
  end
end
