# db/seeds.rb

# Limpando os dados antigos (ordem para evitar FKs)
puts 'Limpando dados antigos…'

defined?(SheetPreparedSpell) && SheetPreparedSpell.destroy_all
defined?(SheetKnownSpell) && SheetKnownSpell.destroy_all
defined?(SpellSource) && SpellSource.destroy_all

defined?(SheetKlass) && SheetKlass.destroy_all
defined?(Sheet) && Sheet.destroy_all

ScheduleCharacter.destroy_all if defined?(ScheduleCharacter)
Schedule.destroy_all if defined?(Schedule)
Character.destroy_all if defined?(Character)
Group.destroy_all if defined?(Group)
DateDimension.destroy_all if defined?(DateDimension)

defined?(Spellcasting) && Spellcasting.destroy_all
defined?(ClassLevel) && ClassLevel.destroy_all
defined?(Feature) && Feature.destroy_all
defined?(Spell) && Spell.destroy_all

Board.destroy_all if defined?(Board)
User.destroy_all if defined?(User)
Role.destroy_all if defined?(Role)

SubKlass.destroy_all if defined?(SubKlass)
Klass.destroy_all if defined?(Klass)
SubRace.destroy_all if defined?(SubRace)
Race.destroy_all if defined?(Race)

ValidateJwtToken.destroy_all if defined?(ValidateJwtToken)

# Criando roles
roles = [
  { name: 'Admin', permissions: ['manage_users', 'manage_groups', 'view_reports'] },
  { name: 'User', permissions: ['view_groups', 'view_characters'] },
  { name: 'Guest', permissions: [] }
]
roles.each { |role| Role.create!(role) }

# Criando usuários
users = [
  { name: 'Alice', username: 'alice123', email: 'alice@example.com', phone: '1234567890', password: 'password', role_id: Role.find_by(name: 'Admin').id },
  { name: 'Bob', username: 'bob456', email: 'bob@example.com', phone: '9876543210', password: 'password', role_id: Role.find_by(name: 'User').id }
]
users.each { |user| User.create!(user) }

# Criando grupos
groups = [
  { name: 'Group A', season: 1, day: 1, year: 2024, description: 'A fun group for adventures!' },
  { name: 'Group B', season: 2, day: 10, year: 2024, description: 'Exploring the unknown.' }
]
groups.each { |group| Group.create!(group) }

# Criando personagens
characters = [
  { name: 'Hero', background: 'A brave hero.', user_id: User.find_by(username: 'alice123').id, group_id: Group.find_by(name: 'Group A').id },
  { name: 'Villain', background: 'A cunning villain.', user_id: User.find_by(username: 'bob456').id, group_id: Group.find_by(name: 'Group B').id }
]
characters.each { |character| Character.create!(character) }

# Criando dimensões de data
date_dimensions = (1..5).map do |i|
  {
    date: Date.today + i.days,
    year: (Date.today + i.days).year,
    month: (Date.today + i.days).month,
    day: (Date.today + i.days).day,
    day_of_week: (Date.today + i.days).cwday,
    day_name: (Date.today + i.days).strftime('%A'),
    is_weekend: [(Date.today + i.days).saturday?, (Date.today + i.days).sunday?].any?,
    available: true
  }
end
date_dimensions.each { |dd| DateDimension.create!(dd) }

# Criando horários (schedules)
schedules = [
  { status: 0, date_dimension_id: DateDimension.first.id, group_id: Group.first.id, title: 'Adventure Start' },
  { status: 1, date_dimension_id: DateDimension.last.id, group_id: Group.last.id, title: 'Final Battle' }
]
schedules.each { |schedule| Schedule.create!(schedule) }

# Criando tokens JWT
tokens = [
  { token: 'abc123' },
  { token: 'xyz789' }
]
tokens.each { |token| ValidateJwtToken.create!(token) }

########################################
# D&D – ENTIDADES BÁSICAS
########################################

############################
# Raças e Sub‑raças (SRD)
############################

# Criando Raças (completa)
[
  'Anão', 'Elfo', 'Humano', 'Draconato', 'Gnomo', 'Meio-Elfo', 'Meio-Orc', 'Halfling', 'Tiefling'
].each { |n| Race.create!(name: n) }

# Criando Sub‑raças
sub_races = []

