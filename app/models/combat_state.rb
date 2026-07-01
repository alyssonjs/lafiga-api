# Singleton de combate por Schedule. Encapsula `active`, `round` e
# `current_turn_index`, e expõe transições idempotentes (`begin!`, `finish!`,
# `advance_turn!`, `set_round!`) que mantêm os invariantes:
#   - `active=true` exige `round >= 1`
#   - `current_turn_index` sempre referencia uma posição válida do tracker
#     (ou 0 quando o combate foi reiniciado e ainda não há combatentes)
#
# Broadcasts via ActionCable são tratados em `RealtimeStateService` (Fase 1C);
# aqui mantemos só o domínio puro para deixar specs rápidas e independentes.
class CombatState < ApplicationRecord
  belongs_to :schedule
  has_many :combat_combatants, -> { order(:position) }, dependent: :destroy

  validates :round, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :current_turn_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :round_consistent_with_active

  # Inicia (ou reinicia) o combate. Idempotente: chamadas repetidas em estado
  # ativo apenas retornam `self`. Reinício após `finish!` reseta round para 1
  # e current_turn_index para 0.
  def begin!
    return self if active?

    update!(
      active: true,
      round: [round, 1].max,
      current_turn_index: 0,
      started_at: started_at || Time.current,
      ended_at: nil,
      movement_ledger: [],
    )
    self
  end

  # Encerra o combate. Mantém o registro para histórico/recap.
  def finish!
    return self unless active?

    update!(active: false, ended_at: Time.current, movement_ledger: [])
    self
  end

  # Avança para o próximo turno PULANDO combatentes mortos (G4). Quando passa
  # do último combatente vivo da rodada, incrementa `round` e volta para o
  # primeiro vivo. Sem combatentes vivos é no-op (evita loop infinito).
  #
  # Após avançar, reseta `actions_used` do combatente que ganhou o turno (G7)
  # — em D&D, ações/bonus/movimento/reação resetam a cada turno.
  #
  # G5 — `with_lock` (SELECT FOR UPDATE) serializa updates concorrentes:
  # quando o DM dispara `advance_turn!` simultaneamente em dois devices, o
  # segundo aguarda o primeiro completar e opera sobre o estado mais recente.
  # Sem o lock, dois `advance_turn!` paralelos podem pular um turno
  # silenciosamente.
  #
  # Duração de condições (`turns_left`): alinhado ao 5e — contador em *rodadas*
  # de combate. O tick ocorre quando a *rodada* termina (último da iniciativa
  # vivo “passa” e a vez volta ao primeiro), não no fim do turno de cada criatura.
  #
  # @return [Array<CombatCombatant>] combatentes alterados que o controller deve
  #   reemitir via `Combat::Broadcaster.combatant_upserted` (o evento
  #   `state_changed` sozinho não atualiza `conditions` no reducer do front).
  def advance_turn!
    return [] unless active?

    broadcast_targets = []

    with_lock do
      reload
      unless active?
        broadcast_targets = []
        next
      end

      living_positions = combat_combatants.where(is_dead: false).order(:position).pluck(:position)
      if living_positions.empty?
        broadcast_targets = []
        next
      end

      next_position = living_positions.find { |p| p > current_turn_index }
      new_round = round
      new_index =
        if next_position
          next_position
        else
          new_round = round + 1
          living_positions.first
        end

      # Fim da rodada = não há próximo vivo com position maior (volta ao primeiro).
      round_advances = next_position.nil?

      ticked_ids = []
      if round_advances
        combat_combatants.where(is_dead: false).order(:position).each do |c|
          ticked_ids << c.id if c.tick_conditions_at_end_of_turn!
        end
      end

      update!(current_turn_index: new_index, round: new_round, movement_ledger: [])
      receiver = combat_combatants.find_by(position: new_index)
      receiver&.reset_turn_actions!

      ids = ticked_ids + [receiver&.id].compact
      broadcast_targets = combat_combatants.where(id: ids.uniq).to_a
    end

    broadcast_targets
  end

  def set_round!(new_round)
    n = new_round.to_i
    raise ArgumentError, 'round deve ser >= 1 com combate ativo' if active? && n < 1
    update!(round: n, movement_ledger: [])
    self
  end

  # --- Interação de combate (Fase 1 — disputa Empurrar/Agarrar) ---------------
  # `active_interaction` é um jsonb livre (ver `Combat::InteractionService`). Os
  # helpers abaixo encapsulam as escritas mantendo o domínio testável sem
  # depender de ActionCable (broadcasts ficam no controller, como nos demais
  # fluxos). A persistência é simples (uma única interação activa por combate).

  # Substitui/cria a interação activa. `payload` é o hash já normalizado.
  def set_active_interaction!(payload)
    update!(active_interaction: payload)
    self
  end

  # Limpa a interação activa (estado de repouso). Idempotente.
  def clear_active_interaction!
    return self if active_interaction.nil?
    update!(active_interaction: nil)
    self
  end

  private

  def round_consistent_with_active
    return unless active?
    errors.add(:round, 'deve ser >= 1 quando combate está ativo') if round.to_i < 1
  end
end
