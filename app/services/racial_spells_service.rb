# frozen_string_literal: true

# Service para aplicar magias inatas de raças/sub-raças aos personagens
# Exemplos:
# - Drow: Luz Dançante (1), Fogo das Fadas (3), Escuridão (5)
# - Tiefling: Thaumaturgy (1), Hellish Rebuke (3), Darkness (5)
# - High Elf: 1 cantrip de Wizard à escolha
#
# Uso:
#   RacialSpellsService.call(sheet: sheet, race_rule: race_rule, character_level: 5)
class RacialSpellsService
  prepend SimpleCommand

  def initialize(sheet:, race_rule:, character_level: nil)
    @sheet = sheet
    @race_rule = race_rule
    @character_level = character_level || CharacterRules.total_level(@sheet)
  end

  def call
    innate_spells = collect_innate_spells
    return @sheet if innate_spells.empty?

    primary_sk = @sheet.sheet_klasses.order(level: :desc).first
    
    unless primary_sk
      Rails.logger.warn "RacialSpellsService: No sheet_klass found for sheet #{@sheet.id}"
      return @sheet
    end

    applied_count = 0

    innate_spells.each do |spell_entry|
      spell = find_spell(spell_entry[:name])
      
      unless spell
        Rails.logger.warn "RacialSpellsService: Spell not found: #{spell_entry[:name]}"
        next
      end

      # Criar ou atualizar SheetKnownSpell
      sheet_known_spell = SheetKnownSpell.find_or_initialize_by(
        sheet_klass: primary_sk,
        spell: spell
      )

      # Se já existe com source diferente, não sobrescrever
      if sheet_known_spell.persisted? && sheet_known_spell.source != 'race'
        Rails.logger.info "RacialSpellsService: Spell #{spell.name} already known from #{sheet_known_spell.source}"
        next
      end

      sheet_known_spell.assign_attributes(
        source: 'race',
        gained_at_class_level: spell_entry[:unlocked_at_level],
        uses_per_rest: spell_entry[:uses], # 'LR', 'SR', ou nil
        uses_remaining: calculate_initial_uses(spell_entry[:uses])
      )

      if sheet_known_spell.save
        applied_count += 1
        Rails.logger.info "RacialSpellsService: Applied #{spell.name} (level #{spell.level}) to #{@sheet.character.name}"
      else
        Rails.logger.warn "RacialSpellsService: Failed to save #{spell.name}: #{sheet_known_spell.errors.full_messages.join(', ')}"
      end
    end

    Rails.logger.info "RacialSpellsService: Applied #{applied_count} racial spells to character level #{@character_level}"
    @sheet
  end

  private

  def collect_innate_spells
    results = []
    
    # Race base innate spells
    process_innate_spells_array(@race_rule[:innate_spells], results)
    
    results
  end

  def process_innate_spells_array(innate_spells_array, results)
    Array(innate_spells_array).each do |entry|
      req_level = (entry[:level] || entry['level'] || 1).to_i
      next if @character_level < req_level
      
      spells_list = entry[:spells] || entry['spells']
      ability = entry[:ability] || entry['ability'] || 'CHA'
      # Default LR only when the rule omits `uses`; explicit nil = unlimited (cantrips)
      uses = if entry.key?(:uses)
               entry[:uses]
             elsif entry.key?('uses')
               entry['uses']
             else
               'LR'
             end
      
      Array(spells_list).each do |spell_name|
        results << {
          name: spell_name,
          ability: ability,
          uses: uses,
          unlocked_at_level: req_level
        }
      end
    end
  end

  def find_spell(spell_name)
    # Tentar busca exata primeiro
    spell = Spell.find_by(name: spell_name)
    return spell if spell

    # Tentar busca case-insensitive
    spell = Spell.find_by('LOWER(name) = ?', spell_name.to_s.downcase)
    return spell if spell

    # Tentar remover acentos e caracteres especiais (best effort)
    normalized = spell_name.to_s.downcase.gsub(/[áàâã]/, 'a').gsub(/[éèê]/, 'e').gsub(/[íì]/, 'i').gsub(/[óòôõ]/, 'o').gsub(/[úù]/, 'u').gsub(/[ç]/, 'c')
    Spell.find_by('LOWER(name) SIMILAR TO ?', "%#{normalized}%")
  end

  def calculate_initial_uses(uses_per_rest)
    case uses_per_rest&.to_s&.upcase
    when 'LR', 'LONG_REST'
      1 # Magias raciais geralmente são 1x por descanso longo
    when 'SR', 'SHORT_REST'
      1 # Se fosse short rest, também 1x
    else
      0 # Cantrips não têm usos limitados
    end
  end
end

