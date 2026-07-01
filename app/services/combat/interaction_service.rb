# frozen_string_literal: true

module Combat
  # Motor (mínimo, Fase 1) do mecanismo genérico de interação de combate.
  # Cobre **apenas** `kind:'contest'` (Empurrar/Agarrar) ponta a ponta:
  #
  #   declared → roll → hit_determined → resolved
  #
  # O service é PURO: recebe params, valida, normaliza, computa a próxima fase
  # e devolve o hash de `active_interaction` (ou `nil` ao limpar). Os broadcasts
  # ActionCable e a persistência ficam no controller (mesmo padrão de
  # `update_movement_ledger`/`ValidateMovementLedgerPayload`).
  #
  # Shape do `active_interaction` (jsonb, chaves string — espelha o que o front
  # consome):
  #   {
  #     "id" => "<uuid>",
  #     "kind" => "contest",
  #     "phase" => "roll" | "hit_determined" | "resolved",
  #     "source_id" => "<characterId do atacante>",
  #     "target_ids" => ["<characterId do defensor>"],
  #     "pending_responders" => [
  #       { "character_id" => "...", "need" => "roll_contest", "owned_by_dm" => false,
  #         "responded" => false }
  #     ],
  #     "contest" => {
  #       "attacker_skill" => "Atletismo",
  #       "defender_skill_options" => ["Atletismo", "Acrobacia"],
  #       "attacker_roll" => { "total" => 18, ... } | nil,
  #       "defender_roll" => { "skill" => "Acrobacia", "total" => 14, ... } | nil,
  #       "outcome" => "source_wins" | "target_wins" | nil
  #     },
  #     "label" => "Empurrão"
  #   }
  module InteractionService
    KIND_CONTEST = 'contest'
    KIND_OPPORTUNITY_ATTACK = 'opportunity_attack'
    DEFENDER_SKILL_OPTIONS = %w[Atletismo Acrobacia].freeze
    ATTACKER_SKILL = 'Atletismo'

    module_function

    # ---- upsert (atacante propõe / o atacante já rolou) -----------------------
    # Cria a interação na fase `roll` com o defensor como pending responder
    # (`need:'roll_contest'`). `attacker_roll` é opcional na proposta (o front
    # rola e envia junto).
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_contest(params)
      p = stringify(params)

      source_id  = presence(p['source_id'])
      target_ids = Array(p['target_ids']).map { |t| presence(t) }.compact
      return nil if source_id.nil? || target_ids.empty?

      kind = (p['kind'] || KIND_CONTEST).to_s
      return nil unless kind == KIND_CONTEST

      defender_id = target_ids.first
      owned_by_dm = truthy(dig(p, 'pending_defender_owned_by_dm'))

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_CONTEST,
        'phase' => 'roll',
        'source_id' => source_id,
        'target_ids' => target_ids,
        'pending_responders' => [
          {
            'character_id' => defender_id,
            'need' => 'roll_contest',
            'owned_by_dm' => owned_by_dm,
            'responded' => false,
          },
        ],
        'contest' => {
          'attacker_skill' => ATTACKER_SKILL,
          'defender_skill_options' => DEFENDER_SKILL_OPTIONS,
          'attacker_roll' => normalize_roll(dig(p, 'contest', 'attacker_roll') || p['attacker_roll']),
          'defender_roll' => nil,
          'outcome' => nil,
        },
        'label' => presence(p['label']) || 'Disputa',
      }
    end

    # ---- upsert OA (Ataque de Oportunidade) -----------------------------------
    # Espelha `build_contest`, mas para `kind:'opportunity_attack'`. O DISPARO
    # vem de QUEM MOVE; o `source_id` é o REATOR (quem ganha a reação). O REATOR
    # é o pending responder (`need:'offer_reaction'`); o MOVER é o alvo
    # (`target_ids`). Cria na fase `roll`. Detalhes do AO (tokens/ataques) ficam
    # no bloco `opportunity_attack`, opaco para o motor (o front os consome).
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_opportunity_attack(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_OPPORTUNITY_ATTACK).to_s
      return nil unless kind == KIND_OPPORTUNITY_ATTACK

      source_id  = presence(p['source_id'])
      target_ids = Array(p['target_ids']).map { |t| presence(t) }.compact
      return nil if source_id.nil? || target_ids.empty?

      oa = normalize_opportunity_attack(dig(p, 'opportunity_attack'))
      return nil if oa.nil?

      reactor_id = source_id
      owned_by_dm = truthy(dig(p, 'pending_responders', 0, 'owned_by_dm'))

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_OPPORTUNITY_ATTACK,
        'phase' => 'roll',
        'source_id' => reactor_id,
        'target_ids' => target_ids,
        'pending_responders' => [
          {
            'character_id' => reactor_id,
            'need' => 'offer_reaction',
            'owned_by_dm' => owned_by_dm,
            'responded' => false,
          },
        ],
        'opportunity_attack' => oa,
        'label' => presence(p['label']) || 'Ataque de Oportunidade',
      }
    end

    # ---- respond (o defensor rola; depois resolve) ----------------------------
    # Aplica a resposta de um responder à interação corrente e avança a fase.
    # `current` é o `active_interaction` persistido; `params` traz
    # `{ character_id, defender_roll: { skill, total, ... }, attacker_roll? }`.
    #
    # Retorna [next_interaction_hash, error_symbol]. `error_symbol` é `nil` em
    # sucesso; caso contrário o caller mapeia para 4xx.
    def apply_response(current, params)
      return [nil, :not_found] if current.blank?

      interaction = deep_dup(current)
      p = stringify(params)
      character_id = presence(p['character_id'])
      return [interaction, :invalid_character] if character_id.nil?

      responder = Array(interaction['pending_responders']).find do |r|
        r['character_id'].to_s == character_id.to_s && !truthy(r['responded'])
      end
      return [interaction, :not_pending] if responder.nil?

      return apply_opportunity_attack_response(interaction, p, responder) if interaction['kind'] == KIND_OPPORTUNITY_ATTACK

      contest = interaction['contest'] ||= {}

      # Atacante pode preencher a rolagem dele aqui também (caso não tenha vindo no upsert).
      if (atk = normalize_roll(p['attacker_roll']))
        contest['attacker_roll'] = atk
      end

      defender_roll = normalize_roll(p['defender_roll'])
      return [interaction, :invalid_roll] if defender_roll.nil?

      skill = presence(dig(p, 'defender_roll', 'skill')) || presence(p['defender_skill'])
      if skill && !DEFENDER_SKILL_OPTIONS.include?(skill)
        return [interaction, :invalid_skill]
      end
      defender_roll['skill'] = skill if skill
      contest['defender_roll'] = defender_roll

      responder['responded'] = true

      maybe_resolve_contest!(interaction)
      [interaction, nil]
    end

    # ---- resolução -----------------------------------------------------------
    # Quando atacante e defensor já rolaram, computa o outcome e marca
    # `hit_determined`. Empate → defensor vence (regra 5e). DM ainda pode
    # arbitrar/limpar depois.
    def maybe_resolve_contest!(interaction)
      contest = interaction['contest'] || {}
      atk = contest['attacker_roll']
      dfn = contest['defender_roll']
      return interaction unless atk.is_a?(Hash) && dfn.is_a?(Hash)

      attacker_total = atk['total'].to_i
      defender_total = dfn['total'].to_i

      contest['outcome'] = attacker_total > defender_total ? 'source_wins' : 'target_wins'
      interaction['phase'] = 'hit_determined'
      interaction
    end

    # ---- respond OA -----------------------------------------------------------
    # O REATOR oferece a reação: grava `roll` (total do d20+mods do ataque) e
    # `damage` no bloco `opportunity_attack`, marca o responder `responded` e
    # avança a fase para `resolved`. NÃO computa hit/miss nem aplica dano aqui:
    # isso exige o AC FRESCO do mover e o DamageService, que vivem no controller
    # (mesmo padrão de `maybe_resolve_contest!` deixar arbitragem ao caller).
    #
    # Retorna [interaction, error_symbol]. `error_symbol` nil em sucesso.
    def apply_opportunity_attack_response(interaction, p, responder)
      oa = interaction['opportunity_attack'] ||= {}

      roll = normalize_roll(dig(p, 'opportunity_attack', 'roll'))
      return [interaction, :invalid_roll] if roll.nil?

      damage = dig(p, 'opportunity_attack', 'damage')
      oa['roll'] = roll
      oa['damage'] = damage.to_i

      responder['responded'] = true
      interaction['phase'] = 'resolved'
      [interaction, nil]
    end

    # --- helpers --------------------------------------------------------------

    # Normaliza o bloco `opportunity_attack` do upsert. Campos descritivos
    # (tokens/nomes/ataques) são passados adiante de forma controlada — o motor
    # não os interpreta, mas o front os consome. `roll`/`damage` só entram no
    # respond. Retorna nil se o bloco estiver ausente/vazio.
    def normalize_opportunity_attack(raw)
      return nil if raw.nil?
      h = stringify(raw)

      out = {}
      out['mover_token_id']      = presence(h['mover_token_id']).to_s      if presence(h['mover_token_id'])
      out['mover_name']          = presence(h['mover_name']).to_s          if presence(h['mover_name'])
      out['mover_combatant_id']  = h['mover_combatant_id']                 unless h['mover_combatant_id'].nil?
      out['reactor_token_id']    = presence(h['reactor_token_id']).to_s    if presence(h['reactor_token_id'])
      out['reactor_name']        = presence(h['reactor_name']).to_s        if presence(h['reactor_name'])
      out['attacks']             = Array(h['attacks']).select { |a| a.is_a?(Hash) }.map { |a| stringify(a) }   if h['attacks'].is_a?(Array)
      out['npc_attacks']         = Array(h['npc_attacks']).select { |a| a.is_a?(Hash) }.map { |a| stringify(a) } if h['npc_attacks'].is_a?(Array)
      out['ignores_disengage']   = truthy(h['ignores_disengage'])          if h.key?('ignores_disengage')
      out['oa_at_disadvantage']  = truthy(h['oa_at_disadvantage'])         if h.key?('oa_at_disadvantage')

      out
    end

    def normalize_roll(raw)
      return nil if raw.nil?
      h = stringify(raw)
      total = h['total']
      return nil unless total.is_a?(Numeric) || (total.is_a?(String) && total.match?(/\A-?\d+\z/))

      out = { 'total' => total.to_i }
      out['formula'] = h['formula'].to_s if presence(h['formula'])
      out['dice'] = Array(h['dice']).map(&:to_i) if h['dice'].is_a?(Array)
      out['advantage'] = h['advantage'].to_s if presence(h['advantage'])
      out['skill'] = h['skill'].to_s if presence(h['skill'])
      out['roll_group_id'] = h['roll_group_id'].to_s if presence(h['roll_group_id'])
      out['natural20'] = true if truthy(h['natural20'])
      out['natural1'] = true if truthy(h['natural1'])
      out
    end

    def stringify(obj)
      return obj.deep_stringify_keys if obj.respond_to?(:deep_stringify_keys)
      obj.is_a?(Hash) ? obj.stringify_keys : {}
    end

    def deep_dup(obj)
      Marshal.load(Marshal.dump(obj))
    rescue StandardError
      stringify(obj)
    end

    def dig(hash, *keys)
      hash.is_a?(Hash) ? hash.dig(*keys) : nil
    end

    def presence(val)
      s = val.to_s
      s.empty? ? nil : (val.is_a?(String) ? s : val)
    end

    def truthy(val)
      [true, 1, '1', 'true'].include?(val)
    end
  end
end
