# frozen_string_literal: true

# dnd:refresh_race_trait_descriptions — fix de DADOS da varredura de RAÇAS (R6).
# Fonte: .cursor/dnd-rules/_VARREDURA-racas.md (R6 — Sopro do Dragão genérico).
#
# Contexto: o `race_summary['traits'][].description` é um SNAPSHOT gravado no
# provisionamento a partir de `Trait.description`. Quando corrigimos o YAML
# (placeholders `<dano>`/`<area>` no breath_weapon e `<dano>` na resistência de
# ancestralidade) + `rake races:import`, o `Trait.description` canônico passa a
# ter os placeholders — mas fichas JÁ provisionadas continuam com o texto
# genérico antigo no snapshot. Esta task re-sincroniza esse snapshot com o
# Trait.description atual, casando por NOME do trait (a chave que o snapshot
# guarda). Em runtime, `CharacterSheetSummaryService#interpolate_trait_description`
# substitui os placeholders pelos valores de `RaceTrait.metadata` ({damage,breath}).
#
# Princípios (CLAUDE.md):
#   • TRANSACIONAL e IDEMPOTENTE: só grava quando a descrição realmente mudou;
#     rodar 2x não altera nada além da 1ª passada.
#   • CRITÉRIO ESTÁVEL: casa por nome de trait normalizado (não por id do DB).
#   • SEGURO: nunca adiciona/remove traits — só atualiza `description` de traits
#     que JÁ existem no snapshot e têm Trait canônico correspondente para a
#     raça/sub-raça da ficha. Atua na coluna `race_summary` E, se presente, no
#     override `metadata['race_summary']`.
#
# Uso:
#   docker exec lafiga_api bundle exec rake dnd:refresh_race_trait_descriptions
#   DRY_RUN=1 docker exec lafiga_api bundle exec rake dnd:refresh_race_trait_descriptions
namespace :dnd do
  desc 'R6 — re-sincroniza race_summary[traits][].description com Trait.description canônico (após races:import). Idempotente. DRY_RUN=1 disponível.'
  task refresh_race_trait_descriptions: :environment do
    dry = %w[1 true yes].include?(ENV['DRY_RUN'].to_s.strip.downcase)
    norm = ->(s) { s.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip }

    scanned = 0
    updated = 0
    traits_touched = 0

    # Cache de mapas nome→description canônico por (race_id, sub_race_id).
    canon_cache = {}
    canon_for = lambda do |race_id, sub_race_id|
      canon_cache[[race_id, sub_race_id]] ||= begin
        map = {}
        race = Race.find_by(id: race_id)
        if race
          records = race.base_traits.to_a
          records += SubRace.find_by(id: sub_race_id)&.traits.to_a || [] if sub_race_id
          records.uniq(&:id).each do |t|
            desc = t.description.to_s
            next if desc.blank?

            map[norm.call(t.name)] = desc
            map[norm.call(t.api_index)] = desc if t.api_index.present?
          end
        end
        map
      end
    end

    # Re-sincroniza um hash race_summary in-place. Retorna [novo_hash, mudou?].
    refresh_summary = lambda do |rs, race_id, sub_race_id|
      return [rs, false] unless rs.is_a?(Hash)

      traits = rs['traits'] || rs[:traits]
      return [rs, false] unless traits.is_a?(Array) && traits.any?

      canon = canon_for.call(race_id, sub_race_id)
      return [rs, false] if canon.empty?

      changed = false
      new_traits = traits.map do |t|
        next t unless t.is_a?(Hash)

        h = t.stringify_keys
        name = h['name'].to_s
        key  = h['api_index'].to_s
        cd = canon[norm.call(key)] || canon[norm.call(name)]
        if cd && cd != h['description'].to_s
          changed = true
          traits_touched += 1
          h.merge('description' => cd)
        else
          h
        end
      end

      [rs.merge('traits' => new_traits), changed]
    end

    Sheet.where.not(race_id: nil).find_each(batch_size: 200) do |sheet|
      scanned += 1
      sheet_changed = false

      ActiveRecord::Base.transaction do
        # 1) Coluna race_summary (fonte canônica do provisioning)
        col = sheet.read_attribute(:race_summary)
        if col.is_a?(Hash) && col.present?
          new_col, changed = refresh_summary.call(col, sheet.race_id, sheet.sub_race_id)
          if changed
            sheet.update_column(:race_summary, new_col) unless dry
            sheet_changed = true
          end
        end

        # 2) Override em metadata['race_summary'] (admin/tooling), se existir
        meta = sheet.metadata
        if meta.is_a?(Hash) && meta['race_summary'].is_a?(Hash)
          new_meta_rs, changed = refresh_summary.call(meta['race_summary'], sheet.race_id, sheet.sub_race_id)
          if changed
            sheet.update_column(:metadata, meta.merge('race_summary' => new_meta_rs)) unless dry
            sheet_changed = true
          end
        end
      end

      updated += 1 if sheet_changed
    end

    puts "dnd:refresh_race_trait_descriptions: #{updated} fichas atualizadas " \
         "(#{traits_touched} traits) de #{scanned} com raça#{dry ? ' [DRY_RUN]' : ''}."
  end
end
