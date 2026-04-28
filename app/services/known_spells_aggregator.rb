require 'set'
class KnownSpellsAggregator
  # Ao snapshotar só `metadata.spell_selections` para conjuradores known, preservar
  # magias materializadas com fonte fora da classe (raça / talento / antecedente).
  # Inclui `subclass` para magias de patrono/lista extra ainda não espelhadas em `spell_selections`
  # após override — evita sumir do summary e mantém `known_source` para chips na ficha.
  NON_CLASS_KNOWN_SOURCES = %w[race feat background subclass].freeze

  # Expõe no summary (`known_by_level`) para a ficha mostrar chip (RAÇA, SUBCLASSE, …).
  def self.known_source_chip_key(raw)
    s = raw.to_s.strip.downcase
    return nil if s.blank? || s == 'class'
    s
  end

  def initialize(sheet)
    @sheet = sheet
  end

  def call
    known = SheetKnownSpell.includes(:spell, :sheet_klass).joins(:sheet_klass).where(sheet_klasses: { sheet_id: @sheet.id })
    by_level = Hash.new { |h,k| h[k] = [] }
    catalog = {}
    seen_ids = Set.new
    spell_selections_overrode_known = false
    known.each do |ks|
      sp = ks.spell
      next if seen_ids.include?(sp.id)
      seen_ids.add(sp.id)
      src = self.class.known_source_chip_key(ks.source)
      row = { id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, description: sp.desc }
      row[:sheet_known_spell_id] = ks.id
      row[:known_source] = src if src
      by_level[sp.level.to_i] << row
      catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
    end

    # Personagens "known" (Ranger, Bruxo, Bardo, etc.): o summary deve refletir
    # `metadata.spell_selections`, que o wizard de Progressão grava após o PATCH.
    # `SheetKnownSpell` pode ficar defasado quando `sync_sheet_known_spells_from_spell_selections!`
    # não rodou (ex.: Spellcasting ausente no ClassLevel antes do fix) ou por corrida.
    begin
      pk = @sheet.sheet_klasses.includes(:klass).order(level: :desc).first
      if pk&.klass
        k = pk.klass
        unless k.api_index.to_s == 'wizard'
          rules = k.api_index.present? ? (ClassRules.find(k.api_index) || {}) : {}
          prep_mode = rules.dig(:feature_rules, :spellcasting, :mode).to_s
          prep_legacy = rules.dig(:spellcasting, :preparation).to_s
          casting_known = prep_mode == 'known' || prep_legacy == 'known'
          if casting_known
            meta_sel = (@sheet.metadata || {}).deep_stringify_keys['spell_selections']
            if meta_sel.is_a?(Hash) && (meta_sel.key?('known') || meta_sel.key?('cantrips'))
              sel_resolver = SpellResolver.new
              new_by_level = Hash.new { |h, kk| h[kk] = [] }
              new_catalog = {}
              new_seen = Set.new
              %w[cantrips known].each do |key|
                next unless meta_sel.key?(key)
                Array(meta_sel[key]).each do |tok|
                  sp = sel_resolver.resolve(tok)
                  next unless sp
                  next if new_seen.include?(sp.id)
                  new_seen.add(sp.id)
                  lvl = sp.level.to_i
                  ks_row = SheetKnownSpell.find_by(sheet_klass_id: pk.id, spell_id: sp.id)
                  chip = self.class.known_source_chip_key(ks_row&.source)
                  row = { id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, description: sp.desc }
                  row[:sheet_known_spell_id] = ks_row.id if ks_row
                  row[:known_source] = chip if chip
                  new_by_level[lvl] << row
                  new_catalog[sp.id] = { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
                end
              end

              SheetKnownSpell.includes(:spell, :sheet_klass).joins(:sheet_klass)
                .where(sheet_klasses: { sheet_id: @sheet.id }, source: NON_CLASS_KNOWN_SOURCES)
                .find_each do |ks|
                  sp = ks.spell
                  next unless sp
                  next if new_seen.include?(sp.id)
                  new_seen.add(sp.id)
                  lvl = sp.level.to_i
                  chip = self.class.known_source_chip_key(ks.source)
                  row = { id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, description: sp.desc }
                  row[:sheet_known_spell_id] = ks.id
                  row[:known_source] = chip if chip
                  new_by_level[lvl] << row
                  new_catalog[sp.id] = { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
                end

              by_level = new_by_level
              catalog = new_catalog
              seen_ids = new_seen
              spell_selections_overrode_known = true
            end
          end
        end
      end
    rescue StandardError
      # mantém agregação via SheetKnownSpell
    end

    if by_level.empty? && !spell_selections_overrode_known
      per = (@sheet.metadata || {}).dig('class_choices', 'per_level') || {}
      per.values.each do |row|
        (row['cantrips'] || []).each do |sp|
          level = (sp['level'] || 0).to_i
          name  = sp['name'] || sp['id']
          entry = { id: nil, name: name }
          by_level[level] << entry unless by_level[level].any? { |e| (e[:id] && entry[:id] && e[:id] == entry[:id]) || e[:name] == entry[:name] }
        end
        (row['spells'] || []).each do |sp|
          level = (sp['level'] || 1).to_i
          name  = sp['name'] || sp['id']
          entry = { id: nil, name: name }
          by_level[level] << entry unless by_level[level].any? { |e| (e[:id] && entry[:id] && e[:id] == entry[:id]) || e[:name] == entry[:name] }
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

    # Merge Magical Secrets and other front-end selections from metadata to ensure
    # they appear in the summary even if not yet persisted to SheetKnownSpell.
    #
    # Phase 12 (causa raiz spells): toda a logica de lookup id/name/lower/slug/
    # translation/aliases agora vive em SpellResolver (compartilhado com
    # LevelUpService). O cache local (por id, por nome lower, por api_index)
    # eh do proprio resolver — uma instancia por call() = O(1) query por chave
    # unica nesta request.
    spell_resolver = SpellResolver.new
    begin
      meta = (@sheet.metadata || {})
      per = (meta.dig('class_choices', 'per_level') || {})

      insert_entry = lambda do |sp_obj|
        return unless sp_obj
        sid   = sp_obj[:id]
        sname = sp_obj[:name]
        sdesc = sp_obj[:desc]
        shl   = sp_obj[:higher_level]
        lvl   = (sp_obj[:level] || 0).to_i
        lvl = 0 if lvl < 0
        exists = by_level[lvl].any? do |e|
          (sid && e[:id] && e[:id].to_i == sid.to_i) || (sname && e[:name] == sname)
        end
        return if exists
        by_level[lvl] << { id: sid, name: sname, desc: sdesc, higher_level: shl, description: sdesc }
        catalog[sid] ||= { id: sid, name: sname, level: lvl, desc: sdesc, higher_level: shl } if sid
      end

      resolve_meta_entry = lambda do |item|
        lvl_hint = item.is_a?(Hash) ? (item['level'] || item[:level]) : nil
        sp = spell_resolver.resolve(item)
        if sp
          { id: sp.id, name: sp.name, level: (lvl_hint || sp.level).to_i, desc: sp.desc, higher_level: sp.higher_level }
        else
          # Best-effort fallback quando nem o resolver achou — exibe so o nome cru.
          # SpellResolver nao loga warn aqui (eh leitura, nao escrita); quem deveria
          # ter resolvido isso eh o LevelUpService. Esta entrada vai aparecer "torta"
          # na ficha — usuario deve corrigir o nome ou adicionar alias.
          sname = item.is_a?(Hash) ? (item['name'] || item[:name] || item['id'] || item[:id]) : item
          sname.present? ? { id: nil, name: sname.to_s, level: (lvl_hint || 0).to_i, desc: nil, higher_level: nil } : nil
        end
      end

      unless spell_selections_overrode_known
        per.values.each do |row|
          next unless row.is_a?(Hash)
          Array(row['cantrips']).each              { |it| insert_entry.call(resolve_meta_entry.call(it)) }
          Array(row['spells']).each                { |it| insert_entry.call(resolve_meta_entry.call(it)) }
          Array(row['learn_any_class_spells']).each { |it| insert_entry.call(resolve_meta_entry.call(it)) }
        end
      end
    rescue => _e
      # ignore metadata merge issues; summary will still carry persisted known
    end

    # Prepared spells (including always-prepared já existentes como registros)
    prepared_by_level = Hash.new { |h,k| h[k] = [] }
    # Helper to upsert a prepared entry and mark flags (always_prepared, circle)
    upsert_prepared = lambda do |spell_obj, opts = {}|
      return unless spell_obj
      sid = spell_obj[:id]
      sname = spell_obj[:name]
      sdesc = spell_obj[:desc]
      shl = spell_obj[:higher_level]
      lvl = (spell_obj[:level] || 0).to_i
      lvl = 0 if lvl < 0
      list = prepared_by_level[lvl]
      if sid
        existing = list.find { |e| e[:id].to_i == sid.to_i }
      else
        existing = list.find { |e| e[:name].to_s == sname.to_s }
      end
      if existing
        # Upgrade flags if this source indicates them
        if opts[:always]
          existing[:always_prepared] = true
        end
        if opts[:circle]
          existing[:circle] = true
        end
        # Enrich description if missing
        existing[:desc] ||= sdesc
        existing[:higher_level] ||= shl
        existing[:description] ||= sdesc
      else
        list << {
          id: sid,
          name: sname,
          desc: sdesc,
          higher_level: shl,
          description: sdesc,
          always_prepared: !!opts[:always],
          circle: !!opts[:circle]
        }
      end
    end
    SheetPreparedSpell.where(sheet_id: @sheet.id).includes(:spell).find_each do |ps|
      sp = ps.spell
      next unless sp
      lvl = sp.level.to_i
      upsert_prepared.call({ id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, level: sp.level }, { always: !!ps.auto })
      catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
    end

    # Incluir auto-prepared derivados (Subclasse por terreno e SpellSource) mesmo
    # quando ainda não materializados em SheetPreparedSpell
    begin
      to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }
      # Phase 12: mesmo SpellResolver da secao anterior — partilham cache via
      # `spell_resolver` declarado acima (1 instancia por call()). Devolve um
      # Hash compativel com `upsert_prepared` ou nil.
      resolve_spell = lambda do |label|
        nm = label.to_s.strip
        return nil if nm.blank?
        sp = spell_resolver.resolve(nm)
        return nil unless sp
        { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
      end

      present_ids = Set.new
      prepared_by_level.each_value do |arr|
        Array(arr).each { |e| present_ids.add(e[:id]) if e[:id] }
      end
      meta = (@sheet.metadata || {})
      per_level = (meta.dig('class_choices','per_level') || {})
      chosen_terrain = begin
        key = nil
        per_level.values.each do |row|
          v = row['terrain'] || row[:terrain] || row['terreno'] || row[:terreno]
          next unless v
          key = (v.is_a?(Hash) ? (v['id'] || v[:id] || v['name'] || v[:name]) : v)
          break if key
        end
        key ? to_slug.call(key) : nil
      rescue
        nil
      end

      @sheet.sheet_klasses.includes(:klass, :sub_klass).each do |sk|
        lvl = (sk.level || 1).to_i
        # Sources de classe/subclasse normais
        ids = SpellSource
                .where(source_type: 'Klass', source_id: sk.klass_id, always_prepared: true)
                .where('min_class_level IS NULL OR min_class_level <= ?', lvl)
                .pluck(:spell_id)
        if sk.sub_klass_id
          ids |= SpellSource
                  .where(source_type: 'SubKlass', source_id: sk.sub_klass_id, always_prepared: true)
                  .where('min_class_level IS NULL OR min_class_level <= ?', lvl)
                  .pluck(:spell_id)
        end

        unless ids.empty?
          spells_by_id = Spell.where(id: ids.uniq).index_by(&:id)
          ids.each do |sid|
            sp = spells_by_id[sid]
            next unless sp
            upsert_prepared.call({ id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, level: sp.level }, { always: true })
            catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
            present_ids.add(sp.id)
          end
        end

        # Subclasse: always_prepared_by_terrain via levels_json (ex.: Druida Terra)
        begin
          sub = sk.sub_klass
          if sub&.levels_json.present? && chosen_terrain
            rows = JSON.parse(sub.levels_json) rescue []
            rows = Array(rows).select { |r| r.is_a?(Hash) && (r['level'].to_i <= lvl) }
            names = []
            rows.each do |r|
              buckets = []
              buckets << r if r['grants'].is_a?(Hash)
              feats = Array(r['features']).select { |f| f.is_a?(Hash) }
              feats.each { |f| buckets << f if f['grants'].is_a?(Hash) }
              buckets.each do |node|
                spells = (node.dig('grants','spells') || {})
                terr = (spells['always_prepared_by_terrain'] || {})
                next unless terr[chosen_terrain]
                terr_map = terr[chosen_terrain] || {}
                terr_map.keys.map(&:to_i).sort.each do |k|
                  next if k > lvl
                  Array(terr_map[k.to_s]).each { |nm| names << nm }
                end
              end
            end
            names.uniq.each do |nm|
              sp = resolve_spell.call(nm)
              next unless sp
              upsert_prepared.call(sp.merge(level: sp[:level] || sp[:lvl]), { always: true, circle: true })
              if sp[:id]
                catalog[sp[:id]] ||= { id: sp[:id], name: sp[:name], level: sp[:level], desc: sp[:desc], higher_level: sp[:higher_level] }
                present_ids.add(sp[:id])
              end
            end
          end
        rescue => _e
        end

        # Fallback adicional: YAML (config/subclass_overrides.yml)
        # - always_prepared
        # - always_prepared_by_terrain (quando chosen_terrain estiver presente)
        begin
          next unless sk.sub_klass && sk.sub_klass.api_index.present?
          ypath = Rails.root.join('config','subclass_overrides.yml')
          if File.exist?(ypath)
            yml = YAML.load_file(ypath) || {}
            cls_key = sk.klass.api_index.to_s
            sub_key = sk.sub_klass.api_index.to_s
            ent = yml.dig(cls_key, sub_key)
            if ent.nil?
              cls_block = yml[cls_key]
              if cls_block.is_a?(Hash)
                ent = cls_block.values.find do |row|
                  row.is_a?(Hash) && row['name'] && sk.sub_klass.name && row['name'].to_s.downcase == sk.sub_klass.name.to_s.downcase
                end
              end
            end
            if ent && ent['levels']
              ent['levels'].each do |row|
                rlevel = (row['level'] || 0).to_i
                next if rlevel <= 0 || rlevel > lvl
                # grants may appear at row level or inside features
                buckets = []
                buckets << row if row['grants'].is_a?(Hash)
                feats = Array(row['features']).select { |f| f.is_a?(Hash) }
                feats.each { |f| buckets << f if f['grants'].is_a?(Hash) }
                buckets.each do |node|
                  spells = (node.dig('grants','spells') || {})
                  # 1) always_prepared simples
                  ap = (spells['always_prepared'] || {})
                  ap.each do |min_lvl, list|
                    ml = min_lvl.to_i
                    next if ml > lvl
                    Array(list).each do |nm|
                      sp = resolve_spell.call(nm)
                      next unless sp
                      upsert_prepared.call(sp, { always: true })
                      if sp[:id]
                        catalog[sp[:id]] ||= { id: sp[:id], name: sp[:name], level: (sp[:level] || 0).to_i, desc: sp[:desc], higher_level: sp[:higher_level] }
                        present_ids.add(sp[:id])
                      end
                    end
                  end
                  # 2) always_prepared_by_terrain (Círculo da Terra)
                  terr = (spells['always_prepared_by_terrain'] || {})
                  if chosen_terrain && terr[chosen_terrain]
                    terr_map = terr[chosen_terrain] || {}
                    terr_map.each do |min_lvl, list|
                      ml = min_lvl.to_i
                      next if ml > lvl
                      Array(list).each do |nm|
                        sp = resolve_spell.call(nm)
                        next unless sp
                        upsert_prepared.call(sp, { always: true, circle: true })
                        if sp[:id]
                          catalog[sp[:id]] ||= { id: sp[:id], name: sp[:name], level: (sp[:level] || 0).to_i, desc: sp[:desc], higher_level: sp[:higher_level] }
                          present_ids.add(sp[:id])
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        rescue => _e
        end
      end
    rescue => _e
      # ignore derivation errors; summary will still include explicit prepared entries
    end

    merge_mystic_arcanum_into_catalog!(@sheet, catalog)

    { known_by_level: by_level, prepared_by_level: prepared_by_level, catalog_by_id: catalog }
  end

  # Arcano místico do bruxo vive em metadata (mystic_arcanum_6…), muitas vezes só como spell_id
  # numérico — não vira SheetKnownSpell. O front usa spells.catalog_by_id para mostrar o nome.
  def merge_mystic_arcanum_into_catalog!(sheet, catalog)
    ids = mystic_arcanum_spell_ids_from_metadata(sheet)
    return if ids.empty?

    Spell.where(id: ids).find_each do |sp|
      catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
    end
  end

  def mystic_arcanum_spell_ids_from_metadata(sheet)
    per = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
    return [] if per.blank?

    ids = []
    per.each_value do |row|
      next unless row.is_a?(Hash)

      [row, row['featureChoices']].compact.each do |h|
        next unless h.is_a?(Hash)

        h.each do |k, v|
          next unless k.to_s.match?(/\Amystic_arcanum_\d+\z/i)

          Array(v).each { |tok| ids.concat(spell_token_to_positive_ids(tok)) }
        end
      end
    end
    ids.map(&:to_i).select(&:positive?).uniq
  end

  def spell_token_to_positive_ids(tok)
    case tok
    when Integer
      tok.positive? ? [tok] : []
    when String
      s = tok.strip
      s.match?(/\A\d+\z/) ? [s.to_i] : []
    when Hash
      sid = tok['id'] || tok[:id]
      spell_token_to_positive_ids(sid)
    else
      []
    end
  end
end
