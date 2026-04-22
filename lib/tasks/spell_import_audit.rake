# frozen_string_literal: true

require 'json'

namespace :spells do
  desc 'Lista nomes em docs/imported_sheets.json que SpellResolver nao resolve (spell_aliases / traducoes)'
  task audit_imported: :environment do
    path = Rails.root.join('docs', 'imported_sheets.json')
    unless File.exist?(path)
      puts "[spells:audit_imported] #{path} ausente — nada a fazer."
      next
    end

    SpellResolver.reset_caches!
    resolver = SpellResolver.new
    sheets = JSON.parse(File.read(path))
    names = []

    sheets.each do |sh|
      Array(sh['spells_listed']).each do |row|
        n = row['name'].to_s.strip
        next if n.blank?
        next if /preparadas|cantrips?|truques/i.match?(n)
        # Ruído comum do XLSX (células numéricas / cabeçalhos), não é nome de magia.
        next if n.match?(/\A\d+(\.\d+)?\z/)
        next if n.match?(/\An[º°]\s*$/i)
        next if ['Conhecidas', 'Aprimorar habilidades'].include?(n)

        names << n
      end
    end

    uniq = names.uniq.sort
    miss = []
    uniq.each do |n|
      miss << n if resolver.resolve(n).nil?
    end

    puts "[spells:audit_imported] #{uniq.size} nomes unicos em spells_listed; #{miss.size} sem match no SpellResolver."
    if miss.any?
      puts '--- adicionar em config/spell_aliases.yml (chave lowercase transliterada) ou corrigir o JSON ---'
      miss.each { |m| puts "  MISS: #{m}" }
      exit 1
    end
    puts 'OK — todos resolvem.'
  end
end
