# Backfill de spells em metadata.class_choices.per_level[*].cantrips/spells.
#
# Por que existe:
#   Antes da Phase 12, `LevelUpService#persist_known_spells!` descartava
#   silenciosamente entries cujo `id` nao fosse numerico (ex.: import por nome,
#   `{"id"=>"Toque arrepiane"}`). A magia ficava orfa em metadata sem virar
#   `SheetKnownSpell` e sem icone/desc na ficha. Phase 12 corrige no fluxo
#   novo (level-up futuro auto-cura), mas chars JA criados precisam de um
#   sweep manual.
#
# O que faz:
#   - Percorre Sheet.where("metadata IS NOT NULL")
#   - Em cada per_level[N].cantrips/spells/learn_any_class_spells, normaliza
#     entries via SpellResolver:
#       * resolveu => substitui por {id, name, level} canonico + cria
#         SheetKnownSpell se faltar
#       * nao resolveu => mantem como esta + loga warn pra acao manual
#   - Idempotente: rodar varias vezes nao causa duplicatas (find_or_create_by!).
#
# Uso:
#   docker exec lafiga_api bundle exec rails spells:backfill_metadata
#   docker exec lafiga_api bundle exec rails spells:backfill_metadata DRY_RUN=1
#   docker exec lafiga_api bundle exec rails spells:backfill_metadata SHEET_ID=13888
namespace :spells do
  desc 'Resolve strings cruas/typos em metadata.class_choices.per_level[*].cantrips/spells e cria SheetKnownSpell faltantes.'
  task backfill_metadata: :environment do
    dry_run  = ENV['DRY_RUN'].to_s == '1'
    sheet_id = ENV['SHEET_ID'].presence&.to_i

    scope = Sheet.where('metadata IS NOT NULL')
    scope = scope.where(id: sheet_id) if sheet_id

    resolver = SpellResolver.new
    counts = Hash.new(0)
    unresolved = []

    scope.find_each(batch_size: 100) do |sheet|
      meta = sheet.metadata || {}
      per = meta.dig('class_choices', 'per_level') || {}
      next if per.empty?

      meta_dirty = false
      per_new = per.deep_dup

      per_new.each do |lvl_str, row|
        next unless row.is_a?(Hash)

        %w[cantrips spells learn_any_class_spells].each do |key|
          arr = Array(row[key])
          next if arr.empty?

          # Marca pra remocao entradas obviamente lixo (puramente numericas
          # tipo "2.0", strings vazias). Excel as vezes coloca valor de outra
          # celula no campo errado.
          to_drop = []

          arr.each_with_index do |sp, idx|
            name_for_check = sp.is_a?(Hash) ? (sp['name'] || sp['id']) : sp
            if name_for_check.to_s.strip.empty? || name_for_check.to_s.strip =~ /\A\d+(\.\d+)?\z/
              to_drop << idx
              counts[:dropped_invalid] += 1
              next
            end

            sid_numeric = case sp
                          when Numeric then sp.to_i
                          when Hash
                            raw = sp['id'] || sp[:id]
                            raw.is_a?(Integer) ? raw : (raw.to_s =~ /\A\d+\z/ ? raw.to_i : nil)
                          else nil
                          end

            if sid_numeric&.positive?
              counts[:already_canonical] += 1
              ensure_known_spell!(sheet, sid_numeric, key, dry_run, counts)
              next
            end

            normalized = resolver.normalize(sp)
            if normalized.nil?
              counts[:unresolved] += 1
              unresolved << "sheet=#{sheet.id} L#{lvl_str} #{key}[#{idx}] = #{sp.inspect}"
              next
            end

            counts[:healed] += 1
            arr[idx] = { 'id' => normalized[:id], 'name' => normalized[:name], 'level' => normalized[:level] }
            row[key] = arr
            meta_dirty = true

            ensure_known_spell!(sheet, normalized[:id], key, dry_run, counts)
          end

          if to_drop.any?
            arr = arr.each_with_index.reject { |_, i| to_drop.include?(i) }.map(&:first)
            row[key] = arr
            meta_dirty = true
          end
        end
      end

      if meta_dirty && !dry_run
        meta_to_save = (sheet.metadata || {}).deep_dup
        meta_to_save['class_choices'] ||= {}
        meta_to_save['class_choices']['per_level'] = per_new
        sheet.update_column(:metadata, meta_to_save)
        counts[:sheets_updated] += 1
      elsif meta_dirty
        counts[:sheets_would_update] += 1
      end
    end

    puts '=== Spell metadata backfill ==='
    puts "DRY_RUN: #{dry_run}"
    puts "SHEET_ID: #{sheet_id || 'all'}"
    counts.each { |k, v| puts "  #{k}: #{v}" }
    if unresolved.any?
      puts "\n--- Unresolved entries (precisam de alias em config/spell_aliases.yml ou correcao manual) ---"
      unresolved.first(50).each { |line| puts "  #{line}" }
      puts "  ... +#{unresolved.size - 50} more" if unresolved.size > 50
    end
  end

  def ensure_known_spell!(sheet, spell_id, key, dry_run, counts)
    return unless spell_id&.positive?
    return if key == 'learn_any_class_spells' # Magical Secrets vai pra outro path
    sk = sheet.sheet_klasses.first
    return unless sk
    exists = SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: spell_id)
    return if exists
    if dry_run
      counts[:known_spell_would_create] += 1
    else
      SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: spell_id)
      counts[:known_spell_created] += 1
    end
  rescue => e
    Rails.logger.warn "spells:backfill_metadata SheetKnownSpell create failed sheet=#{sheet.id} spell=#{spell_id}: #{e.message}"
    counts[:known_spell_create_failed] += 1
  end
end
