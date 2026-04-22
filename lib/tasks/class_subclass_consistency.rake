namespace :dnd do
  desc 'Lista SheetKlass com level >= subclass_level mas sub_klass_id IS NULL (auditoria). Use REPAIR=1 para tentar resolver via metadata.'
  task audit_missing_subclass: :environment do
    repair = ENV['REPAIR'].to_s == '1'
    rows = SheetKlass
      .joins(:klass)
      .where(sub_klass_id: nil)
      .where('sheet_klasses.level >= klasses.subclass_level')
      .where.not(klasses: { subclass_level: nil })
      .order(:id)

    puts "[audit_missing_subclass] #{rows.count} SheetKlass(es) sem subclasse mas elegíveis"
    by_klass = rows.group_by { |sk| sk.klass.api_index }
    by_klass.each do |kapi, list|
      puts "  #{kapi}: #{list.size} (sheets: #{list.first(8).map(&:sheet_id).join(', ')}#{list.size > 8 ? '…' : ''})"
    end

    if repair
      repaired = 0
      rows.find_each do |sk|
        sheet = sk.sheet
        meta = sheet.metadata || {}
        choice = meta.dig('class_choices', 'subclass_id') || meta.dig('class_choices', 'subclassId')
        next if choice.blank?
        sub = SubKlass.find_by(id: choice.to_i) if choice.to_s.match?(/\A\d+\z/)
        sub ||= SubKlass.find_by(api_index: choice.to_s)
        if sub && sub.klass_id == sk.klass_id
          sk.update_columns(sub_klass_id: sub.id)
          repaired += 1
          puts "[audit_missing_subclass] sk=#{sk.id} sheet=#{sk.sheet_id} → #{sub.api_index}"
        end
      end
      puts "[audit_missing_subclass] REPAIR feito em #{repaired} SheetKlass(es)"
    else
      puts '[audit_missing_subclass] (somente auditoria — passe REPAIR=1 para tentar consertar a partir do metadata.class_choices.subclass_id)'
    end
  end
end
