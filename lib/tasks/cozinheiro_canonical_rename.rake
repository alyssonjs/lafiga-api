# frozen_string_literal: true

# Renomeia api_indexes legados das subclasses do Cozinheiro para canônico (PDF).
# Migra SheetKlass/SubKlassLevel/SpellSource referências antes de deletar/renomear.
# Idempotente — pode rodar múltiplas vezes sem efeitos colaterais.
#
# Mapeamento (legacy → canonical PDF):
#   mestre-da-fritura       → sous-chef
#   alquimista-gourmet      → mestre-cuca
#   mestre-do-fogo-e-fumaca → sargento-alimentar
#   cantineiro-de-guerra    → mestre-cervejeiro
#   doceiro-encantado       (mantém — homebrew Lafiga)
#   amassador-de-monstros   (novo — não tem legado)
#
# Uso:
#   bundle exec rails dnd:rename_cozinheiro_canonical
#   bundle exec rails dnd:rename_cozinheiro_canonical[dry_run=true]
#
# Após renomear, rode `dnd:apply_subclass_overrides` para popular features novas.

namespace :dnd do
  RENAME_MAP = {
    'mestre-da-fritura'        => 'sous-chef',
    'alquimista-gourmet'       => 'mestre-cuca',
    'mestre-do-fogo-e-fumaca'  => 'sargento-alimentar',
    'cantineiro-de-guerra'     => 'mestre-cervejeiro'
  }.freeze

  CANONICAL_NAMES = {
    'sous-chef'              => 'Sous Chef',
    'sargento-alimentar'     => 'Sargento Alimentar',
    'mestre-cuca'            => 'Mestre-Cuca',
    'mestre-cervejeiro'      => 'Mestre Cervejeiro',
    'amassador-de-monstros'  => 'Amassador de Monstros',
    'doceiro-encantado'      => 'Doceiro Encantado'
  }.freeze

  desc 'Renomeia subclasses legadas do Cozinheiro para os api_indexes canônicos do PDF'
  task :rename_cozinheiro_canonical, [:dry_run] => :environment do |_t, args|
    dry_run = args[:dry_run].to_s.downcase == 'true'
    prefix = dry_run ? '[DRY-RUN] ' : ''

    cook = Klass.find_by(api_index: 'cozinheiro')
    unless cook
      puts "[cook-rename] ERRO: Klass 'cozinheiro' não encontrada. Rode dnd:apply_subclass_overrides primeiro."
      next
    end

    puts "#{prefix}Iniciando rename de subclasses do Cozinheiro (klass_id=#{cook.id})…"

    ActiveRecord::Base.transaction do
      RENAME_MAP.each do |legacy_idx, canonical_idx|
        legacy = SubKlass.find_by(api_index: legacy_idx, klass_id: cook.id)
        canonical = SubKlass.find_by(api_index: canonical_idx, klass_id: cook.id)

        if legacy.nil? && canonical.nil?
          puts "  • #{legacy_idx} → #{canonical_idx}: nenhuma linha (skip)"
          next
        end

        if legacy && canonical && legacy.id != canonical.id
          # Both exist — migrate refs from legacy to canonical, then delete legacy
          puts "#{prefix}  • #{legacy_idx} (##{legacy.id}) + #{canonical_idx} (##{canonical.id}): migrando refs e deletando legado"
          unless dry_run
            SubKlassLevel.where(sub_klass_id: legacy.id).update_all(sub_klass_id: canonical.id)
            SpellSource.where(source_type: 'SubKlass', source_id: legacy.id).update_all(source_id: canonical.id)
            SheetKlass.where(sub_klass_id: legacy.id).update_all(sub_klass_id: canonical.id)
            legacy.destroy!
          end
        elsif legacy && canonical.nil?
          # Only legacy exists — rename in place
          new_name = CANONICAL_NAMES[canonical_idx] || legacy.name
          puts "#{prefix}  • #{legacy_idx} (##{legacy.id}) → renomeando api_index para #{canonical_idx} e nome para '#{new_name}'"
          unless dry_run
            legacy.update!(api_index: canonical_idx, name: new_name)
          end
        elsif canonical
          # Only canonical exists — nothing to migrate
          puts "  • #{canonical_idx} (##{canonical.id}): já canônico (skip)"
        end
      end

      # Garante que o nome de doceiro-encantado e amassador-de-monstros estão corretos
      ['doceiro-encantado', 'amassador-de-monstros'].each do |idx|
        sub = SubKlass.find_by(api_index: idx, klass_id: cook.id)
        next unless sub
        expected_name = CANONICAL_NAMES[idx]
        if sub.name != expected_name
          puts "#{prefix}  • #{idx}: corrigindo nome '#{sub.name}' → '#{expected_name}'"
          sub.update!(name: expected_name) unless dry_run
        end
      end
    end

    puts "#{prefix}Concluído. #{dry_run ? 'Nenhuma alteração persistida.' : 'Mudanças aplicadas.'}"
    puts "Próximo passo: rode `bundle exec rails dnd:apply_subclass_overrides` para popular as features canônicas."
  end

  desc 'Verifica estado atual das subclasses do Cozinheiro (read-only)'
  task verify_cozinheiro_canonical: :environment do
    cook = Klass.find_by(api_index: 'cozinheiro')
    unless cook
      puts "[cook-verify] Klass 'cozinheiro' não encontrada"
      next
    end

    puts "Subclasses do Cozinheiro (#{cook.sub_klasses.count} total):"
    cook.sub_klasses.order(:api_index).each do |sk|
      status = if RENAME_MAP.key?(sk.api_index)
                 "⚠️  LEGADO (deveria virar #{RENAME_MAP[sk.api_index]})"
               elsif CANONICAL_NAMES.key?(sk.api_index)
                 "✅ canônico"
               else
                 "❓ desconhecido"
               end
      puts "  • [#{sk.id}] #{sk.api_index} — '#{sk.name}' #{status}"
    end

    expected = CANONICAL_NAMES.keys.sort
    actual = cook.sub_klasses.pluck(:api_index).sort
    missing = expected - actual
    puts "\nFaltando (precisa criar via apply_subclass_overrides): #{missing.inspect}" if missing.any?
    puts "\nTotal canônico esperado: 6 (5 do PDF + Doceiro Encantado homebrew)"
  end
end
