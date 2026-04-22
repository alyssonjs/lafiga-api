# frozen_string_literal: true

require 'rails_helper'
require 'json'
require_relative '../support/imported_sheets_payload_builder'
require_relative '../support/imported_sheets_spell_seeder'

# Phase 2.1 — Resilience até o LEVEL REAL da campanha
#
# Estende a Phase 2.0 (provision em level 1) tentando subir cada ficha
# até o nível que ela realmente tinha na campanha LaFiga.
#
# Limitação atual desta fase:
#   - Casters de magia conhecida (bard, cleric, druid, paladin, ranger,
#     sorcerer, warlock, wizard) precisam de SheetKnownSpell registros
#     para passar pelo LevelUpGuardService em strict mode (default em RSpec).
#     Como o test DB não tem `Spell` seedado (só vem via `dnd:import`), eles
#     ficam pendentes para Phase 2.1.B (seed de Spell + spells_listed
#     materializados em per_level[N].cantrips/spells).
#   - Para casters, validamos AO MENOS o provision em level 1 (já feito em
#     imported_sheets_provisioning_resilience_spec).
#
# Estratégia:
#   - `ImportedSheetsPayloadBuilder.target_level_for(sheet)` define até onde
#     tentar subir (level real para non-caster, 1 para caster).
#   - Cada ficha vira um example. Não-caster que sobe é validado em
#     `Sheet#sheet_klasses.first.level == target_level` e
#     `metadata['current_level'] == target_level`.
RSpec.describe 'Imported XLSX sheets — full-level resilience', type: :service do
  let(:user)          { create(:user) }
  let(:default_bg)    { Background.find_by(api_index: 'soldier') || Background.first }
  let(:default_align) { Alignment.find_by(api_index: 'n')        || Alignment.first  }

  before(:all) do
    ImportedSheetsSeeder.seed_all!
    ImportedSheetsSpellSeeder.seed_all!
  end

  ImportedSheetsSeeder.auditable_sheets.each do |sheet|
    tab          = sheet['tab_name']
    class_idx    = sheet.dig('meta', 'klass', 'class_api_index').to_s
    sub_idx      = sheet.dig('meta', 'klass', 'subclass_api_index')
    target_lv    = ImportedSheetsPayloadBuilder.target_level_for(sheet)
    is_caster    = !ImportedSheetsPayloadBuilder::NON_CASTER_CLASSES.include?(class_idx)

    it "[#{tab}] #{class_idx}/#{sub_idx || '-'} sobe até L#{target_lv}" do
      payload = ImportedSheetsPayloadBuilder.build(
        sheet,
        user: user,
        background: default_bg,
        alignment: default_align
      )

      cmd = CharacterProvisioningService.call(user: user, payload: payload)

      expect(cmd.success?).to be(true), -> {
        msgs = cmd.errors.full_messages.join('; ') rescue cmd.inspect
        "[#{tab}] #{class_idx}/#{sub_idx || '-'} target_lv=#{target_lv} falhou: #{msgs}"
      }

      sheet_record = Sheet.order(:id).last
      expect(sheet_record).to be_present
      expect(sheet_record.metadata['current_level']).to eq(target_lv), -> {
        "[#{tab}] esperado current_level=#{target_lv}, " \
        "veio #{sheet_record.metadata['current_level']}"
      }

      sk = sheet_record.sheet_klasses.first
      expect(sk).to be_present
      expect(sk.level).to eq(target_lv), -> {
        "[#{tab}] sheet_klass.level=#{sk.level} != target=#{target_lv}"
      }

      # Subclass aplicada quando atingiu o threshold da classe
      if sub_idx.present?
        klass_threshold = sk.klass.subclass_level.to_i
        if target_lv >= klass_threshold
          expect(sk.sub_klass_id).to be_present, -> {
            "[#{tab}] subclass=#{sub_idx} esperada em L#{klass_threshold} mas SheetKlass#sub_klass_id está nulo"
          }
        end
      end
    end
  end
end
