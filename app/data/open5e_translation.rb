# frozen_string_literal: true

# Open5eTranslation — mapas determinísticos EN→PT para importar criaturas da
# Open5e (SRD 5.1) no shape MonsterEntry (PT-BR). Aterrado nos valores DISTINTOS
# reais do snapshot `db/seeds/open5e_srd_creatures.json` (325 criaturas SRD).
#
# Só campos ESTRUTURADOS (enums finitos) — a prosa (traits/ações não-ataque) é
# traduzida na Fase 2. Ver api/OPEN5E_MONSTER_IMPORT_PLAN.md.
module Open5eTranslation
  module_function

  SIZE = {
    'tiny' => 'Minusculo', 'small' => 'Pequeno', 'medium' => 'Medio',
    'large' => 'Grande', 'huge' => 'Enorme', 'gargantuan' => 'Colossal'
  }.freeze

  # Bate 1:1 com MonsterType do front (fiend→Infernal, ooze→Limo, undead→Morto-vivo).
  TYPE = {
    'aberration' => 'Aberracao', 'beast' => 'Besta', 'celestial' => 'Celestial',
    'construct' => 'Constructo', 'dragon' => 'Dragao', 'elemental' => 'Elemental',
    'fey' => 'Fada', 'fiend' => 'Infernal', 'giant' => 'Gigante',
    'humanoid' => 'Humanoide', 'monstrosity' => 'Monstruosidade',
    'ooze' => 'Limo', 'plant' => 'Planta', 'undead' => 'Morto-vivo'
  }.freeze

  # Todas as 16 strings de alignment vistas no snapshot SRD.
  ALIGNMENT = {
    'lawful good' => 'Leal e Bom', 'neutral good' => 'Neutro e Bom',
    'chaotic good' => 'Caotico e Bom', 'lawful neutral' => 'Leal e Neutro',
    'neutral' => 'Neutro', 'chaotic neutral' => 'Caotico e Neutro',
    'lawful evil' => 'Leal e Mau', 'neutral evil' => 'Neutro e Mau',
    'chaotic evil' => 'Caotico e Mau', 'unaligned' => 'Sem Alinhamento',
    'any alignment' => 'Qualquer Alinhamento',
    'any chaotic alignment' => 'Qualquer Alinhamento',
    'any evil alignment' => 'Qualquer Alinhamento',
    'any non-good alignment' => 'Qualquer Alinhamento',
    'any non-lawful alignment' => 'Qualquer Alinhamento',
    'neutral good (50%) or neutral evil (50%)' => 'Neutro e Bom ou Neutro e Mau'
  }.freeze

  DAMAGE_TYPE = {
    'acid' => 'acido', 'bludgeoning' => 'contundente', 'cold' => 'frio',
    'fire' => 'fogo', 'lightning' => 'relampago', 'necrotic' => 'necrotico',
    'piercing' => 'perfurante', 'poison' => 'veneno', 'psychic' => 'psiquico',
    'radiant' => 'radiante', 'slashing' => 'cortante', 'thunder' => 'trovao',
    'force' => 'forca'
  }.freeze

  # As 13 condições vistas no SRD. Bate com o id EN do sistema de condições
  # (front) e o label PT usado no MonsterEntry.conditionImmunities (playbook §6).
  CONDITION = {
    'blinded' => 'cego', 'charmed' => 'encantado', 'deafened' => 'surdo',
    'exhaustion' => 'exaustao', 'frightened' => 'amedrontado',
    'grappled' => 'agarrado', 'incapacitated' => 'incapacitado',
    'invisible' => 'invisivel', 'paralyzed' => 'paralisado',
    'petrified' => 'petrificado', 'poisoned' => 'envenenado',
    'prone' => 'caido', 'restrained' => 'contido', 'stunned' => 'atordoado',
    'unconscious' => 'inconsciente'
  }.freeze

  SKILL = {
    'acrobatics' => 'Acrobacia', 'animal_handling' => 'Adestrar Animais',
    'arcana' => 'Arcanismo', 'athletics' => 'Atletismo', 'deception' => 'Enganacao',
    'history' => 'Historia', 'insight' => 'Intuicao', 'intimidation' => 'Intimidacao',
    'investigation' => 'Investigacao', 'medicine' => 'Medicina',
    'nature' => 'Natureza', 'perception' => 'Percepcao', 'performance' => 'Atuacao',
    'persuasion' => 'Persuasao', 'religion' => 'Religiao',
    'sleight_of_hand' => 'Prestidigitacao', 'stealth' => 'Furtividade',
    'survival' => 'Sobrevivencia'
  }.freeze

  # Fallbacks: se não houver mapping, devolve o próprio valor titleizado (não
  # perde dado; sinaliza que faltou um mapping para revisar).
  def size(key);      SIZE[key.to_s]            || key.to_s.capitalize; end
  def type(key);      TYPE[key.to_s]            || key.to_s.capitalize; end
  def alignment(str); ALIGNMENT[str.to_s.strip.downcase] || str.to_s;   end
  def damage(key);    DAMAGE_TYPE[key.to_s]     || key.to_s;            end
  def condition(key); CONDITION[key.to_s]       || key.to_s;            end
  def skill(key);     SKILL[key.to_s]           || key.to_s.tr('_', ' ').capitalize; end

  # pés -> metros no padrão D&D 5e (5 ft = 1,5 m => ft * 0.3), string PT ("1,5 m").
  def feet_to_meters_str(feet)
    return nil if feet.nil?
    m = (feet.to_f * 0.3)
    (m % 1).zero? ? "#{m.to_i} m" : format('%.1f m', m).tr('.', ',')
  end

  # Parseia a STRING de display (texto real do statblock, AUTORITATIVO) de
  # damage_immunities/resistances/vulnerabilities -> lista PT. Preferir sempre o
  # display ao array estruturado: o array ACHATA a clausula "from nonmagical" em
  # tipos fisicos avulsos (ex.: lista "slashing" como imunidade total quando so
  # vale p/ armas nao magicas) e as vezes inclui tipos que nem estao no display.
  #
  # Formato: segmentos separados por ";". Um segmento com "nonmagical/nonsilver"
  # e a clausula fisica; os demais sao listas de tipos por virgula/"and".
  def damage_display_list(display)
    disp = display.to_s.strip
    return [] if disp.empty?
    out = []
    disp.split(';').each do |seg|
      seg = seg.strip
      next if seg.empty?
      if seg =~ /nonmagical|nonsilver/i
        out << physical_nonmagical_pt(seg)
      else
        seg.split(/,|\band\b/i).each do |tok|
          t = tok.strip.downcase
          out << damage(t) unless t.empty?
        end
      end
    end
    out.uniq
  end

  # "[bludgeoning, piercing, and ]slashing from nonmagical attacks[ not made with
  # adamantine/silvered weapons]" -> string PT. Extrai QUAIS tipos fisicos a
  # clausula cobre (varia) e a excecao (adamantina/prateada).
  def physical_nonmagical_pt(segment)
    s = segment.to_s.downcase
    types = %w[bludgeoning piercing slashing].select { |t| s.include?(t) }.map { |t| DAMAGE_TYPE[t] }
    types = %w[contundente perfurante cortante] if types.empty?
    base = types.length > 1 ? "#{types[0..-2].join(', ')} e #{types[-1]}" : types.first
    exc = if s.include?('adamantine') then ' (exceto adamantinas)'
          elsif s.include?('silver')  then ' (exceto prateadas)'
          else ''
          end
    "#{base} de armas nao magicas#{exc}"
  end
end