# Anão
if (dwarf = Race.find_by(name: 'Anão'))
  sub_races << { name: 'Anão da Colina',    race_id: dwarf.id }
  sub_races << { name: 'Anão da Montanha',  race_id: dwarf.id }
end

# Elfo
if (elf = Race.find_by(name: 'Elfo'))
  sub_races << { name: 'Alto Elfo',            race_id: elf.id }
  sub_races << { name: 'Elfo da Floresta',     race_id: elf.id }
  sub_races << { name: 'Elfo Negro (Drow)',    race_id: elf.id }
end

# Humano
if (human = Race.find_by(name: 'Humano'))
  sub_races << { name: 'Humano Variante',      race_id: human.id }
end

# Gnomo
if (gnome = Race.find_by(name: 'Gnomo'))
  sub_races << { name: 'Gnomo da Floresta',    race_id: gnome.id }
  sub_races << { name: 'Gnomo da Rocha',       race_id: gnome.id }
end

# Halfling
if (halfling = Race.find_by(name: 'Halfling'))
  sub_races << { name: 'Pés Leves',            race_id: halfling.id }
  sub_races << { name: 'Robusto',              race_id: halfling.id }
end

sub_races.each { |sr| SubRace.create!(sr) }

########################################
# Classes e Subclasses (completas)
########################################

# Criando Classes (com campos úteis e subclass_level correto)
[
  {name: 'Bárbaro',    api_index: 'barbarian', hit_die: 12, spellcasting_ability: nil,   subclass_level: 3},
  {name: 'Bardo',      api_index: 'bard',      hit_die: 8,  spellcasting_ability: 'CHA', subclass_level: 3},
  {name: 'Bruxo',      api_index: 'warlock',   hit_die: 8,  spellcasting_ability: 'CHA', subclass_level: 1},
  {name: 'Clérigo',    api_index: 'cleric',    hit_die: 8,  spellcasting_ability: 'WIS', subclass_level: 1},
  {name: 'Druida',     api_index: 'druid',     hit_die: 8,  spellcasting_ability: 'WIS', subclass_level: 2},
  {name: 'Feiticeiro', api_index: 'sorcerer',  hit_die: 6,  spellcasting_ability: 'CHA', subclass_level: 1},
  {name: 'Guerreiro',  api_index: 'fighter',   hit_die: 10, spellcasting_ability: nil,   subclass_level: 3},
  {name: 'Ladino',     api_index: 'rogue',     hit_die: 8,  spellcasting_ability: nil,   subclass_level: 3},
  {name: 'Mago',       api_index: 'wizard',    hit_die: 6,  spellcasting_ability: 'INT', subclass_level: 2},
  {name: 'Monge',      api_index: 'monk',      hit_die: 8,  spellcasting_ability: nil,   subclass_level: 3},
  {name: 'Paladino',   api_index: 'paladin',   hit_die: 10, spellcasting_ability: 'CHA', subclass_level: 3},
  {name: 'Patrulheiro',api_index: 'ranger',    hit_die: 10, spellcasting_ability: 'WIS', subclass_level: 3},
].each { |k| Klass.create!(k) }

# Criando Subclasses (completas, nomes PT‑BR alinhados ao ClassRules)
sub_klasses = []

# Bárbaro
if (k = Klass.find_by(name: 'Bárbaro'))
  sub_klasses += [
    {name: 'Caminho do Berserker', klass_id: k.id},
    {name: 'Caminho do Totem', klass_id: k.id},
  ]
end

# Bardo
if (k = Klass.find_by(name: 'Bardo'))
  sub_klasses += [
    {name: 'Colégio do Conhecimento', klass_id: k.id},
    {name: 'Colégio do Valor', klass_id: k.id},
  ]
end

# Bruxo
if (k = Klass.find_by(name: 'Bruxo'))
  sub_klasses += [
    {name: 'O Ínfero', klass_id: k.id},
    {name: 'A Rainha/Príncipe das Fadas', klass_id: k.id},
    {name: 'O Grande Antigo', klass_id: k.id},
  ]
end

# Clérigo (Domínios)
if (k = Klass.find_by(name: 'Clérigo'))
  %w[Vida Luz Conhecimento Natureza Tempestade Trapaça Guerra].each do |nm|
    sub_klasses << { name: nm, klass_id: k.id }
  end
