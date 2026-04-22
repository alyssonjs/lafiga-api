# frozen_string_literal: true

require 'rake'

SEED_SCOPE = ENV['SEED_ONLY']&.strip
RACE_ONLY = SEED_SCOPE == 'races' || %w[1 true yes].include?(ENV['RACE_ONLY']&.to_s&.strip&.downcase)

FULL_PURGE_LIST = %w[
  SheetPreparedSpell SheetKnownSpell SpellSource SheetKlass Sheet
  ScheduleCharacter Schedule DateDimension Character Group
  Spellcasting ClassLevel Feature Spell
  ChannelMembership Channel Message Board
  SheetFeat SheetItem Item MagicItem Feat
  SubKlassLevel SubKlass Klass RaceTrait
  Alignment Background Race SubRace
  ValidateJwtToken Role User
].freeze
RACE_PURGE_LIST = %w[RaceTrait SubRace Race].freeze
MODELS_TO_PURGE = (RACE_ONLY ? RACE_PURGE_LIST : FULL_PURGE_LIST).freeze


def safe_purge(model_name)
  klass = model_name.safe_constantize
  return unless klass

  klass.delete_all if klass.respond_to?(:delete_all)
rescue => e
  puts "  • Falha ao limpar #{model_name}: #{e.message}"
end


def seed_races_from_rules
  puts 'Importando raças a partir de config/race_rules.yml…'

  bundle = RaceRules.reload!
  race_defs = bundle[:races] || {}
  trait_defs = bundle[:trait_definitions] || {}

  trait_records = {}
  trait_defs.each do |key, cfg|
    key_str = key.to_s
    trait = Trait.find_or_initialize_by(api_index: key_str)
    trait.name = cfg[:name].presence || key_str.titleize
    description_parts = []
    description_parts << cfg[:description].to_s.strip if cfg[:description].present?
    if cfg[:sheet_impact].present?
      description_parts << "Impacto na ficha: #{cfg[:sheet_impact]}"
    end
    trait.description = description_parts.reject(&:blank?).join("\n\n")
    trait.save!
    trait_records[key.to_sym] = trait
  end

  race_defs.each_value do |race_cfg|
    race = Race.find_or_initialize_by(name: race_cfg[:name])
    race.api_index = (race_cfg[:id].presence || race_cfg[:name].to_s.parameterize(separator: '_'))
    race.save!

    RaceTrait.where(race: race).delete_all

    assign_race_traits(race, nil, race_cfg[:traits], trait_records)

    (race_cfg[:subraces] || {}).each_value do |sub_cfg|
      subrace = SubRace.find_or_initialize_by(race: race, name: sub_cfg[:name])
      subrace.api_index = (sub_cfg[:id].presence || sub_cfg[:name].to_s.parameterize(separator: '_'))
      subrace.save!
      assign_race_traits(race, subrace, sub_cfg[:traits], trait_records)
    end
  end
end


def assign_race_traits(race, subrace, traits_cfg, trait_records)
  Array(traits_cfg).each do |entry|
    entry_hash = entry.respond_to?(:deep_symbolize_keys) ? entry.deep_symbolize_keys : { key: entry.to_sym }
    key = entry_hash[:key]&.to_sym
    next unless key

    trait = trait_records[key] || Trait.find_or_initialize_by(api_index: key.to_s)
    trait.name ||= key.to_s.titleize
    trait.save! unless trait.persisted?
    trait_records[key] ||= trait

    metadata = entry_hash.except(:key)
    RaceTrait.create!(race: race, sub_race: subrace, trait: trait, metadata: metadata)
  end
end

puts 'Limpando dados antigos…'
ActiveRecord::Base.connection.disable_referential_integrity do
  MODELS_TO_PURGE.each { |name| safe_purge(name) }
end

if RACE_ONLY
  seed_races_from_rules
  puts '\nSeeds concluídos.'
  return
end

puts 'Criando perfis e usuários base…'
# Roles do produto:
#   - DM     => admin do site todo. Mestra qualquer grupo/sessão. Único papel
#               com permissão para mutar estado de combate, NPCs, session_logs
#               e configurações globais.
#   - Player => usuário comum. Cria personagens, participa de grupos, joga
#               sessões. NÃO pode iniciar combate nem editar NPCs.
#   - Admin  => legado. Mantido como alias de DM até a migração completa de
#               specs/checks antigos. `Group.user_is_dm?` aceita ambos.
#   - User / Guest => legado dos seeds originais; serão removidos após a
#               migração dos specs que ainda referenciam.
roles = [
  { name: 'DM',     permissions: %w[manage_users manage_groups manage_sessions manage_combat manage_catalog view_reports] },
  { name: 'Player', permissions: %w[view_groups view_characters create_character join_session] },
  { name: 'Admin',  permissions: %w[manage_users manage_groups view_reports] },  # legado — alias de DM
  { name: 'User',   permissions: %w[view_groups view_characters] },               # legado — alias de Player
  { name: 'Guest',  permissions: [] }
]
roles.each do |attrs|
  role = Role.find_or_initialize_by(name: attrs[:name])
  role.permissions = attrs[:permissions]
  role.save!
