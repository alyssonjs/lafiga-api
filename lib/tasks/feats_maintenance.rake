namespace :feats do
  # Re-aplica FeatRules.apply em Sheet#metadata['feats'] e re-sincroniza ability scores.
  # Util quando FeatRules muda (novo special_rule, ajuste em ability_bonuses, etc) e queremos
  # propagar a mudanca para fichas ja persistidas, sem esperar o jogador re-editar.
  desc 'Rebuild Sheet#metadata.feats[]: re-aplica FeatRules.apply e re-sync ability scores'
  task rebuild_sheets_metadata: :environment do
    puts '=== feats:rebuild_sheets_metadata ==='
    affected_sheets = 0
    rewritten_entries = 0
    skipped = 0

    Sheet.where.not(metadata: nil).find_each do |sheet|
      feats_meta = (sheet.metadata || {})['feats']
      next if feats_meta.blank?

      new_feats = []
      changed_in_sheet = false

      feats_meta.each do |entry|
        unless entry.is_a?(Hash)
          new_feats << entry
          next
        end

        fid = entry['feat_id'] || entry[:feat_id]
        if fid.blank?
          new_feats << entry
          next
        end

        choices = entry['choices'] || entry[:choices] || {}
        choices = choices.to_unsafe_h if choices.respond_to?(:to_unsafe_h)
        canonical = begin
          FeatRules.apply(fid, choices || {})
        rescue StandardError => e
          puts "  Sheet ##{sheet.id}: FeatRules.apply(#{fid}) falhou: #{e.message}"
          nil
        end

        if canonical.nil?
          new_feats << entry
          skipped += 1
          next
        end

        rebuilt = entry.merge(
          'name'                => canonical[:name] || entry['name'],
          'ability_bonuses'     => (canonical[:ability_bonuses] || {}).deep_stringify_keys,
          'proficiency_bonuses' => (canonical[:proficiency_bonuses] || {}).deep_stringify_keys,
          'cantrips'            => (canonical[:cantrips] || {}).deep_stringify_keys,
          'spells'              => (canonical[:spells] || {}).deep_stringify_keys,
          'features'            => begin
            f = canonical[:features] || {}
            f.respond_to?(:deep_stringify_keys) ? f.deep_stringify_keys : f
          end
        )

        if rebuilt != entry
          changed_in_sheet = true
          rewritten_entries += 1
        end
        new_feats << rebuilt
      end

      next unless changed_in_sheet

      meta = sheet.metadata.dup
      meta['feats'] = new_feats
      sheet.update!(metadata: meta)
      affected_sheets += 1

      begin
        CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)
      rescue StandardError => e
        puts "  Sheet ##{sheet.id}: sync_ability_columns_from_metadata! falhou: #{e.message}"
      end

      puts "  Sheet ##{sheet.id} (char_id=#{sheet.character_id}): #{new_feats.size} feat(s) regravados"
    end

    puts ''
    puts "Sheets afetadas: #{affected_sheets}"
    puts "Entradas regravadas: #{rewritten_entries}"
    puts "Skipped (apply falhou): #{skipped}"
  end
end
