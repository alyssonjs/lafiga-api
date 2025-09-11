class CharacterResourcesService
  # Computes and optionally persists class-specific resources to Sheet.metadata.
  # For now, supports a minimal set (e.g., Barbarian Rage uses).
  def initialize(sheet)
    @sheet = sheet
  end

  def call(persist: true)
    data = (@sheet.metadata || {}).dup
    data['resources'] ||= {}

    @sheet.sheet_klasses.includes(:klass).each do |sk|
      next unless sk.klass
      api = sk.klass.api_index.to_s
      name = sk.klass.name.to_s.downcase
      if api == 'barbarian' || name.include?('bárbar') || name.include?('barbar')
        data['resources']['rage'] = barbarian_rage(sk.level.to_i)
      end
    end

    if persist
      @sheet.update!(metadata: data)
    end
    data['resources']
  end

  private

  # PHB: Rage uses per long rest: 2 (lvl1), 3 (lvl3), 4 (lvl6), 5 (lvl12), 6 (lvl17)
  def barbarian_rage(level)
    uses = case level
           when 0 then 0
           when 1..2 then 2
           when 3..5 then 3
           when 6..11 then 4
           when 12..16 then 5
           else 6
           end
    { uses: uses, recharge: 'LR' }
  end
end