end

# Usuários de exemplo:
#   - dm@lafiga.test       => Role: DM. Use este para testar combate/wizard de DM.
#   - alice@example.com    => Role: Player. Personagem em Group A.
#   - bob@example.com      => Role: Player. Personagem em Group B.
users = [
  { name: 'Carol Mestre', username: 'carol_dm', email: 'dm@lafiga.test',     phone: '0000000000', password: 'password', role: Role.find_by!(name: 'DM') },
  { name: 'Alice',        username: 'alice123', email: 'alice@example.com',  phone: '1234567890', password: 'password', role: Role.find_by!(name: 'Player') },
  { name: 'Bob',          username: 'bob456',   email: 'bob@example.com',    phone: '9876543210', password: 'password', role: Role.find_by!(name: 'Player') }
]
users.each do |attrs|
  user = User.find_or_initialize_by(username: attrs[:username])
  user.update!(attrs)
end

puts 'Criando grupos e agendas de exemplo…'
groups = [
  { name: 'Group A', season: 1, day: 1, year: 2024, description: 'Mesa experimental A' },
  { name: 'Group B', season: 2, day: 10, year: 2024, description: 'Mesa experimental B' }
]
groups.each do |attrs|
  Group.find_or_create_by!(name: attrs[:name]) { |g| g.update!(attrs) }
end

characters = [
  { name: 'Hero', background: 'Um herói destemido.', user: User.find_by!(username: 'alice123'), group: Group.find_by!(name: 'Group A') },
  { name: 'Villain', background: 'Um antagonista ardiloso.', user: User.find_by!(username: 'bob456'), group: Group.find_by!(name: 'Group B') }
]
characters.each do |attrs|
  Character.find_or_create_by!(name: attrs[:name]) { |c| c.update!(attrs) }
end

puts 'Criando dimensões de data…'
(0...5).each do |offset|
  date = Date.today + offset.days
  DateDimension.find_or_create_by!(date: date) do |dd|
    dd.year = date.year
    dd.month = date.month
    dd.day = date.day
    dd.day_of_week = date.cwday
    dd.day_name = date.strftime('%A')
    dd.is_weekend = date.saturday? || date.sunday?
    dd.available = true
  end
end

puts 'Criando agendas…'
schedules = [
  { status: 0, date_dimension: DateDimension.order(:date).first, group: Group.first, title: 'Adventure Start' },
  { status: 1, date_dimension: DateDimension.order(:date).last, group: Group.last, title: 'Final Battle' }
]
schedules.each do |attrs|
  Schedule.find_or_create_by!(title: attrs[:title]) { |s| s.update!(attrs) }
end

puts 'Criando tokens JWT de exemplo…'
%w[abc123 xyz789].each do |token|
  ValidateJwtToken.find_or_create_by!(token: token)
end

# Raças e sub-raças
seed_races_from_rules

puts 'Carregando dados de D&D através das tarefas rake…'
Rails.application.load_tasks unless Rake::Task.task_defined?('dnd:bootstrap')


def run_seed_task(task_name)
  unless Rake::Task.task_defined?(task_name)
    puts "  • Tarefa #{task_name} não encontrada; verifique se foi declarada."
    return false
  end

  task = Rake::Task[task_name]
  task.reenable
  task.invoke
  true
rescue => e
  puts "  • Falha ao executar #{task_name}: #{e.message}"
  false
end

# Após dnd:load_local: opcional SEED_MONSTERS=1 (db/seeds/monsters.json) e
# SEED_IMPORTED_SHEETS_REHYDRATE=1 (docs/imported_sheets.json) — ver api/README.md
preferred_task = if ENV['SEED_DND_TASK'].present?
  ENV['SEED_DND_TASK']
elsif ENV['SKIP_DND_API'] == '1'
  'dnd:load_local'
else
  'dnd:bootstrap'
end

ran = run_seed_task(preferred_task)
run_seed_task('dnd:load_local') unless ran || preferred_task == 'dnd:load_local'

puts '\nSeeds concluídos.'
