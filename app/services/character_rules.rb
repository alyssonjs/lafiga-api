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
    (sheet.sheet_klasses.sum(:level) || 0).to_i
  end

  # Modificador de habilidade
  def self.modifier(score)
    return 0 if score.nil?
    ((score.to_i - 10) / 2.0).floor
  end
end

