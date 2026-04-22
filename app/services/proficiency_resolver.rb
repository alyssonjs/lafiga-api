class ProficiencyResolver
  class << self
    # Normalize text: downcase, remove accents, replace spaces with dashes
    def normalize(text)
      t = (text || '').to_s.downcase.strip
      t = I18n.transliterate(t) rescue t
      t.gsub('  ', ' ').gsub(' ', '-')
    end

    # Resolve armor categories from a heterogeneous list of strings
    # Returns Set["light","medium","heavy","shields"]
    def resolve_armor_categories(list)
      require 'set'
      set = Set.new
      Array(list).each do |raw|
        t = (raw || '').to_s.downcase
        next if t.empty?

        # direct mentions (pt/en)
        set << 'light'   if t.include?('leve') || t.include?('light')
        set << 'medium'  if t.include?('média') || t.include?('media') || t.include?('medium')
        set << 'heavy'   if t.include?('pesad') || t.include?('heavy')
        set << 'shields' if t.include?('escudo') || t.include?('escudos') || t.include?('shield')

        # if it's an armor item name/index, infer from catalog/tables
        begin
          idx = EquipmentCatalog.normalize_index(OpenStruct.new(item_index: raw)) rescue normalize(raw)
          row = EquipmentCatalog.armor_row(idx) rescue nil
          row ||= EquipmentRules::ARMOR_TABLE[idx] rescue nil
          if row && row[:cat]
            set << row[:cat].to_s
          end
        rescue; end
      end

      # Try database Items as fallback (if present)
      begin
        Array(list).each do |raw|
          n = normalize(raw)
          item = Item.find_by(api_index: n)
          next unless item && item.kind.to_s == 'armor'
          cat = (item.category || item.props.dig('armor','cat') rescue nil)
          set << cat.to_s if cat.present?
        end
      rescue; end

      set
    end

    # Resolve weapon categories and specific items.
    # Returns hash: { cats: Set["simple","martial","melee","ranged"], props: Set["light","finesse",...], items: Set[api_index] }
    def resolve_weapons(list)
      require 'set'
      cats  = Set.new
      props = Set.new
      items = Set.new

      Array(list).each do |raw|
        t = (raw || '').to_s.downcase
        next if t.empty?

        # broad categories (pt/en)
        cats << 'simple' if t.include?('simples') || t.include?('simple')
        cats << 'martial' if t.include?('marciais') || t.include?('marcial') || t.include?('martial')
        cats << 'melee' if t.include?('corpo') || t.include?('melee')
        cats << 'ranged' if t.include?('distância') || t.include?('distancia') || t.include?('ranged')

        # properties common words
        props << 'light' if t.include?('leve') || t.include?('light')
        props << 'finesse' if t.include?('finesse')
        props << 'heavy' if t.include?('pesada') || t.include?('heavy')
        props << 'reach' if t.include?('alcance') || t.include?('reach')
        props << 'thrown' if t.include?('arremesso') || t.include?('thrown')
        props << 'loading' if t.include?('carregamento') || t.include?('loading')
        props << 'versatile' if t.include?('versátil') || t.include?('versatil') || t.include?('versatile')

        # try equipment catalog exact matches (aliases inclusive)
        begin
          idx = EquipmentCatalog.normalize_index(OpenStruct.new(item_index: raw)) rescue normalize(raw)
          if EquipmentRules::WEAPON_TABLE.key?(idx)
            items << idx
            row = EquipmentRules::WEAPON_TABLE[idx]
            cats << row[:category].to_s if row[:category]
            cats << row[:type].to_s if row[:type]
            %i[light finesse heavy reach loading thrown versatile].each do |p|
              props << p.to_s if row[p]
            end
          elsif EquipmentCatalog.data['weapons'][idx]
            items << idx
            w = EquipmentCatalog.data['weapons'][idx]
            cats << w['category'].to_s if w['category']
            cats << w['type'].to_s if w['type']
            Array(w['properties']).each { |p| props << normalize(p) }
          else
            # Attempt loose alias match by name
            EquipmentCatalog.data['weapons'].each do |k, w|
              name = (w['name'] || '').to_s.downcase
              if name == raw.to_s.downcase
                items << k
                cats << w['category'].to_s if w['category']
                cats << w['type'].to_s if w['type']
                Array(w['properties']).each { |p| props << normalize(p) }
                break
              end
            end
          end
        rescue; end
      end

      # Fallback: DB items
      begin
        Array(list).each do |raw|
          n = normalize(raw)
          item = Item.find_by(api_index: n)
          next unless item && item.kind.to_s == 'weapon'
          items << item.api_index
          cats << item.category.to_s if item.category.present?
          Array(item.tags).each do |tg|
            st = tg.to_s
            cats << st if %w[simple martial melee ranged].include?(st)
            props << st if %w[light finesse heavy reach loading thrown versatile].include?(st)
          end
        end
      rescue; end

      { cats: cats, props: props, items: items }
    end
  end
end


