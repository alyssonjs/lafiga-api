# frozen_string_literal: true

namespace :lafiga do
  namespace :users do
    desc <<~DESC.squish
      Cria admins (alysson/bruno @lafiga.com) e atualiza emails dos utilizadores demo
      para @lafiga.com. Config: config/production_users.yml.
      Em production use PROD_BOOTSTRAP_PASSWORD para novos utilizadores.
    DESC
    task seed_production: :environment do
      path = Rails.root.join('config', 'production_users.yml')
      unless File.exist?(path)
        puts "[lafiga:users] Ficheiro em falta: #{path}"
        exit 1
      end

      data = YAML.load_file(path) || {}
      pwd = ENV['PROD_BOOTSTRAP_PASSWORD'].to_s.presence
      admins = Array(data['admins'])
      migrations = Array(data['demo_email_migration'])

      needs_admin_password = admins.any? do |row|
        row = (row || {}).stringify_keys
        !User.exists?(email: row['email'].to_s.strip.downcase)
      end
      if Rails.env.production? && needs_admin_password && pwd.blank?
        abort '[lafiga:users] Em production defina PROD_BOOTSTRAP_PASSWORD para criar admins novos.'
      end
      pwd ||= 'password'

      puts '[lafiga:users] --- admins ---'
      admins.each do |row|
        row = (row || {}).symbolize_keys
        role = Role.find_by!(name: row[:role].to_s)
        user = User.find_or_initialize_by(email: row[:email].to_s.strip.downcase)
        user.assign_attributes(
          username: row[:username].to_s,
          name: row[:name].to_s,
          phone: row[:phone].to_s,
          role: role
        )
        created = user.new_record?
        user.password = pwd if created
        user.save!
        puts "  ✓ #{user.email} (#{user.username})#{created ? ' [criado]' : ' [já existia]'}"
      end

      puts '[lafiga:users] --- emails demo (@lafiga.com) ---'
      migrations.each do |row|
        row = row.symbolize_keys
        user = User.find_by(username: row[:username].to_s)
        unless user
          puts "  • Ignorado (não existe): username=#{row[:username]}"
          next
        end
        new_email = row[:email].to_s.strip.downcase
        if user.email == new_email
          puts "  • Já atualizado: #{user.username} -> #{new_email}"
          next
        end
        user.update!(email: new_email)
        puts "  ✓ #{row[:username]} -> #{new_email}"
      end

      puts '[lafiga:users] Concluído.'
    end
  end
end
