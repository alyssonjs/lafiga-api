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
  { name: 'Alice', username: 'alice123', email: 'alice@example.com', phone: '1234567890', password_digest: 'password', role_id: Role.find_by(name: 'Admin').id },
  { name: 'Bob', username: 'bob456', email: 'bob@example.com', phone: '9876543210', password_digest: 'password', role_id: Role.find_by(name: 'User').id }
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

puts 'Seed data loaded successfully!'
