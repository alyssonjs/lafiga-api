# frozen_string_literal: true

# Ordem recomendada (traduções de features):
#   1) dnd_translations:build_features_pt   — opcional; regenera dnd_translations.features.pt.yml a partir dos JSON *_by_md5
#   2) dnd_translations:merge_features_pt — mescla o shard automático em dnd_translations.yml
#   3) dnd_translations:merge_features_book — por último; aplica revisão alinhada ao livro (dnd_translations.features.book.yml)
#
require 'rbconfig'
require 'yaml'

module DndTranslationsOrderedWrite
  module_function

  def ordered_hash(data)
    data = data.transform_keys(&:to_s)
    order = %w[
      schools classes features feature_descs
      backgrounds background_descs alignments alignment_descs
      traits trait_descs spells
    ]
    ordered = {}
    order.each { |k| ordered[k] = data[k] if data.key?(k) }
    data.each_key { |k| ordered[k] = data[k] unless ordered.key?(k) }
    ordered
  end

  def write!(data, path)
    File.write(path, "#{ordered_hash(data).to_yaml(line_width: -1)}")
  end
end

namespace :dnd_translations do
  def load_spells_rows_from_yml(path)
    # Prefer single-document load (matches config/spells.yml layout).
    begin
      y = YAML.load_file(path) || {}
      rows = Array(y['spells'])
      return rows if rows.any?
    rescue StandardError => e
      warn "[dnd_translations] spells.yml load_file failed: #{e.message}"
    end

    # Same multi-block strategy as spells:replace when the file repeats `spells:`.
    content = File.read(path)
    segments = []
    current = []
    inside = false
    content.each_line do |line|
      if line.match?(/^\s*spells:\s*$/)
        segments << current.join if inside && current.any?
        current = []
        inside = true
        next
      end
      current << line if inside
    end
    segments << current.join if inside && current.any?

    all_rows = []
    segments.each_with_index do |seg, idx|
      y = YAML.safe_load("spells:\n" + seg, permitted_classes: [], aliases: true) || {}
      all_rows.concat(Array(y['spells']))
    rescue StandardError => e
      warn "[dnd_translations] YAML segment #{idx + 1} failed: #{e.message}"
    end
    all_rows
  end

  desc 'Atualiza a seção spells em config/dnd_translations.yml a partir de config/spells.yml (api_index => name). Mantém slugs extras já presentes no YAML ativo que não existem em spells.yml.'
  task sync_spells_from_yml: :environment do
    spells_path = Rails.root.join('config', 'spells.yml')
    out_path = Rails.root.join('config', 'dnd_translations.yml')

    unless File.exist?(spells_path)
      puts "[dnd_translations] spells.yml não encontrado: #{spells_path}"
      next
    end

    rows = load_spells_rows_from_yml(spells_path.to_s)
    from_yml = {}
    rows.each do |row|
      next unless row.is_a?(Hash)

      idx = row['api_index'].to_s.presence
      name = row['name'].to_s.presence
      next if idx.blank? || name.blank?

      from_yml[idx] = name
    end

    if from_yml.empty?
      puts '[dnd_translations] Nenhuma magia válida em spells.yml'
      next
    end

    data = File.exist?(out_path) ? (YAML.load_file(out_path) || {}) : {}
    data = data.transform_keys(&:to_s)
    prev_spells = (data['spells'] || {}).transform_keys(&:to_s).transform_values(&:to_s)

    merged = from_yml.dup
    prev_spells.each do |slug, pt_name|
      merged[slug] ||= pt_name
    end

    data['spells'] = merged.sort.to_h

    DndTranslationsOrderedWrite.write!(data, out_path.to_s)
    puts "[dnd_translations] spells: #{from_yml.size} a partir de spells.yml, #{merged.size} chaves no total em #{out_path}"
  end

  desc 'Mescla config/dnd_translations.priority.yml em config/dnd_translations.yml (feature_descs, backgrounds, alignments, traits, etc.)'
  task merge_priority: :environment do
    base_path = Rails.root.join('config', 'dnd_translations.yml')
    pri_path = Rails.root.join('config', 'dnd_translations.priority.yml')

    unless File.exist?(base_path)
      puts "[dnd_translations] Arquivo base ausente: #{base_path}"
      next
    end
    unless File.exist?(pri_path)
      puts "[dnd_translations] Arquivo de prioridade ausente: #{pri_path}"
      next
    end

    data = YAML.load_file(base_path) || {}
    data = data.transform_keys(&:to_s)
    pri = YAML.load_file(pri_path) || {}
    pri = pri.transform_keys(&:to_s)

    pri.each do |key, val|
      if val.is_a?(Hash) && data[key].is_a?(Hash)
        data[key] = data[key].merge(val.transform_keys(&:to_s))
      else
        data[key] = val
      end
    end

    DndTranslationsOrderedWrite.write!(data, base_path.to_s)
    puts "[dnd_translations] Mesclado #{pri_path} -> #{base_path}"
  end

  desc 'Aplica patches do Livro do Jogador em config/dnd_translations.features.book.yml (scripts/apply_livro_book_feature_patches.rb)'
  task apply_livro_book_patches: :environment do
    script = Rails.root.join('scripts', 'apply_livro_book_feature_patches.rb')
    unless File.exist?(script)
      puts "[dnd_translations] Script ausente: #{script}"
      next
    end
    ok = system(RbConfig.ruby, script.to_s)
    raise "[dnd_translations] apply_livro_book_patches falhou (exit #{$CHILD_STATUS.exitstatus})" unless ok
  end

  desc 'Gera config/dnd_translations.features.pt.yml a partir dos JSON pt_*_by_md5 (scripts/build_dnd_features_pt.rb)'
  task build_features_pt: :environment do
    script = Rails.root.join('scripts', 'build_dnd_features_pt.rb')
    unless File.exist?(script)
      puts "[dnd_translations] Script ausente: #{script}"
      next
    end
    ok = system(RbConfig.ruby, script.to_s)
    raise "[dnd_translations] build_features_pt falhou (exit #{$CHILD_STATUS.exitstatus})" unless ok
  end

  desc 'Mescla config/dnd_translations.features.pt.yml em dnd_translations.yml (features + feature_descs; chaves do shard sobrescrevem o base)'
  task merge_features_pt: :environment do
    base_path = Rails.root.join('config', 'dnd_translations.yml')
    shard_path = Rails.root.join('config', 'dnd_translations.features.pt.yml')

    unless File.exist?(base_path)
      puts "[dnd_translations] Arquivo base ausente: #{base_path}"
      next
    end
    unless File.exist?(shard_path)
      puts "[dnd_translations] Arquivo ausente: #{shard_path}"
      next
    end

    data = YAML.load_file(base_path) || {}
    data = data.transform_keys(&:to_s)
    shard = YAML.load_file(shard_path)
    if shard.nil?
      puts "[dnd_translations] YAML inválido ou vazio: #{shard_path}"
      next
    end
    shard = shard.transform_keys(&:to_s)

    %w[features feature_descs].each do |section|
      next unless shard[section].is_a?(Hash)

      base_h = (data[section] || {}).transform_keys(&:to_s)
      shard[section].transform_keys(&:to_s).each do |k, v|
        next if v.nil?
        next if v.is_a?(String) && v.strip.empty?

        base_h[k] = v
      end
      data[section] = base_h
    end

    DndTranslationsOrderedWrite.write!(data, base_path.to_s)
    nfeat = shard['features']&.size || 0
    ndesc = shard['feature_descs']&.size || 0
    puts "[dnd_translations] merge_features_pt: shard features=#{nfeat} feature_descs=#{ndesc} -> #{base_path}"
  end

  desc 'Mescla config/dnd_translations.features.book.yml em dnd_translations.yml (features + feature_descs; camada editorial por cima do merge_features_pt)'
  task merge_features_book: :environment do
    base_path = Rails.root.join('config', 'dnd_translations.yml')
    book_path = Rails.root.join('config', 'dnd_translations.features.book.yml')

    unless File.exist?(base_path)
      puts "[dnd_translations] Arquivo base ausente: #{base_path}"
      next
    end
    unless File.exist?(book_path)
      puts "[dnd_translations] Arquivo ausente (nada a mesclar): #{book_path}"
      next
    end

    data = YAML.load_file(base_path) || {}
    data = data.transform_keys(&:to_s)
    book = YAML.load_file(book_path)
    if book.nil?
      puts "[dnd_translations] YAML inválido ou vazio: #{book_path}"
      next
    end
    book = book.transform_keys(&:to_s)

    %w[features feature_descs].each do |section|
      next unless book[section].is_a?(Hash)

      base_h = (data[section] || {}).transform_keys(&:to_s)
      book[section].transform_keys(&:to_s).each do |k, v|
        next if v.nil?
        next if v.is_a?(String) && v.strip.empty?

        base_h[k] = v
      end
      data[section] = base_h
    end

    DndTranslationsOrderedWrite.write!(data, base_path.to_s)
    nfeat = book['features']&.size || 0
    ndesc = book['feature_descs']&.size || 0
    puts "[dnd_translations] merge_features_book: book features=#{nfeat} feature_descs=#{ndesc} -> #{base_path}"
  end

  desc 'Lista chaves em dnd_translations.todo.yml (feature_descs / features) sem tradução em dnd_translations.yml'
  task verify_features: :environment do
    root = Rails.root.join('config')
    todo_path = root.join('dnd_translations.todo.yml')
    dnd_path = root.join('dnd_translations.yml')

    unless File.exist?(todo_path) && File.exist?(dnd_path)
      puts '[dnd_translations] verify_features: faltam arquivos todo ou dnd_translations.yml'
      next
    end

    todo = YAML.load_file(todo_path) || {}
    dnd = YAML.load_file(dnd_path) || {}
    todo_fd = (todo['feature_descs'] || {}).keys.map(&:to_s)
    dnd_fd = (dnd['feature_descs'] || {}).keys.map(&:to_s).to_set
    missing_desc = todo_fd.reject { |k| dnd_fd.include?(k) }

    todo_ft = (todo['features'] || {}).keys.map(&:to_s)
    dnd_ft = (dnd['features'] || {}).keys.map(&:to_s).to_set
    missing_titles = todo_ft.reject { |k| dnd_ft.include?(k) }

    puts "[dnd_translations] verify_features:"
    puts "  feature_descs no todo: #{todo_fd.size}"
    puts "  feature_descs faltando no dnd_translations.yml: #{missing_desc.size}"
    puts "  features (títulos) no todo: #{todo_ft.size}"
    puts "  títulos faltando no dnd_translations.yml: #{missing_titles.size}"

    if missing_desc.any?
      puts '  exemplos feature_descs faltando:'
      missing_desc.take(15).each { |k| puts "    - #{k}" }
    end
    if missing_titles.any?
      puts '  exemplos títulos faltando:'
      missing_titles.take(15).each { |k| puts "    - #{k}" }
    end

    exit(1) if missing_desc.any? || missing_titles.any?
  end

  # Orquestrador: rebuilda dnd_translations.yml na ordem canonica.
  # Substitui o checklist da skill update-dnd-translations: o usuario precisava
  # rodar 4-5 tasks na ordem certa; agora chama uma so e o pipeline garante a ordem.
  #
  # Ordem (do mais geral pra revisao final):
  #   1. build_features_pt        — regenera shard automatico de features pt
  #   2. merge_features_pt        — mescla shard automatico em dnd_translations.yml
  #   3. apply_livro_book_patches — aplica patches do livro em features.book.yml
  #   4. merge_features_book      — mescla camada editorial sobre o automatico
  #   5. merge_priority           — mescla priority.yml (overrides manuais)
  #   6. sync_spells_from_yml     — sincroniza spells: a partir de spells.yml
  #   7. verify_features          — relatorio final (exit 1 se faltarem chaves)
  #
  # Use SKIP_VERIFY=1 para nao falhar quando ainda houver chaves pendentes.
  desc 'Rebuilda dnd_translations.yml inteiro (orquestra build/merge/sync/verify na ordem canonica).'
  task rebuild: :environment do
    sequence = %w[
      dnd_translations:build_features_pt
      dnd_translations:merge_features_pt
      dnd_translations:apply_livro_book_patches
      dnd_translations:merge_features_book
      dnd_translations:merge_priority
      dnd_translations:sync_spells_from_yml
    ]
    sequence << 'dnd_translations:verify_features' unless ENV['SKIP_VERIFY'] == '1'

    sequence.each do |task_name|
      next puts "[dnd_translations:rebuild] #{task_name} nao definida — skip" unless Rake::Task.task_defined?(task_name)
      puts "\n══ #{task_name} ══"
      task = Rake::Task[task_name]
      task.reenable
      task.invoke
    end

    puts "\n[dnd_translations:rebuild] concluido."
  end
end
