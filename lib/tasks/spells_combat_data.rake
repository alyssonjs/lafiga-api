# frozen_string_literal: true

# Importa `spells.combat_data` a partir do seed derivado da Open5e (SRD 5e)
# + curadoria manual. Lógica em `lib/spell_combat_data_importer.rb`.
#
# Fontes:
#   - db/seeds/spell_combat_data.json   (auto-derivado da Open5e)
#   - config/spell_combat_overrides.yml (curadoria manual)
#
# Casa por `spells.api_index` (slug EN). Idempotente. Não toca magias sem
# entrada (combat_data continua `{}`).
#
# Uso:
#   docker exec lafiga_api bundle exec rails spells:import_combat_data
#   docker exec lafiga_api bundle exec rails spells:import_combat_data DRY_RUN=1
#   docker exec lafiga_api bundle exec rails spells:import_combat_data RESET=1   # zera antes
namespace :spells do
  desc 'Importa combat_data (dano/TR/área/alcance/upcast/cantrip/duração/condições) das magias (seed Open5e + overrides).'
  task import_combat_data: :environment do
    require Rails.root.join('lib/spell_combat_data_importer.rb').to_s
    SpellCombatDataImporter.import!(
      dry_run: ENV['DRY_RUN'].to_s == '1',
      reset:   ENV['RESET'].to_s == '1',
      logger:  ->(m) { puts m }
    )
  end
end
