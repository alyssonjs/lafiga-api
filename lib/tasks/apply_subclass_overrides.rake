# frozen_string_literal: true

require 'yaml'

# Task independente para aplicar apenas os overrides/grants de subclasses a partir do YAML local
# Não baixa nada da API e não recria ClassLevels

module DndImportHelpers
  module_function

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
      # Aliases canonicos para SubKlasses do Patrulheiro:
      # - 'cacador' (PT-BR para Hunter PHB) -> 'hunter' (api_index SRD).
      # - 'batedor' (Scout XGtE) NAO eh alias de Hunter — sao subclasses
      #   distintas. Antes do fix do bug do Adimael, ambos `cacador` e
      #   `batedor` aliasavam para 'hunter', sobrescrevendo Hunter e deixando
      #   Batedor sem grants. Cobertura: subclasses/sync_features_from_levels_json_service_spec.rb
      'cacador' => 'hunter',
      'mestre-das-bestas' => 'beast_master'
    },
    'sorcerer' => {
      'linhagem-draconica' => 'draconic',
      'magia-selvagem' => 'wild'
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

  def load_yaml_overrides
    path = Rails.root.join('config','subclass_overrides.yml')
    return {} unless File.exist?(path)
    YAML.load_file(path) || {}
  rescue
    {}
  end

  def load_yaml_main
    path = Rails.root.join('config','subclass.yml')
    return {} unless File.exist?(path)
    YAML.load_file(path) || {}
  rescue
    {}
  end

  def merged_overrides
    over = load_yaml_overrides

    # Only subclass_overrides.yml is the source of truth here
    normalized = {}
    (over || {}).each do |klass_key, val|
      canon = CLASS_ALIASES[klass_key.to_s] || klass_key
      next unless val.is_a?(Hash)
      normalized[canon] ||= {}
      normalized[canon] = (normalized[canon] || {}).merge(val) { |_k, a, b| (a || {}).merge(b || {}) }
    end
    normalized
  end

  # Deduplicate SubKlass records per Klass.
  # Agrupa por api_index e também por slug(name) para capturar duplicatas com índices diferentes.
  # Mantém o registro com api_index definido (ou o menor id) e migra relacionamentos dos demais.
  def dedup_subclasses!(klass)
    to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }
    list = klass.sub_klasses.to_a
    # 1) Por slug do nome
    by_slug = list.group_by { |sk| to_slug.call(sk.name) }
    # 2) Por api_index (quando presente)
    by_idx  = list.select { |sk| sk.api_index.present? }.group_by { |sk| sk.api_index }

    # Helper para consolidar um grupo de duplicatas
    consolidate = lambda do |arr|
      arr = Array(arr).compact.uniq { |sk| sk.id }
      return if arr.size <= 1
      keep = arr.find { |sk| sk.api_index.present? } || arr.min_by(&:id)
      (arr - [keep]).each do |dup|
        next if dup.id == keep.id
        begin
          SubKlassLevel.where(sub_klass_id: dup.id).update_all(sub_klass_id: keep.id)
          SpellSource.where(source_type: 'SubKlass', source_id: dup.id).update_all(source_id: keep.id)
          SheetKlass.where(sub_klass_id: dup.id).update_all(sub_klass_id: keep.id)
          dup.destroy!
          puts "    • Mesclada subclasse duplicada ##{dup.id} → ##{keep.id} (#{keep.api_index || to_slug.call(keep.name)})"
        rescue => e
          puts "    • Aviso: falha ao mesclar duplicata SubKlass ##{dup.id} em ##{keep.id}: #{e.message}"
        end
      end
    end

    by_slug.each_value { |arr| consolidate.call(arr) }
    by_idx.each_value  { |arr| consolidate.call(arr) }
  end

  def apply_subclass_overrides!(klass)
    # Primeiro, limpe duplicatas existentes para esta classe
    dedup_subclasses!(klass)
    all = merged_overrides
    overrides = all[klass.api_index] || {}
    overrides.each do |sub_idx, raw|
      # Skip non-subclass blocks (warlock extras)
      next if %w[boons invocations rules].include?(sub_idx.to_s)
      # Ensure we have a hash payload
      next unless raw.is_a?(Hash)
      data = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
      # Map subclass id aliases to canonical
      mapped_idx = SUBCLASS_ALIASES.dig(klass.api_index.to_s, sub_idx.to_s) || sub_idx
      sub = SubKlass.find_or_initialize_by(api_index: mapped_idx, klass_id: klass.id)
      # YAML é a fonte de verdade: sobrescreve sempre que houver dado
      nm = (data[:name] || data['name'])
      fl = (data[:flavor] || data['flavor'])
      ds = (data[:description] || data['description'])
      sub.name = nm if nm.present?
      sub.subclass_flavor = fl if fl.present?
      sub.description = ds if ds.present?
      lv = (data[:levels] || data['levels'])
      if lv.present?
        safe_levels = Array(lv).compact.select { |r| r.is_a?(Hash) }
        sub.levels_json = safe_levels.to_json
      end
      sub.save!
    end
  end

  def apply_subclass_grants!(klass)
    all = merged_overrides
    overrides = all[klass.api_index] || {}
    overrides.each do |sub_idx, raw|
      next if %w[boons invocations rules].include?(sub_idx.to_s)
      next unless raw.is_a?(Hash)
      data = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
      mapped_idx = SUBCLASS_ALIASES.dig(klass.api_index.to_s, sub_idx.to_s) || sub_idx
      sub = SubKlass.find_by(api_index: mapped_idx, klass_id: klass.id)
      next unless sub

      # Limpeza preventiva: apague vínculos antigos de always_prepared/expanded para esta subclasse
      begin
        SpellSource.where(source_type: 'SubKlass', source_id: sub.id, always_prepared: true).delete_all
        SpellSource.where(source_type: 'SubKlass', source_id: sub.id).where("coalesce(notes,'') = ?", 'expanded').delete_all
      rescue => e
        puts "    • Aviso: falha ao limpar SpellSource para #{klass.api_index}/#{mapped_idx}: #{e.message}"
      end

      parsed = JSON.parse(sub.levels_json.presence || '[]') rescue []
      parsed = Array(parsed).compact.select { |r| r.is_a?(Hash) }
      by_level = parsed.each_with_object({}) do |row, h|
        lvl = (row['level'] || row[:level]).to_i rescue 0
        next if lvl < 0
        h[lvl] = row
      end

      Array(data[:levels] || data['levels'] || []).each do |raw_row|
        row = raw_row.respond_to?(:with_indifferent_access) ? raw_row.with_indifferent_access : raw_row
        lvl = (row[:level] || row['level']).to_i
        next if lvl <= 0
        existing = (by_level[lvl] ||= { 'level' => lvl, 'features' => [] })
        grants = (row[:grants] || row['grants'] || {})
        choices = (row[:choices] || row['choices'] || {})
        # YAML é a fonte de verdade: sobrescreva grants/choices neste nível
        existing['grants'] = grants if grants.present?
        existing['choices'] = choices if choices.present?
        # Import feature list if provided
        feats = (row[:features] || row['features'] || [])
        if feats.present?
          # Substitua a lista de features pelo que vier do YAML
          existing['features'] = feats
        end
        by_level[lvl] = existing

        # always_prepared (melhor-esforço por nome ou slug)
        begin
          # Load translations once
          tr_path = Rails.root.join('config','dnd_translations.yml')
          tr = File.exist?(tr_path) ? (YAML.load_file(tr_path) || {}) : {}
          spell_tr = (tr['spells'] || {})
          pt_to_slug = spell_tr.invert rescue {}
          pt_to_slug_ci = {}
          spell_tr.each { |slug, pt| pt_to_slug_ci[pt.to_s.downcase] = slug }
          to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }
          resolve_spell = ->(label) do
            nm = label.to_s.strip
            return nil if nm.blank?
            sp = Spell.find_by(name: nm) || Spell.find_by(api_index: nm)
            return sp if sp
            slug = pt_to_slug[nm] || pt_to_slug_ci[nm.downcase]
            sp = slug ? Spell.find_by(api_index: slug) : nil
            return sp if sp
            guess = to_slug.call(nm)
            sp = Spell.find_by(api_index: guess)
            return sp if sp
            sp = Spell.where('LOWER(name) = ?', nm.downcase).first
            sp
          end
          ap = (grants.is_a?(Hash) ? (grants[:spells] || grants['spells'] || {}) : {})
          ap = (ap[:always_prepared] || ap['always_prepared'] || {})
          ap.each do |min_lvl, names|
            Array(names).each do |nm|
              sp = resolve_spell.call(nm)
              next unless sp
              ss = SpellSource.find_or_initialize_by(source_type: 'SubKlass', source_id: sub.id, spell_id: sp.id)
              ss.always_prepared = true
              ml = min_lvl.to_i
              ss.min_class_level = ml if ml > 0
              ss.save!
            end
          end
        rescue
        end
      end

      # Top-level choices for the subclass (attach at choose_level or klass.subclass_level)
      begin
        top_choices = (data[:choices] || data['choices'] || {})
        if top_choices.present?
          choose_lvl = (data[:choose_level] || data['choose_level'] || klass.subclass_level || 3).to_i
          choose_lvl = 3 if choose_lvl <= 0
          ex = (by_level[choose_lvl] ||= { 'level' => choose_lvl, 'features' => [] })
          # Preferência ao YAML principal
          ex['choices'] = top_choices
          by_level[choose_lvl] = ex
        end
      rescue
      end

      # Top-level rules metadata (store in level 0 row for reference)
      begin
        top_rules = (data[:rules] || data['rules'] || {})
        if top_rules.present?
          meta = (by_level[0] ||= { 'level' => 0 })
          # Sobrescrever regras com o YAML
          meta['rules'] = top_rules
          by_level[0] = meta
        end
      rescue
      end

      # Expanded spells (persist in SpellSource with notes='expanded')
      begin
        # Reuse resolver
        tr_path = Rails.root.join('config','dnd_translations.yml')
        tr = File.exist?(tr_path) ? (YAML.load_file(tr_path) || {}) : {}
        spell_tr = (tr['spells'] || {})
        pt_to_slug = spell_tr.invert rescue {}
        pt_to_slug_ci = {}
        spell_tr.each { |slug, pt| pt_to_slug_ci[pt.to_s.downcase] = slug }
        to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }
        resolve_spell = ->(label) do
          nm = label.to_s.strip
          return nil if nm.blank?
          sp = Spell.find_by(name: nm) || Spell.find_by(api_index: nm)
          return sp if sp
          slug = pt_to_slug[nm] || pt_to_slug_ci[nm.downcase]
          sp = slug ? Spell.find_by(api_index: slug) : nil
          return sp if sp
          guess = to_slug.call(nm)
          sp = Spell.find_by(api_index: guess)
          return sp if sp
          sp = Spell.where('LOWER(name) = ?', nm.downcase).first
          sp
        end

        expanded = (data[:expanded_spells] || data['expanded_spells'] || {})
        expanded.each do |min_lvl, names|
          ml = min_lvl.to_i
          Array(names).each do |nm|
            sp = resolve_spell.call(nm)
            next unless sp
            ss = SpellSource.find_or_initialize_by(source_type: 'SubKlass', source_id: sub.id, spell_id: sp.id)
            ss.always_prepared = false
            ss.min_class_level = (ml > 0 ? ml : nil)
            ss.notes = 'expanded'
            ss.save!
          end
        end
      rescue
      end

      sub.levels_json = by_level.values.sort_by { |r| r['level'].to_i }.to_json
      sub.save!
    end
  end
