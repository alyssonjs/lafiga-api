# frozen_string_literal: true

# Phase 8.1 — utilitário para limpar fichas de teste criadas pelo script
# `front-lafiga/scripts/provision-imported-as-bob.ts`.
#
# Esse script usa o prefixo `[P81]` no `Character#name` para identificar fichas
# que foram provisionadas pela suite de validação ponta-a-ponta (front pipeline
# → POST /provision real → DB do dev). Quando você quiser zerar e re-rodar,
# chame:
#
#   docker exec -e DISABLE_SPRING=1 lafiga_api bin/rake phase81:cleanup
#
# Por que existe (e por que não usa `dependent: :destroy`):
#   Hoje as associações Character → Sheet → SheetKlass → SheetKnownSpell /
#   SheetPreparedSpell / SheetItem / SheetFeat / SheetRuntimeState NÃO declaram
#   `dependent: :destroy` em todos os elos, então um `Character#destroy` simples
#   estoura `PG::ForeignKeyViolation`. Esta task descobre dinamicamente todas
#   as tabelas que têm FK para `characters` / `sheets` / `sheet_klasses` e apaga
#   na ordem topológica correta, sem precisar atualizar a task quando uma nova
#   tabela ganhar FK.
namespace :phase81 do
  # Correlaciona nome `[P81] …` com `tab_name` / `meta.name` do JSON importado.
  def phase81_match_tab_for_character(character_name, imported_rows)
    suffix = character_name.to_s.sub(/\A\[P81\]\s*/i, '').strip
    return suffix if suffix.blank?

    imported_rows.each do |row|
      tab = row['tab_name'].to_s.strip
      meta_name = (row.dig('meta', 'name') || '').to_s.strip
      next if tab.empty? && meta_name.empty?

      return tab if tab.present? && (suffix.casecmp?(tab) || suffix.include?(tab) || tab.include?(suffix))
      if meta_name.present? && (suffix.casecmp?(meta_name) || suffix.include?(meta_name) || meta_name.include?(suffix))
        return tab.presence || meta_name
      end
    end
    suffix
  end

  desc 'Lista personagens [P81] (qualquer user): tab estimado, email, group_id, chaves do chibi'
  task audit_p81: :environment do
    path = Rails.root.join('docs', 'imported_sheets.json')
    rows = File.exist?(path) ? JSON.parse(File.read(path)) : []

    scope = Character.where('name LIKE ?', '[P81]%').includes(:user, :sheet).order(:id)
    if scope.none?
      puts '  nenhum personagem com nome LIKE "[P81]%".'
      next
    end

    puts format('%-18s %-28s %6s %8s  %s', 'tab_estimado', 'personagem', 'user_id', 'group_id', 'user_email')
    puts '-' * 110
    scope.each do |c|
      tab = phase81_match_tab_for_character(c.name, rows)
      g = c.group_id
      em = c.user&.email || '?'
      puts format('%-18s %-28s %6s %8s  %s', tab.to_s[0, 18], c.name.to_s[0, 28], c.user_id, g.inspect, em)
      next unless c.sheet

      ch = c.sheet.avatar_customization
      next if ch.blank?

      keys = ch.is_a?(Hash) ? ch.keys.take(12).join(', ') : ch.class.name
      puts "      └─ chibi keys: #{keys}#{ch.is_a?(Hash) && ch.size > 12 ? '…' : ''}"
    end
    puts '-' * 110
    puts "  total: #{scope.count}"
  end

  desc 'Exporta manifest para re-provision (user_id, group_id, avatar chibi) em docs/imported_sheets_provision_manifest.json'
  task export_manifest: :environment do
    path = Rails.root.join('docs', 'imported_sheets.json')
    unless File.exist?(path)
      abort "Arquivo ausente: #{path}"
    end

    rows = JSON.parse(File.read(path))
    out = {}
    Character.where('name LIKE ?', '[P81]%').includes(:user, :sheet).find_each do |c|
      tab = phase81_match_tab_for_character(c.name, rows)
      entry = {
        'user_id' => c.user_id,
        'user_email' => c.user&.email,
        'group_id' => c.group_id,
        'character_name_snapshot' => c.name
      }
      if c.sheet&.avatar_customization.present?
        entry['avatarCustomization'] = c.sheet.avatar_customization.deep_stringify_keys
      end
      out[tab] = entry
    end

    dest = Rails.root.join('docs', 'imported_sheets_provision_manifest.json')
    File.write(dest, JSON.pretty_generate(out))
    puts "  ✓ #{out.size} entradas → #{dest}"
    puts '  Rode phase81:cleanup e em seguida o script TS (ele lê esse arquivo automaticamente se existir).'
  end

  desc 'Remove todas as fichas com prefixo [P81] (qualquer dono — para re-import limpo)'
  task cleanup: :environment do
    char_ids = Character.where('name LIKE ?', '[P81]%').pluck(:id)
    if char_ids.empty?
      puts '  nenhuma ficha [P81] para remover.'
      next
    end

    sheet_ids = Sheet.where(character_id: char_ids).pluck(:id)
    sheet_klass_ids = SheetKlass.where(sheet_id: sheet_ids).pluck(:id)
    puts "  P81: chars=#{char_ids.size} sheets=#{sheet_ids.size} sheet_klasses=#{sheet_klass_ids.size}"

    conn = ActiveRecord::Base.connection
    sheet_referrers = []
    sheet_klass_referrers = []
    char_referrers = []
    conn.tables.each do |t|
      (conn.foreign_keys(t) rescue []).each do |fk|
        case fk.to_table
        when 'sheets'        then sheet_referrers << [t, fk.column]
        when 'sheet_klasses' then sheet_klass_referrers << [t, fk.column]
        when 'characters'    then char_referrers << [t, fk.column]
        end
      end
    end

    delete = lambda { |table, col, ids|
      next if ids.empty?

      list = ids.map(&:to_i).join(',')
      conn.execute("DELETE FROM #{table} WHERE #{col} IN (#{list})")
    }

    sheet_klass_referrers.each { |t, c| delete.call(t, c, sheet_klass_ids) }
    sheet_referrers.each       { |t, c| delete.call(t, c, sheet_ids) }
    Sheet.where(id: sheet_ids).delete_all
    char_referrers.each        { |t, c| delete.call(t, c, char_ids) }
    Character.where(id: char_ids).delete_all

    puts "  ✓ removidas #{char_ids.size} personagens [P81]."
  end
