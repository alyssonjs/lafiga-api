# frozen_string_literal: true

# Seeder usado pelos specs de Phase 2 (resilience das fichas importadas
# do XLSX da campanha LaFiga).
#
# Lê api/docs/canonical_indexes.json (gerado por tmp/export_canonical_indexes.rb)
# e cria, no DB de teste atual, todos os Klass / SubKlass / Race / SubRace /
# Background / Alignment necessários para que o CharacterProvisioningService
# possa resolver as fichas reais por api_index.
#
# IMPORTANTE: cria apenas o esqueleto mínimo (api_index + name + hit_die +
# subclass_level). Não popula `levels_json`, descrições, sub-features etc —
# para Phase 2 baseline (provision em level 1) isso é suficiente. Para Phase
# 2.1 (level-up até o level real da ficha) provavelmente vamos precisar do
# seed completo via `dnd:import`.
module ImportedSheetsSeeder
  module_function

  CANONICAL_PATH = Rails.root.join('docs', 'canonical_indexes.json')
  IMPORTED_PATH  = Rails.root.join('docs', 'imported_sheets.json')

  def canonical
    @canonical ||= JSON.parse(File.read(CANONICAL_PATH))
  end

  def imported_sheets
    @imported_sheets ||= JSON.parse(File.read(IMPORTED_PATH))
  end

  # Sheets reais para audit (exclui template + ignorados)
  def auditable_sheets
    imported_sheets.reject { |s| s.dig('meta', 'skip_audit') }
  end

  def seed_all!
    seed_klasses!
    seed_subklasses!
    seed_races!
    seed_subraces!
    seed_backgrounds!
    seed_alignments!
  end

  def seed_klasses!
    canonical['klasses'].each do |api_index, info|
      Klass.find_or_create_by!(api_index: api_index) do |k|
        k.name           = info['name']
        k.hit_die        = info['hit_die'].to_i.nonzero? || 8
        k.subclass_level = info['subclass_level'].to_i.nonzero? || 3
      end
    end
  end

  def seed_subklasses!
    canonical['subklasses'].each do |class_idx, subs|
      klass = Klass.find_by(api_index: class_idx)
      next unless klass

      subs.each do |sub_idx, info|
        SubKlass.find_or_create_by!(api_index: sub_idx, klass_id: klass.id) do |s|
          s.name = info['name']
        end
      end
    end
  end

  def seed_races!
    canonical['races'].each do |api_index, info|
      Race.find_or_create_by!(api_index: api_index) { |r| r.name = info['name'] }
    end
  end

  def seed_subraces!
    canonical['subraces'].each do |race_idx, subs|
      race = Race.find_by(api_index: race_idx)
      next unless race

      subs.each do |sub_idx, info|
        SubRace.find_or_create_by!(api_index: sub_idx, race_id: race.id) do |s|
          s.name = info['name']
        end
      end
    end
  end

  def seed_backgrounds!
    canonical['backgrounds'].each do |api_index, info|
      Background.find_or_create_by!(api_index: api_index) do |b|
        b.name         = info['name']
        b.feature_name = info['feature_name']
        b.feature_desc = info['feature_desc']
      end
    end
  end

  def seed_alignments!
    canonical['alignments'].each do |api_index, info|
      Alignment.find_or_create_by!(api_index: api_index) { |a| a.name = info['name'] }
    end
  end
end

RSpec.configure do |config|
  config.include ImportedSheetsSeeder, type: :service
end