end

namespace :dnd do
  desc "Aplica overrides/grants de subclasses do YAML local (sem baixar nada, não recria class_levels)"
  task apply_subclass_overrides: :environment do
    puts "Aplicando overrides/grants de subclasses a partir de config/subclass_overrides.yml…"
    Klass.find_each do |klass|
      begin
        DndImportHelpers.apply_subclass_overrides!(klass)
        DndImportHelpers.apply_subclass_grants!(klass)
      rescue => e
        puts "  • Falha ao aplicar overrides para #{klass.name}: #{e.message}"
      end
    end
    puts "Sincronizando SubKlassLevel/Feature a partir de levels_json…"
    results = Subclasses::SyncFeaturesFromLevelsJsonService.run_all(
      logger: ->(msg) { puts msg },
    )
    by_status = results.group_by(&:status).transform_values(&:size)
    puts "Sync subklass features: #{by_status.inspect}"
    puts "Concluído."
  end

  desc "Deduplica subclasses por classe, migrando relacionamentos (seguro para rodar a qualquer momento)"
  task dedup_subclasses: :environment do
    puts "Deduplicando subclasses…"
    Klass.find_each do |klass|
      begin
        puts "- #{klass.name}"
        DndImportHelpers.dedup_subclasses!(klass)
      rescue => e
        puts "  • Falha ao deduplicar #{klass.name}: #{e.message}"
      end
    end
    puts "Concluído."
  end
end
