# Converts a Character#draft_data blob (per-step shape, see CharacterDraftSchema)
# into the {character:, wizard:} payload that CharacterProvisioningService consumes.
#
# This is the SERVER-SIDE replacement for front-lafiga/src/services/draftToProvisionPayload.ts.
# When the wizard finishes, the frontend calls POST /character_drafts/:id/provision with
# no body — the controller passes `from_server_draft: true`, and the provisioning service
# uses this builder to materialize the legacy payload from `character.draft_data`.
#
# Conservative: we resolve numeric DB ids when present, fall back to api_index when
# the draft stored a string slug, and pass through arbitrary fields untouched.
class CharacterDraftPayloadBuilder
  ABILITY_KEYS = %w[str dex con int wis cha].freeze

  # Erro distinto para chamada com draft inutilizável. Permite que callers
  # (controller, service) capturem só este caso e devolvam mensagem precisa
  # ao invés do "Validation failed: Name can't be blank" genérico do AR.
  class IncompleteDraftError < ArgumentError; end

  # Campos mínimos que o `CharacterProvisioningService` exige para conseguir
  # `Character#save!` sem violar validações. Mantemos a lista pequena para
  # não bloquear chamadas legítimas durante criação parcial (ex.: teste BDD
  # que provê só name+background); mais validações ficam no service em si.
  REQUIRED_DRAFT_FIELDS = %w[name background].freeze

  def self.build(character)
    new(character).build
  end

  def initialize(character)
    @character = character
    @draft     = CharacterDraftSchema.migrate(character.draft_data || {})
  end

  def build
    wizard = {
      'meta'       => meta_block,
      'race'       => race_block,
      'background' => background_block,
      'klass'      => klass_block,
      'equipment'  => equipment_block,
      'avatar'     => avatar_block,
      'spells'     => spells_block
    }
    gen = general_block
    wizard['general'] = gen if gen.present?

    payload = {
      'character' => character_block,
      'wizard'    => wizard
    }
    assert_minimum_payload!(payload)
    payload
  end

  private

  attr_reader :character, :draft

  def character_block
    {
      'id'         => character.id,
      'name'       => draft['name'],
      'background' => draft.dig('selectedBackground', 'name') || draft['_bgName'],
      # Status do Character ao concluir o wizard: provisão final = active.
      # Usar Rails enum em vez de string solta blinda contra renomeação.
      'status'     => Character.statuses['active']
    }.compact
  end

  def meta_block
    {
      'name'         => draft['name'],
      'alignmentKey' => alignment_api_key
    }.compact
  end

  # Mesmas chaves que GeneralEditService / contrato do front (`wizard.general`).
  def general_block
    gen = {}
    %w[playerName isNPC npcRole npcFaction npcLocation npcStatus dmNotes].each do |k|
      next unless draft.key?(k)

      v = draft[k]
      if k == 'isNPC'
        gen[k] = ActiveModel::Type::Boolean.new.cast(v)
        next
      end
      next if v.nil?

      gen[k] = v
    end
    gen
  end

  def race_block
    base = ability_scores
    bonuses = race_bonuses
    final = base.transform_values.with_index do |v, _|
      v.to_i
    end
    # Apply bonuses on top of baseAttributes for `attributes`
    attributes = ABILITY_KEYS.each_with_object({}) do |k, h|
      h[k] = final[k].to_i + bonuses[k].to_i
    end

    {
      'raceId'         => numeric_or_nil(draft.dig('selectedRace', 'id') || draft['_raceId']),
      # subRaceId aceita string slug PT/EN (ex.: "Drow") quando o front não tem
      # id numérico — o provisioning resolve depois via api_index/nome.
      'subRaceId'      => numeric_or_nil(subrace_identifier) || subrace_identifier,
      'ruleId'         => race_api_index,
      'subRuleId'      => sub_race_api_index,
      'raceChoices'    => draft['raceChoices'] || {},
      'attributes'     => attributes,
      'baseAttributes' => base,
      'abilityBonuses' => bonuses
    }.compact
  end

  def background_block
    {
      'backgroundKey'    => background_api_key,
      'backgroundName'   => draft.dig('selectedBackground', 'name') || draft['_bgName'],
      'backgroundProfs'  => draft['backgroundToolChoices'].to_a + draft['backgroundLanguageChoices'].to_a,
      'backgroundIdeals' => draft['backgroundIdeals'].to_a,
      'backgroundBonds'  => draft['backgroundBonds'].to_a,
      'backgroundFlaws'  => draft['backgroundFlaws'].to_a,
      'backgroundPersonalityTraits' => draft['backgroundPersonalityTraits'].to_a
    }.compact
  end

  def klass_block
    {
      'klassId'           => numeric_or_nil(draft.dig('selectedClass', 'id') || draft['_classId']),
      'klassRuleSlug'     => klass_api_index,
      'level'             => (draft['level'] || 1).to_i,
      # classSubclassId pode ser:
      #   - id numérico do banco (admin/edit), ou
      #   - slug PT/EN (ex.: "circulo-vida"), ou
      #   - nome PT exibido no wizard (ex.: "Círculo da Vida").
      # Mantemos string adiante quando não for numérico — CharacterProvisioningService#resolve_subclass_id
      # tenta SubklassSlugResolver.normalize, depois api_index e por fim busca por nome.
      'classSubclassId'   => numeric_or_nil(subclass_identifier) || subclass_identifier,
      'classSkillPicks'   => Array(draft['classSkillPicks']) + Array(draft['selectedSkills']),
      'classPicksByLevel' => class_picks_by_level
    }.compact
  end

  # `selectedSubclass` pode estar persistido como:
  #   - hash legado salvo pelo ClassStepService:  { 'id' => 'Círculo da Vida' }
  #   - string nua vinda de drafts/restore antigo: 'Círculo da Vida'
  #   - nil
  def subclass_identifier
    raw = draft['selectedSubclass']
    return raw.presence if raw.is_a?(String)
    return nil unless raw.is_a?(Hash)
    (raw['id'] || raw['name']).to_s.presence
  end

  def subrace_identifier
    raw = draft['selectedSubrace']
    return raw.presence if raw.is_a?(String)
    return nil unless raw.is_a?(Hash)
    (raw['id'] || raw['name']).to_s.presence
  end

  def class_picks_by_level
    out = {}
    out['1'] = (draft['level1Choices'] || {}).deep_dup
    out['1']['skills'] = Array(draft['selectedSkills']) if draft['selectedSkills'].present?
    if draft['level1HpChoice'].present?
      out['1']['hp'] = draft['level1HpChoice'].is_a?(Hash) ? draft['level1HpChoice'].deep_dup : draft['level1HpChoice']
    end
    Array(draft['levelChoices']).each do |row|
      next unless row.is_a?(Hash)
      lv = row['level'].to_i
      next unless lv >= 2
      # Front grava `asiChoice` (com `featGrantChoices`); CharacterSheetSummaryService
      # e CharacterProvisioningService leem `asi` (com `choices`). Sem essa traducao
      # os ASIs nao sao aplicados aos atributos finais e os talentos perdem suas
      # escolhas (ex.: pericias do Perito).
      out[lv.to_s] = LevelChoiceNormalizer.normalize_row(row).except('level')
    end
    out
  end

  def equipment_block
    {
      'equipmentMode'    => draft['equipmentMode'],
      'equipmentChoices' => draft['equipmentChoices'] || [],
      'equipmentGenericSelections' => draft['equipmentGenericSelections'] || {},
      'startingGoldRolled' => draft['startingGoldRolled']
    }.compact
  end

  def avatar_block
    {
      'customization' => draft['avatarCustomization'] || {}
    }
  end

  def spells_block
    draft['spellSelections'] || {}
  end

  def ability_scores
    src = draft['abilityScores'] || {}
    # Quando o jogador NÃO escolheu nenhum atributo no draft, caímos no piso
    # do point-buy (PHB) — o jogador pode pagar 0 pontos para ficar com tudo
    # em 8. Constante canônica em `CharacterRules`.
    ABILITY_KEYS.each_with_object({}) do |k, h|
      h[k] = (src[k] || CharacterRules::ABILITY_SCORE_MIN_POINT_BUY).to_i
    end
  end

  def race_bonuses
    # 1) Forma explícita: cliente que já manda `abilityBonuses` no draft.
    raw = draft.dig('raceChoices', 'abilityBonuses') || dig_field('selectedRace', 'abilityBonuses')
    if raw.is_a?(Hash) && raw.present?
      return ABILITY_KEYS.each_with_object({}) { |k, h| h[k] = (raw[k] || 0).to_i }
    end

    # 2) D3 — derivar da REGRA canônica (fixos) + `chosenAbilities` (escolhidos),
    # em paridade com `buildProvisionPayload`/`parseRacialBonuses` do front. O
    # `RaceChoices` do FE NÃO preenche `abilityBonuses` (usa `chosenAbilities:
    # string[]`); sem isto, o caminho server-draft perdia o +1/+1 escolhido do
    # Meio-Elfo / Humano Variante e os bônus fixos de qualquer raça.
    chosen = Array(draft.dig('raceChoices', 'chosenAbilities'))
    derived = begin
      applied = RaceRules.apply(race_id: race_api_index, subrace_id: sub_race_api_index, choices: {})
      RaceRules.ability_bonuses(applied[:ability], chosen_abilities: chosen)
    rescue StandardError => e
      Rails.logger.warn("CharacterDraftPayloadBuilder#race_bonuses: #{e.class}: #{e.message}")
      {}
    end
    ABILITY_KEYS.each_with_object({}) { |k, h| h[k] = (derived[k] || 0).to_i }
  end

  def race_api_index
    rid = numeric_or_nil(dig_field('selectedRace', 'id') || draft['_raceId'])
    return dig_field('selectedRace', 'ruleSlug') unless rid
    Race.find_by(id: rid)&.api_index
  end

  def sub_race_api_index
    raw_id = subrace_identifier
    sid = numeric_or_nil(raw_id)
    if sid.nil?
      # Sem id numérico: devolve o identificador textual como melhor esforço de slug.
      return dig_field('selectedSubrace', 'ruleSlug') || raw_id
    end
    SubRace.find_by(id: sid)&.api_index
  end

  def klass_api_index
    kid = numeric_or_nil(dig_field('selectedClass', 'id') || draft['_classId'])
    return dig_field('selectedClass', 'ruleSlug') unless kid
    Klass.find_by(id: kid)&.api_index
  end

  def background_api_key
    bid = numeric_or_nil(draft['_bgId'] || dig_field('selectedBackground', 'id'))
    return draft['_bgName'] unless bid
    Background.find_by(id: bid)&.api_index
  end

  def alignment_api_key
    aid = numeric_or_nil(draft['_alignId'] || dig_field('selectedAlignment', 'id'))
    return dig_field('selectedAlignment', 'api_index') unless aid
    Alignment.find_by(id: aid)&.api_index
  end

  def numeric_or_nil(v)
    return nil if v.blank?
    s = v.to_s
    return nil unless s.match?(/\A\d+\z/)
    s.to_i
  end

  # Defensive helper para campos `selectedRace`/`selectedSubrace`/`selectedClass`
  # /`selectedSubclass`/`selectedBackground`/`selectedAlignment` que historicamente
  # foram gravados pelo front em DOIS formatos:
  #   * Hash {id, name, ruleSlug, ...} (formato atual)
  #   * String "Humano Padrão" (formato legado, ainda presente em chars antigos
  #     como #9; ver tmp/test_provision_runtime.rb)
  # Sem este guard, `draft.dig('selectedSubrace', 'ruleSlug')` levanta
  # `TypeError: String does not have #dig method` no provisioning.
  def dig_field(key, *path)
    val = draft[key]
    return nil unless val.is_a?(Hash)
    val.dig(*path)
  end

  # Falha cedo com mensagem precisa quando o draft não tem os campos mínimos.
  # Sem isso, o `Character#save!` no provisioning service quebra com "Name
  # can't be blank, Background can't be blank" — mensagem técnica que esconde
  # a causa real (draft_data vazio em char active, ver
  # `character_drafts_controller#provision`).
  #
  # Gap G11.1 do relatorio de auditoria de steps: antes so checava
  # `name` e `background` e confiava no frontend para garantir que race,
  # classe, atributos, etc. estavam presentes. Resultado: drafts corrompidos
  # (state perdido por bug do front, save corrompido em localStorage,
  # client antigo) chegavam ao `CharacterProvisioningService` e quebravam
  # com mensagem generica do AR la dentro. Agora rejeitamos cedo no
  # builder com `IncompleteDraftError` listando TODOS os campos faltantes
  # (nao so o primeiro), facilitando o front exibir o que falta.
  def assert_minimum_payload!(payload)
    missing = []
    missing << 'name'       if payload.dig('character', 'name').to_s.strip.empty?
    missing << 'background' if payload.dig('character', 'background').to_s.strip.empty?

    race = payload.dig('wizard', 'race') || {}
    if race['raceId'].blank? && race['ruleId'].blank?
      missing << 'race'
    end

    klass = payload.dig('wizard', 'klass') || {}
    if klass['klassId'].blank? && klass['klassRuleSlug'].blank?
      missing << 'class'
    end

    level = klass['level'].to_i
    missing << 'class.level' if level < 1

    base_scores = race['baseAttributes'] || {}
    if ABILITY_KEYS.any? { |k| base_scores[k].to_i <= 0 }
      missing << 'abilityScores'
    end

    return if missing.empty?

    raise IncompleteDraftError,
          "draft_data incompleto: faltam #{missing.join(', ')} — character " \
          "##{character.id} (status=#{character.status}). Em chars ativos " \
          'use PATCH /character_drafts/:id em modo edit para alterar dados; ' \
          '/provision exige draft_data completo.'
  end
end
