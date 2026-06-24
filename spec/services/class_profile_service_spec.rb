# frozen_string_literal: true

require 'rails_helper'

# Phase 2.4.B — Bug raiz dos DCs incorretos para third-casters (EK/AT) na
# fidelidade Phase 2.3:
# ClassProfileService usava apenas `klass.spellcasting_ability`. Para Eldritch
# Knight (subklass de Fighter) e Arcane Trickster (subklass de Rogue), a
# classe pai não tem spellcasting_ability setado → fallback CHA. Resultado:
# Allan EK L7 reportava DC=11 quando esperado 15 (INT 18 + prof 3 + 8).
#
# Fix: priorizar `SubclassSpellcasting.lookup(...).ability` (config/subclass_spellcasting.yml).
RSpec.describe ClassProfileService, type: :service do
  let(:user) do
    User.create!(
      email: "cps_#{SecureRandom.hex(4)}@example.com",
      username: "cps#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id
    )
  end
  let(:character) { Character.create!(user: user, name: "Spec #{SecureRandom.hex(2)}", background: 'Sage') }
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  def build_sheet(klass_api:, klass_name:, sub_api: nil, sub_name: nil, level:, abilities: {})
    klass = Klass.find_or_create_by!(api_index: klass_api) { |k| k.name = klass_name; k.hit_die = 'd10' }
    sub_klass = if sub_api
                  SubKlass.find_or_create_by!(klass: klass, api_index: sub_api) { |s| s.name = sub_name }
                end
    sheet = Sheet.create!(
      character: character, race: race,
      str: abilities[:str] || 14, dex: abilities[:dex] || 14, con: abilities[:con] || 14,
      int: abilities[:int] || 10, wis: abilities[:wis] || 10, cha: abilities[:cha] || 10,
      hp_max: 10, hp_current: 10, current_level: level
    )
    SheetKlass.create!(sheet: sheet, klass: klass, sub_klass: sub_klass, level: level)
    sheet.reload
  end

  describe 'subclass third-caster (Eldritch Knight)' do
    it 'usa INT (não CHA) para spell DC e atk bonus em Fighter EK L7' do
      sheet = build_sheet(
        klass_api: 'fighter', klass_name: 'Guerreiro',
        sub_api: 'cavaleiro-arcano', sub_name: 'Cavaleiro Arcano',
        level: 7, abilities: { int: 18, cha: 8 }
      )
      result = described_class.new(sheet).call

      expect(result[:ability]).to eq('INT'),
        "EK deve usar INT (subclass override em config/subclass_spellcasting.yml).\n" \
        "  Bug pré-fix: usava klass.spellcasting_ability ou fallback 'CHA'."
      expect(result[:spell_save_dc]).to eq(15)  # 8 + 4 (INT 18) + 3 (prof L7)
      expect(result[:spell_attack_bonus]).to eq(7) # 4 + 3
    end
  end

  describe 'subclass third-caster (Arcane Trickster)' do
    it 'usa INT (não CHA) para spell DC e atk bonus em Rogue AT L9' do
      sheet = build_sheet(
        klass_api: 'rogue', klass_name: 'Ladino',
        sub_api: 'trapaceiro-arcano', sub_name: 'Trapaceiro Arcano',
        level: 9, abilities: { int: 16, cha: 10 }
      )
      result = described_class.new(sheet).call
      expect(result[:ability]).to eq('INT')
      expect(result[:spell_save_dc]).to eq(15)  # 8 + 3 (INT 16) + 4 (prof L9)
    end
  end

  describe 'subclass third-caster (Caminho do Punho Sagrado — Monge)' do
    it 'usa SAB (não CHA) para spell DC e atk bonus em Monk Punho Sagrado L7' do
      sheet = build_sheet(
        klass_api: 'monk', klass_name: 'Monge',
        sub_api: 'caminho_punho_sagrado', sub_name: 'Caminho do Punho Sagrado',
        level: 7, abilities: { wis: 16, cha: 8 }
      )
      result = described_class.new(sheet).call

      expect(result[:ability]).to eq('WIS'),
        "Punho Sagrado deve usar SAB (subclass override em config/subclass_spellcasting.yml).\n" \
        "  Bug pré-fix: sem entrada para monk → fallback 'CHA'."
      expect(result[:spell_save_dc]).to eq(14)      # 8 + 3 (WIS 16) + 3 (prof L7)
      expect(result[:spell_attack_bonus]).to eq(6)  # 3 + 3
    end
  end

  describe 'full caster (Wizard) ainda funciona' do
    it 'usa INT do klass.spellcasting_ability' do
      Klass.find_or_create_by!(api_index: 'wizard') do |k|
        k.name = 'Mago'
        k.hit_die = 'd6'
        k.spellcasting_ability = 'INT'
      end
      Klass.find_by(api_index: 'wizard').update!(spellcasting_ability: 'INT')
      sheet = build_sheet(
        klass_api: 'wizard', klass_name: 'Mago',
        level: 5, abilities: { int: 18 }
      )
      result = described_class.new(sheet).call
      expect(result[:ability]).to eq('INT')
      expect(result[:spell_save_dc]).to eq(15) # 8 + 4 + 3
    end

    it 'usa INT do ClassRules quando klass.spellcasting_ability está nil (seed/import incompleto)' do
      w = Klass.find_or_create_by!(api_index: 'wizard') do |k|
        k.name = 'Mago'
        k.hit_die = 'd6'
      end
      previous = w.spellcasting_ability
      w.update!(spellcasting_ability: nil)
      begin
        sheet = build_sheet(
          klass_api: 'wizard', klass_name: 'Mago',
          level: 9, abilities: { int: 20, cha: 8 }
        )
        result = described_class.new(sheet).call
        expect(result[:ability]).to eq('INT')
        # 8 + 5 (INT 20) + 4 (prof L9) = 17 — paridade com fidelidade XLSX / Mago real
        expect(result[:spell_save_dc]).to eq(17)
        expect(result[:spell_attack_bonus]).to eq(9)
      ensure
        w.update!(spellcasting_ability: previous)
      end
    end
  end

  describe '.spellcasting_ability_from_class_rules' do
    it 'resolve INT para wizard e WIS para cleric' do
      expect(described_class.spellcasting_ability_from_class_rules('wizard')).to eq('INT')
      expect(described_class.spellcasting_ability_from_class_rules('cleric')).to eq('WIS')
    end

    it 'retorna nil para classe sem spellcasting em ClassRules' do
      expect(described_class.spellcasting_ability_from_class_rules('cozinheiro')).to be_nil
    end
  end

  describe 'sem subclass nem ability (fallback CHA)' do
    it 'devolve CHA como último recurso' do
      sheet = build_sheet(
        klass_api: 'cozinheiro', klass_name: 'Cozinheiro',
        level: 1, abilities: { cha: 14 }
      )
      Klass.find_by(api_index: 'cozinheiro').update!(spellcasting_ability: nil)
      result = described_class.new(sheet.reload).call
      expect(result[:ability]).to eq('CHA')
    end
  end
end
