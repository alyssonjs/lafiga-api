# frozen_string_literal: true

# dnd:cleanup_sheet_data — limpeza de DADOS (seed/DB) da varredura de fichas.
# Fonte: .cursor/dnd-rules/classes/_VARREDURA-fichas.md (seção "Dados (seed/DB)" D1–D6).
#
# Cobre as operações destrutivas D1–D4. D5/D6 são aditivas e ficam no YAML
# (config/subclass_overrides.yml) + re-materialização via dnd:apply_subclass_overrides.
#
# Princípios (CLAUDE.md / pedido):
#   • TRANSACIONAL: cada subtask roda em ActiveRecord::Base.transaction.
#   • IDEMPOTENTE: rodar 2x não muda nada além da 1ª passada.
#   • CRITÉRIO ESTÁVEL: nada por id hardcoded do relatório (ids são do DB local).
#     Tudo por nome normalizado / api_index / orfandade / mapa semântico.
#   • SEGURO: nunca esvazia um nível; só apaga ghost/legado quando há canônica
#     presente E a contagem é 1:1 (ou menos). Sem critério → relata, não apaga.
#
# Uso:
#   docker exec lafiga_api bundle exec rake dnd:cleanup_sheet_data            # D1–D4 (all)
#   docker exec lafiga_api bundle exec rake dnd:cleanup_sheet_data:d1         # só ghosts/legados
#   docker exec lafiga_api bundle exec rake dnd:cleanup_sheet_data:d2         # só dedup semântico
#   docker exec lafiga_api bundle exec rake dnd:cleanup_sheet_data:d3         # só Zona da Verdade
#   docker exec lafiga_api bundle exec rake dnd:cleanup_sheet_data:d4         # só feature-lixo
#   DRY_RUN=1 docker exec ... rake dnd:cleanup_sheet_data                     # só relata, não grava
namespace :dnd do
  namespace :cleanup_sheet_data do
    # ── helpers compartilhados ───────────────────────────────────────────────
    NORM = lambda do |s|
      ActiveSupport::Inflector.transliterate(s.to_s).downcase
        .gsub(/[^a-z0-9]+/, ' ').strip.gsub(/\s+/, ' ')
    end

    DRY = ->{ ENV['DRY_RUN'].to_s == '1' || ENV['DRY_RUN'].to_s.downcase == 'true' }

    # Pares semânticos (nomes diferentes, MESMA subclasse). Canônico = api_index
    # PT-BR que casa com o YAML / tem levels_json populado. legado = o duplicado.
    # Resolvido por api_index (estável), não por id.
    SEMANTIC_DUP = {
      'fighter' => [{ legacy: 'champion', canon: 'campeao' }],
      'rogue'   => [{ legacy: 'thief',    canon: 'ladrao' }],
      'cleric'  => [{ legacy: 'life',     canon: 'dominio-da-vida' }],
      # Evocação: id 'evocacao' está vazio (levels_json nil) porém em uso real;
      # 'evocation' é o correto/populado e é o alvo do apply (alias YAML
      # 'escola-de-evocacao' → 'evocation'). Canônico = 'evocation'.
      'wizard'  => [{ legacy: 'evocacao', canon: 'evocation' }],
    }.freeze

    # Apaga uma Feature com segurança: desassocia das levels, limpa o cache
    # denormalizado (characters_features) e destrói se ficar órfã. Mesmo padrão
    # de sorcerer_canonical.rake. Retorna :destroyed | :kept.
    def self.safe_destroy_feature!(feature, log:)
      feature.class_levels.to_a.each { |cl| cl.features.delete(feature) }
      feature.sub_klass_levels.to_a.each { |skl| skl.features.delete(feature) }
      CharactersFeature.where(feature_id: feature.id).delete_all
      feature.reload
      if feature.class_levels.exists? || feature.sub_klass_levels.exists?
        log.call("    mantida (ainda referenciada): #{feature.api_index.inspect}")
        return :kept
      end
      feature.destroy!
      :destroyed
    rescue ActiveRecord::InvalidForeignKey => e
      log.call("    mantida (FK): #{feature.api_index.inspect} — #{e.message.lines.first&.strip}")
      :kept
    end

    # ── D1 — Remover features-fantasma/legadas por CRITÉRIO ───────────────────
    desc 'D1: remove features de subclasse ghost/legadas ausentes do levels_json (1:1 seguro)'
    task d1: :environment do
      log = ->(m) { puts m }
      log.call("[D1] Removendo features de subclasse ghost/legadas (critério estável; DRY_RUN=#{DRY.call})…")
      deleted = 0; kept = 0; reported = 0; touched_levels = 0

      ActiveRecord::Base.transaction do
        SubKlass.includes(:klass, sub_klass_levels: :features).find_each do |sub|
          canon = (JSON.parse(sub.levels_json.presence || '[]') rescue [])
          next if canon.empty?
          canon_by_lvl = {}
          canon.each do |r|
            lvl = (r['level'] || r[:level]).to_i
            canon_by_lvl[lvl] = Array(r['features'] || r[:features])
              .map { |f| NORM.call(f['name'] || f[:name]) }.reject(&:blank?)
          end

          sub.sub_klass_levels.each do |skl|
            cset = canon_by_lvl[skl.level] || []
            # Sem canônica declarada nesse nível → sem critério → NÃO apaga.
            next if cset.empty?

            feats    = skl.features.to_a
            matched  = feats.select { |f| cset.include?(NORM.call(f.name)) }
            nonmatch = feats.reject { |f| cset.include?(NORM.call(f.name)) }
            next if nonmatch.empty?

            # Segurança: só apaga quando há canônica presente E contagem 1:1
            # (ou menos non-match que canônicas). Caso contrário, relata.
            if matched.empty? || nonmatch.size > matched.size
              reported += nonmatch.size
              log.call("  • RELATADO (sem critério seguro) #{sub.klass.api_index}/#{sub.api_index} L#{skl.level}: " \
                       "#{nonmatch.map(&:name).inspect} (matched=#{matched.size})")
              next
            end

            touched_levels += 1
            nonmatch.each do |f|
              # Desassocia desta level primeiro (escopo da subclasse).
              skl.features.delete(f)
              CharactersFeature.where(feature_id: f.id).delete_all
              f.reload
              # Só destrói o registro Feature se ficou totalmente órfão; senão
              # apenas a associação foi removida (a feature pode ser de outra sub).
              if !f.class_levels.exists? && !f.sub_klass_levels.exists?
                f.destroy! unless DRY.call
              end
              deleted += 1
              log.call("  • #{sub.klass.api_index}/#{sub.api_index} L#{skl.level}: " \
                       "ghost #{f.name.inspect} (id=#{f.id}) removida")
            end
          end
        end
        raise ActiveRecord::Rollback if DRY.call
      end

      log.call("[D1] Concluído. associações/features removidas: #{deleted} | mantidas: #{kept} | " \
               "relatadas (sem critério): #{reported} | níveis tocados: #{touched_levels}" + (DRY.call ? " [DRY_RUN — rollback]" : ''))
    end

    # ── D2 — Deduplicar subclasses semânticas ─────────────────────────────────
    desc 'D2: mescla subclasses semanticamente duplicadas (champion→campeao etc.) por api_index'
    task d2: :environment do
      log = ->(m) { puts m }
      log.call("[D2] Deduplicando subclasses semânticas (DRY_RUN=#{DRY.call})…")
      merged = 0; moved = 0

      ActiveRecord::Base.transaction do
        SEMANTIC_DUP.each do |klass_api, pairs|
          klass = Klass.find_by(api_index: klass_api)
          next unless klass
          pairs.each do |pair|
            dup   = SubKlass.find_by(klass_id: klass.id, api_index: pair[:legacy])
            canon = SubKlass.find_by(klass_id: klass.id, api_index: pair[:canon])
            next if dup.nil?                       # idempotente: já removido
            if canon.nil?
              log.call("  • PULADO #{klass_api}: canônico #{pair[:canon].inspect} ausente (não mescla às cegas).")
              next
            end
            next if dup.id == canon.id

            # 1) Repontar fichas da duplicata → canônica.
            m = SheetKlass.where(sub_klass_id: dup.id).update_all(sub_klass_id: canon.id)
            moved += m
            # 2) Limpar levels/spell-sources da duplicata (a canônica já tem os
            #    corretos via apply_subclass_overrides; evita conflito de índice).
            SubKlassLevel.where(sub_klass_id: dup.id).find_each do |skl|
              skl.features.clear
              skl.destroy!
            end
            SpellSource.where(source_type: 'SubKlass', source_id: dup.id).delete_all
            # 3) Destruir a duplicata.
            dup.destroy!
            merged += 1
            log.call("  • #{klass_api}: removido ##{dup.id} (#{pair[:legacy]}) → mantido ##{canon.id} (#{pair[:canon]})" +
                     (m.positive? ? " [#{m} ficha(s) repontada(s)]" : ''))
          end
        end
        raise ActiveRecord::Rollback if DRY.call
      end

      log.call("[D2] Concluído. subclasses mescladas: #{merged} | fichas repontadas: #{moved}" + (DRY.call ? " [DRY_RUN — rollback]" : ''))
    end

    # ── D3 — Deduplicar magia 'Zona da Verdade' ───────────────────────────────
    desc 'D3: mescla a magia órfã "Zona da Verdade" na canônica e padroniza nome PT-BR'
    task d3: :environment do
      log = ->(m) { puts m }
      log.call("[D3] Deduplicando 'Zona da Verdade' (DRY_RUN=#{DRY.call})…")

      ActiveRecord::Base.transaction do
        candidates = Spell.where('LOWER(name) LIKE ? OR LOWER(name) LIKE ?',
                                 '%zona da verdade%', '%zone of truth%').to_a
        if candidates.size < 2
          log.call("  • Nada a fazer (#{candidates.size} registro(s) — já deduplicado).")
        else
          # Canônica = a que tem mais SpellSource (em uso real). Empate → menor id.
          canon = candidates.max_by { |sp| [SpellSource.where(spell_id: sp.id).count, -sp.id] }
          orphans = candidates - [canon]
          orphans.each do |orphan|
            # Repontar referências com tratamento de conflito (índices únicos).
            repoint_spell_refs!(orphan_id: orphan.id, canon_id: canon.id, log: log)
            orphan.destroy!
            log.call("  • mesclada Spell ##{orphan.id} (#{orphan.name.inspect}) → ##{canon.id}")
          end
          # Padroniza nome PT-BR na canônica.
          if canon.name != 'Zona da Verdade'
            log.call("  • renomeando canônica ##{canon.id}: #{canon.name.inspect} → \"Zona da Verdade\"")
            canon.update!(name: 'Zona da Verdade')
          end
        end
        raise ActiveRecord::Rollback if DRY.call
      end

      log.call("[D3] Concluído." + (DRY.call ? ' [DRY_RUN — rollback]' : ''))
    end

    # Repontar todas as referências de uma Spell órfã para a canônica, lidando
    # com índices únicos (apaga o que colidiria, repoint do resto).
    def self.repoint_spell_refs!(orphan_id:, canon_id:, log:)
      # SpellSource: índice único (source_type, source_id, spell_id).
      SpellSource.where(spell_id: orphan_id).find_each do |ss|
        if SpellSource.where(source_type: ss.source_type, source_id: ss.source_id, spell_id: canon_id).exists?
          ss.delete
        else
          ss.update_columns(spell_id: canon_id)
        end
      end
      # sheet_known_spells: índice único (sheet_klass_id, spell_id).
      SheetKnownSpell.where(spell_id: orphan_id).find_each do |k|
        if SheetKnownSpell.where(sheet_klass_id: k.sheet_klass_id, spell_id: canon_id).exists?
          k.delete
        else
          k.update_columns(spell_id: canon_id)
        end
      end
      # sheet_prepared_spells: índice único (sheet_id, spell_id).
      SheetPreparedSpell.where(spell_id: orphan_id).find_each do |p|
        if SheetPreparedSpell.where(sheet_id: p.sheet_id, spell_id: canon_id).exists?
          p.delete
        else
          p.update_columns(spell_id: canon_id)
        end
      end
    end

    # ── D4 — Remover feature-lixo 'Ataque de peido' ───────────────────────────
    desc 'D4: remove a feature-lixo "Ataque de peido" (por nome) e suas associações'
    task d4: :environment do
      log = ->(m) { puts m }
      log.call("[D4] Removendo feature-lixo 'Ataque de peido' (DRY_RUN=#{DRY.call})…")
      destroyed = 0; kept = 0

      ActiveRecord::Base.transaction do
        Feature.where('LOWER(name) = ?', 'ataque de peido').find_each do |f|
          res = safe_destroy_feature!(f, log: log)
          if res == :destroyed
            destroyed += 1
            log.call("  • removida Feature ##{f.id} (#{f.api_index.inspect})")
          else
            kept += 1
          end
        end
        raise ActiveRecord::Rollback if DRY.call
      end

      log.call("[D4] Concluído. apagadas: #{destroyed} | mantidas: #{kept}" + (DRY.call ? ' [DRY_RUN — rollback]' : ''))
    end
  end

  desc 'Limpeza de dados D1–D4 da varredura de fichas (transacional, idempotente, por critério estável)'
  task cleanup_sheet_data: :environment do
    # Ordem: D4 (lixo) e D1 (ghosts) primeiro; D2 (dedup subclasses) depois;
    # D3 (spell) por último. Cada subtask é transacional por si.
    %w[d4 d1 d2 d3].each do |t|
      Rake::Task["dnd:cleanup_sheet_data:#{t}"].invoke
    end
    puts '[dnd:cleanup_sheet_data] Todos os passos D1–D4 concluídos.'
  end
end
