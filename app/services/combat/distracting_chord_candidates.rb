# frozen_string_literal: true

module Combat
  # Descobre no servidor os Bardos que podem receber a oferta do Acorde.
  # Jogadores não recebem fichas completas de outros participantes, portanto o
  # browser não tem dados suficientes para montar esta lista com segurança.
  class DistractingChordCandidates
    RANGE_FT = 60.0

    def self.call(schedule:, combat_state:, caster:)
      new(schedule: schedule, combat_state: combat_state, caster: caster).call
    end

    def initialize(schedule:, combat_state:, caster:)
      @schedule = schedule
      @combat_state = combat_state
      @caster = caster
    end

    def call
      return [] unless @schedule && @combat_state && @caster

      @combat_state.combat_combatants.filter_map do |combatant|
        next if combatant.id == @caster.id
        next unless combatant.combatable_type == Character.name
        next unless enemies?(@caster, combatant)
        next unless reaction_available?(combatant)
        next unless target_senses_allow?(combatant)
        next unless in_range?(combatant)

        profile_command = Combat::DistractingChordProfile.call(combatant: combatant)
        next unless profile_command.success?

        profile = profile_command.result
        next unless profile[:used] < profile[:total]

        {
          character_id: combatant.combatable_id.to_s,
          name: combatant.name.to_s,
          dc: profile[:dc],
          die: profile[:die],
          owned_by_dm: owned_by_dm?(combatant.combatable),
        }
      end
    end

    private

    def reaction_available?(combatant)
      !truthy?(Hash(combatant.actions_used)['reaction']) &&
        Hash(combatant.turn_state)['reactionUsedRound'].to_i != @combat_state.round.to_i
    end

    def target_senses_allow?(bard)
      !condition?(bard, 'blinded') && !condition?(@caster, 'invisible') && !condition?(@caster, 'deafened')
    end

    def in_range?(bard)
      map = @schedule.battle_map
      return true unless map

      bard_token = token_for(map, bard)
      caster_token = token_for(map, @caster)
      return true unless bard_token && caster_token

      alternating_diagonal_ft(bard_token, caster_token, map.cell_world_ft.to_f) <= RANGE_FT
    end

    def token_for(map, combatant)
      Array(map.tokens).find do |token|
        if combatant.combatable_type == Character.name
          token['characterId'].to_s == combatant.combatable_id.to_s
        else
          token['npcId'].to_s == combatant.combatable_id.to_s || token['id'].to_s == combatant.id.to_s
        end
      end
    end

    def alternating_diagonal_ft(a, b, cell_ft)
      dx = (a['x'].to_f - b['x'].to_f).abs
      dy = (a['y'].to_f - b['y'].to_f).abs
      diagonal = [dx, dy].min.floor
      straight = (dx - dy).abs
      diagonal_cost = (diagonal / 2) * cell_ft * 3
      diagonal_cost += cell_ft if diagonal.odd?
      diagonal_cost + (straight * cell_ft)
    end

    def enemies?(left, right)
      group_id_for(left) != group_id_for(right)
    end

    def group_id_for(combatant)
      member_type = combatant.combatable_type == Character.name ? 'character' : 'combat_npc'
      explicit = @schedule.combat_groups_normalized['members'].find do |member|
        member['memberType'] == member_type && member['memberId'].to_s == combatant.combatable_id.to_s
      end
      return explicit['groupId'].to_s if explicit

      dm_controlled_character_ids.include?(combatant.combatable_id.to_i) ? '__default_npc__' :
        (combatant.combatable_type == Character.name ? '__default_pc__' : '__default_npc__')
    end

    def dm_controlled_character_ids
      @dm_controlled_character_ids ||= (
        @schedule.linked_npc_sheet_ids_normalized + @schedule.dm_temp_npc_character_ids_normalized
      ).to_set
    end

    def owned_by_dm?(character)
      dm_controlled_character_ids.include?(character.id) || Group.user_is_dm?(character.user)
    end

    def condition?(combatant, expected)
      Array(combatant.conditions).any? do |condition|
        id = condition.is_a?(Hash) ? (condition['id'] || condition[:id]) : condition
        id.to_s == expected
      end
    end

    def truthy?(value)
      [true, 1, '1', 'true'].include?(value)
    end
  end
end