end

# Phase 10 — purge do pool RSpec de spells que vazou para o dev DB.
#
# O `ImportedSheetsSpellSeeder` (api/spec/support/) cria spells "fake" com
# `api_index LIKE 'rspec-%'` e nomes "RSpec Cantrip N" / "RSpec Spell L1 #N"
# para destravar `LevelUpGuardService` em strict mode no test DB. Algum
# fluxo (provavelmente um `provision-imported-as-bob.ts` rodado quando o
# seeder estava sem guard de Rails.env.test?) vazou esses registros para o
# dev DB, e o `LevelUpService#persist_known_spells!` em strict mode auto-
# completou drafts vazios pegando essas spells fake — fazendo a UI mostrar
# "RSpec Cantrip 6" no lugar de "Prestidigitação", etc.
#
# Esta task remove o pool inteiro e cascateia em SheetKnownSpell /
# SheetPreparedSpell / SpellSource que apontam pra ele, sem tocar em
# spells reais.
#
# Uso:
#   docker exec -e DISABLE_SPRING=1 lafiga_api bin/rake phase10:purge_rspec_spells
namespace :phase10 do
  desc 'Remove spells RSpec do dev DB + referencias orfas (SheetKnownSpell, SheetPreparedSpell, SpellSource)'
  task purge_rspec_spells: :environment do
    rspec_spell_ids = Spell.where("api_index LIKE 'rspec-%'").pluck(:id)
    if rspec_spell_ids.empty?
      puts '  nenhuma spell RSpec encontrada — nada a fazer.'
      next
    end

    puts "  alvo: #{rspec_spell_ids.size} spells RSpec"

    refs_known    = SheetKnownSpell.where(spell_id: rspec_spell_ids).count
    refs_prepared = SheetPreparedSpell.where(spell_id: rspec_spell_ids).count
    refs_sources  = SpellSource.where(spell_id: rspec_spell_ids).count
    puts "  referencias: known=#{refs_known} prepared=#{refs_prepared} sources=#{refs_sources}"

    SheetKnownSpell.where(spell_id: rspec_spell_ids).delete_all
    SheetPreparedSpell.where(spell_id: rspec_spell_ids).delete_all
    SpellSource.where(spell_id: rspec_spell_ids).delete_all
    Spell.where(id: rspec_spell_ids).delete_all

    puts "  ✓ purgadas. Spell.count agora = #{Spell.count}."
  end
end
