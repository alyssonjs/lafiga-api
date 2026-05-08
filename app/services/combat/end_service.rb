module Combat
  # Encerra o combate de uma sessão. Encapsula:
  #   1. CombatState#finish! (marca ended_at, active=false)
  #   2. Sincronização HP Combatant → Sheet (cura/dano persistem fora do combate)
  #   3. (Opcional) Marcar NPCs sobreviventes como `defeated_at` se quiser
  #      "limpar a sala" ao terminar — DESLIGADO por padrão. Sobreviventes
  #      podem voltar em combates futuros (ex.: ladrão que escapou).
  #
  # G27 — Sincronização HP Combatant → Sheet
  # ----------------------------------------
  # Cada PC vivo no tracker copia hp_current de volta para sua Sheet. Isso
  # transforma o combate em "fonte da verdade temporária": o que aconteceu no
  # combate (cura/dano/descanso curto) persiste na Sheet quando termina.
  #
  # PCs marcados is_dead=true (3 falhas em death save): copiam hp_current=0
  # para Sheet. O front trata o status "incapacitado" via Sheet (separado).
  #
  # PCs is_stabilized=true: copiam hp_current=0 (estabilizado a 0 HP) ou o
  # hp atual se tomaram cura mid-combate.
  class EndService
    prepend SimpleCommand

    def initialize(schedule:, current_user: nil)
      @schedule = schedule
      @current_user = current_user
    end

    def call
      return errors.add(:schedule, 'inexistente') && nil if @schedule.nil?

      cs = @schedule.combat_state
      return errors.add(:combat_state, 'sessão sem combate iniciado') && nil if cs.nil?

      finished = ActiveRecord::Base.transaction do
        Combat::Broadcaster.silently { sync_pc_hp_back_to_sheets(cs) }
        cs.finish!
        cs
      end

      Combat::Broadcaster.state_changed(finished.reload)
      finished
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { |m| errors.add(:base, m) }
      nil
    end

    private

    def sync_pc_hp_back_to_sheets(cs)
      cs.combat_combatants.where(combatable_type: 'Character').includes(combatable: :sheet).each do |combatant|
        sheet = combatant.combatable&.sheet
        next unless sheet

        sheet.update!(
          hp_current: combatant.hp_current.to_i,
          temp_hp:    combatant.temp_hp.to_i,
          # hp_max não é sincronizado de volta — combatant.hp_max é cache
          # (pode ter sido editado pelo DM mid-combate via spell/effect mas
          # "fora de combate" o hp_max canônico vem da Sheet/level).
        )

        # Fase 6C — round-trip de runtime state.
        # Conditions, concentration e death_saves ficavam órfãos em
        # CombatCombatant após o combate. Agora copiamos para
        # SheetRuntimeState (entidade canônica fora-de-combate).
        sync_runtime_state_back_to_sheet(sheet, combatant)
      end
    end

    # Copia o estado mutável (não-HP) do combatente para SheetRuntimeState.
    # Sem este sync, condições aplicadas em combate (envenenado/paralisado/
    # atordoado) e concentração ativa eram perdidas ao terminar.
    def sync_runtime_state_back_to_sheet(sheet, combatant)
      patch = {
        'conditions'    => Array(combatant.conditions),
        'concentration' => combatant.is_concentrating ? combatant.concentration_spell.to_s : nil,
        'death_saves'   => combatant.death_saves.is_a?(Hash) ?
                            combatant.death_saves : SheetRuntimeState::DEATH_SAVES_DEFAULT.dup
      }

      sheet.runtime!.apply_patch!(patch)
    rescue StandardError => e
      Rails.logger.warn "[Combat::EndService] runtime sync falhou para sheet ##{sheet.id}: #{e.class}: #{e.message}"
    end
  end
end
