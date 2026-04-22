class StartingEquipmentService
  class << self
    CONFIG_PATH = Rails.root.join('config', 'classes_starting_equipment.yml')

    def classes_config
      @classes_config ||= begin
        if File.exist?(CONFIG_PATH)
          (YAML.safe_load(File.read(CONFIG_PATH)) || {}).with_indifferent_access
        else
          {}
        end
      end
    end

    def resolve(class_id:, background_id: nil)
      klass_key = normalize_key(class_id)
      # Prefer YAML config if present; fallback to ClassRules embedded format
      yaml_entry = begin
        classes_config.dig(:classes_starting_equipment, klass_key) ||
          classes_config.dig('classes_starting_equipment', klass_key)
      rescue
        nil
      end
      if yaml_entry
        resolved = resolve_from_yaml(yaml_entry)
        bg = resolve_background(background_id)
        rule_for_gold = begin
          ClassRules.find(klass_key)
        rescue
          {}
        end
        gold = starting_gold_for(rule_for_gold)
        return { class_id: klass_key.to_s, **resolved, background: bg, starting_gold: gold }
      end

      rule = ClassRules::CLASS_RULES[klass_key.to_sym] rescue nil
      return { error: 'class not found' } unless rule

      se = rule[:starting_equipment] || {}
      choices = Array(se[:choices]).map { |c| resolve_choice_block(c) }
      extras  = Array(se[:extras]).flat_map { |t| resolve_token_list(t) }

      bg = resolve_background(background_id)

      gold = starting_gold_for(rule)

      {
        class_id: klass_key.to_s,
        choices: choices,
        extras: extras,
        background: bg,
        starting_gold: gold
      }
    end

    # Builds starting gold info from class rule (expects rule[:starting_gold] like "2d4x10" or "5d4")
    def starting_gold_for(rule)
      return nil unless rule.is_a?(Hash)
      formula = (rule[:starting_gold] || rule['starting_gold'] || '').to_s
      return nil if formula.empty?
      m = formula.match(/(\d+)d4(?:x(\d+))?/i)
      return { formula: formula } unless m
      num = m[1].to_i
      mult = (m[2] || '1').to_i
      min_sum = num * 1
      max_sum = num * 4
      avg_sum = num * 2.5
      {
        formula: formula,
        die: 'd4',
        num: num,
        multiplier: mult,
        min_gp: (min_sum * mult).to_i,
        max_gp: (max_sum * mult).to_i,
        average_gp: (avg_sum * mult).to_i
      }
    end

    private
    # YAML structure resolver (config/classes_starting_equipment.yml)
    def resolve_from_yaml(entry)
      fixed = Array(entry[:fixed]).map do |r|
        raw_idx = normalize_key(r[:item])
        # Resolve canonical index (e.g., armadura-couro -> leather)
        canonical = EquipmentCatalog.find_index(raw_idx) rescue raw_idx
        idx = canonical || raw_idx
        {
          kind: kind_for_index(r[:item]),
          index: idx,
          name: display_name_for(idx, r[:item]),
          qty: (r[:qty] || 1).to_i
        }
      end
      choices = Array(entry[:choices]).map do |grp|
        opts = Array(grp[:or]).map do |opt|
          if opt[:item]
            raw_idx = normalize_key(opt[:item])
            # Resolve canonical index
            canonical = EquipmentCatalog.find_index(raw_idx) rescue raw_idx
            idx = canonical || raw_idx
            item_name = display_name_for(idx, opt[:item])
            {
              label: item_name,
              items: [{
                kind: kind_for_index(opt[:item]),
                index: idx,
                name: item_name,
                qty: (opt[:qty] || 1).to_i
              }],
              meta: opt
            }
          elsif opt[:tag]
            indexes = expand_tag(opt[:tag], subtype_hint: opt[:subtype_hint])
            first = indexes.first
            tag_label = tag_to_label(opt[:tag])
            items = first ? [{
              kind: kind_for_index(first),
              index: first,
              name: display_name_for(first, first),
              qty: (opt[:qty] || 1).to_i
            }] : []
            { label: tag_label, items: items, meta: opt }
          else
            { label: 'opção', items: [] }
          end
        end
        { choose: 1, options: opts, bonus: grp[:bonus] }
      end
      { choices: choices, extras: fixed }
    end

    def tag_to_label(tag)
      labels = {
        'any_simple_weapon' => 'Qualquer arma simples',
        'any_simple_melee' => 'Arma simples corpo-a-corpo',
        'any_simple_ranged' => 'Arma simples à distância',
        'any_martial_weapon' => 'Qualquer arma marcial',
        'any_martial_melee' => 'Arma marcial corpo-a-corpo',
        'any_martial_ranged' => 'Arma marcial à distância',
        'instrument' => 'Instrumento musical'
      }
      labels[tag.to_s] || tag.to_s.tr('-_', ' ').capitalize
    end

    def expand_tag(tag, subtype_hint: nil)
      case tag.to_s
      when 'any_simple_weapon' then weapon_indexes_by(filter: { category: 'simple' })
      when 'any_simple_melee' then weapon_indexes_by(filter: { category: 'simple', type: 'melee' })
      when 'any_martial_weapon' then weapon_indexes_by(filter: { category: 'martial' })
      when 'any_martial_melee' then weapon_indexes_by(filter: { category: 'martial', type: 'melee' })
      else []
      end
    end


    def normalize_key(val)
      (val || '').to_s.downcase.strip
        .gsub(' ', '-')
        .gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e')
        .gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    end

    def resolve_choice_block(block)
      {
        choose: (block[:choose] || 1).to_i,
        options: Array(block[:options]).map { |opt| resolve_option(opt) }
      }
    end

    # A single option may be a bundle joined by '+' (e.g., "leather+longbow+arrows:20")
    def resolve_option(option_str)
      parts = option_str.to_s.split('+')
      items = parts.flat_map { |p| resolve_token(p) }
      label = option_label_for(items, option_str)
      { label: label, items: items }
    end

    def humanize_option(opt)
      opt.to_s.tr('-', ' ')
    end

    # Accepts a token which may include quantity suffix ':N' and wildcards like 'simple:any'
    def resolve_token(token)
      token = token.to_s.strip
      return [] if token.empty?

      name, qty = token.split(':', 2)
      qty = qty.to_i if qty
      qty = 1 if qty.nil? || qty <= 0

      # Wildcards
      if name.include?(':any')
        base = name.sub(':any', '')
        expand_any(base).map do |idx|
          {
            kind: kind_for_index(idx),
            index: idx,
            qty: 1,
            original: name,
            name: display_name_for(idx, name)
          }
        end
      else
        canonical = begin
          EquipmentCatalog.find_index(name)
        rescue
          nil
        end
        idx = canonical || normalize_key(name)
        [{
          kind: kind_for_index(idx),
          index: idx,
          qty: qty,
          original: name,
          name: display_name_for(idx, name)
        }]
      end
    end

    # Resolve comma-separated token list inside extras (also supports '+')
    def resolve_token_list(text)
      text.to_s.split(',').flat_map { |piece|
        piece.to_s.split('+').flat_map { |t|
          resolved = resolve_token(t)
          # If it's a gear-like token we might not find a kind; keep as text
          resolved.any? ? resolved : [{ kind: 'gear', text: t.to_s.strip }]
        }
      }.compact
    end

    # Returns an array of equipment indexes for a wildcard like 'simple', 'martial-melee', etc.
    def expand_any(base)
      key = normalize_key(base)
      case key
      when 'simple', 'armas-simples'
        weapon_indexes_by(filter: { category: 'simple' })
      when 'martial', 'armas-marcial', 'armas-marcials', 'armas-marcialis', 'armas-marciais'
        weapon_indexes_by(filter: { category: 'martial' })
      when 'simple-melee'
        weapon_indexes_by(filter: { category: 'simple', type: 'melee' })
      when 'simple-ranged'
        weapon_indexes_by(filter: { category: 'simple', type: 'ranged' })
      when 'martial-melee'
        weapon_indexes_by(filter: { category: 'martial', type: 'melee' })
      when 'martial-ranged'
        weapon_indexes_by(filter: { category: 'martial', type: 'ranged' })
      when 'instrument', 'instrumento', 'instrumentos'
        [] # Frontend can handle instrument picker; not tracked in DB yet
      else
        []
      end
    end

    def kind_for_index(idx)
      k = normalize_key(idx)
      # quick heuristics based on tables and DB
      return 'weapon' if weapon_row_for(k)
      return 'armor' if armor_row_for(k)
      return 'shield' if k.include?('shield') || k.include?('escudo')
      'gear'
    end

    def option_label_for(items, fallback)
      special = fallback.to_s.strip.downcase
      special_label = {
        'simple:any' => 'Arma simples (à escolha)',
        'simple-melee:any' => 'Arma simples corpo-a-corpo (à escolha)',
        'simple-ranged:any' => 'Arma simples à distância (à escolha)',
        'martial:any' => 'Arma marcial (à escolha)',
        'martial-melee:any' => 'Arma marcial corpo-a-corpo (à escolha)',
        'martial-ranged:any' => 'Arma marcial à distância (à escolha)'
      }[special]
      return special_label if special_label

      names = items.map do |item|
        idx = item[:index]
        qty = (item[:qty] || 1).to_i
        name = item[:name] || (idx ? display_name_for(idx, item[:original]) : nil)
        name ||= item[:original] || item[:text]
        next unless name
        qty > 1 ? "#{qty}× #{name}" : name
      end.compact
      if names.any?
        names.join(' + ')
      else
        humanize_option(fallback)
      end
    end

    def display_name_for(index, fallback = nil)
      idx = normalize_key(index)
      data = EquipmentCatalog.data
      sources = %w[weapons armors gear packs tools consumables]
      
      # Use lookup that supports aliases
      sources.each do |section|
        collection = data[section]
        next unless collection.is_a?(Hash)
        row = lookup_entry_with_alias(collection, idx)
        return row['name'] if row.is_a?(Hash) && row['name']
      end
      
      # shields might be stored separately
      shields = data['shields']
      if shields.is_a?(Hash)
        row = lookup_entry_with_alias(shields, idx)
        return row['name'] if row.is_a?(Hash) && row['name']
      end
      
      # Try to find canonical index and get name from there
      canonical = EquipmentCatalog.find_index(index) rescue nil
      if canonical && canonical != idx
        return display_name_for(canonical, fallback)
      end
      
      fallback ? fallback.to_s.tr('-', ' ').split.map(&:capitalize).join(' ') : idx.tr('-', ' ').split.map(&:capitalize).join(' ')
    end
    
    def lookup_entry_with_alias(collection, key)
      return nil unless collection.is_a?(Hash)
      entry = collection[key]
      return entry if entry
      collection.each do |_slug, row|
        next unless row.is_a?(Hash)
        aliases = Array(row['aliases']).map { |a| normalize_key(a) }
        return row if aliases.include?(key)
        # Also check normalized name
        name_normalized = normalize_key(row['name']) if row['name']
        return row if name_normalized == key
      end
      nil
    end

    def weapon_indexes_by(filter: {})
      # Prefer DB
      if defined?(Item)
        scope = Item.where(kind: 'weapon')
        if filter[:category]
          scope = scope.where(category: filter[:category])
        end
        if filter[:type]
          scope = scope.where("(props->>'type') = ?", filter[:type])
        end
        return scope.order(:api_index).pluck(:api_index)
      end

      # Fallback to EquipmentRules table
      if defined?(EquipmentRules)
        table = EquipmentRules::WEAPON_TABLE rescue {}
        table.select { |_k, v|
          ok = true
          ok &&= (filter[:category].nil? || v[:category].to_s == filter[:category].to_s)
          ok &&= (filter[:type].nil? || v[:type].to_s == filter[:type].to_s)
          ok
        }.keys.sort
      else
        []
      end
    end

    def weapon_row_for(idx)
      if defined?(EquipmentRules)
        (EquipmentRules::WEAPON_TABLE rescue {})[normalize_key(idx)]
      end
    end

    def armor_row_for(idx)
      if defined?(EquipmentRules)
        (EquipmentRules::ARMOR_TABLE rescue {})[normalize_key(idx)]
      end
    end

    def resolve_background(background_id)
      return nil unless background_id
      key = normalize_key(background_id)
      path = Rails.root.join('config', 'backgrounds_phb.yml')
      return nil unless File.exist?(path)
      data = YAML.safe_load(File.read(path)) rescue nil
      return nil unless data && data['backgrounds'].is_a?(Hash)
      bg = data['backgrounds'][key]
      return { id: key } unless bg

      # Normalize structured entries like { item: "Roupas finas", qty: 1, container: "cinto" }
      entries = Array(bg['starting_equipment']).map do |row|
        if row.is_a?(Hash)
          {
            item: (row['item'] || row[:item]).to_s,
            qty: ((row['qty'] || row[:qty] || 1).to_i),
            container: (row['container'] || row[:container])
          }
        else
          { item: row.to_s, qty: 1, container: nil }
        end
      end

      extras_text = entries.map { |e| e[:item].to_s }
      choices_text = Array(bg['starting_equipment_options']).map(&:to_s)

      # Extract coin amounts from structured items like "Algibeira (15 po)"
      coins = 0
      coin_lines = []
      entries.each do |e|
        str = e[:item].to_s
        str.scan(/(\d+)\s*po\b/i) do |m|
          val = m[0].to_i
          coins += val
          coin_lines << str
        end
      end

      # Build structured extras for the frontend: [{ text, qty }]
      # Filter out flavor/descriptive items that are not real equipment
      flavor_patterns = [
        /\(à escolha\)/i,
        /\(p\.ex\./i,
        /\(por exemplo/i,
        /lembrança de admirador/i,
        /ricordação/i,
        /carta de colega/i,
        /token/i,
        /bugiganga/i
      ]
      
      extras_items = entries.filter_map do |e|
        text = e[:item].to_s
        
        # Skip flavor items (descriptive, not real equipment)
        is_flavor = flavor_patterns.any? { |pattern| text.match?(pattern) }
        next nil if is_flavor
        
        qty  = (e[:qty].to_i > 0 ? e[:qty].to_i : 1)
        idx  = begin
          EquipmentCatalog.find_index(text)
        rescue
          nil
        end
        entry = { text: text, qty: qty }
        if idx
          entry[:index] = idx
          entry[:item_index] = idx
          entry[:name] = display_name_for(idx, text)
        end
        entry
      end

      {
        id: key,
        name: bg['name'],
        extras_text: extras_text,
        choices_text: choices_text,
        coins_gp: (coins > 0 ? coins : nil),
        coins_text: coin_lines,
        extras_structured: extras_items
      }
    rescue
      nil
    end
  end
end
