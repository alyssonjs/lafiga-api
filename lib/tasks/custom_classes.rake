# frozen_string_literal: true

namespace :custom do
  desc 'Garante a existência da classe Cozinheiro (api_index: cozinheiro)'
  task ensure_cook_class: :environment do
    begin
      k = Klass.find_or_initialize_by(api_index: 'cozinheiro')
      k.name = 'Cozinheiro'
      k.hit_die = 8
      # classe sem conjuração nativa
      k.spellcasting_ability = nil if k.respond_to?(:spellcasting_ability=)
      k.save!
      puts "[custom] Classe garantida: #{k.name} (api_index=#{k.api_index}, id=#{k.id})"
    rescue => e
      puts "[custom] Falha ao garantir Cozinheiro: #{e.message}"
      raise
    end
  end

  desc 'Garante Cozinheiro e aplica overrides/grants de subclasses do YAML'
  task bootstrap_cook: :environment do
    Rake::Task['custom:ensure_cook_class'].invoke
    if Rake::Task.task_defined?('dnd:apply_subclass_overrides')
      Rake::Task['dnd:apply_subclass_overrides'].reenable
      Rake::Task['dnd:apply_subclass_overrides'].invoke
    else
      puts '[custom] Tarefa dnd:apply_subclass_overrides não encontrada; execute manualmente após garantir a classe.'
    end
  end
end

