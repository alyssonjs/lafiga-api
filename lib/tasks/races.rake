namespace :races do
  desc 'Importa/atualiza raças a partir de config/race_rules.yml sem apagar personagens'
  task import: :environment do
    puts 'Importando raças a partir de config/race_rules.yml...'

    bundle = RaceRules.reload!
    race_defs = bundle[:races] || {}
    trait_defs = bundle[:trait_definitions] || {}

    trait_records = {}
    trait_defs.each do |key, cfg|
      key_str = key.to_s
      trait = Trait.find_or_initialize_by(api_index: key_str)
      trait.name = cfg[:name].presence || key_str.titleize

      description_parts = []
      description_parts << cfg[:description].to_s.strip if cfg[:description].present?
      description_parts << "Impacto na ficha: #{cfg[:sheet_impact]}" if cfg[:sheet_impact].present?
      trait.description = description_parts.reject(&:blank?).join("\n\n")
      trait.save!
      trait_records[key.to_sym] = trait
    end

    assign_traits = lambda do |race, subrace, traits_cfg|
      Array(traits_cfg).each do |entry|
        entry_hash = entry.respond_to?(:deep_symbolize_keys) ? entry.deep_symbolize_keys : { key: entry.to_sym }
        key = entry_hash[:key]&.to_sym
        next unless key

        trait = trait_records[key] || Trait.find_or_initialize_by(api_index: key.to_s)
        trait.name ||= key.to_s.titleize
        trait.save! unless trait.persisted?
        trait_records[key] ||= trait

        RaceTrait.create!(
          race: race,
          sub_race: subrace,
          trait: trait,
          metadata: entry_hash.except(:key),
        )
      end
    end

    imported_races = 0
    imported_subraces = 0

    race_defs.each_value do |race_cfg|
      api_index = (race_cfg[:id].presence || race_cfg[:name].to_s.parameterize(separator: '_')).to_s
      race = Race.find_by(api_index: api_index) || Race.find_or_initialize_by(name: race_cfg[:name])
      race.api_index = api_index
      race.name = race_cfg[:name]
      race.playable = true if race.new_record? && race.respond_to?(:playable=)
      race.save!

      RaceTrait.where(race: race).delete_all
      assign_traits.call(race, nil, race_cfg[:traits])
      imported_races += 1

      (race_cfg[:subraces] || {}).each_value do |sub_cfg|
        sub_api_index = (sub_cfg[:id].presence || sub_cfg[:name].to_s.parameterize(separator: '_')).to_s
        subrace = SubRace.find_by(race: race, api_index: sub_api_index) ||
                  SubRace.find_or_initialize_by(race: race, name: sub_cfg[:name])
        subrace.api_index = sub_api_index
        subrace.name = sub_cfg[:name]
        subrace.playable = true if subrace.new_record? && subrace.respond_to?(:playable=)
        subrace.save!

        assign_traits.call(race, subrace, sub_cfg[:traits])
        imported_subraces += 1
      end
    end

    puts "Raças importadas: #{imported_races}; sub-raças importadas: #{imported_subraces}."
  end
end
