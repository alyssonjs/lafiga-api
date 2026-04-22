class RaceProfileService
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    # Ordem de prioridade (Bug Adimael):
    #   1. metadata['race_summary'] — override explicito (admin/tooling).
    #   2. sheet.race_summary (coluna) — fonte autoritativa populada pelo
    #      CharacterProvisioningService. Pre-fix, era ignorada e cai-mos no
    #      fallback do RaceRules, que devolvia 30 ft para Wood Elf em vez
    #      dos 35 ft corretos. Cobertura: race_profile_service_spec.rb.
    #   3. Fallback derivado de RaceRules.apply (com api_index canonico).
    meta = @sheet.metadata || {}
    rs = meta['race_summary']
    return normalize(rs) if rs.present?

    column_rs = @sheet.race_summary
    return normalize(column_rs) if column_rs.is_a?(Hash) && column_rs.present?

    # Fallback: build from RaceRules if possible.
    #
    # Preferimos `api_index` (canonico, ex.: 'elf'/'wood') porque ele ja vive
    # na taxonomia que `RaceRules` consome. Caso esteja em branco (fichas
    # antigas anteriores ao seed canonico), caimos para `name.parameterize`
    # com mapeamento PT-BR -> EN. O bug original do Adimael Neverdie era
    # exatamente este fallback rodar com sub_race.name = "Elfo da Floresta",
    # virando "elfo_da_floresta" — chave que nao existia em sub_map_by_race
    # ('floresta' => 'wood' nao casava). Resultado: Wood Elf 30 ft em vez
    # de 35 ft. Cobertura: spec/services/race_profile_service_spec.rb.
    race = @sheet.race&.api_index.presence || @sheet.race&.name&.parameterize&.underscore
    sub  = @sheet.sub_race&.api_index.presence || @sheet.sub_race&.name&.parameterize&.underscore
    # Map PT-BR slugs to rule keys (YAML ids)
    race_map = {
      'anao' => 'dwarf',
      'elfo' => 'elf',
      'halfling' => 'halfling',
      'humano' => 'human',
      'draconato' => 'dragonborn',
      'gnomo' => 'gnome',
      'meio-elfo' => 'half_elf',
      'meio-orc' => 'half_orc',
      'tiefling' => 'tiefling',
      'aarakocra' => 'aarakocra',
      'centauro' => 'centaur'
    }
    sub_map_by_race = {
      'dwarf' => {
        'anao_da_montanha' => 'mountain', 'montanha' => 'mountain',
        'anao_da_colina' => 'hill', 'colina' => 'hill'
      },
      'elf' => {
        'alto_elfo' => 'high', 'alto' => 'high',
        'floresta' => 'wood',
        'drow' => 'drow', 'negro' => 'drow'
      },
      'gnome' => {
        'gnomo_da_floresta' => 'forest', 'floresta' => 'forest',
        'gnomo_das_rochas' => 'rock', 'rocha' => 'rock'
      },
      'human' => { 'variante' => 'variant' },
      'halfling' => {
        'pes_leves' => 'lightfoot', 'pés_leves' => 'lightfoot',
        'robusto' => 'stout'
      },
      'tiefling' => {
        'abissal' => 'abissal', 'ctonico' => 'ctonico', 'ctoníco' => 'ctonico', 'infernal' => 'infernal'
      },
      'aarakocra' => {
        'falconicos' => 'falconicos', 'falcônicos' => 'falconicos',
        'nocturnos' => 'nocturnos', 'cypselanos' => 'cypselanos'
      }
    }
    race = race_map[race] || race
    sub  = (sub_map_by_race[race] || {})[sub] || sub
    selection = { race_id: race, subrace_id: sub, choices: {} }
    begin
      applied = RaceRules.apply(selection)
      normalize({
        'speed_ft' => applied[:speed],
        'speed_m' => (applied[:speed].to_i * 0.3).round,
        'darkvision' => applied[:darkvision],
        'languages' => applied[:languages],
        'proficiencies' => applied[:proficiencies],
        'traits' => Array(applied[:traits]).map { |t| t[:key] }
      })
    rescue
      normalize({})
    end
  end

  private

  def normalize(rs)
    speed_ft = rs['speed_ft'] || rs[:speed_ft]
    speed_m  = rs['speed_m']  || rs[:speed_m]
    # Derivar speed_m a partir de speed_ft quando ausente (PHB: 5 ft = 1.5 m).
    # CharacterProvisioningService persiste apenas speed_ft no race_summary;
    # antes deste fallback, summary.movement.speed_m vinha nil.
    speed_m ||= (speed_ft.to_f * 0.3048).round(1) if speed_ft.to_i > 0
    {
      speed_ft: speed_ft,
      speed_m: speed_m,
      darkvision: rs['darkvision'] || rs[:darkvision],
      languages: rs['languages'] || rs[:languages] || [],
      proficiencies: rs['proficiencies'] || rs[:proficiencies] || {},
      traits: (rs['traits'] || rs[:traits] || [])
    }
  end
end
