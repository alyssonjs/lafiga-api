# frozen_string_literal: true

require 'yaml'

namespace :snacks do
  desc 'Importa petiscos (snacks) do Cozinheiro a partir de config/cook_snacks.yml e associa a classe/subclasses'
  task import: :environment do
    path = Rails.root.join('config','cook_snacks.yml')
    unless File.exist?(path)
      puts "[snacks] Arquivo não encontrado: #{path}"
      next
    end
    data = YAML.load_file(path) || {}
    list = Array(data['spells'])
    if list.empty?
      puts "[snacks] Nenhum item em spells:[]"
      next
    end

    # Classe Cozinheiro
    cook = Klass.find_by(api_index: 'cozinheiro')
    unless cook
      puts "[snacks] Classe 'cozinheiro' não encontrada"
      next
    end

    # Mapa de nomes usados no YAML -> api_index canônico das subclasses (PDF).
    # Pós-rewrite (2026-04-30): subclassIds canônicos do PDF substituíram os
    # legados (mestre-da-fritura, alquimista-gourmet, mestre-do-fogo-e-fumaca,
    # cantineiro-de-guerra). Aliases legados mantidos para retro-compat com
    # cook_snacks.yml que ainda usem nomes antigos.
    SUBCLASS_NAME_MAP = {
      # Canônicos (PDF)
      'sous chef' => 'sous-chef',
      'sous_chef' => 'sous-chef',
      'sous-chef' => 'sous-chef',
      'sargento alimentar' => 'sargento-alimentar',
      'sargento_alimentar' => 'sargento-alimentar',
      'sargento-alimentar' => 'sargento-alimentar',
      'mestre-cuca' => 'mestre-cuca',
      'mestre_cuca' => 'mestre-cuca',
      'mestre cuca' => 'mestre-cuca',
      'mestre cervejeiro' => 'mestre-cervejeiro',
      'mestre_cervejeiro' => 'mestre-cervejeiro',
      'mestre-cervejeiro' => 'mestre-cervejeiro',
      'amassador de monstros' => 'amassador-de-monstros',
      'amassador_de_monstros' => 'amassador-de-monstros',
      'amassador-de-monstros' => 'amassador-de-monstros',
      # Homebrew Lafiga
      'doceiro' => 'doceiro-encantado',
      'doceiro encantado' => 'doceiro-encantado',
      'doceiro-encantado' => 'doceiro-encantado',
      # Aliases legados (api_indexes antigos → canônicos)
      'mestre-da-fritura' => 'sous-chef',
      'mestre da fritura' => 'sous-chef',
      'alquimista-gourmet' => 'mestre-cuca',
      'alquimista gourmet' => 'mestre-cuca',
      'mestre-do-fogo-e-fumaca' => 'sargento-alimentar',
      'mestre do fogo e fumaca' => 'sargento-alimentar',
      'mestre do fogo e fumaça' => 'sargento-alimentar',
      'cantineiro-de-guerra' => 'mestre-cervejeiro',
      'cantineiro de guerra' => 'mestre-cervejeiro'
    }.freeze

    to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }

    created = 0
    linked  = 0
    list.each do |row|
      next unless row.is_a?(Hash)
      api_index = (row['api_index'].presence || to_slug.call(row['name'])).to_s
      name      = row['name'].to_s
      level     = row['level'].to_i
      school    = row['school'].to_s
      ritual    = !!row['ritual']
      conc      = !!row['concentration']
      range     = row['range']
      dur       = row['duration']
      casting   = row['casting_time']
      comps     = Array(row['components']).join(', ')
      desc      = Array(row['desc']).join("\n\n")
      higher    = Array(row['higher_level']).join("\n\n")

      sp = Spell.find_or_initialize_by(api_index: api_index)
      sp.name = name
      sp.level = level
      sp.school = school if sp.respond_to?(:school=)
      sp.ritual = ritual if sp.respond_to?(:ritual=)
      sp.concentration = conc if sp.respond_to?(:concentration=)
      sp.range = range if sp.respond_to?(:range=)
      sp.duration = dur if sp.respond_to?(:duration=)
      sp.casting_time = casting if sp.respond_to?(:casting_time=)
      sp.components = comps if sp.respond_to?(:components=)
      sp.desc = desc if sp.respond_to?(:desc=)
      sp.higher_level = higher if sp.respond_to?(:higher_level=)
      sp.save!
      created += 1 if sp.previous_changes.key?('id')

      # Resolver pré-requisito de nível: usar campo min_level, se existir; senão, extrair do texto "Pré-requisito: Nº nível"
      min_lvl = begin
        (row['min_level'] || row[:min_level]).to_i
      rescue
        0
      end
      if min_lvl <= 0
        m = desc.match(/pr[ée]-?requisito\s*:\s*(\d{1,2})/i)
        min_lvl = m ? m[1].to_i : 1
      end

      # Resolver subclasse opcional
      sub_key = row['requires_subclass'].to_s.downcase
      if sub_key.blank?
        # Tentar extrair do texto após a vírgula: "Pré-requisito: 7º nível, Sous Chef"
        m2 = desc.match(/pr[ée]-?requisito[^,]*,\s*([^\.\n]+)/i)
        sub_key = m2 ? m2[1].to_s.downcase.strip : ''
      end
      sub_api = SUBCLASS_NAME_MAP[sub_key]

      if sub_api.present?
        sub = cook.sub_klasses.find_by(api_index: sub_api)
        unless sub
          puts "[snacks] Subclasse não encontrada para '#{sub_key}' (esperado #{sub_api}); vinculando à classe."
        end
        target_type = (sub ? 'SubKlass' : 'Klass')
        target_id   = (sub ? sub.id : cook.id)
      else
        target_type = 'Klass'
        target_id   = cook.id
      end

      ss = SpellSource.find_or_initialize_by(source_type: target_type, source_id: target_id, spell_id: sp.id)
      ss.always_prepared = false
      ss.min_class_level = (min_lvl > 1 ? min_lvl : nil)
      ss.notes = 'snack'
      ss.save!
      linked += 1
    end

    puts "[snacks] Spells upserted: #{created}; links created/updated: #{linked}"
  end
end
