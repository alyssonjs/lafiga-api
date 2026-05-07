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
    raw_race = @sheet.race&.api_index.presence || @sheet.race&.name&.parameterize&.underscore
    raw_sub  = @sheet.sub_race&.api_index.presence || @sheet.sub_race&.name&.parameterize&.underscore

    # Tradução PT-BR → canônico delegada a `RaceRules`. Antes, este service
    # mantinha um `race_map` e `sub_map_by_race` paralelos que precisavam ser
    # sincronizados manualmente com `RaceRules.{RACE,SUBRACE}_KEY_ALIASES` —
    # risco de divergência ao adicionar nova raça/sub-raça (ex.: tabaxi não
    # estava no mapa local). Single source of truth: `race_rules.rb`.
    race = RaceRules.normalize_race_key(raw_race)
    sub  = RaceRules.canonical_subrace_key(race, raw_sub)
    selection = { race_id: race, subrace_id: sub, choices: {} }
    begin
      applied = RaceRules.apply(selection)
      # speed_m: usar fator PHB exato (1 ft = 0,3048 m) com 1 casa decimal,
      # idêntico ao fallback de `normalize`. Antes, o call usava `* 0.3` e
      # `round` (0 casas), gerando 9 m em vez de 9.1 m para 30 ft. Resultado
      # era inconsistente quando race_summary continha speed_m (caminho do
      # call) vs apenas speed_ft (caminho do normalize fallback).
      speed_ft = applied[:speed].to_i
      normalize({
        'speed_ft' => applied[:speed],
        'speed_m' => (speed_ft * 0.3048).round(1),
        # Darkvision no YAML é Hash `{range: N}`; normalizar antes de propagar
        # para o consumer evita vazamento do Hash quando o fallback dispara
        # (race_summary vazio em fichas legadas).
        'darkvision' => RaceRules.normalize_range(applied[:darkvision]),
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

    # Darkvision pode vir como Integer (caminho normal — CPS persiste assim
    # após o fix) OU como Hash {range: N} (fichas legadas, override em
    # metadata, fallback do RaceRules.apply quando race_summary está vazio).
    # Sempre devolvemos Integer para o consumer.
    raw_dv = rs['darkvision'] || rs[:darkvision]
    {
      speed_ft: speed_ft,
      speed_m: speed_m,
      darkvision: RaceRules.normalize_range(raw_dv),
      languages: rs['languages'] || rs[:languages] || [],
      proficiencies: rs['proficiencies'] || rs[:proficiencies] || {},
      traits: (rs['traits'] || rs[:traits] || [])
    }
  end
end
