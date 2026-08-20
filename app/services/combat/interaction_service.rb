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
    KIND_HOSTILE_CASTING = 'hostile_casting'
    KIND_TARGET_CONSENT = 'target_consent'
    KIND_INSTINCTIVE_FORTITUDE = 'instinctive_fortitude'
    KIND_PROTECTIVE_SWAP = 'protective_swap'
    KIND_TRIBE_DEFENDER = 'tribe_defender'
    KIND_COMBAT_INSPIRATION_AC = 'combat_inspiration_ac'
    KIND_STRONG_PERSONALITY = 'strong_personality'
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

    # ---- upsert Conjuração Hostil (Frustrar Conjuração, Desistente L10) --------
    # O DISPARO vem do MESTRE ao declarar que uma criatura hostil está conjurando
    # (não há ação de conjuração de NPC no engine; monsterDatabase não tem spells).
    # `source_id` é o CONJURADOR; `target_ids` são os REATORES (Desistentes L10+ a
    # ≤9 m) — cada um vira pending responder (`need:'offer_reaction'`). Fase inicial
    # `declared`. Detalhes (nome/nível da magia, CD) ficam no bloco `hostile_casting`.
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_hostile_casting(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_HOSTILE_CASTING).to_s
      return nil unless kind == KIND_HOSTILE_CASTING

      source_id  = presence(p['source_id'])
      target_ids = Array(p['target_ids']).map { |t| presence(t) }.compact
      return nil if source_id.nil? || target_ids.empty?

      hc = normalize_hostile_casting(dig(p, 'hostile_casting'))
      return nil if hc.nil?

      responders_in = Array(dig(p, 'pending_responders'))
      pending = target_ids.map do |rid|
        raw = responders_in.find { |r| stringify(r)['character_id'].to_s == rid.to_s }
        owned = truthy(stringify(raw || {})['owned_by_dm'])
        {
          'character_id' => rid,
          'need' => 'offer_reaction',
          'owned_by_dm' => owned,
          'responded' => false,
        }
      end

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_HOSTILE_CASTING,
        'phase' => 'declared',
        'source_id' => source_id,
        'target_ids' => target_ids,
        'pending_responders' => pending,
        'hostile_casting' => hc,
        'label' => presence(p['label']) || 'Conjuração hostil',
      }
    end

    # ---- upsert Consentimento de Alvo (magia voluntária/benéfica) -------------
    # Um conjurador (`source_id`) mira um PC (`target_ids.first`) com magia que
    # exige alvo VOLUNTÁRIO. O DONO do PC decide (M2): `need:'consent'`, fase
    # única `declared`. A Aversão à Magia (Desistente) auto-recusa (`auto_refuse`
    # informativo no bloco). Recusar/cancelar não consome nada (F3.6).
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_target_consent(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_TARGET_CONSENT).to_s
      return nil unless kind == KIND_TARGET_CONSENT

      source_id  = presence(p['source_id'])
      target_ids = Array(p['target_ids']).map { |t| presence(t) }.compact
      return nil if source_id.nil? || target_ids.empty?

      tc = normalize_target_consent(dig(p, 'target_consent'))
      return nil if tc.nil?

      target_id = target_ids.first
      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == target_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_TARGET_CONSENT,
        'phase' => 'declared',
        'source_id' => source_id,
        'target_ids' => [target_id],
        'pending_responders' => [
          { 'character_id' => target_id, 'need' => 'consent', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'target_consent' => tc,
        'label' => presence(p['label']) || 'Consentimento de alvo',
      }
    end

    # ---- upsert Fortitude Instintiva (Furioso Imortal L14) --------------------
    # O DISPARO vem de QUEM APLICOU o dano (o cliente do atacante/Mestre roda o
    # `handleUpdateCombatant` que detecta `justDowned`). `source_id` é o BÁRBARO
    # que caiu a 0 PV (o REATOR), único `target_id`. O DONO do PC decide (M2):
    # `need:'offer_reaction'`, fase única `declared`. Aceitar → entra em Fúria +
    # volta a 1 PV + consome a reação (server-side no respond). Recusar não
    # consome nada. Bloco `instinctive_fortitude` só descritivo (nome).
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_instinctive_fortitude(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_INSTINCTIVE_FORTITUDE).to_s
      return nil unless kind == KIND_INSTINCTIVE_FORTITUDE

      source_id  = presence(p['source_id'])
      target_ids = Array(p['target_ids']).map { |t| presence(t) }.compact
      return nil if source_id.nil? || target_ids.empty?

      reactor_id = source_id
      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == reactor_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_INSTINCTIVE_FORTITUDE,
        'phase' => 'declared',
        'source_id' => reactor_id,
        'target_ids' => [reactor_id],
        'pending_responders' => [
          { 'character_id' => reactor_id, 'need' => 'offer_reaction', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'instinctive_fortitude' => normalize_instinctive_fortitude(dig(p, 'instinctive_fortitude')),
        'label' => presence(p['label']) || 'Fortitude Instintiva',
      }
    end

    # ---- upsert Fúria Protetora: Trocar de Lugar (Protetor Tribal L3) ---------
    # O ATACANTE (dono do turno / Mestre por NPC) declara que um ataque MELEE vai
    # mirar um ALIADO adjacente a um Protetor Tribal elegível. Fluxo de DOIS
    # respondedores sequenciais:
    #   fase `awaiting_protector`: o Protetor (`source_id`, `need:'offer_reaction'`)
    #     decide TROCAR (accept) ou não (decline);
    #   fase `awaiting_consent`: o dono do ALIADO (`ally_char_id`, `need:'consent'`)
    #     confirma a troca (accept) ou recusa (decline).
    # O consumo da reação (server-side) e o `outcome:'accepted'` acontecem no
    # respond; o SWAP de posição + o retarget do ataque são executados pelo front
    # do atacante ao ver `phase:'resolved'`.
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_protective_swap(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_PROTECTIVE_SWAP).to_s
      return nil unless kind == KIND_PROTECTIVE_SWAP

      ps = normalize_protective_swap(dig(p, 'protective_swap'))
      return nil if ps.nil?

      reactor_id = presence(p['source_id']) || ps['reactor_char_id']
      return nil if reactor_id.nil?

      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == reactor_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_PROTECTIVE_SWAP,
        'phase' => 'awaiting_protector',
        'source_id' => reactor_id,
        'target_ids' => [reactor_id],
        'pending_responders' => [
          { 'character_id' => reactor_id, 'need' => 'offer_reaction', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'protective_swap' => ps,
        'label' => presence(p['label']) || 'Fúria Protetora: Trocar de Lugar',
      }
    end

    # ---- upsert Defensor da Tribo (Protetor Tribal L10) ----------------------
    # O DISPARO vem de QUEM APLICOU o dano (aplicador/atacante do turno, ou o Mestre
    # por NPC). Quando um aliado cai a 0 PV / inconsciente / paralisado, oferece a
    # reação ao DEFENSOR elegível (`source_id`, único responder, `offer_reaction`,
    # fase única `declared`). Aceitar → consome a reação (respond) + `outcome:accepted`;
    # o front executa o movimento (Defensor → espaço do aliado) e a marca não-alvejável.
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_tribe_defender(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_TRIBE_DEFENDER).to_s
      return nil unless kind == KIND_TRIBE_DEFENDER

      td = normalize_tribe_defender(dig(p, 'tribe_defender'))
      return nil if td.nil?

      defender_id = presence(p['source_id']) || td['defender_char_id']
      return nil if defender_id.nil?

      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == defender_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_TRIBE_DEFENDER,
        'phase' => 'declared',
        'source_id' => defender_id,
        'target_ids' => [defender_id],
        'pending_responders' => [
          { 'character_id' => defender_id, 'need' => 'offer_reaction', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'tribe_defender' => td,
        'label' => presence(p['label']) || 'Defensor da Tribo',
      }
    end

    # ---- upsert Inspiração em Combate: CA (Bardo, Colégio da Bravura L3) ------
    # O DISPARO vem do ATACANTE (dono do turno; NPC → Mestre já coberto), logo
    # depois da rolagem de ataque. O `source_id` é o ALVO (o REATOR que carrega o
    # dado), único pending responder (`need:'offer_reaction'`), fase única
    # `declared`.
    #
    # ⚠️ A interação NÃO decide acerto/erro. Neste projeto o V/X é do MESTRE, no
    # card do chat; aqui só entra a CA EFETIVA contra ESTE ataque (base + dado).
    # Aceitar → o respond consome a reação E o dado (server-side) e resolve com
    # `final_ac`; recusar → `declined` e NADA é consumido (F3.18). Enquanto a
    # janela está aberta o front segura o V/X — senão o Mestre decidiria contra
    # uma CA que está prestes a mudar.
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_combat_inspiration_ac(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_COMBAT_INSPIRATION_AC).to_s
      return nil unless kind == KIND_COMBAT_INSPIRATION_AC

      ci = normalize_combat_inspiration_ac(dig(p, 'combat_inspiration_ac'))
      return nil if ci.nil?

      reactor_id = presence(p['source_id']) || ci['target_char_id']
      return nil if reactor_id.nil?

      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == reactor_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_COMBAT_INSPIRATION_AC,
        'phase' => 'declared',
        'source_id' => reactor_id.to_s,
        'target_ids' => [reactor_id.to_s],
        'pending_responders' => [
          { 'character_id' => reactor_id.to_s, 'need' => 'offer_reaction', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'combat_inspiration_ac' => ci,
        'label' => presence(p['label']) || 'Inspiração em Combate: CA',
      }
    end

    # ---- Personalidade Forte (Bardo · Virtuosismo L3) ------------------------
    #
    # HOUSERULE DA MESA (19/08): a fonte impressa manda gastar a AÇÃO, no turno
    # seguinte do Bardo. A mesa trocou por REAÇÃO, decidida na hora.
    #
    # ⚠️ Por que isto PRECISA ser interação (e não turn_state do Bardo, que já
    # existia): como reação, a condição é escrita no turno do AGRESSOR — em geral
    # um NPC do Mestre. O cliente do Bardo levaria 403 nesse PATCH (`conditions`
    # está fora de PLAYER_TURN_STATE_FIELDS e o gate exige turno próprio). O
    # servidor é quem tem autorização para gravar; enquanto era AÇÃO isso passava
    # despercebido porque o Bardo escrevia no próprio turno.
    #
    # UM agressor por interação, de propósito. A lista existia no desenho de AÇÃO
    # porque a decisão era adiada e as janelas se acumulavam entre turnos; na
    # reação cada TR tem um agressor (uma criatura age por turno), e com 1 reação
    # por rodada um segundo botão seria natimorto.
    #
    # Retorna o hash normalizado, ou `nil` se inválido (caller → 422).
    def build_strong_personality(params)
      p = stringify(params)

      kind = (p['kind'] || KIND_STRONG_PERSONALITY).to_s
      return nil unless kind == KIND_STRONG_PERSONALITY

      sp = normalize_strong_personality(dig(p, 'strong_personality'))
      return nil if sp.nil?

      reactor_id = presence(p['source_id']) || sp['bard_char_id']
      return nil if reactor_id.nil?

      raw = Array(dig(p, 'pending_responders')).find { |r| stringify(r)['character_id'].to_s == reactor_id.to_s }
      owned = truthy(stringify(raw || {})['owned_by_dm'])

      {
        'id' => presence(p['id']) || SecureRandom.uuid,
        'kind' => KIND_STRONG_PERSONALITY,
        'phase' => 'declared',
        'source_id' => reactor_id.to_s,
        'target_ids' => [reactor_id.to_s],
        'pending_responders' => [
          { 'character_id' => reactor_id.to_s, 'need' => 'offer_reaction', 'owned_by_dm' => owned, 'responded' => false },
        ],
        'strong_personality' => sp,
        'label' => presence(p['label']) || 'Personalidade Forte: desmoralizar',
      }
    end

    # `aggressor_combatant_id` é OBRIGATÓRIO: sem ele o respond não teria em quem
    # gravar a condição, e uma janela que gasta a reação sem efeito é pior que
    # janela nenhuma (mesma disciplina do `base_ac`/`die` da Inspiração em Combate).
    def normalize_strong_personality(raw)
      return nil if raw.nil?
      h = stringify(raw)

      bard = presence(h['bard_char_id'])
      aggressor_cc = presence(h['aggressor_combatant_id'])
      return nil if bard.nil? || aggressor_cc.nil?

      out = {
        'bard_char_id' => bard.to_s,
        'aggressor_combatant_id' => aggressor_cc.to_s,
      }
      out['bard_name']      = presence(h['bard_name']).to_s      if presence(h['bard_name'])
      out['aggressor_name'] = presence(h['aggressor_name']).to_s if presence(h['aggressor_name'])
      out['effect_label']   = presence(h['effect_label']).to_s   if presence(h['effect_label'])
      out
    end

    # Bloco descritivo + os números que o prompt e o log precisam. `die_roll`/
    # `final_ac`/`outcome` só entram no respond. `base_ac` e `die` são
    # OBRIGATÓRIOS: sem eles não há CA efetiva para calcular, e uma janela que não
    # muda nada seria pior que janela nenhuma (gastaria a reação à toa).
    def normalize_combat_inspiration_ac(raw)
      return nil if raw.nil?
      h = stringify(raw)

      target = presence(h['target_char_id'])
      die    = presence(h['die'])
      return nil if target.nil? || die.nil?
      return nil unless die.to_s.match?(/\Ad\d+\z/)
      return nil unless h['base_ac'].to_s.match?(/\A\d+\z/)

      out = {
        'target_char_id' => target.to_s,
        'die' => die.to_s,
        'base_ac' => h['base_ac'].to_i,
      }
      out['attacker_name']    = presence(h['attacker_name']).to_s    if presence(h['attacker_name'])
      out['target_name']      = presence(h['target_name']).to_s      if presence(h['target_name'])
      out['attack_name']      = presence(h['attack_name']).to_s      if presence(h['attack_name'])
      out['attack_roll_total'] = h['attack_roll_total'].to_i if h['attack_roll_total'].to_s.match?(/\A-?\d+\z/)
      # Card do ataque no feed: é por ele que o front repõe a CA exibida ao Mestre.
      out['roll_group_id']    = presence(h['roll_group_id']).to_s    if presence(h['roll_group_id'])
      out['die_roll'] = nil
      out['final_ac'] = nil
      out['outcome'] = nil
      out
    end

    def normalize_tribe_defender(raw)
      return nil if raw.nil?
      h = stringify(raw)

      defender = presence(h['defender_char_id'])
      ally     = presence(h['ally_char_id'])
      return nil if defender.nil? || ally.nil?

      out = {
        'defender_char_id' => defender.to_s,
        'ally_char_id' => ally.to_s,
      }
      out['ally_owned_by_dm'] = truthy(h['ally_owned_by_dm'])
      out['defender_token_id'] = presence(h['defender_token_id']).to_s if presence(h['defender_token_id'])
      out['ally_token_id']     = presence(h['ally_token_id']).to_s     if presence(h['ally_token_id'])
      out['downed_name']       = presence(h['downed_name']).to_s       if presence(h['downed_name'])
      out['outcome'] = nil
      out
    end

    def normalize_protective_swap(raw)
      return nil if raw.nil?
      h = stringify(raw)

      reactor = presence(h['reactor_char_id'])
      ally    = presence(h['ally_char_id'])
      return nil if reactor.nil? || ally.nil?

      out = {
        'reactor_char_id' => reactor.to_s,
        'ally_char_id' => ally.to_s,
        'ally_owned_by_dm' => truthy(h['ally_owned_by_dm']),
        'reactor_owned_by_dm' => truthy(h['reactor_owned_by_dm']),
      }
      out['attacker_token_id'] = presence(h['attacker_token_id']).to_s if presence(h['attacker_token_id'])
      out['ally_token_id']     = presence(h['ally_token_id']).to_s     if presence(h['ally_token_id'])
      out['reactor_token_id']  = presence(h['reactor_token_id']).to_s  if presence(h['reactor_token_id'])
      %w[reactor_from_col reactor_from_row ally_from_col ally_from_row].each do |key|
        out[key] = h[key].to_f if h[key].is_a?(Numeric)
      end

      am = stringify(h['attack_meta'] || {})
      out['attack_meta'] = {
        'name' => presence(am['name']).to_s,
        'caster_name' => presence(am['caster_name']).to_s,
        'bonus' => presence(am['bonus']).to_s,
        'damage' => presence(am['damage']).to_s,
        'damage_type' => presence(am['damage_type']).to_s,
      }
      out['outcome'] = nil
      out['swap_applied'] = false
      out
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

    # O reator confirmou que vai executar o AO. Sem Protetor elegível, o mesmo
    # active_interaction avança para a rolagem. Com Fúria Protetora, a troca vira
    # uma subfase do AO em vez de ocupar/clobberar o slot global da interação.
    def prepare_opportunity_attack(current, params)
      return [nil, :not_found] if current.blank?

      interaction = deep_dup(current)
      return [interaction, :invalid_phase] unless interaction['kind'] == KIND_OPPORTUNITY_ATTACK && interaction['phase'] == 'roll'

      p = stringify(params)
      character_id = presence(p['character_id'])
      return [interaction, :invalid_character] if character_id.nil?

      responder = pending_responder(interaction, character_id)
      return [interaction, :not_pending] if responder.nil?
      return [interaction, :invalid_response] unless truthy(dig(p, 'opportunity_attack', 'commit'))

      oa = interaction['opportunity_attack'] ||= {}
      oa['attack_committed'] = true
      oa['reactor_owned_by_dm'] = truthy(responder['owned_by_dm'])

      raw_swap = p['protective_swap']
      if raw_swap.present?
        swap = normalize_protective_swap(raw_swap)
        return [interaction, :invalid_response] if swap.nil?

        interaction['protective_swap'] = swap
        interaction['phase'] = 'awaiting_protector'
        interaction['pending_responders'] = [
          responder_hash(
            swap['reactor_char_id'],
            'offer_reaction',
            truthy(swap['reactor_owned_by_dm']),
          ),
        ]
      else
        resume_opportunity_attack_roll!(interaction)
      end

      [interaction, nil]
    end

    # Respostas das duas subfases da Fúria Protetora embutida no AO. Recusar
    # retoma a rolagem original. Consentir preserva o alvo original até o cliente
    # responsável pelo mapa confirmar que aplicou a troca de tokens.
    def apply_opportunity_attack_protective_swap_response(current, params)
      return [nil, :not_found] if current.blank?

      interaction = deep_dup(current)
      unless interaction['kind'] == KIND_OPPORTUNITY_ATTACK &&
             %w[awaiting_protector awaiting_consent].include?(interaction['phase'])
        return [interaction, :invalid_phase]
      end

      p = stringify(params)
      character_id = presence(p['character_id'])
      return [interaction, :invalid_character] if character_id.nil?

      responder = pending_responder(interaction, character_id)
      return [interaction, :not_pending] if responder.nil?

      decision = stringify(p['protective_swap'] || {})
      accept = truthy(decision['accept'])
      decline = truthy(decision['decline'])
      return [interaction, :invalid_response] if accept == decline

      swap = interaction['protective_swap']
      return [interaction, :invalid_response] unless swap.is_a?(Hash)

      if decline
        interaction['protective_swap'] = swap.merge('outcome' => 'declined')
        resume_opportunity_attack_roll!(interaction)
        return [interaction, nil]
      end

      if interaction['phase'] == 'awaiting_protector'
        interaction['phase'] = 'awaiting_consent'
        interaction['pending_responders'] = [
          responder_hash(swap['ally_char_id'], 'consent', truthy(swap['ally_owned_by_dm'])),
        ]
        return [interaction, nil]
      end

      interaction['protective_swap'] = swap.merge('outcome' => 'accepted', 'swap_applied' => false)
      interaction['phase'] = 'awaiting_swap_apply'
      interaction['pending_responders'] = [
        # O swap move DOIS tokens e a API de mapa reserva essa mutação atômica ao
        # Mestre. O dono do aliado já consentiu na fase anterior; daqui em diante
        # o DM apenas persiste a troca e confirma a retomada do AO.
        responder_hash(swap['ally_char_id'], 'apply_swap', true),
      ]
      [interaction, nil]
    end

    # Confirmação do cliente que aplicou o swap no mapa. Só aqui o AO troca o
    # alvo persistido para o Protetor e libera o reator para rolar o ataque.
    def complete_opportunity_attack_swap(current, params, retarget)
      return [nil, :not_found] if current.blank?

      interaction = deep_dup(current)
      unless interaction['kind'] == KIND_OPPORTUNITY_ATTACK && interaction['phase'] == 'awaiting_swap_apply'
        return [interaction, :invalid_phase]
      end

      p = stringify(params)
      character_id = presence(p['character_id'])
      return [interaction, :invalid_character] if character_id.nil?
      return [interaction, :not_pending] if pending_responder(interaction, character_id).nil?
      return [interaction, :invalid_response] unless truthy(dig(p, 'opportunity_attack', 'swap_applied'))

      target = stringify(retarget)
      mover_identity = presence(target['mover_identity'])
      mover_token_id = presence(target['mover_token_id'])
      return [interaction, :invalid_response] if mover_identity.nil? || mover_token_id.nil?

      oa = interaction['opportunity_attack'] ||= {}
      original_mover_token_id = presence(dig(interaction, 'protective_swap', 'ally_token_id')) ||
                                presence(oa['mover_token_id'])
      oa['mover_token_id'] = mover_token_id.to_s
      oa['mover_name'] = presence(target['mover_name']).to_s
      oa['mover_combatant_id'] = target['mover_combatant_id'] unless target['mover_combatant_id'].nil?
      Array(oa['queued_reactions']).each do |queued|
        next unless queued.is_a?(Hash)
        next unless queued['mover_token_id'].to_s == original_mover_token_id.to_s

        queued['mover_token_id'] = mover_token_id.to_s
        queued['mover_name'] = presence(target['mover_name']).to_s
      end
      interaction['target_ids'] = [mover_identity.to_s]
      interaction['protective_swap'] = Hash(interaction['protective_swap']).merge('swap_applied' => true)
      resume_opportunity_attack_roll!(interaction)
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
      out['mover_from_col']      = h['mover_from_col'].to_f                 if h['mover_from_col'].is_a?(Numeric)
      out['mover_from_row']      = h['mover_from_row'].to_f                 if h['mover_from_row'].is_a?(Numeric)
      if h['queued_reactions'].is_a?(Array)
        out['queued_reactions'] = h['queued_reactions'].filter_map do |raw_entry|
          entry = stringify(raw_entry)
          reactor_token_id = presence(entry['reactor_token_id'])
          reactor_name = presence(entry['reactor_name'])
          mover_token_id = presence(entry['mover_token_id'])
          mover_name = presence(entry['mover_name'])
          next if [reactor_token_id, reactor_name, mover_token_id, mover_name].any?(&:nil?)

          {
            'reactor_token_id' => reactor_token_id.to_s,
            'reactor_name' => reactor_name.to_s,
            'mover_token_id' => mover_token_id.to_s,
            'mover_name' => mover_name.to_s,
          }
        end
      end

      out
    end

    # Normaliza o bloco `hostile_casting` do upsert. Descritivo (nome/nível/CD são
    # informativos p/ o prompt); o motor não os interpreta. `outcome` só entra no
    # respond. Retorna nil se ausente/vazio.
    def normalize_hostile_casting(raw)
      return nil if raw.nil?
      h = stringify(raw)

      out = { 'hostile' => true }
      out['caster_id']   = presence(h['caster_id']).to_s   if presence(h['caster_id'])
      out['caster_name'] = presence(h['caster_name']).to_s if presence(h['caster_name'])
      out['spell_name']  = presence(h['spell_name']).to_s  if presence(h['spell_name'])
      out['spell_level'] = h['spell_level'].to_i if h['spell_level'].to_s.match?(/\A\d+\z/)
      out['dc']          = h['dc'].to_i          if h['dc'].to_s.match?(/\A\d+\z/)
      # Modificador de TR de SAB do CONJURADOR — o emissor computa da ficha/perfil
      # na declaração, porque quem responde (o Bardo) não tem acesso a ela.
      # Aceita negativo (mod. ruim de SAB é comum).
      if h['caster_save_bonus'].to_s.match?(/\A-?\d+\z/)
        out['caster_save_bonus'] = h['caster_save_bonus'].to_i
      end
      reactors = normalize_hostile_casting_reactors(h['reactors'])
      out['reactors'] = reactors if reactors.present?
      # Conjuração SEGURADA no cliente do conjurador (emissão automática): muda o
      # FIM da janela — em vez de limpar, resolve com `outcome` para o disparador
      # retomar ou falhar o cast.
      out['held_cast'] = true if truthy(h['held_cast'])
      out['held_by_client_id'] = presence(h['held_by_client_id']).to_s if presence(h['held_by_client_id'])
      out['outcome'] = nil
      out
    end

    # Metadata por responder. É o que diz à carta, à fila e ao respond QUAL feature
    # cada reator está usando (Frustrar Conjuração × Acorde Distrativo) sem que o
    # leitor precise da ficha dele — e sobrevive a reload. Entrada malformada CAI:
    # um reator sem família viraria uma carta sem identidade.
    def normalize_hostile_casting_reactors(raw)
      return nil unless raw.is_a?(Hash) || raw.respond_to?(:to_unsafe_h)

      stringify(raw).each_with_object({}) do |(character_id, meta), acc|
        m = stringify(meta)
        family = m['family'].to_s
        next unless %w[superstitious virtuoso].include?(family)

        entry = { 'family' => family }
        entry['name'] = presence(m['name']).to_s if presence(m['name'])
        entry['dc']   = m['dc'].to_i if m['dc'].to_s.match?(/\A\d+\z/)
        # Só a FACE do dado (d6/d8/d10/d12) — é a base da validação do `die_roll`
        # no respond. Um dado livre aqui viraria penalidade arbitrária no TR.
        entry['die']  = m['die'].to_s if m['die'].to_s.match?(/\Ad\d+\z/)
        acc[character_id.to_s] = entry
      end
    end

    # Normaliza o bloco `target_consent` do upsert. Descritivo (conjurador/magia/
    # benéfico/auto-recusa). `outcome` só entra no respond. Retorna nil se ausente.
    def normalize_target_consent(raw)
      return nil if raw.nil?
      h = stringify(raw)

      out = {}
      out['caster_id']   = presence(h['caster_id']).to_s   if presence(h['caster_id'])
      out['caster_name'] = presence(h['caster_name']).to_s if presence(h['caster_name'])
      out['spell_name']  = presence(h['spell_name']).to_s  if presence(h['spell_name'])
      out['beneficial']  = truthy(h['beneficial']) if h.key?('beneficial')
      out['auto_refuse'] = truthy(h['auto_refuse']) if h.key?('auto_refuse')
      out['outcome'] = nil
      out
    end

    # Normaliza o bloco `instinctive_fortitude` do upsert. Só descritivo (nome do
    # Bárbaro caído, para o prompt). O motor não interpreta. Nunca nil (bloco
    # opcional): devolve ao menos `{}` normalizado.
    def normalize_instinctive_fortitude(raw)
      h = stringify(raw || {})
      out = {}
      out['downed_name'] = presence(h['downed_name']).to_s if presence(h['downed_name'])
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

    def pending_responder(interaction, character_id)
      Array(interaction['pending_responders']).find do |responder|
        responder['character_id'].to_s == character_id.to_s && !truthy(responder['responded'])
      end
    end

    def responder_hash(character_id, need, owned_by_dm)
      {
        'character_id' => character_id.to_s,
        'need' => need,
        'owned_by_dm' => truthy(owned_by_dm),
        'responded' => false,
      }
    end

    def resume_opportunity_attack_roll!(interaction)
      oa = interaction['opportunity_attack'] ||= {}
      interaction['phase'] = 'attack_roll'
      interaction['pending_responders'] = [
        responder_hash(interaction['source_id'], 'roll_attack', truthy(oa['reactor_owned_by_dm'])),
      ]
      interaction
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
