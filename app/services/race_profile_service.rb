class RaceProfileService
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    meta = @sheet.metadata || {}
    rs = meta['race_summary']
    if rs.present?
      return normalize(rs)
    end

    # Fallback: build from RaceRules if possible
    race = @sheet.race&.name&.parameterize&.underscore
    sub  = @sheet.sub_race&.name&.parameterize&.underscore
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
    {
      speed_ft: rs['speed_ft'] || rs[:speed_ft],
      speed_m: rs['speed_m'] || rs[:speed_m],
      darkvision: rs['darkvision'] || rs[:darkvision],
      languages: rs['languages'] || rs[:languages] || [],
      proficiencies: rs['proficiencies'] || rs[:proficiencies] || {},
      traits: (rs['traits'] || rs[:traits] || [])
    }
  end
end

