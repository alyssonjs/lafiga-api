namespace :equipment do
  desc 'Upsert items (weapons/armors/shields/gear/etc) from equipment.yml (fallback EquipmentRules) into the database'
  task import_items: :environment do
    require 'yaml'

    catalog = begin
      EquipmentCatalog.data
    rescue => e
      puts "[warn] EquipmentCatalog unavailable: #{e.message}"
      {}
    end

    WeaponSections = %w[weapons].freeze
    ArmorSections  = %w[armors].freeze
    ShieldSections = %w[shields].freeze
    GearSections   = %w[gear packs tools consumables].freeze

    titleize = ->(slug) { slug.to_s.tr('-', ' ').split.map { |w| w.present? ? w[0].upcase + w[1..] : w }.join(' ') }

    normalize_props = ->(value) do
      return {} unless value
      if value.respond_to?(:deep_stringify_keys)
        value.deep_stringify_keys
      elsif value.respond_to?(:stringify_keys)
        value.stringify_keys
      else
        value
      end
    end

    upsert = lambda do |slug, attrs|
      # Strategy: Use YAML slug as api_index (keep Portuguese identifiers)
      # Store English aliases in props for lookup purposes
      
      slug_str = slug.to_s
      aliases = Array(attrs[:aliases]).compact.map(&:to_s)
      
      # Use the slug from YAML as primary index
      api_index = EquipmentCatalog.normalize_index(slug_str)
      
      item = Item.find_or_initialize_by(api_index: api_index)
      props = normalize_props.call(attrs.delete(:props) || attrs.delete(:props_json))
      # Store aliases in props for lookup
      props['aliases'] = aliases if aliases.any?
      attrs.delete(:aliases)
      attrs[:props] = props.presence
      attrs[:tags]  = Array(attrs[:tags]).reject(&:blank?).presence
      item.assign_attributes(attrs.compact)
      item.save! if item.changed?
      item
    end

    count = Hash.new(0)

    if catalog.present?
      WeaponSections.each do |section|
        (catalog[section] || {}).each do |slug, row|
          next unless row.is_a?(Hash)
          props = Array(row['properties']).map { |p| p.to_s.downcase }
          upsert.call(slug, {
            name: row['name'],
            aliases: row['aliases'], # Pass aliases to upsert
            kind: 'weapon',
            category: row['category'],
            weight_kg: row['weight_kg'],
            props: {
              'type' => row['type'],
              'hands' => (row['hands'] || (props.include?('two-handed') ? 2 : 1)).to_i,
              'damage_die' => row['damage_die'],
              'versatile_die' => row['versatile_die'],
              'range' => row['range'],
              'light' => props.include?('light'),
              'finesse' => props.include?('finesse'),
              'heavy' => props.include?('heavy'),
              'thrown' => props.include?('thrown') || props.include?('arremesso'),
              'loading' => props.include?('loading'),
              'reach' => props.include?('reach') || props.include?('alcance'),
              'special' => props.include?('special'),
              'versatile' => props.include?('versatile') || props.include?('versatil'),
              'ammunition' => (row['type'] == 'ranged' && !props.include?('thrown') && !props.include?('arremesso')),
              'cost_cp' => row['cost_cp']
            }
          })
          count[:weapon] += 1
        end
      end

      ArmorSections.each do |section|
        (catalog[section] || {}).each do |slug, row|
          next unless row.is_a?(Hash)
          upsert.call(slug, {
            name: row['name'],
            aliases: row['aliases'], # Pass aliases to upsert
            kind: 'armor',
            category: row['cat'],
            weight_kg: row['weight_kg'],
            props: {
              'ac_base' => row['base'],
              'dex_cap' => row['dex_cap'],
              'stealth_dis' => !!row['stealth_dis'],
              'str_req' => row['str_req'],
              'cost_cp' => row['cost_cp']
            }
          })
          count[:armor] += 1
        end
      end

      shield_payload = catalog['shields']
      shield_list = case shield_payload
                    when Hash then shield_payload.to_a
                    when Array then shield_payload.map { |slug| [slug, {}] }
                    else []
                    end
      shield_list.each do |slug, row|
        row ||= {}
        upsert.call(slug, {
          name: row['name'] || titleize.call(slug),
          kind: 'shield',
          category: 'shield',
          weight_kg: row['weight_kg'],
          props: {
            'ac_bonus' => row['ac_bonus'] || 2,
            'cost_cp' => row['cost_cp']
          }
        })
        count[:shield] += 1
      end

      GearSections.each do |section|
        (catalog[section] || {}).each do |slug, row|
          next unless row.is_a?(Hash)
          # Map 'pack' to 'gear' since Item enum doesn't have 'pack'
          raw_kind = row['kind'] || section.singularize
          kind = raw_kind == 'pack' ? 'gear' : raw_kind
          category = row['category'] || section.singularize
          props = normalize_props.call(row['props'] || {})
          props['cost_cp'] ||= row['cost_cp'] if row['cost_cp']
          props['contents'] ||= row['contents'] if row['contents']
          upsert.call(slug, {
            name: row['name'],
            aliases: row['aliases'], # Pass aliases to upsert
            kind: kind,
            category: category,
            weight_kg: row['weight_kg'],
            description: row['description'] || row['notes'],
            props: props
          })
          count[kind.to_sym] += 1
        end
      end
    end

    summary = count.keys.sort.map { |k| "#{k}=#{count[k]}" }.join(', ')
    puts "Imported/updated items → #{summary.presence || 'none'}"
  rescue => e
    puts "[error] equipment:import_items failed: #{e.class}: #{e.message}"
    raise
  end
end
