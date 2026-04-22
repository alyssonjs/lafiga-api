# frozen_string_literal: true

require 'rails_helper'
require 'json'
require_relative '../support/imported_sheets_payload_builder'
require_relative '../support/imported_sheets_spell_seeder'
require_relative '../support/imported_sheets_fidelity_report'

# Phase 2.2 — Fidelidade dos números
#
# Para cada uma das 35 fichas auditáveis:
#   1) Provisiona via CharacterProvisioningService até o nível real.
#   2) Compara os números chave do Sheet recém-criado com a XLSX.
#
# STRICT (falha): abilities, current_level, prof_bonus.
# WINDOW (falha): hp_max dentro da janela rolável teoricamente.
# REPORT (não-falha): hp_max XLSX vs sistema, AC, spell_save_dc/attack, speed.
#
# Saída adicional: tmp/phase22_fidelity_report.json
RSpec.describe 'Imported XLSX sheets — Phase 2.2 fidelity', type: :service do
  let(:user)          { create(:user) }
  let(:default_bg)    { Background.find_by(api_index: 'soldier') || Background.first }
  let(:default_align) { Alignment.find_by(api_index: 'n')        || Alignment.first  }

  before(:all) do
    ImportedSheetsSeeder.seed_all!
    ImportedSheetsSpellSeeder.seed_all!
    ImportedSheetsFidelityReport.reset!
  end

  after(:all) do
    ImportedSheetsFidelityReport.flush!
    rep = ImportedSheetsFidelityReport.entries
    divergences = rep.values.count { |e| e['hp_diff'].to_i.abs > 0 }
    Rails.logger.info(
      "[Phase2.2] HP-diff em #{divergences}/#{rep.size} fichas — relatório completo " \
      "em #{ImportedSheetsFidelityReport::REPORT_PATH.call}"
    )
  end

  ImportedSheetsSeeder.auditable_sheets.each do |sheet|
    tab          = sheet['tab_name']
    class_idx    = sheet.dig('meta', 'klass', 'class_api_index').to_s
    sub_idx      = sheet.dig('meta', 'klass', 'subclass_api_index')
    target_lv    = ImportedSheetsPayloadBuilder.target_level_for(sheet)

    it "[#{tab}] #{class_idx}/#{sub_idx || '-'} L#{target_lv} bate números chave" do
      payload = ImportedSheetsPayloadBuilder.build(
        sheet,
        user: user,
        background: default_bg,
        alignment: default_align
      )

      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> {
        cmd.errors.full_messages.join('; ')
      }

      sheet_record = Sheet.order(:id).last
      expect(sheet_record).to be_present

      # Phase 2.5 — patcha metadata['feats'] após o provisioning para que o
      # FeatProducer consuma feats reais da ficha (Mobilidade, Robusto, etc.).
      # Esses feats não são passados via wizard payload (ASI handshake) por
      # simplicidade do builder de teste; a fidelidade trata como pos-fix.
      feats_meta = ImportedSheetsPayloadBuilder.feats_metadata_for(sheet)
      if feats_meta.any?
        sheet_record.update!(
          metadata: (sheet_record.metadata || {}).merge('feats' => feats_meta)
        )
      end

      report = { 'tab' => tab, 'class' => class_idx, 'level' => target_lv, 'feats_applied' => feats_meta.map { |f| f['feat_id'] } }

      aggregate_failures "fidelity[#{tab}]" do
        # ---- STRICT: abilities ---------------------------------------------
        expected = ImportedSheetsFidelityReport.expected_abilities(sheet)
        actual   = ImportedSheetsFidelityReport.actual_abilities(sheet_record)
        report['abilities_xlsx']   = expected
        report['abilities_system'] = actual
        ImportedSheetsFidelityReport::ABILITY_KEYS.each do |k|
          expect(actual[k]).to eq(expected[k]), -> {
            "[#{tab}] ability #{k.upcase}: XLSX=#{expected[k]} ≠ Sheet=#{actual[k]}"
          }
        end

        # ---- STRICT: current_level + prof_bonus ----------------------------
        report['level_xlsx']   = sheet.dig('meta', 'level').to_i
        report['level_system'] = sheet_record.metadata['current_level'].to_i
        expect(sheet_record.metadata['current_level'].to_i).to eq(target_lv)

        expected_prof = ImportedSheetsFidelityReport.proficiency_bonus_for(target_lv)
        report['prof_bonus_xlsx']   = sheet.dig('meta', 'proficiency_bonus').to_i
        report['prof_bonus_system'] = expected_prof
        if sheet.dig('meta', 'proficiency_bonus').to_i.nonzero?
          expect(sheet.dig('meta', 'proficiency_bonus').to_i).to eq(expected_prof), -> {
            "[#{tab}] prof_bonus XLSX=#{sheet.dig('meta','proficiency_bonus')} ≠ esperado L#{target_lv}=#{expected_prof}"
          }
        end

        # ---- WINDOW: hp_max ------------------------------------------------
        klass_record = sheet_record.sheet_klasses.first.klass
        con_mod      = (sheet_record.con.to_i - 10) / 2
        window       = ImportedSheetsFidelityReport.hp_window(klass_record, target_lv, con_mod)
        xlsx_hp      = sheet.dig('hit_points', 'total').to_i
        sys_hp       = sheet_record.hp_max.to_i
        report['hp_xlsx']     = xlsx_hp
        report['hp_system']   = sys_hp
        report['hp_window']   = window
        report['hp_diff']     = xlsx_hp.zero? ? nil : (xlsx_hp - sys_hp)

        expect(sys_hp).to be_between(window[:min], window[:max]), -> {
          "[#{tab}] hp_max sistema=#{sys_hp} fora da janela [#{window[:min]}, #{window[:max]}] " \
          "(klass=#{klass_record.api_index} hd=#{klass_record.hit_die} L=#{target_lv} con_mod=#{con_mod})"
        }

        # XLSX hp_max sanity-check (tolerante): apenas warn quando o valor
        # vier visivelmente errado da extração (caso Aberrama: cell trocada
        # com hp_current). Não falha o spec nesses casos para não bloquear
        # a fidelidade do resto da matriz; sinaliza no report.
        if xlsx_hp.positive?
          if xlsx_hp.between?(window[:min], window[:max] + 5)
            report['hp_xlsx_status'] = 'in_window'
          else
            report['hp_xlsx_status'] = 'out_of_window_likely_extractor_bug'
            Rails.logger.warn("[Phase2.2] hp_max XLSX=#{xlsx_hp} de [#{tab}] fora da janela [#{window[:min]}, #{window[:max] + 5}] — provavelmente cell trocada na extração")
          end
        end

        # ---- Phase 2.3: summary calculado vs XLSX --------------------------
        summary = CharacterSheetSummaryService.call(sheet_id: sheet_record.id).result || {}
        combat  = sheet['combat'] || {}
        report['combat_xlsx'] = {
          'ac' => combat['ac'], 'spell_save_dc' => combat['spell_save_dc'],
          'spell_attack' => combat['spell_attack'], 'speed_m' => combat['speed_m'],
          'passive_perception' => combat['passive_perception']
        }
        # speed_m: provisioning só persiste speed_ft. Converter para metros
        # usando a regra D&D 5e (5 ft = 1.5 m). Fallback: race_summary['speed_ft'].
        sys_speed_ft = summary.dig(:movement, :speed_ft) ||
                       sheet_record.race_summary&.dig('speed_ft')
        sys_speed_m  = sys_speed_ft.present? ? (sys_speed_ft.to_f / 5.0 * 1.5) : nil
        report['summary_system'] = {
          'speed_ft'         => sys_speed_ft,
          'speed_m_derived'  => sys_speed_m,
          'spell_save_dc'    => summary.dig(:conjuration, :spell_save_dc),
          'spell_attack'     => summary.dig(:conjuration, :spell_attack_bonus),
          'ac'               => summary.dig(:equipment, :ac, :ac)
        }

        # speed_m: comparar como REPORT quando há bonus de classe não modelado
        # (Monk Unarmored Movement, Barbarian Fast Movement) ou quando o XLSX
        # contém valor fora da janela razoável (provável feat Mobile/Pés
        # Ligeiros não capturado pelo extractor, ou erro de digitação).
        if combat['speed_m'].to_f > 0 && sys_speed_m
          gap = (combat['speed_m'].to_f - sys_speed_m).round(2)
          if gap.abs <= 0.6
            # match — nada a fazer
          else
            report['speed_m_status']     = 'gap_class_or_feat_or_xlsx'
            report['speed_m_gap']        = gap
            applied_feats = (sheet_record.metadata['feats'] || []).map { |f| f['feat_id'] || f[:feat_id] }
            report['speed_m_explanation'] =
              if %w[monk barbarian].include?(class_idx) && !applied_feats.include?('mobilidade')
                'class_bonus_not_modeled (Unarmored Movement / Fast Movement)'
              elsif applied_feats.include?('mobilidade') && combat['speed_m'].to_f > sys_speed_m
                'mobile_aplicado_xlsx_diverge_likely_player_typo'
              elsif combat['speed_m'].to_f > sys_speed_m
                'likely_mobile_feat_or_homebrew_not_captured'
              else
                'likely_xlsx_extraction_error_or_player_typo'
              end
          end
        end

        # STRICT p/ casters principais (full+half) E third-casters (EK/AT)
        # após Phase 2.4.B. Outros casos (Ki monk, Manobras BM) ainda usam
        # DC alternativo via classe — vão como REPORT.
        primary_caster_classes = %w[bard cleric druid paladin ranger sorcerer warlock wizard]
        third_caster_subclasses = %w[cavaleiro-arcano trapaceiro-arcano]
        sub_idx = sheet.dig('meta', 'klass', 'subclass_api_index').to_s
        is_third_caster = third_caster_subclasses.include?(sub_idx)
        if primary_caster_classes.include?(class_idx) || is_third_caster
          if combat['spell_save_dc'].to_i > 0 && summary.dig(:conjuration, :spell_save_dc).to_i > 0
            expect(summary.dig(:conjuration, :spell_save_dc)).to eq(combat['spell_save_dc']), -> {
              "[#{tab}] spell_save_dc: XLSX=#{combat['spell_save_dc']} ≠ sistema=#{summary.dig(:conjuration, :spell_save_dc)}"
            }
          end
          if combat['spell_attack'].to_i > 0 && summary.dig(:conjuration, :spell_attack_bonus).to_i > 0
            expect(summary.dig(:conjuration, :spell_attack_bonus)).to eq(combat['spell_attack']), -> {
              "[#{tab}] spell_attack: XLSX=#{combat['spell_attack']} ≠ sistema=#{summary.dig(:conjuration, :spell_attack_bonus)}"
            }
          end
        else
          # REPORT: log diff p/ não-casters principais (DC alternativo)
          if combat['spell_save_dc'].to_i > 0
            report['non_primary_caster_dc'] = {
              'class' => class_idx, 'xlsx' => combat['spell_save_dc'],
              'system_conjuration' => summary.dig(:conjuration, :spell_save_dc)
            }
          end
        end
      end

      ImportedSheetsFidelityReport.add(tab, report)
    end
  end
end
