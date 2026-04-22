# frozen_string_literal: true

# Lafiga: Imports parsed spell entries from `api/docs/spelldatabase.parsed.json`
# (produced by `python3 api/docs/spell_xlsx_parser.py`) and merges them into
# `api/config/spells.yml`, replacing the (short summary) `desc` of existing
# spells with the full PHB pt-BR text and adding spells that did not exist.
#
# Usage:
#   1) python3 api/docs/spell_xlsx_parser.py
#   2) bundle exec rake spells:import_xlsx           # writes spells.merged.yml
#   3) review diff, then `mv config/spells.merged.yml config/spells.yml`
#   4) bundle exec rake spells:replace               # repopulate the DB
#
# Env flags:
#   WRITE=1            -- overwrite spells.yml in place (skip the .merged.yml step)
#   REPORT=path.md     -- override report path (default api/docs/spells_import_report.md)

require 'json'
require 'yaml'
require 'set'

namespace :spells do
  desc 'Merge parsed xlsx spells into config/spells.yml (writes .merged.yml unless WRITE=1)'
  task import_xlsx: :environment do
    require Rails.root.join('lib/spells_import_helpers.rb').to_s
    h = SpellsImportHelpers
    api_root    = Rails.root.to_s
    json_path   = File.join(api_root, 'docs', 'spelldatabase.parsed.json')
    yml_path    = File.join(api_root, 'config', 'spells.yml')
    out_path    = ENV['WRITE'].to_s == '1' ? yml_path : File.join(api_root, 'config', 'spells.merged.yml')
    report_path = ENV.fetch('REPORT', File.join(api_root, 'docs', 'spells_import_report.md'))

    unless File.exist?(json_path)
      warn "[spells:import_xlsx] JSON missing at #{json_path}."
      warn "  Run first: python3 api/docs/spell_xlsx_parser.py"
      exit 1
    end
    unless File.exist?(yml_path)
      warn "[spells:import_xlsx] YAML missing at #{yml_path}"
      exit 1
    end

    parsed_xlsx = JSON.parse(File.read(json_path))
    yaml_blob   = YAML.load_file(yml_path) || { 'spells' => [] }
    existing    = Array(yaml_blob['spells'])

    # 0o pass — Dedup interno do YML.
    #
    # Em rodadas anteriores do importer, magias da xlsx com nome divergente
    # do YML acabaram criadas como entradas paralelas (`pt-*`), gerando pares
    # como `spirit-guardians`/`Espiritos Guardioes` + `pt-espirito-guardiao`/
    # `Espirito Guardiao`. Antes de qualquer matching com a xlsx, fundimos
    # esses pares.
    #
    # Gate de seguranca (CRITICO):
    # - Signature sozinha (level+school+casting_time+range+components) tem
    #   muitos falsos positivos (cantrips de evocacao, etc). USAMOS apenas
    #   como confirmacao secundaria.
    # - Gate primario: Levenshtein dos nomes folded <= max(2, 15% do menor).
    #   Isso cobre singular/plural ("espirito/espiritos guardiao/guardioes")
    #   e typos ("invulnerabilidade" vs "invunerabilidade") sem casar magias
    #   genuinamente diferentes ("Moldar Agua" vs "Moldar Terra", dist ~5).
    deduped = []
    pairs_to_check = []
    existing.each_with_index do |row, i|
      sig = h.signature_for_yml(row)
      next unless sig
      ((i + 1)...existing.size).each do |j|
        other = existing[j]
        next unless h.signature_for_yml(other) == sig
        next unless h.near_duplicate_names?(row['name'], other['name'])
        pairs_to_check << [row, other]
      end
    end

    pairs_to_check.each do |a, b|
      next if deduped.any? { |d| d[:removed_index].to_s == a['api_index'].to_s || d[:removed_index].to_s == b['api_index'].to_s }
      winner, loser = h.pick_canonical(a, b)
      deduped << { kept: winner['name'], removed: loser['name'], removed_index: loser['api_index'] }
    end

    removed_indexes = Set.new(deduped.map { |d| d[:removed_index].to_s })
    existing.reject! { |row| removed_indexes.include?(row['api_index'].to_s) }

    by_fold = {}
    existing.each do |row|
      key = h.fold(row['name'].to_s)
      by_fold[key] = row if key && !key.empty?
    end

    used_api_indexes = Set.new(existing.map { |r| r['api_index'].to_s }.reject(&:empty?))
    used_pt_indexes  = used_api_indexes.dup

    created  = []
    updated  = []
    unchanged = []
    school_mismatch = []
    component_mismatch = []
    seen_xlsx_keys = Set.new

    pending_xlsx = []

    parsed_xlsx.each do |sp|
      key = h.fold(sp['name'])
      next if key.empty?
      next if seen_xlsx_keys.include?(key) # planilha tem duplicata
      seen_xlsx_keys << key

      existing_row = by_fold[key]
      if existing_row
        if existing_row['school'].to_s != sp['school'].to_s
          school_mismatch << "#{sp['name']}: yml=#{existing_row['school']} xlsx=#{sp['school']}"
        end
        old_components = Array(existing_row['components']).map(&:to_s).sort
        new_components = Array(sp['components']).map(&:to_s).sort
        if !old_components.empty? && old_components != new_components
          component_mismatch << "#{sp['name']}: yml=#{old_components.inspect} xlsx=#{new_components.inspect}"
        end

        before = existing_row.dup
        merged = h.merge_into_existing(existing_row, sp)
        if h.same_payload?(before, merged)
          unchanged << sp['name']
        else
          updated << sp['name']
        end
      else
        # Adia para o 2o pass: pode ser que essa magia ja exista no YML com nome
        # auto-traduzido (yaml_only). Vamos tentar matching por signature antes
        # de criar uma duplicata.
        pending_xlsx << sp
      end
    end

    # 2o pass — Reconciliacao por signature.
    #
    # Para cada magia da xlsx que NAO bateu por nome, tentamos achar uma
    # magia "yaml_only" (presente no YML mas nao na xlsx) com mesma signature
    # (level, school, casting_time, range normalizado, components ordenados).
    # Quando casa, a xlsx e tratada como fonte da verdade do NOME PT-BR e o
    # registro YML e renomeado IN PLACE. O `api_index` original e preservado,
    # entao todas as FKs de SpellSource continuam validas.
    yaml_only_rows = existing.reject { |row| seen_xlsx_keys.include?(h.fold(row['name'].to_s)) }
    yaml_only_index = yaml_only_rows.each_with_object({}) do |row, acc|
      sig = h.signature_for_yml(row)
      next unless sig
      (acc[sig] ||= []) << row
    end

    renamed = []
    pending_xlsx.each do |sp|
      sig = h.signature_for_xlsx(sp)
      bucket = yaml_only_index[sig]
      # Mesmo gate de Levenshtein do dedup: signature sozinha gera falsos
      # positivos. So renomeia se nome muito proximo. Caso contrario cria
      # como nova entrada `pt-*`.
      candidate = bucket && bucket.find { |row| h.near_duplicate_names?(row['name'], sp['name']) }
      if candidate
        bucket.delete(candidate)
        old_name = candidate['name']
        h.merge_into_existing(candidate, sp) # rewrite incluindo o NOME oficial da xlsx
        by_fold[h.fold(sp['name'])] = candidate
        renamed << { from: old_name, to: sp['name'], api_index: candidate['api_index'] }
        updated << sp['name']
      else
        new_index = h.generate_pt_api_index(sp['name'], used_pt_indexes)
        used_pt_indexes << new_index
        existing << h.build_new_row(sp, new_index)
        by_fold[h.fold(sp['name'])] = existing.last
        created << sp['name']
      end
    end

    yaml_only = existing
                .reject { |row| seen_xlsx_keys.include?(h.fold(row['name'].to_s)) }
                .map { |row| row['name'] }

    sorted = existing.sort_by { |r| [r['level'].to_i, h.fold(r['name'].to_s)] }
    yaml_blob['spells'] = sorted

    File.write(out_path, yaml_blob.to_yaml(line_width: -1))

    # Persiste acoes de dedup como JSON para `spells:apply_dedup` migrar
    # referencias no DB (SpellSource / SheetKnownSpell / SheetPreparedSpell)
    # antes de deletar os api_index orfaos.
    actions_path = File.join(api_root, 'docs', 'spells_dedup_actions.json')
    actions = deduped.map do |d|
      kept = existing.find { |r| r['name'].to_s == d[:kept].to_s }
      {
        'removed_api_index' => d[:removed_index],
        'kept_api_index'    => kept ? kept['api_index'] : nil,
        'kept_name'         => kept ? kept['name'] : d[:kept],
        'removed_name'      => d[:removed],
      }
    end.reject { |a| a['kept_api_index'].nil? }
    File.write(actions_path, JSON.pretty_generate(actions))

    write_report(report_path, {
      out_path: out_path.sub(api_root + '/', ''),
      total_xlsx: parsed_xlsx.size,
      created: created,
      updated: updated,
      unchanged: unchanged,
      yaml_only: yaml_only,
      school_mismatch: school_mismatch,
      component_mismatch: component_mismatch,
      renamed: renamed,
      deduped: deduped,
    })
    puts "[spells:import_xlsx] wrote #{out_path}"
    puts "  deduped=#{deduped.size} created=#{created.size} updated=#{updated.size} unchanged=#{unchanged.size}"
    puts "  renamed=#{renamed.size} yaml_only=#{yaml_only.size}"
    puts "  school_mismatch=#{school_mismatch.size} component_mismatch=#{component_mismatch.size}"
    puts "  report=#{report_path}"
  end

  # Os helpers puros (fold/levenshtein/stem_pt/signature_*/pick_canonical/etc)
  # vivem em lib/spells_import_helpers.rb e sao incluidos no namespace via
  # `include SpellsImportHelpers` no topo do arquivo, para que possam ser
  # cobertos por specs unitarios sem depender de Rake::Application.

  def write_report(path, data)
    lines = []
    lines << '# Spells xlsx import report'
    lines << ''
    lines << "- output yaml: `#{data[:out_path]}`"
    lines << "- xlsx spells parsed: #{data[:total_xlsx]}"
    lines << "- deduped (pares no YML com mesma signature, pt-* descartado): #{Array(data[:deduped]).size}"
    lines << "- created (new in YAML): #{data[:created].size}"
    lines << "- updated (desc replaced): #{data[:updated].size}"
    lines << "- renamed (yaml auto-traducao -> xlsx oficial): #{Array(data[:renamed]).size}"
    lines << "- unchanged: #{data[:unchanged].size}"
    lines << "- yaml-only (in YAML, not in xlsx, sem signature match): #{data[:yaml_only].size}"
    lines << "- school mismatch: #{data[:school_mismatch].size}"
    lines << "- component mismatch: #{data[:component_mismatch].size}"
    lines << ''
    if Array(data[:deduped]).any?
      lines << '## deduped'
      lines << ''
      lines << '| mantido | removido | api_index removido |'
      lines << '|---|---|---|'
      Array(data[:deduped]).each do |d|
        lines << "| #{d[:kept]} | #{d[:removed]} | `#{d[:removed_index]}` |"
      end
      lines << ''
    end
    if Array(data[:renamed]).any?
      lines << '## renamed'
      lines << ''
      lines << '| antes (yaml) | depois (xlsx) | api_index preservado |'
      lines << '|---|---|---|'
      Array(data[:renamed]).each do |r|
        lines << "| #{r[:from]} | #{r[:to]} | `#{r[:api_index]}` |"
      end
      lines << ''
    end
    %i[created updated yaml_only school_mismatch component_mismatch].each do |section|
      arr = Array(data[section])
      next if arr.empty?
      lines << "## #{section}"
      lines << ''
      arr.each { |x| lines << "- #{x}" }
      lines << ''
    end
    File.write(path, lines.join("\n"))
  end
end
