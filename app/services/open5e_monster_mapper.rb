# frozen_string_literal: true

# Open5eMonsterMapper — PORO. Converte UMA criatura da Open5e v2 (SRD 5.1) numa
# linha no shape `MonsterEntry` (PT-BR) que o `MonsterEngineSyncService` consome.
#
# Decisões (ver api/OPEN5E_MONSTER_IMPORT_PLAN.md):
#  - Escopo SRD 5.1 (OGL); atribuição obrigatória em payload.attribution.
#  - Campos estruturados traduzidos p/ PT (Open5eTranslation); prosa fica EN na
#    Fase 1 (name/nameEN + traits/ações não-ataque), com `*EN` guardado.
#  - Ataque: o `attacks[].damage_type` da Open5e é NÃO confiável → parseamos o
#    `desc` (template SRD) para os dados de combate; guardamos o cru em `attacksRaw`.
class Open5eMonsterMapper
  ATTRIBUTION = {
    'source' => 'Open5e',
    'document' => 'System Reference Document 5.1',
    'document_key' => 'srd-2014',
    'publisher' => 'Wizards of the Coast',
    'license' => 'OGL-1.0a',
    'permalink' => 'https://dnd.wizards.com/resources/systems-reference-document'
  }.freeze

  ABILITY = {
    'strength' => 'str', 'dexterity' => 'dex', 'constitution' => 'con',
    'intelligence' => 'int', 'wisdom' => 'wis', 'charisma' => 'cha'
  }.freeze

  def self.call(creature)
    new(creature).call
  end

  def initialize(creature)
    @c = creature || {}
  end

  def call
    ri = @c['resistances_and_immunities'] || {}
    row = {
      'id'       => slug,
      'name'     => name, # EN (tradução PT do nome é Fase 2)
      'nameEN'   => name,
      'size'     => T.size(dig(@c, 'size', 'key')),
      'type'     => T.type(dig(@c, 'type', 'key')),
      'alignment' => T.alignment(@c['alignment']),
      'ac'       => @c['armor_class'],
      'acType'   => presence(@c['armor_detail']),
      'hp'       => @c['hit_points'],
      'hitDice'  => presence(@c['hit_dice']),
      'speed'    => speed,
      'stats'    => stats,
      'savingThrows' => saving_throws,
      'skills'   => skills,
      'damageResistances'     => damages(ri['damage_resistances'], ri['damage_resistances_display']),
      'damageImmunities'      => damages(ri['damage_immunities'], ri['damage_immunities_display']),
      'damageVulnerabilities' => damages(ri['damage_vulnerabilities'], ri['damage_vulnerabilities_display']),
      'conditionImmunities'   => condition_immunities(ri['condition_immunities']),
      'senses'   => senses,
      'languages' => languages,
      'cr'       => cr_string(@c['challenge_rating']),
      'xp'       => @c['experience_points'],
      'traits'   => traits,
      'source'   => 'open5e',
      'attribution' => ATTRIBUTION
    }.merge(actions_buckets)

    compact(row)
  end

  private

  T = Open5eTranslation

  def slug
    key = @c['key'].to_s.sub(/\Asrd[_-]/, '')
    "open5e-#{key}"
  end

  def name
    @c['name'].to_s.strip
  end

  def cr_string(f)
    return '0' if f.nil?
    case f
    when 0.125 then '1/8'
    when 0.25 then '1/4'
    when 0.5 then '1/2'
    else f == f.to_i ? f.to_i.to_s : f.to_s
    end
  end

  def stats
    src = @c['ability_scores'] || {}
    ABILITY.each_with_object({}) { |(en, pt), h| h[pt] = src[en] if src[en] }
  end

  def speed
    src = @c['speed_all'] || @c['speed'] || {}
    out = {}
    %w[walk fly swim climb burrow].each do |k|
      v = src[k]
      out[k] = v if v.is_a?(Numeric) && v.positive?
    end
    out['hover'] = true if src['hover'] == true
    out
  end

  # saving_throws traz só os proficientes (o *_all traz todos os mods).
  def saving_throws
    src = @c['saving_throws'] || {}
    ABILITY.each_with_object({}) { |(en, pt), h| h[pt] = src[en] if src[en] }
  end

  def skills
    (@c['skill_bonuses'] || {}).each_with_object({}) do |(k, v), h|
      h[T.skill(k)] = v
    end
  end

  # O display string (texto real do statblock) é AUTORITATIVO: o array
  # estruturado da Open5e achata "X from nonmagical attacks" em "X" (imunidade
  # total) e às vezes lista tipos ausentes do display. Só caímos no array quando
  # não há display. Ver T.damage_display_list.
  def damages(arr, display)
    disp = display.to_s.strip
    return T.damage_display_list(disp) unless disp.empty?

    (arr || []).map { |it| T.damage(it['key'] || it['name']&.downcase) }.uniq
  end

  def condition_immunities(arr)
    (arr || []).map { |it| T.condition(it['key'] || it['name']&.downcase) }.uniq
  end

  def senses
    out = {}
    { 'darkvision' => 'darkvision_range', 'blindsight' => 'blindsight_range',
      'tremorsense' => 'tremorsense_range', 'truesight' => 'truesight_range' }.each do |pt, src|
      v = @c[src]
      out[pt] = v if v.is_a?(Numeric) && v.positive?
    end
    out['passivePerception'] = @c['passive_perception'] || 10
    out
  end

  def languages
    str = @c.dig('languages', 'as_string') || @c['languages_as_string']
    return [] if str.to_s.strip.empty?
    str.split(',').map(&:strip).reject(&:empty?)
  end

  def traits
    (@c['traits'] || []).map do |t|
      { 'name' => t['name'], 'description' => t['desc'], 'descriptionEN' => t['desc'] }
    end
  end

  # Split por action_type: ACTION→actions, REACTION→reactions,
  # LEGENDARY_ACTION→legendaryActions.actions, BONUS_ACTION→bonusActions.
  def actions_buckets
    buckets = Hash.new { |h, k| h[k] = [] }
    (@c['actions'] || []).sort_by { |a| a['order_in_statblock'] || 0 }.each do |a|
      row = build_action(a)
      case a['action_type']
      when 'REACTION'         then buckets['reactions'] << row
      when 'LEGENDARY_ACTION' then buckets['legendary'] << row
      when 'BONUS_ACTION'     then buckets['bonusActions'] << row
      else buckets['actions'] << row
      end
    end
    out = {}
    out['actions']      = buckets['actions']
    out['reactions']    = buckets['reactions'] if buckets['reactions'].any?
    out['bonusActions'] = buckets['bonusActions'] if buckets['bonusActions'].any?
    if buckets['legendary'].any?
      out['legendaryActions'] = { 'description' => legendary_desc, 'actions' => buckets['legendary'] }
    end
    out
  end

  def legendary_desc
    'A criatura pode realizar acoes lendarias, escolhendo entre as opcoes abaixo. ' \
    'So uma opcao de acao lendaria pode ser usada por vez e apenas no fim do turno ' \
    'de outra criatura. A criatura recupera as acoes lendarias gastas no inicio do seu turno.'
  end

  def build_action(a)
    parsed = parse_attack(a['desc'].to_s)
    row = { 'name' => a['name'], 'descriptionEN' => a['desc'] }
    if parsed
      row['description'] = parsed[:pt]
      row['attack'] = parsed[:attack]
    else
      row['description'] = a['desc'] # prosa: EN na Fase 1
    end
    raw = a['attacks']
    row['attacksRaw'] = raw if raw.is_a?(Array) && raw.any?
    row
  end

  # Parseia o template SRD do `desc` (fonte confiável) → dados de combate + PT.
  def parse_attack(desc)
    head = desc.match(/\A(Melee or Ranged|Melee|Ranged)\s+(?:Weapon|Spell)\s+Attack:\s*([+-]\d+)\s+to hit/i)
    return nil unless head

    kind = head[1].downcase
    kind = if kind.start_with?('melee or') then 'melee_or_ranged'
           elsif kind.start_with?('ranged') then 'ranged'
           else 'melee'
           end
    to_hit = head[2].to_i
    reach_ft = desc[/reach\s+(\d+)\s*ft/i, 1]&.to_i
    range = desc.match(/range\s+(\d+)\/(\d+)\s*ft/i)

    # Dado entre parênteses é OPCIONAL: bestas CR 0 têm dano fixo ("Hit: 1
    # piercing damage" sem "(NdM)"). Se não houver "N ... damage", não é ataque
    # de dano (ex.: "Hit: the creature is grappled") → fica como prosa.
    hit = desc.match(/Hit:\s*(\d+)\s*(?:\(([0-9]+d[0-9]+(?:\s*[+-]\s*[0-9]+)?)\)\s*)?(\w+)\s+damage/i)
    return nil unless hit

    dmg = { 'avg' => hit[1].to_i, 'type' => T.damage(hit[3].downcase) }
    dmg['dice'] = hit[2].gsub(/\s+/, '') if hit[2]
    extra = nil
    if (em = desc.match(/plus\s+(\d+)\s*(?:\(([0-9]+d[0-9]+)\)\s*)?(\w+)\s+damage/i))
      extra = { 'avg' => em[1].to_i, 'type' => T.damage(em[3].downcase) }
      extra['dice'] = em[2] if em[2]
    end

    attack = { 'kind' => kind, 'toHit' => to_hit, 'damage' => dmg }
    attack['reach'] = T.feet_to_meters_str(reach_ft) if reach_ft
    if range
      attack['range'] = T.feet_to_meters_str(range[1].to_i)
      attack['longRange'] = T.feet_to_meters_str(range[2].to_i)
    end
    attack['extra'] = extra if extra

    { attack: attack, pt: pt_attack_line(desc, kind, to_hit, reach_ft, range, dmg, extra) }
  end

  def pt_attack_line(desc, kind, to_hit, reach_ft, range, dmg, extra)
    kind_pt = case kind
              when 'ranged' then 'Ataque a Distancia com Arma'
              when 'melee_or_ranged' then 'Ataque Corpo a Corpo ou a Distancia com Arma'
              else 'Ataque Corpo a Corpo com Arma'
              end
    dist = []
    dist << "alcance #{T.feet_to_meters_str(reach_ft)}" if reach_ft
    dist << "distancia #{T.feet_to_meters_str(range[1].to_i)}/#{T.feet_to_meters_str(range[2].to_i)}" if range
    hit_str = dmg['dice'] ? "#{dmg['avg']} (#{dmg['dice']}) #{dmg['type']}" : "#{dmg['avg']} #{dmg['type']}"
    if extra
      hit_str += extra['dice'] ? ", mais #{extra['avg']} (#{extra['dice']}) #{extra['type']}" : ", mais #{extra['avg']} #{extra['type']}"
    end
    line = "#{kind_pt}: #{to_hit >= 0 ? '+' : ''}#{to_hit} para acertar, #{dist.join(' ou ')}, um alvo. Acerto: #{hit_str}."
    rider = desc[/damage\.\s*(.+)\z/im, 1]
    rider ? "#{line} #{rider.strip}" : line # rider em EN (Fase 2 traduz)
  end

  # helpers
  def dig(h, *ks); ks.reduce(h) { |m, k| m.is_a?(Hash) ? m[k] : nil }; end
  def presence(v); v.to_s.strip.empty? ? nil : v; end

  # Campos que o tipo MonsterEntry do front trata como OBRIGATÓRIOS — sempre
  # emitir, mesmo vazios, senão o modal quebra (ex.: `languages.length` de
  # undefined). `stats`/`senses` nunca vêm vazios, mas listar é inócuo.
  ALWAYS_EMIT = %w[actions languages speed stats senses].freeze

  def compact(h)
    h.each_with_object({}) do |(k, v), out|
      next if v.nil?
      next if v.respond_to?(:empty?) && v.empty? && !ALWAYS_EMIT.include?(k)
      out[k] = v
    end
  end
end
