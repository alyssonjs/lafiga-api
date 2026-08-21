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

    def self.evaluate(schedule:, combat_state:, caster:)
      new(schedule: schedule, combat_state: combat_state, caster: caster).evaluate
    end

    # Contrato antigo (só os elegíveis) — o controller de upsert usa este.
    def call
      evaluate[:eligible]
    end

    # Elegíveis + os BLOQUEADOS POR ECONOMIA.
    #
    # A separação existe para que a mesa saiba POR QUE a janela não abriu. Um
    # Bardo do Virtuosismo ao alcance, que vê e é ouvido, mas sem reação ou sem
    # dado de Inspiração, é uma quase-oferta: sem log, a conjuração simplesmente
    # segue e ninguém entende que a feature foi checada (19/08 — o Bardo estava
    # com 5/5 dados gastos e o silêncio pareceu bug).
    #
    # Só a ECONOMIA vira aviso. Identidade, alcance e sentidos ficam calados de
    # propósito: todo mundo que não é Bardo do Virtuosismo cairia no log a cada
    # conjuração. Mesma disciplina do emissor das Palavras de Interrupção.
    def evaluate
      return { eligible: [], blocked: [] } unless @schedule && @combat_state && @caster

      eligible = []
      blocked = []

      @combat_state.combat_combatants.each do |combatant|
        next if combatant.id == @caster.id
        next unless combatant.combatable_type == Character.name
        next unless enemies?(@caster, combatant)
        # ALVO antes da ECONOMIA (F6.8): quem nem podia ser oferecido não vira
        # aviso de "sem recurso".
        next unless target_senses_allow?(combatant)
        next unless in_range?(combatant)

        profile_command = Combat::DistractingChordProfile.call(combatant: combatant)
        next unless profile_command.success?

        profile = profile_command.result
        unless reaction_available?(combatant)
          blocked << { name: combatant.name.to_s, reason: :reaction_used }
          next
        end
        unless profile[:used] < profile[:total]
          blocked << { name: combatant.name.to_s, reason: :no_inspiration }
          next
        end

        eligible << {
          character_id: combatant.combatable_id.to_s,
          name: combatant.name.to_s,
          dc: profile[:dc],
          die: profile[:die],
          owned_by_dm: owned_by_dm?(combatant.combatable),
        }
      end

      { eligible: eligible, blocked: blocked }
    end

    private

    # Espelha `reactionAvailableForRound` do front — regra da mesa: a reação
    # recarrega na VIRADA DA RODADA.
    #
    # ⚠️ Exigir a flag crua `actions_used.reaction` falsa E o carimbo diferente
    # (a versão anterior) reintroduziu no servidor o bug do Ainor (18/08): a flag
    # só é limpa no turno DO REATOR, então, entre a virada da rodada e a vez dele,
    # ela fica presa em `true`. Quem age ANTES dele na iniciativa — justamente o
    # caso do conjurador — via o Bardo como "já reagiu" a rodada inteira.
    # Carimbo de rodada PASSADA = reação recarregada, flag crua ou não.
    def reaction_available?(combatant)
      Combat::ReactionEconomy.available?(combatant, @combat_state.round)
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
