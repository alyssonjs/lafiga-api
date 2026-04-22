# frozen_string_literal: true

require 'rails_helper'
require 'json'
require_relative '../support/imported_sheets_payload_builder'
require_relative '../support/imported_sheets_spell_seeder'

# Phase 7 — Contract front-end ↔ summary sobre as 35 fichas REAIS importadas
#
# Por que isso existe:
# A Phase 3.0 validou o contract (33 chaves obrigatórias) sobre 4 personas
# sintéticas (rogue/wizard/EK/barbarian) — escolhidas para PASSAR. Nunca
# validamos as 35 fichas reais da campanha contra esse mesmo contract.
#
# Esta spec faz exatamente isso: para cada ficha auditável, provisiona até o
# nível real da campanha e verifica se o JSON do summary tem todas as chaves
# que o front-lafiga (`mergeSheetSummaryIntoCharacter`) consome.
#
# Estratégia anti-mascaramento:
#   - NÃO falha no primeiro erro: coleta TODOS os gaps por ficha em um
#     relatório acumulado.
#   - Imprime o relatório no final mesmo quando passa.
#   - Categoriza gaps em STRICT (front quebra) vs WARNING (campo opcional).
#
# Reusa o contract da Phase 3.0 (FRONT_REQUIRED_KEYS) para garantir que
# qualquer mudança no contract atinja ambos os specs.
RSpec.describe 'Imported XLSX sheets — front contract (Phase 7)' do
  let(:user)          { create(:user) }
  let(:default_bg)    { Background.find_by(api_index: 'soldier') || Background.first }
  let(:default_align) { Alignment.find_by(api_index: 'n')        || Alignment.first  }

  # Reusa o contract canônico da Phase 3.0
  FRONT_CONTRACT_KEYS = [
    [%i[sheet name],                [String, NilClass]],
    [%i[sheet hp_max],               Integer],
    [%i[sheet experience_points],    Integer],
    [%i[sheet alignment_index],     [String, NilClass]],
    [%i[sheet race name],           [String, NilClass]],
    [%i[abilities scores str], Integer],
    [%i[abilities scores dex], Integer],
    [%i[abilities scores con], Integer],
    [%i[abilities scores int], Integer],
    [%i[abilities scores wis], Integer],
    [%i[abilities scores cha], Integer],
    [%i[abilities sources],    Hash],
    [%i[movement speed_ft], Integer],
    [%i[movement speed_m],  [Numeric, NilClass]],
    [[:prof_bonus], Integer],
    [[:klasses],          Array],
    [%i[proficiencies skills],     Hash],
    [%i[proficiencies languages],  Array],
    [%i[proficiencies armor],      Array],
    [%i[proficiencies weapons],    Array],
    [%i[proficiencies tools],      Array],
    [[:saving_throws], Array],
    [%i[equipment ac ac],     Integer],
    [%i[equipment inventory], Array],
    [%i[equipment equipped],  Hash],
    [%i[conjuration ability],            [String, NilClass]],
    [%i[conjuration spell_save_dc],      [Integer, NilClass]],
    [%i[conjuration spell_attack_bonus], [Integer, NilClass]],
    [%i[spells known_by_level],    [Hash, NilClass]],
    [[:features], Array],
    [[:feats],    Array],
    [[:traits], Array],
    [[:background], Hash],
    [[:runtime_state], Hash],
    [[:avatar_customization], Hash]
  ].freeze

  REPORT = []

  before(:all) do
    ImportedSheetsSeeder.seed_all!
    ImportedSheetsSpellSeeder.seed_all!
    REPORT.clear
  end

  after(:all) do
    next if REPORT.empty?

    pass     = REPORT.count { |r| r[:status] == :ok }
    fail_    = REPORT.count { |r| r[:status] == :fail }
    prov     = REPORT.count { |r| r[:status] == :provision_failed }
    warn_n   = REPORT.count { |r| Array(r[:warnings]).any? }
    puts ''
    puts "=" * 78
    puts "Phase 7 — Front contract sobre fichas REAIS (#{REPORT.size} total)"
    puts "  ✓ contract OK         : #{pass}"
    puts "  ✗ contract com gaps   : #{fail_}"
    puts "  ⚠ provision falhou    : #{prov}"
    puts "  ⚠ quality warnings    : #{warn_n}  (campos opcionais vazios em casos suspeitos)"
    puts "=" * 78

    REPORT.select { |r| r[:status] != :ok }.each do |r|
      puts "[#{r[:tab]}] #{r[:class_idx]}/#{r[:sub_idx] || '-'} L#{r[:level]} — #{r[:status]}"
      Array(r[:missing]).each   { |k| puts "  MISSING : #{k}" }
      Array(r[:mistyped]).each  { |k| puts "  MISTYPED: #{k}" }
      puts "  ERROR   : #{r[:error]}" if r[:error]
    end

    if warn_n > 0
      puts ''
      puts '--- QUALITY WARNINGS (não falham, mas sugerem bugs latentes) ---'
      REPORT.select { |r| Array(r[:warnings]).any? }.each do |r|
        puts "[#{r[:tab]}] #{r[:class_idx]}/#{r[:sub_idx] || '-'} L#{r[:level]}:"
        r[:warnings].each { |w| puts "  ⚠ #{w}" }
      end
    end
    puts ''
  end

  ImportedSheetsSeeder.auditable_sheets.each do |sheet|
    tab       = sheet['tab_name']
    class_idx = sheet.dig('meta', 'klass', 'class_api_index').to_s
    sub_idx   = sheet.dig('meta', 'klass', 'subclass_api_index')
    target_lv = ImportedSheetsPayloadBuilder.target_level_for(sheet)

    it "[#{tab}] #{class_idx}/#{sub_idx || '-'} L#{target_lv} satisfaz contract do front" do
      record = { tab: tab, class_idx: class_idx, sub_idx: sub_idx, level: target_lv }

      # 1) Provision
      payload = ImportedSheetsPayloadBuilder.build(
        sheet, user: user, background: default_bg, alignment: default_align
      )
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      unless cmd.success?
        record[:status] = :provision_failed
        record[:error]  = cmd.errors.full_messages.join('; ')
        REPORT << record
        # Não validamos contract se nem provision passou; mas a Phase 2.1 já
        # garante isso, então aqui é só safety net.
        raise "provision falhou: #{record[:error]}"
      end

      # 2) Summary
      sheet_record = Sheet.order(:id).last
      result = CharacterSheetSummaryService.call(sheet_id: sheet_record.id).result
      unless result.is_a?(Hash)
        record[:status] = :provision_failed
        record[:error]  = "summary retornou #{result.class}, esperava Hash"
        REPORT << record
        raise record[:error]
      end

      summary = result.respond_to?(:with_indifferent_access) ? result.with_indifferent_access : result.deep_symbolize_keys

      # 3) Contract check (não falha imediatamente — coleta gaps)
      missing = []
      mistyped = []
      FRONT_CONTRACT_KEYS.each do |path, expected_type|
        node = dig_summary(summary, path)
        if node.nil? && !Array(expected_type).include?(NilClass)
          missing << path.join('.')
          next
        end
        next if node.nil? && Array(expected_type).include?(NilClass)
        ok = Array(expected_type).any? { |t| node.is_a?(t) }
        mistyped << "#{path.join('.')}: esperado=#{Array(expected_type).join('/')} got=#{node.class}" unless ok
      end

      # 4) Validações estruturais extra (mesmas da Phase 3.0)
      klasses = summary['klasses'] || summary[:klasses]
      if klasses.is_a?(Array) && klasses.any?
        first = klasses.first
        unless first.is_a?(Hash)
          mistyped << 'klasses[0]: esperado=Hash got=' + first.class.to_s
        else
          missing << 'klasses[0].name'  unless (first['name']  || first[:name]).is_a?(String)
          missing << 'klasses[0].level' unless (first['level'] || first[:level]).is_a?(Integer)
        end
      else
        missing << 'klasses (vazio ou não-Array)'
      end

      skills = (summary['proficiencies'] || {})['skills'] || (summary[:proficiencies] || {})[:skills] || {}
      %w[class background race].each do |k|
        missing << "proficiencies.skills.#{k}" unless skills.is_a?(Hash) && (skills.key?(k) || skills.key?(k.to_sym))
      end

      # 5) Análise de QUALIDADE: campos opcionais vazios em casos onde
      # provavelmente NÃO deveriam estar. Vai para REPORT como warning, não
      # falha o teste. Detecta bugs silenciosos.
      quality_warnings = []
      caster_classes = %w[bard cleric druid sorcerer warlock wizard]
      half_caster    = %w[paladin ranger]
      third_caster_subs = { 'fighter' => 'cavaleiro-arcano', 'rogue' => 'trapaceiro-arcano' }

      conj_dc = summary.dig('conjuration', 'spell_save_dc') || summary.dig(:conjuration, :spell_save_dc)
      conj_ab = summary.dig('conjuration', 'ability')       || summary.dig(:conjuration, :ability)
      spells_known = summary.dig('spells', 'known_by_level') || summary.dig(:spells, :known_by_level) || {}

      if caster_classes.include?(class_idx) && target_lv >= 1
        quality_warnings << 'caster sem conjuration.spell_save_dc'    if conj_dc.nil?
        quality_warnings << 'caster sem conjuration.ability'          if conj_ab.nil? || conj_ab.to_s.empty?
        quality_warnings << "caster L#{target_lv} sem spells.known_by_level populado" if spells_known.empty?
      end
      if half_caster.include?(class_idx) && target_lv >= 2
        quality_warnings << "half-caster L#{target_lv} sem conjuration.spell_save_dc" if conj_dc.nil?
      end
      if sub_idx.present? && third_caster_subs[class_idx] == sub_idx && target_lv >= 3
        quality_warnings << "third-caster (#{class_idx}/#{sub_idx}) L#{target_lv} sem conjuration.spell_save_dc" if conj_dc.nil?
        quality_warnings << "third-caster (#{class_idx}/#{sub_idx}) deveria ter ability=INT" if conj_ab && conj_ab.to_s.upcase != 'INT'
      end

      klasses_arr = Array(summary['klasses'] || summary[:klasses])
      first_klass = klasses_arr.first || {}
      first_sub   = first_klass['subclass'] || first_klass[:subclass]
      klass_thr   = first_klass['subclass_threshold'] || first_klass[:subclass_threshold]
      if sub_idx.present? && klass_thr.is_a?(Integer) && target_lv >= klass_thr
        if first_sub.nil? || (first_sub.is_a?(Hash) && (first_sub['api_index'] || first_sub[:api_index]).blank?)
          quality_warnings << "klasses[0].subclass deveria estar setada (sub_idx=#{sub_idx}, target=#{target_lv}, threshold=#{klass_thr})"
        end
      end

      record[:status]   = (missing.empty? && mistyped.empty?) ? :ok : :fail
      record[:missing]  = missing
      record[:mistyped] = mistyped
      record[:warnings] = quality_warnings
      REPORT << record

      aggregate_failures "contract[#{tab}]" do
        expect(missing).to  eq([]), "Chaves AUSENTES no summary (front quebra):\n  - #{missing.join("\n  - ")}"
        expect(mistyped).to eq([]), "Chaves com TIPO errado:\n  - #{mistyped.join("\n  - ")}"
      end
    end
  end

  def dig_summary(summary, path)
    node = summary
    path.each do |key|
      return nil unless node.is_a?(Hash)
      node = node[key.to_s] || node[key.to_sym]
    end
    node
  end
end
