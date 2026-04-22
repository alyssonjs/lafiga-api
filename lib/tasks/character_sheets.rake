namespace :sheets do
  desc 'Reconstrói Sheet#class_summary (armor/weapon/tool profs) para fichas legadas vazias.'
  task rebuild_class_summary: :environment do
    require 'json'
    scope = Sheet.all
    total = scope.count
    before = histogram(scope)
    puts "[sheets:rebuild_class_summary] total=#{total}"
    puts "[sheets:rebuild_class_summary] BEFORE histogram: #{before.to_json}"

    rebuilt = 0
    skipped = 0
    failed = 0

    scope.find_each do |sheet|
      cs = sheet.read_attribute(:class_summary)
      armor_empty = cs.nil? || !cs.is_a?(Hash) || Array(cs['armor_proficiencies']).empty?
      next unless armor_empty

      ok = ClassSummaryRebuilder.call(sheet)
      if ok
        rebuilt += 1
      else
        skipped += 1
      end
    rescue StandardError => e
      failed += 1
      Rails.logger.error("[sheets:rebuild_class_summary] sheet=#{sheet.id} #{e.class}: #{e.message}")
    end

    after = histogram(scope.reload)
    puts "[sheets:rebuild_class_summary] rebuilt=#{rebuilt} skipped=#{skipped} failed=#{failed}"
    puts "[sheets:rebuild_class_summary] AFTER  histogram: #{after.to_json}"
  end

  desc 'Mostra quantas fichas têm class_summary vazio (sem rebuild).'
  task audit_class_summary: :environment do
    require 'json'
    scope = Sheet.all
    puts "[sheets:audit_class_summary] total=#{scope.count}"
    puts "[sheets:audit_class_summary] histogram: #{histogram(scope).to_json}"
  end

  desc 'Gera (no STDOUT) a matriz de cobertura por classe/subclasse cruzando ClassRules + DB.'
  task audit_coverage: :environment do
    script = Rails.root.join('scripts', 'audit_class_coverage.rb').to_s
    if File.exist?(script)
      load script
    else
      warn "[sheets:audit_coverage] script nao encontrado: #{script}"
    end
  end

  def histogram(scope)
    counts = { empty: 0, partial: 0, full: 0, missing: 0 }
    scope.find_each do |s|
      cs = s.read_attribute(:class_summary)
      if cs.nil? || !cs.is_a?(Hash) || cs.empty?
        counts[:missing] += 1
      elsif Array(cs['armor_proficiencies']).empty? && Array(cs['weapon_proficiencies']).empty?
        counts[:empty] += 1
      elsif Array(cs['armor_proficiencies']).empty? || Array(cs['weapon_proficiencies']).empty?
        counts[:partial] += 1
      else
        counts[:full] += 1
      end
    end
    counts
  end
end
