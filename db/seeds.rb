# db/seeds.rb

# Limpando os dados antigos
Character.destroy_all
Schedule.destroy_all
Group.destroy_all
DateDimension.destroy_all
User.destroy_all
Role.destroy_all
ValidateJwtToken.destroy_all

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
    available: [true, false].sample
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

# Criando Raças
races = [
  {name: 'Anão'},
  {name: 'Elfo'},
  {name: 'Humano'},
  {name: 'Meio-Orc'},
  {name: 'Gnomo'},
]
races.each {|race| Race.create!(race)}

#Criando Sub Raças
sub_races = [
  {name: 'Anão da Montanha', race_id: Race.find_by(name: 'Anão').id},
  {name: 'Anão da Colina', race_id: Race.find_by(name: 'Anão').id},
  {name: 'Alto Elfo', race_id: Race.find_by(name: 'Elfo').id},
  {name: 'Elfo da Floresta', race_id: Race.find_by(name: 'Elfo').id},
  {name: 'Elfo Negro', race_id: Race.find_by(name: 'Elfo').id},
  {name: 'Gnomo da Rocha', race_id: Race.find_by(name: 'Gnomo').id},
  {name: 'Gnomo da Floresta', race_id: Race.find_by(name: 'Gnomo').id}
]
sub_races.each {|sub_race| SubRace.create!(sub_race)}

# Criando Classes
klasses = [
  {name: 'Bardo'},
  {name: 'Bárbaro'},
  {name: 'Bruxo'},
  {name: 'Clérigo'},
  {name: 'Druida'},
  {name: 'Feiticeiro'},
  {name: 'Guerreiro'},
  {name: 'Ladino'},
  {name: 'Mago'},
]
klasses.each {|klass| Klass.create!(klass)}

#Criando Sub Classes
sub_klasses = [
  {name: 'Caminho do Furioso', klass_id: Klass.find_by(name: 'Bárbaro').id},
  {name: 'Caminho do Guerreiro Totêmico', klass_id: Klass.find_by(name: 'Bárbaro').id},
  {name: 'Colégio do Conhecimento', klass_id: Klass.find_by(name: 'Bardo').id},
  {name: 'Colégio da Bravura', klass_id: Klass.find_by(name: 'Bardo').id},
  {name: 'Arquifada', klass_id: Klass.find_by(name: 'Bruxo').id},
  {name: 'Corruptor', klass_id: Klass.find_by(name: 'Bruxo').id},
  {name: 'Grande Antigo', klass_id: Klass.find_by(name: 'Bruxo').id}
  {name: 'Círculo da Terra', klass_id: Klass.find_by(name: 'Druida').id}
  {name: 'Círculo da Lua', klass_id: Klass.find_by(name: 'Druida').id}
]
sub_klasses.each {|sub_klass| SubKlass.create!(sub_klass)}

puts 'Seed data loaded successfully!'
