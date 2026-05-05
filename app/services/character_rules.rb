class CharacterRules
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

