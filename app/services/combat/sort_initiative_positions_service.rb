# frozen_string_literal: true

module Combat
  # Reordena `position` dos combatentes por iniciativa (maior primeiro) e
  # desempate por `tie_break_dex` (valor da DEX no momento do combate).
  # Combatentes vivos sem iniciativa rolada ficam no fim (ordem estável).
  # Mortos permanecem no fim.
  class SortInitiativePositionsService
    prepend SimpleCommand

    def initialize(combat_state:)
      @combat_state = combat_state
    end

    def call
      return errors.add(:combat_state, 'inexistente') && nil if @combat_state.nil?

      list = @combat_state.combat_combatants.order(:position).to_a
      return list if list.empty?

      living = list.reject(&:is_dead)
      rolled = living.reject { |c| c.initiative.nil? }
      unrolled = living.select { |c| c.initiative.nil? }
      dead = list.select(&:is_dead)

      ordered = rolled.sort_by { |c| [-c.initiative.to_i, -c.tie_break_dex.to_i, -c.id] } + unrolled + dead
      ordered_ids = ordered.map(&:id)

      result = Combat::ReorderService.call(
        combat_state: @combat_state,
        ordered_combatant_ids: ordered_ids,
        current_user: nil,
      )
      return nil if result.nil?

      @combat_state.reload
      # `current_turn_index` no modelo é a `position` do combatente ativo.
      @combat_state.update!(current_turn_index: 0)

      @combat_state.combat_combatants.reload.order(:position)
    end
  end
end