end

# Druida (Círculos)
if (k = Klass.find_by(name: 'Druida'))
  sub_klasses += [
    {name: 'Círculo da Terra', klass_id: k.id},
    {name: 'Círculo da Lua', klass_id: k.id},
  ]
end

# Guerreiro (Arquétipos)
if (k = Klass.find_by(name: 'Guerreiro'))
  sub_klasses += [
    {name: 'Campeão', klass_id: k.id},
    {name: 'Mestre de Batalha', klass_id: k.id},
    {name: 'Cavaleiro Arcano', klass_id: k.id},
  ]
end

# Monge (Tradições)
if (k = Klass.find_by(name: 'Monge'))
  sub_klasses += [
    {name: 'Caminho da Mão Aberta', klass_id: k.id},
    {name: 'Caminho da Sombra', klass_id: k.id},
    {name: 'Caminho dos Quatro Elementos', klass_id: k.id},
  ]
end

# Paladino (Juramentos)
if (k = Klass.find_by(name: 'Paladino'))
  sub_klasses += [
    {name: 'Juramento da Devoção', klass_id: k.id},
    {name: 'Juramento dos Anciões', klass_id: k.id},
    {name: 'Juramento da Vingança', klass_id: k.id},
  ]
end

# Patrulheiro (Conclaves)
if (k = Klass.find_by(name: 'Patrulheiro'))
  sub_klasses += [
    {name: 'Caçador', klass_id: k.id},
    {name: 'Mestre das Feras', klass_id: k.id},
  ]
end

# Ladino (Arquétipos)
if (k = Klass.find_by(name: 'Ladino'))
  sub_klasses += [
    {name: 'Ladrão', klass_id: k.id},
    {name: 'Assassino', klass_id: k.id},
    {name: 'Trapaceiro Arcano', klass_id: k.id},
  ]
end

# Feiticeiro (Origens)
if (k = Klass.find_by(name: 'Feiticeiro'))
  sub_klasses += [
    {name: 'Linhagem Dracônica', klass_id: k.id},
    {name: 'Magia Selvagem', klass_id: k.id},
  ]
end

# Mago (Escolas)
if (k = Klass.find_by(name: 'Mago'))
  %w[Abjuração Conjuração Adivinhação Encantamento Evocação Ilusão Necromancia Transmutação].each do |nm|
    sub_klasses << { name: nm, klass_id: k.id }
  end
end

sub_klasses.each { |sk| SubKlass.create!(sk) }

########################################
# D&D – EXEMPLOS DE MAGIAS E PROGRESSÃO
########################################

# Magias simples para exemplo
fire_bolt = Spell.find_or_create_by!(api_index: 'fire-bolt') do |s|
  s.name = 'Fire Bolt'
  s.level = 0
  s.school = 'Evocation'
  s.range = '120 feet'
  s.components = %w[V S].to_json
  s.ritual = false
  s.duration = 'Instantaneous'
  s.concentration = false
  s.casting_time = '1 action'
  s.desc = ['You hurl a mote of fire...'].to_json
end

magic_missile = Spell.find_or_create_by!(api_index: 'magic-missile') do |s|
  s.name = 'Magic Missile'
  s.level = 1
  s.school = 'Evocation'
  s.range = '120 feet'
  s.components = %w[V S].to_json
  s.ritual = false
  s.duration = 'Instantaneous'
  s.concentration = false
  s.casting_time = '1 action'
  s.desc = ['Three glowing darts of magical force...'].to_json
end

eldritch_blast = Spell.find_or_create_by!(api_index: 'eldritch-blast') do |s|
  s.name = 'Eldritch Blast'
  s.level = 0
  s.school = 'Evocation'
  s.range = '120 feet'
  s.components = %w[V S].to_json
  s.ritual = false
  s.duration = 'Instantaneous'
  s.concentration = false
  s.casting_time = '1 action'
  s.desc = ['A beam of crackling energy...'].to_json
end

# Class levels + spellcasting (nível 1) para Mago e Bruxo
wizard = Klass.find_by(api_index: 'wizard')
warlock = Klass.find_by(api_index: 'warlock')

