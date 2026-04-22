namespace :subclasses do
  desc "Import subclass spells (always prepared) from config/subclass_spells.yml and config/subclass.yml"
  task import_spells: :environment do
    require 'yaml'
    # Aliases for class and subclass slugs in PT -> canonical api_index
    CLASS_ALIASES = {
      'guerreiro' => 'fighter'
    }.freeze
    SUBCLASS_ALIASES = {
      'barbarian' => {
        'caminho-do-furioso' => 'berserker',
        'caminho-do-guerreiro-totemico' => 'totem'
      },
      'bard' => {
        'colegio-da-bravura' => 'valor',
        'colegio-do-conhecimento' => 'lore'
      },
      'warlock' => {
        'arquifada' => 'archfey',
        'corruptor' => 'fiend',
        'grande-antigo' => 'great_old_one'
      },
      'ranger' => {
        'mestre-das-bestas' => 'beast_master'
      },
      'paladin' => {
        'juramento-de-devocao' => 'devotion',
        'juramento-dos-ancioes' => 'ancients',
        'juramento-de-vinganca' => 'vengeance'
      },
      'wizard' => {
        'escola-de-evocacao' => 'evocation'
      }
    }.freeze

    # Alias for spell PT variants -> canonical slug
    SPELL_ALIAS_PT_TO_SLUG = {
      'identificação' => 'identify',
      'augúrio' => 'augury',
      'dificultar detecção' => 'nondetection',
      'falar com os mortos' => 'speak-with-dead',
      'vidência' => 'clairvoyance',
      'golpe constritor' => 'ensnaring-strike',
      'raio lunar' => 'moonbeam',
      'passo nebuloso' => 'misty-step',
      'ampliar plantas' => 'plant-growth',
      'caminhar em árvores' => 'tree-stride',
      'crescer espinhos' => 'spike-growth',
      'convocar relâmpagos' => 'call-lightning',
      'nevasca' => 'sleet-storm',
      'controlar a água' => 'control-water',
      'onda destrutiva' => 'destructive-wave'
    }.freeze
    # Build translation maps to resolve PT names <-> slugs
    tr_path = Rails.root.join('config','dnd_translations.yml')
    tr = File.exist?(tr_path) ? (YAML.load_file(tr_path) || {}) : {}
    spell_tr = (tr['spells'] || {})
    slug_to_pt = spell_tr # e.g., 'create-or-destroy-water' => 'Criar ou Destruir Água'
    pt_to_slug = spell_tr.invert rescue {}
    # Case-insensitive PT->slug map
    pt_to_slug_ci = {}
    spell_tr.each { |slug, pt| pt_to_slug_ci[pt.to_s.downcase] = slug }

    # Helper to slugify any string
    to_slug = ->(s) {
      str = s.to_s
      ActiveSupport::Inflector.transliterate(str).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'')
    }
    # Resolve a spell by PT name or by slug; tries multiple strategies
    resolve_spell = ->(label) {
      nm = label.to_s.strip
      return nil if nm.blank?
      # 1) exact PT name
      sp = Spell.find_by(name: nm)
      return sp if sp
      # 2) by api_index directly (slug provided)
      sp = Spell.find_by(api_index: nm)
      return sp if sp
      # 3) PT alias
      alias_slug = SPELL_ALIAS_PT_TO_SLUG[nm.downcase]
      if alias_slug
        sp = Spell.find_by(api_index: alias_slug)
        return sp if sp
      end
      # 4) translations: PT -> slug (case-insensitive)
      slug = pt_to_slug[nm] || pt_to_slug_ci[nm.downcase]
      sp = slug ? Spell.find_by(api_index: slug) : nil
      return sp if sp
      # 5) slugify the PT/EN name and try api_index
      guess = to_slug.call(nm)
      sp = Spell.find_by(api_index: guess)
      return sp if sp
      # 6) last resort: case-insensitive name match
      sp = Spell.where('LOWER(name) = ?', nm.downcase).first
      return sp if sp
      nil
    }
    path = Rails.root.join('config','subclass_spells.yml')
    unless File.exist?(path)
      puts "No subclass_spells.yml found at #{path}"
      next
    end
    data = YAML.load_file(path) || {}
    total_links = 0
    data.each do |klass_api, subs|
      klass = Klass.find_by(api_index: klass_api)
      unless klass
        puts "• Skipping unknown class: #{klass_api}"
        next
      end
      subs.each do |sub_api, conf|
        sub = klass.sub_klasses.find_by(api_index: sub_api)
        unless sub
          puts "  • Skipping unknown subclass: #{klass_api}/#{sub_api}"
          next
        end
        list = Array(conf['always_prepared'])
        list.each do |row|
          name = (row['name'] || row['spell'] || row[:name] || row[:spell]).to_s
          next if name.blank?
          min_level = (row['min_level'] || row[:min_level]).to_i
          sp = resolve_spell.call(name)
          unless sp
            puts "    • Spell not found: #{name} — tried name/api_index/translations/slug"
            next
          end
          ss = SpellSource.find_or_initialize_by(source_type: 'SubKlass', source_id: sub.id, spell_id: sp.id)
          ss.always_prepared = true
          ss.min_class_level = min_level if min_level && min_level > 0
          ss.save!
          total_links += 1
          puts "    • Linked #{name} (always prepared#{min_level>0 ? ", min #{min_level}" : ''}) to #{klass_api}/#{sub_api}"
        end
      end
    end
    puts "Done. Linked #{total_links} spells to subclasses (from subclass_spells.yml)."

    # === Also import from config/subclass.yml (grants.spells.always_prepared by level) ===
    yaml_path = Rails.root.join('config','subclass.yml')
    unless File.exist?(yaml_path)
      puts "No subclass.yml found at #{yaml_path}"
      next
    end
    ydata = YAML.load_file(yaml_path) || {}

    # Helper to resolve subclasse record by api slug or by display name
    resolve_subklass = ->(klass, sub_key, sub_hash) do
      # 1) try api_index exact
      rec = klass.sub_klasses.find_by(api_index: sub_key)
      return rec if rec
      # 2) try by name equality (case-insensitive)
      name = sub_hash.is_a?(Hash) ? sub_hash['name'] : nil
      if name.present?
        rec = klass.sub_klasses.where('LOWER(name) = ?', name.to_s.downcase).first
        return rec if rec
      end
      # 3) try slugified name
      if name.present?
        guess = to_slug.call(name)
        rec = klass.sub_klasses.find_by(api_index: guess)
        return rec if rec
      end
      nil
    end

    linked_yaml = 0
    ydata.each do |klass_api, subs|
      klass_key = CLASS_ALIASES[klass_api.to_s] || klass_api
      klass = Klass.find_by(api_index: klass_api)
      unless klass
        klass = Klass.find_by(api_index: klass_key)
      end
      unless klass
        puts "• (YAML) Skipping unknown class: #{klass_api}"
        next
      end
      unless subs.is_a?(Hash)
        next
      end
      subs.each do |sub_key, sub_hash|
        # Skip non-subclass blocks (e.g., warlock boons/invocations/rules)
        next if %w[boons invocations rules].include?(sub_key.to_s)
        next unless sub_hash.is_a?(Hash)
        # Try alias for subclass first
        mapped_key = SUBCLASS_ALIASES.dig(klass.api_index.to_s, sub_key.to_s) || sub_key
        sub = resolve_subklass.call(klass, mapped_key, sub_hash)
        unless sub
          puts "  • (YAML) Skipping unknown subclass: #{klass.api_index}/#{sub_key}"
          next
        end
        # Link expanded spells for Warlock patrons (not always prepared)
        if klass.api_index.to_s == 'warlock' && sub_hash['expanded_spells'].is_a?(Hash)
          sub_hash['expanded_spells'].each do |min_lvl, arr|
            Array(arr).each do |label|
              nm = label.to_s
              next if nm.blank?
              sp = resolve_spell.call(nm)
              next unless sp
              ss = SpellSource.find_or_initialize_by(source_type: 'SubKlass', source_id: sub.id, spell_id: sp.id)
              ss.always_prepared = false
              ml = min_lvl.to_i
              ss.min_class_level = ml if ml > 0
              ss.notes = 'expanded'
              ss.save!
            end
          end
        end

        levels = Array(sub_hash['levels'])
        next if levels.empty?
        levels.each do |row|
          next unless row.is_a?(Hash)
          grants = (row['grants'] || {})
          spells = (grants['spells'] || {})
          # Ignore terrain-specific maps here (handled elsewhere)
          ap_map = spells['always_prepared']
          next unless ap_map.is_a?(Hash)
          ap_map.each do |min_lvl, list|
            Array(list).each do |label|
              name = label.to_s
              next if name.blank?
              sp = resolve_spell.call(name)
              unless sp
                puts "    • (YAML) Spell not found: #{name} — tried name/api_index/translations/slug"
                next
              end
              ss = SpellSource.find_or_initialize_by(source_type: 'SubKlass', source_id: sub.id, spell_id: sp.id)
              ss.always_prepared = true
              lvl_i = min_lvl.to_i
              ss.min_class_level = (lvl_i > 0 ? lvl_i : nil)
              ss.save!
              linked_yaml += 1
              puts "    • (YAML) Linked #{name} (always prepared#{lvl_i>0 ? ", min #{lvl_i}" : ''}) to #{klass_api}/#{sub.api_index}"
            end
          end
        end
      end
    end
    puts "Done. Linked #{linked_yaml} spells to subclasses (from subclass.yml)."
  end

end
