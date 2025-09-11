class KnownSpellsAggregator
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    known = SheetKnownSpell.joins(:spell, :sheet_klass).where(sheet_klasses: { sheet_id: @sheet.id })
    by_level = Hash.new { |h,k| h[k] = [] }
    catalog = {}
    known.each do |ks|
      sp = ks.spell
      by_level[sp.level.to_i] << { id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, description: sp.desc }
      catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
    end

    if by_level.empty?
      per = (@sheet.metadata || {}).dig('class_choices', 'per_level') || {}
      per.values.each do |row|
        (row['cantrips'] || []).each do |sp|
          level = (sp['level'] || 0).to_i
          name  = sp['name'] || sp['id']
          by_level[level] << { id: nil, name: name }
        end
        (row['spells'] || []).each do |sp|
          level = (sp['level'] || 1).to_i
          name  = sp['name'] || sp['id']
          by_level[level] << { id: nil, name: name }
        end
      end

      # Enrich fallback entries with description (best-effort) and fill catalog
      names = by_level.values.flatten.map { |h| h[:name] }.compact.uniq
      unless names.empty?
        Spell.where(name: names).find_each do |sp|
          # Update any entry with this name
          by_level.each_value do |arr|
            arr.each do |entry|
              next unless entry[:name] == sp.name
              entry[:id] ||= sp.id
              entry[:desc] = sp.desc
              entry[:higher_level] = sp.higher_level
              entry[:description] = sp.desc
            end
          end
          catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
        end
      end
    end

    { known_by_level: by_level, catalog_by_id: catalog }
  end
end