wizard_l1 = wizard.class_levels.find_or_create_by!(level: 1) do |cl|
  cl.prof_bonus = 2
  cl.ability_score_bonuses = 0
end
wizard_l1.create_spellcasting!(level: 1, cantrips_known: 3, spells_known: nil, spell_slots: { '1' => 2 }.to_json) unless wizard_l1.spellcasting

warlock_l1 = warlock.class_levels.find_or_create_by!(level: 1) do |cl|
  cl.prof_bonus = 2
  cl.ability_score_bonuses = 0
end
warlock_l1.create_spellcasting!(level: 1, cantrips_known: 2, spells_known: 2, spell_slots: {}.to_json, pact_slot_level: 1, pact_slots: { 'pact' => 1 }.to_json) unless warlock_l1.spellcasting

# Fontes de magias (classe e raça)
SpellSource.find_or_create_by!(source_type: 'Klass', source_id: wizard.id, spell_id: fire_bolt.id)
SpellSource.find_or_create_by!(source_type: 'Klass', source_id: wizard.id, spell_id: magic_missile.id)
SpellSource.find_or_create_by!(source_type: 'Klass', source_id: warlock.id, spell_id: eldritch_blast.id)

# Exemplo racial: Elfo com cantrip "Fire Bolt" sempre disponível (apenas demonstração)
elf = Race.find_by(name: 'Elfo')
SpellSource.find_or_create_by!(source_type: 'Race', source_id: elf.id, spell_id: fire_bolt.id, always_prepared: true)

# Criar Sheets para personagens existentes com atributos/HP e classes
hero = Character.find_by(name: 'Hero')
villain = Character.find_by(name: 'Villain')

hero_sheet = Sheet.find_or_create_by!(character_id: hero.id) do |s|
  s.race_id = elf.id
  s.sub_race_id = SubRace.find_by(race_id: elf.id)&.id
  s.str = 10; s.dex = 14; s.con = 12; s.int = 16; s.wis = 10; s.cha = 8
  s.hp_max = 8; s.hp_current = 8; s.temp_hp = 0
end

# Hero como Mago 1
hero_wizard = SheetKlass.find_or_create_by!(sheet_id: hero_sheet.id, klass_id: wizard.id) do |sk|
  sk.level = 1
end

# Preparadas do Mago (exemplo) e conhecidas (cantrip)
SheetPreparedSpell.find_or_create_by!(sheet_id: hero_sheet.id, spell_id: magic_missile.id) do |sp|
  sp.auto = false
  sp.source = 'class'
end
SheetKnownSpell.find_or_create_by!(sheet_klass_id: hero_wizard.id, spell_id: fire_bolt.id) do |ks|
  ks.gained_at_class_level = 1
  ks.source = 'class'
end

villain_sheet = Sheet.find_or_create_by!(character_id: villain.id) do |s|
  s.race_id = Race.find_by(name: 'Humano').id
  s.sub_race_id = nil
  s.str = 12; s.dex = 12; s.con = 14; s.int = 8; s.wis = 10; s.cha = 16
  s.hp_max = 8; s.hp_current = 8; s.temp_hp = 0
end

# Villain como Bruxo 1
villain_warlock = SheetKlass.find_or_create_by!(sheet_id: villain_sheet.id, klass_id: warlock.id) do |sk|
  sk.level = 1
end

SheetKnownSpell.find_or_create_by!(sheet_klass_id: villain_warlock.id, spell_id: eldritch_blast.id) do |ks|
  ks.gained_at_class_level = 1
  ks.source = 'class'
end

########################################
# Fim dos exemplos D&D
########################################

puts 'Seeds concluídos com sucesso!'

# =========================
# Extra: 10 personagens aleatórios (User: Bob)
# =========================
begin
  bob = User.find_by(username: 'bob456') || User.find_by(name: 'Bob')
  if bob
    puts "\nGerando 10 personagens aleatórios para #{bob.username || bob.name}…"
    created = RandomCharacterGenerator.generate_random_characters(count: 10, max_level_per_char: 20, user: bob)
    puts "Criados: #{created.map(&:name).join(', ')}"
  else
    puts '\nUsuário Bob não encontrado; pulando geração de personagens aleatórios.'
  end
rescue => e
  puts "\nFalha ao gerar personagens aleatórios: #{e.message}"
end
