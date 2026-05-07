class CharacterRules
  # ============================================================
  # Constantes de regras (5e PHB) — single source of truth para a
  # pipeline de criação de personagem. Antes da consolidação, esses
  # números viviam hardcoded em vários services (abilities_step,
  # general_step, payload_builder, provisioning_service), com risco
  # de divergência (ex.: payload_builder usava `|| 8` enquanto
  # provisioning usava `|| 10` para a mesma intenção).
  # ============================================================

  # Atributos
  ABILITY_SCORE_MIN_POINT_BUY = 8       # PHB point-buy floor (escolha ativa)
  ABILITY_SCORE_MAX_POINT_BUY = 15      # PHB point-buy ceiling (antes de racial)
  ABILITY_SCORE_HARD_MAX      = 20      # Cap absoluto pré-epic (PHB)
  ABILITY_SCORE_DEFAULT       = 10      # "Safe null" — atributo neutro (mod 0)

  # Nível
  MIN_LEVEL = 1
  MAX_LEVEL = 20

  # Classe
  DEFAULT_HIT_DIE = 8                   # d8 = mediano (Bardo/Clérigo/Druida/Ladino/Monge/Patrulheiro)

  # Magias (estrutura de buckets para spellSelections no draft + provisioning)
  SPELL_SELECTION_BUCKETS = %w[cantrips known spellbook prepared].freeze

  # ============================================================

  # Calcula bônus de proficiência pelo nível total do personagem (5e PHB)
  def self.proficiency_bonus(total_level)
    case total_level.to_i
    when 1..4   then 2
    when 5..8   then 3
    when 9..12  then 4
    when 13..16 then 5
    else              6
    end
  end

  # Soma os níveis de todas as classes da sheet
  def self.total_level(sheet)
    if sheet.association(:sheet_klasses).loaded?
      sheet.sheet_klasses.sum { |sk| sk.level.to_i }
    else
      (sheet.sheet_klasses.sum(:level) || 0).to_i
    end
  end

  # Modificador de habilidade
  def self.modifier(score)
    return 0 if score.nil?
    ((score.to_i - 10) / 2.0).floor
  end

  # Normaliza qualquer forma comum de ability (PT/EN, abreviado/completo) para
  # a chave curta usada em `abilities[:mods]` (str/dex/con/int/wis/cha).
  # Retorna nil quando não reconhece o input.
  #
  # Bug original: `klass.spellcasting_ability` permitia formas como 'Inteligência'
  # ou 'Carisma' (PT-BR completo), que eram só `upcase + downcase`-ed e não
  # batiam com as chaves do hash de mods (sempre 3 letras EN). Resultado:
  # `mods[:inteligência] || 0` → 0, e Mago/Bardo/etc. ficavam com CD/atk usando
  # mod 0 — independente do INT/CHA real.
  ABILITY_NORMALIZE_MAP = {
    'STR' => 'str', 'FOR' => 'str', 'FORCA' => 'str', 'FORÇA' => 'str',
    'STRENGTH' => 'str',
    'DEX' => 'dex', 'DES' => 'dex', 'DESTREZA' => 'dex', 'DEXTERITY' => 'dex',
    'CON' => 'con', 'CONSTITUICAO' => 'con', 'CONSTITUIÇÃO' => 'con', 'CONSTITUTION' => 'con',
    'INT' => 'int', 'INTELIGENCIA' => 'int', 'INTELIGÊNCIA' => 'int', 'INTELLIGENCE' => 'int',
    'WIS' => 'wis', 'SAB' => 'wis', 'SABEDORIA' => 'wis', 'WISDOM' => 'wis',
    'CHA' => 'cha', 'CAR' => 'cha', 'CARISMA' => 'cha', 'CHARISMA' => 'cha'
  }.freeze

  def self.normalize_ability_key(raw)
    return nil if raw.nil?
    s = raw.to_s.strip.upcase
    return nil if s.blank?
    ABILITY_NORMALIZE_MAP[s]
  end
end

