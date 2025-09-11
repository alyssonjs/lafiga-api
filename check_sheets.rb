# Verificar sheets criadas
sheets = Sheet.all
puts "Sheets existentes: #{sheets.count}"
sheets.each do |s|
  puts "- Sheet ID: #{s.id}, Personagem: #{s.character.name}, Nível: #{s.current_level}"
  puts "  Raça: #{s.race.name}, Alinhamento: #{s.alignment&.name}, Antecedente: #{s.background&.name}"
  puts "  Colunas normalizadas: alignment_id=#{s.alignment_id}, background_id=#{s.background_id}, current_level=#{s.current_level}"
  puts "  Race choices: #{s.race_choices.present? ? 'presente' : 'ausente'}"
  puts "  Class choices: #{s.class_choices.present? ? 'presente' : 'ausente'}"
  puts "  Race summary: #{s.race_summary.present? ? 'presente' : 'ausente'}"
  puts "  Class summary: #{s.class_summary.present? ? 'presente' : 'ausente'}"
  puts "  Features by level: #{s.features_by_level.present? ? 'presente' : 'ausente'}"
  puts "  Race bonuses: #{s.race_bonuses_applied.present? ? 'presente' : 'ausente'}"
  puts "---"
end
