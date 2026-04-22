# frozen_string_literal: true

require 'rake'

module Dnd
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
  desc 'Carrega dados locais (sem acessar API): feats, itens e regras de subclasses'
  task load_local: :environment do
    sequence = []
    sequence << 'feats:import' if Rake::Task.task_defined?('feats:import')
    sequence << 'items:import_all' if Rake::Task.task_defined?('items:import_all')
    sequence << 'subclasses:import' if Rake::Task.task_defined?('subclasses:import')
    sequence << 'dnd:apply_subclass_overrides' if Rake::Task.task_defined?('dnd:apply_subclass_overrides')
    sequence << 'subclasses:import_spells' if Rake::Task.task_defined?('subclasses:import_spells')

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
