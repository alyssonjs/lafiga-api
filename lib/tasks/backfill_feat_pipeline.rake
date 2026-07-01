# frozen_string_literal: true

# dnd:backfill_feats — re-materializa o pipeline de TALENTOS em fichas EXISTENTES.
# Fonte: .cursor/dnd-rules/_VARREDURA-talentos.md (raízes F1–F11, D3, D4).
#
# Por quê: as correções da varredura são de CÓDIGO (FeatRules.apply,
# FeatSpecialRulesService, build_resources, etc.) e passam a valer para NOVAS
# atribuições. Fichas já criadas, porém, têm `metadata['feats'][]` congelado no
# formato antigo:
#   • special_rules com famílias inteiras = {} (Curandeiro/Líder/Adepto Marcial…) → F2/F3
#   • proficiency_bonuses não-resolvido (Poliglota languages_choose / Especialista
#     em Armas weapons.choose) → D3/D4
#   • ability_bonuses ok, mas colunas autoritativas podem ter o artefato
#     "Ajuste manual -1" (half-feat sem sync) → F5
# Este rake recomputa esses campos a partir das `choices` já gravadas e regrava
# só quando há diferença real (idempotente).
#
# Princípios (CLAUDE.md):
#   • TRANSACIONAL por ficha (uma falha não derruba o lote).
#   • IDEMPOTENTE: 2ª passada não muda nada.
#   • CRITÉRIO ESTÁVEL: itera por presença de `metadata['feats']`, sem id hardcoded.
#   • SEGURO: preserva id/level_gained/choices; não toca em fichas sem feats.
#
# Uso:
#   docker exec lafiga_api bundle exec rake dnd:backfill_feats
#   DRY_RUN=1 docker exec lafiga_api bundle exec rake dnd:backfill_feats         # só relata
#   docker exec lafiga_api bundle exec rake dnd:backfill_feats:spells            # só SheetKnownSpell (F7/F8)
namespace :dnd do
  DRY_FEATS = -> { %w[1 true yes].include?(ENV['DRY_RUN'].to_s.downcase) }

  # Recalcula os campos resolvidos de UMA entrada de metadata['feats'] a partir
  # do feat_id + choices gravados. Retorna o hash atualizado (ou o original).
  def self.rebuild_feat_entry(sheet, entry)
    feat_id = entry['feat_id'] || entry[:feat_id]
    return entry if feat_id.blank?
    return entry unless FeatRules.find(feat_id)

    choices = entry['choices'] || entry[:choices] || {}
    summary = FeatRules.apply(feat_id, choices)
    special = FeatSpecialRulesService.new(sheet, feat_id, choices).apply_special_rules

    entry.merge(
      'name'                => summary[:name],
      'ability_bonuses'     => summary[:ability_bonuses],
      'proficiency_bonuses' => summary[:proficiency_bonuses],
      'cantrips'            => summary[:cantrips],
      'spells'              => summary[:spells],
      'features'            => summary[:features],
      'special_rules'       => special
    )
  rescue StandardError => e
    Rails.logger.warn("[backfill_feats] entry #{feat_id} falhou na sheet ##{sheet.id}: #{e.message}")
    entry
  end

  desc 'Re-materializa metadata[feats] (special_rules/proficiency_bonuses) de fichas existentes (F2/F3/D3/D4)'
  task backfill_feats: :environment do
    dry = DRY_FEATS.call
    puts "[backfill_feats] Re-materializando metadata['feats'] (DRY_RUN=#{dry})…"
    scanned = 0; changed = 0; synced = 0

    # JSON ?| operador: linhas cujo metadata tem a chave 'feats'.
    scope = Sheet.where("metadata ? 'feats'")
    scope.find_each(batch_size: 200) do |sheet|
      meta = sheet.metadata || {}
      feats = meta['feats']
      next unless feats.is_a?(Array) && feats.any?
      scanned += 1

      rebuilt = feats.map { |e| e.is_a?(Hash) ? rebuild_feat_entry(sheet, e.deep_stringify_keys) : e }
      # Normaliza via JSON (símbolos→string, igual à serialização jsonb) nos DOIS
      # lados para a comparação ser idempotente — senão chaves símbolo do rebuild
      # divergiriam das string já persistidas e o rake reescreveria sempre.
      rebuilt_norm = JSON.parse(rebuilt.to_json)
      next if rebuilt_norm == JSON.parse(feats.to_json)

      changed += 1
      ids = rebuilt_norm.map { |e| e.is_a?(Hash) ? e['feat_id'] : e }.compact
      puts "  • sheet ##{sheet.id}: atualizando feats #{ids.inspect}"
      next if dry

      ActiveRecord::Base.transaction do
        fresh = sheet.metadata || {}
        fresh['feats'] = rebuilt_norm
        sheet.update!(metadata: fresh)
        # F5 — fichas autoritativas: re-sincroniza colunas para apagar o
        # artefato "Ajuste manual -1" de half-feats.
        if fresh['ability_scores_include_all_increments'] ||
           (fresh['base_ability_scores'].is_a?(Hash) && fresh['base_ability_scores'].keys.any?)
          CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)
          synced += 1
        end
      end
    rescue StandardError => e
      puts "  ! sheet ##{sheet.id} pulada: #{e.class}: #{e.message}"
    end

    puts "[backfill_feats] Concluído. fichas com feats: #{scanned} | atualizadas: #{changed} | colunas sincronizadas: #{synced}" +
         (dry ? ' [DRY_RUN — nada gravado]' : '')
  end

  namespace :backfill_feats do
    desc 'Materializa SheetKnownSpell source:feat para talentos de magia já atribuídos (F7/F8)'
    task spells: :environment do
      dry = DRY_FEATS.call
      puts "[backfill_feats:spells] Materializando magias de talento (DRY_RUN=#{dry})…"
      scanned = 0; created = 0

      find_spell = lambda do |token, level|
        t = token.to_s.strip
        next nil if t.empty?
        s = level ? Spell.where(level: level) : Spell.all
        s.find_by(name: t) || s.find_by(api_index: t) ||
          s.where('LOWER(name) = ?', t.downcase).first ||
          (t.match?(/\A\d+\z/) ? s.find_by(id: t.to_i) : nil)
      end

      Sheet.where("metadata ? 'feats'").find_each(batch_size: 200) do |sheet|
        feats = (sheet.metadata || {})['feats']
        next unless feats.is_a?(Array) && feats.any?
        sheet_klass = sheet.sheet_klasses.first
        next unless sheet_klass

        feats.each do |entry|
          next unless entry.is_a?(Hash)
          feat_id = entry['feat_id']
          rule = FeatRules.find(feat_id)
          next unless rule
          choices = entry['choices'] || {}
          summary = FeatRules.apply(feat_id, choices) rescue {}

          mm = begin
            sr = rule[:special_rules] || rule['special_rules']
            sr = FeatRules.parse_jsonish(sr) if sr.is_a?(String)
            (sr.is_a?(Hash) ? (sr[:magic_modifiers] || sr['magic_modifiers']) : {}) || {}
          end
          mm = mm.deep_stringify_keys if mm.respond_to?(:deep_stringify_keys)

          cantrips = Array((summary[:cantrips] || {}).then { |h| h.is_a?(Hash) ? (h['cantrips'] || h[:cantrips]) : nil })
          cantrips |= Array(choices['cantrips'] || choices[:cantrips]) if mm['learn_cantrip']
          spells = Array((summary[:spells] || {}).then { |h| h.is_a?(Hash) ? (h['spells'] || h[:spells]) : nil })
          spells |= Array(choices['spells'] || choices[:spells]) if mm['ritual_book']

          one_per_long = feat_id.to_s == 'magico_iniciante'

          cantrips.map(&:to_s).reject(&:blank?).each do |tok|
            sp = find_spell.call(tok, 0)
            next unless sp
            scanned += 1
            next if dry
            row = SheetKnownSpell.find_or_create_by(sheet_klass: sheet_klass, spell: sp) { |r| r.source = 'feat' }
            created += 1 if row.previously_new_record?
          end

          spells.map(&:to_s).reject(&:blank?).each do |tok|
            sp = find_spell.call(tok, nil)
            next unless sp
            scanned += 1
            next if dry
            row = SheetKnownSpell.find_or_create_by(sheet_klass: sheet_klass, spell: sp) { |r| r.source = 'feat' }
            created += 1 if row.previously_new_record?
            if one_per_long && row.source == 'feat' && row.uses_per_rest.blank?
              row.update(uses_per_rest: 'LR', uses_remaining: 1)
            end
          end
        rescue StandardError => e
          puts "  ! sheet ##{sheet.id} feat #{entry['feat_id']}: #{e.class}: #{e.message}"
        end
      end

      puts "[backfill_feats:spells] Concluído. tokens avaliados: #{scanned} | SheetKnownSpell criados: #{created}" +
           (dry ? ' [DRY_RUN — nada gravado]' : '')
    end
  end
end
