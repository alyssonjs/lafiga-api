# frozen_string_literal: true

require 'rake'

module Dnd
  # Sequências compartilhadas entre `dnd:load_local` e `dnd:load_local_full` (YAML local, idempotente).
  module LocalYaml
    module_function

    def core_sequence
      sequence = []
      sequence << 'feats:import' if Rake::Task.task_defined?('feats:import')
      sequence << 'items:import_all' if Rake::Task.task_defined?('items:import_all')
      sequence << 'subclasses:import' if Rake::Task.task_defined?('subclasses:import')
      sequence << 'dnd:apply_subclass_overrides' if Rake::Task.task_defined?('dnd:apply_subclass_overrides')
      sequence << 'subclasses:import_spells' if Rake::Task.task_defined?('subclasses:import_spells')
      sequence
    end

    def optional_tail
      tail = []
      monsters_json = Rails.root.join('db', 'seeds', 'monsters.json')
      if ENV['SEED_MONSTERS'].to_s.strip == '1' && Rake::Task.task_defined?('monsters:import')
        if File.exist?(monsters_json)
          tail << 'monsters:import'
        else
          puts "[dnd] SEED_MONSTERS=1 mas #{monsters_json} ausente; ignorando monsters:import"
        end
      end

      imported_json = Rails.root.join('docs', 'imported_sheets.json')
      if ENV['SEED_IMPORTED_SHEETS_REHYDRATE'].to_s.strip == '1' && Rake::Task.task_defined?('sheet_items:rehydrate_imported')
        if File.exist?(imported_json)
          tail << 'sheet_items:rehydrate_imported'
        else
          puts "[dnd] SEED_IMPORTED_SHEETS_REHYDRATE=1 mas #{imported_json} ausente; ignorando sheet_items:rehydrate_imported"
        end
      end
      tail
    end
  end

  module TaskRunner
    module_function

    def invoke(task_name)
      unless Rake::Task.task_defined?(task_name)
        puts "[dnd] task #{task_name} não encontrada; pulando"
        return
      end

      task = Rake::Task[task_name]
      task.reenable
      puts "[dnd] executando #{task_name}"
      task.invoke
    rescue => e
      puts "[dnd] falha ao executar #{task_name}: #{e.message}"
      raise
    end

    def run_sequence(task_names)
      Array(task_names).each do |name|
        invoke(name)
      end
    end
  end
end

namespace :dnd do
  desc 'Dados locais: feats, itens, subclasses; opcional SEED_MONSTERS=1 / SEED_IMPORTED_SHEETS_REHYDRATE=1 (ver api/README.md)'
  task load_local: :environment do
    sequence = Dnd::LocalYaml.core_sequence + Dnd::LocalYaml.optional_tail

    if sequence.empty?
      puts '[dnd] Nenhuma tarefa local encontrada para executar.'
      next
    end

    Dnd::TaskRunner.run_sequence(sequence)
  end

  desc 'YAML local completo (1 comando): class_overrides, Cozinheiro, snacks, depois o mesmo núcleo que load_local. Requer base SRD (dnd:import ou dump). Opcional: SEED_MONSTERS=1, SEED_IMPORTED_SHEETS_REHYDRATE=1'
  task load_local_full: :environment do
    sequence = []
    sequence << 'classes:apply_overrides' if Rake::Task.task_defined?('classes:apply_overrides')
    sequence << 'custom:ensure_cook_class' if Rake::Task.task_defined?('custom:ensure_cook_class')
    sequence << 'snacks:import' if Rake::Task.task_defined?('snacks:import')
    sequence.concat(Dnd::LocalYaml.core_sequence)
    sequence.concat(Dnd::LocalYaml.optional_tail)

    sequence.uniq!
    if sequence.empty?
      puts '[dnd] Nenhuma tarefa local encontrada para executar.'
      next
    end

    Dnd::TaskRunner.run_sequence(sequence)
  end

  desc 'Fluxo completo: importa da API (quando permitido) e aplica dados locais'
  task bootstrap: :environment do
    tasks = []
    skip_api = ENV['SKIP_DND_API'] == '1'
    api_task = 'dnd:import'
    if !skip_api && Rake::Task.task_defined?(api_task)
      tasks << api_task
    elsif skip_api
      puts '[dnd] SKIP_DND_API=1 — ignorando dnd:import'
    else
      puts "[dnd] #{api_task} não encontrado; prosseguindo apenas com dados locais"
    end

    tasks << 'dnd:load_local'
    Dnd::TaskRunner.run_sequence(tasks)
  end
end
