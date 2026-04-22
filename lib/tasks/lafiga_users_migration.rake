# frozen_string_literal: true

# Migração de contas de utilizador entre ambientes: exporta lista sem secrets,
# importa com password inicial vinda de ENV.
#
# Ver api/config/users_migration.example.yml
module LafigaUsersMigrationHelpers
  module_function

  # Se USERS_MIGRATION_EMAIL_DOMAIN=lafiga.com, reescreve cada email para
  # `local@lafiga.com` (útil quando a BD local tem @example.com / @lafiga.test).
  def export_email_for_migration(raw_email)
    email = raw_email.to_s.strip.downcase
    domain = ENV["USERS_MIGRATION_EMAIL_DOMAIN"].to_s.strip.downcase.presence
    return email if domain.blank? || email.blank?
    local = email.split("@", 2).first
    return email if local.blank?
    "#{local}@#{domain}"
  end
end

namespace :lafiga do
  namespace :users do
    desc "Exporta todos os User (sem password) para YAML no STDOUT ou USERS_MIGRATION_OUT. Opcional: USERS_MIGRATION_EMAIL_DOMAIN=lafiga.com para homogeneizar domínio. USERS_MIGRATION_EXPORT_EXCLUDE_IDS=3,416 para excluir contas de teste. Correr na BD fonte (ex.: local)."
    task export_for_migration: :environment do
      require "yaml"

      exclude_ids = ENV["USERS_MIGRATION_EXPORT_EXCLUDE_IDS"].to_s.split(",").map { |s| s.strip.to_i }.reject(&:zero?)

      scope = User.includes(:role).order(:id)
      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?

      rows = scope.map do |u|
        {
          "email" => LafigaUsersMigrationHelpers.export_email_for_migration(u.email),
          "username" => u.username.to_s,
          "name" => u.name.to_s,
          "phone" => u.phone.to_s,
          "role" => u.role&.name.to_s
        }
      end

      out = { "users" => rows }
      yml = YAML.dump(out)

      dest = ENV["USERS_MIGRATION_OUT"].to_s.strip
      if dest.present?
        File.write(dest, yml)
        puts "[lafiga:users] Escrito: #{dest} (#{rows.size} users)"
      else
        $stdout << yml
      end
      dom = ENV["USERS_MIGRATION_EMAIL_DOMAIN"].to_s.strip
      puts "[lafiga:users] Emails reescritos para @#{dom}" if dom.present?
    end

    desc "Importa users de USERS_MIGRATION_YML (defeito: config/users_migration.yml). Novos: password=USERS_MIGRATION_PASSWORD ou PROD_BOOTSTRAP_PASSWORD. Existentes: só atualiza name/phone/username/role se UPDATE_EXISTING=1"
    task import_from_yaml: :environment do
      require "yaml"

      path = ENV["USERS_MIGRATION_YML"].to_s.strip.presence || Rails.root.join("config", "users_migration.yml")
      path = path.to_s
      unless File.file?(path)
        abort "[lafiga:users] Ficheiro inexistente: #{path} — gera com export_for_migration ou copia a partir de config/users_migration.example.yml"
      end

      data = YAML.load_file(path) || {}
      list = Array(data["users"] || data[:users])
      if list.empty?
        abort "[lafiga:users] Nenhum user na chave 'users' em #{path}"
      end

      pwd = ENV["USERS_MIGRATION_PASSWORD"].to_s.strip.presence || ENV["PROD_BOOTSTRAP_PASSWORD"].to_s.strip.presence
      needs_new = list.any? do |row|
        row = (row || {}).stringify_keys
        row["email"].present? && !User.exists?(email: row["email"].to_s.strip.downcase)
      end
      if needs_new && pwd.blank? && Rails.env.production?
        abort "[lafiga:users] Criação de novos users em production: defina USERS_MIGRATION_PASSWORD (ou PROD_BOOTSTRAP_PASSWORD)"
      end
      pwd ||= "password" unless Rails.env.production?

      update_existing = %w[1 true yes].include?(ENV["UPDATE_EXISTING"].to_s.strip.downcase)

      created = 0
      updated = 0
      skipped = 0

      list.each do |row|
        row = (row || {}).stringify_keys
        email = row["email"].to_s.strip.downcase
        if email.blank?
          puts "  • Ignorado: sem email | #{row.inspect}"
          skipped += 1
          next
        end

        role_name = row["role"].to_s.strip.presence || "Player"
        role = Role.where("LOWER(roles.name) = ?", role_name.downcase).first
        unless role
          puts "  • Ignorado: role desconhecida #{role_name.inspect} | #{email}"
          skipped += 1
          next
        end

        user = User.find_or_initialize_by(email: email)
        is_new = user.new_record?

        if is_new
          user.assign_attributes(
            username: row["username"].to_s.presence || email.split("@").first.parameterize.underscore[0, 32],
            name: row["name"].to_s.presence || email,
            phone: row["phone"].to_s,
            role: role
          )
          user.password = pwd
          user.save!
          puts "  ✓ [criado] #{user.email} (#{user.username})"
          created += 1
        elsif update_existing
          user.update!(
            username: row["username"].to_s.presence || user.username,
            name: row["name"].to_s.presence || user.name,
            phone: row["phone"].to_s,
            role: role
          )
          puts "  ✓ [atualizado] #{user.email} (#{user.username})"
          updated += 1
        else
          puts "  • [já existia, skip] #{email} — defina UPDATE_EXISTING=1 para alinhar nome/phone/role"
          skipped += 1
        end
      end

      puts "[lafiga:users] Concluído. criados=#{created} atualizados=#{updated} ignorados/sem alteração=#{skipped}"
    end
  end
end
