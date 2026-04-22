# Re-hidrata SheetItems + coins de fichas P81 a partir do imported_sheets.json.
#
# Por que existe:
#   2 fichas P81 (Angelina, Valac) sofreram `TypeError: fetch failed` no
#   `provision-imported-as-bob.ts` durante a hidratacao pos-provision e ficaram
#   sem armas, sem armaduras, sem itens vestidos e sem moedas. Outras fichas
#   podem precisar de re-import quando o callback do SheetItem for atualizado
#   (ex.: novo mapeamento de aliases). Esta task encapsula o fluxo de
#   hidratacao em Ruby (sem precisar subir o front e re-rodar o tsx script).
#
# O que faz, por sheet:
#   - resolve a entrada correspondente no `api/docs/imported_sheets.json` pelo
#     nome do personagem (`[P81] X` -> X)
#   - atualiza Sheet#coins quando o JSON tem cp/sp/gp/pp > 0
#   - cria SheetItems para inventory_bag + armor_weapons.{weapons, armor,
#     wearing}, deduplicando armas que aparecem em `armor_weapons.armor` mas
#     ja estao em `armor_weapons.weapons` (defeito comum do XLSX)
#   - usa source: 'imported_xlsx' como marcador idempotente: items ja
#     existentes com mesmo (sheet_id, source, item_name, quantity) NAO sao
#     duplicados
#
# O `before_validation :resolve_catalog_item` no SheetItem cuida automaticamente
# de ligar cada novo registro ao Item canonico (criando-o se necessario).
#
# Uso:
#   docker exec lafiga_api bundle exec rails sheet_items:rehydrate_imported
#   docker exec lafiga_api bundle exec rails sheet_items:rehydrate_imported NAMES=Angelina,Valac
#   docker exec lafiga_api bundle exec rails sheet_items:rehydrate_imported DRY_RUN=1
namespace :sheet_items do
  desc 'Re-hidrata SheetItems + coins de fichas P81 a partir de docs/imported_sheets.json (idempotente).'
  task rehydrate_imported: :environment do
    require 'json'

    dry_run    = ENV['DRY_RUN'].to_s == '1'
    name_filter = ENV['NAMES'].to_s.split(',').map(&:strip).reject(&:empty?)

    json_path = Rails.root.join('docs/imported_sheets.json')
    unless File.exist?(json_path)
      puts "ERRO: arquivo nao encontrado: #{json_path}"
      exit 1
    end

    all = JSON.parse(File.read(json_path))
    by_name = all.each_with_object({}) do |s, acc|
      key = (s.dig('meta', 'name') || s['tab_name']).to_s.strip
      acc[key.downcase] = s if key.present?
    end

    scope = Sheet.joins(:character).where("characters.name LIKE ?", '[P81]%')
    if name_filter.any?
      conditions = name_filter.map { |_| 'characters.name ILIKE ?' }.join(' OR ')
      values = name_filter.map { |n| "[P81] #{n}%" }
      scope = scope.where(conditions, *values)
    end

    counts = Hash.new(0)

    scope.find_each do |sheet|
      ch_name = sheet.character.name
      excel_name = ch_name.sub(/^\[P81\]\s*/, '').strip
      source = by_name[excel_name.downcase] || by_name[excel_name.split.first.to_s.downcase]
      unless source
        puts "  ! #{ch_name.ljust(35)} fonte nao encontrada no JSON"
        counts[:no_source] += 1
        next
      end

      coin_changes = nil
      c = source['coins'] || {}
      cp = c['copper'].to_i; sp = c['silver'].to_i; gp = c['gold'].to_i; pp = c['platinum'].to_i
      bonus = wallet_bonus_from_algibeira_rows(source)
      merged = {
        'cp' => cp + bonus['cp'],
        'sp' => sp + bonus['sp'],
        'ep' => 0 + bonus['ep'],
        'gp' => gp + bonus['gp'],
        'pp' => pp + bonus['pp']
      }
      if merged.values.any?(&:positive?)
        cur = sheet.wallet_hash.stringify_keys
        if cur != merged
          coin_changes = merged
          sheet.set_pouch_wallet!(Sheet::PRIMARY_POUCH_ID, merged) unless dry_run
        end
      end

      weapon_names_lower = Array(source.dig('armor_weapons', 'weapons')).map { |it| it['name'].to_s.downcase.strip }.to_set

      candidates = []
      Array(source['inventory_bag']).each do |it|
        candidates << build_candidate(it, nil)
      end
      Array(source.dig('armor_weapons', 'weapons')).each do |it|
        candidates << build_candidate(it, 'Armas')
      end
      Array(source.dig('armor_weapons', 'armor')).each do |it|
        # Skip se o nome ja apareceu em weapons (defeito do XLSX que duplica).
        next if weapon_names_lower.include?(it['name'].to_s.downcase.strip)
        candidates << build_candidate(it, 'Armaduras & Escudos')
      end
      Array(source.dig('armor_weapons', 'wearing')).each do |it|
        candidates << build_candidate(it, nil)
      end
      candidates.compact!

      unless dry_run
        SheetItem.where(sheet_id: sheet.id, source: 'imported_xlsx').find_each do |si|
          next unless AlgibeiraCoinParser.pouch_coin_item?(si.item_name)
          si.destroy
        end
      end

      added = 0
      skipped_existing = 0
      candidates.each do |cand|
        existing = SheetItem.where(
          sheet_id: sheet.id,
          source: 'imported_xlsx',
          item_name: cand[:name],
          quantity: cand[:qty]
        ).count
        if existing > 0
          skipped_existing += 1
          next
        end

        next if dry_run
        si = SheetItem.create(
          sheet_id: sheet.id,
          item_name: cand[:name],
          quantity: cand[:qty],
          category: cand[:category],
          source: 'imported_xlsx'
        )
        if si.persisted?
          added += 1
        else
          counts[:item_save_failed] += 1
          puts "    ! save failed sheet=#{sheet.id} name=#{cand[:name].inspect} -> #{si.errors.full_messages}"
        end
      end

      counts[:sheets_processed] += 1
      counts[:items_added] += added
      counts[:coin_updates] += 1 if coin_changes

      puts format('  %s%s candidates=%d added=%d skip_existing=%d %s',
                  ch_name.ljust(35),
                  coin_changes ? " coins=#{coin_changes.values_at('cp','sp','gp','pp').join('/')}" : '',
                  candidates.size, added, skipped_existing,
                  dry_run ? '(DRY)' : '')
    end

    puts ''
    puts '=== Re-hydration summary ==='
    puts "DRY_RUN: #{dry_run}"
    puts "NAMES filter: #{name_filter.inspect}" if name_filter.any?
    counts.each { |k, v| puts "  #{k.to_s.ljust(20)} #{v}" }
  end

  # Helper para tarefas privadas em rake (precisa estar no nivel do namespace).
  def build_candidate(it, category)
    return nil unless it.is_a?(Hash)
    nm = it['name'].to_s.strip
    return nil if nm.blank? || nm =~ /\A\d+(\.\d+)?\z/
    return nil if AlgibeiraCoinParser.pouch_coin_item?(nm)

    { name: nm, qty: [(it['quantity'] || 1).to_i, 1].max, category: category }
  end

  def wallet_bonus_from_algibeira_rows(source)
    out = Sheet::COIN_DEFAULTS.dup
    Array(source['inventory_bag']).each do |it|
      nm = it['name'].to_s
      next unless AlgibeiraCoinParser.pouch_coin_item?(nm)

      w = AlgibeiraCoinParser.parse_pouch_wallet(nm)
      Sheet::COIN_KEYS.each { |k| out[k] += w[k].to_i }
    end
    out
  end

  desc 'Remove SheetItems que sao "algibeira com moedas" e credita na Carteira (primary).'
  task merge_algibeira_items_into_wallet: :environment do
    dry_run = ENV['DRY_RUN'].to_s == '1'
    scope = SheetItem.all
    scope = scope.where(sheet_id: ENV['SHEET_ID'].to_i) if ENV['SHEET_ID'].present?

    n = 0
    scope.find_each do |si|
      next unless AlgibeiraCoinParser.pouch_coin_item?(si.item_name)

      w = AlgibeiraCoinParser.parse_pouch_wallet(si.item_name)
      next if Sheet::COIN_KEYS.all? { |k| w[k].to_i <= 0 }

      sh = si.sheet
      next unless sh

      puts "  sheet=#{sh.id} item=#{si.id} #{si.item_name.inspect} -> carteira" unless dry_run
      n += 1
      next if dry_run

      sh.apply_coin_delta!(w)
      si.destroy
    end
    puts "=== merge_algibeira_items_into_wallet: #{n} item(ns) #{dry_run ? '(DRY)' : ''}==="
  end
end
