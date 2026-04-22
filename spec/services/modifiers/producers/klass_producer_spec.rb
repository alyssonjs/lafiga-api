# frozen_string_literal: true

require 'rails_helper'

# Phase 2.4.A — Bug raiz dos gaps de speed na fidelidade Phase 2.3:
# KlassProducer lia `rule[:features]`, mas ClassRules define `:feature_rules`.
# Resultado: para Bárbaro nv 5+ (Movimento Rápido) e Monge nv 2+ (Movimento sem
# Armadura), nenhum modifier de speed era emitido, e o summary devolvia speed
# base de raça apenas. Cobertura: imported_sheets_fidelity_spec.rb (Phase 2.3).
RSpec.describe Modifiers::Producers::KlassProducer, type: :service do
  let(:user) do
    User.create!(
      email: "klass_prod_#{SecureRandom.hex(4)}@example.com",
      username: "kp#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id
    )
  end
  let(:character) { Character.create!(user: user, name: "Spec #{SecureRandom.hex(2)}", background: 'Sage') }

  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  def build_sheet_with_klass(klass_api:, klass_name:, level:)
    klass = Klass.find_or_create_by!(api_index: klass_api) do |k|
      k.name = klass_name
      k.hit_die = 'd8'
    end
    sheet = Sheet.create!(
      character: character, race: race,
      str: 14, dex: 14, con: 14, int: 10, wis: 12, cha: 10,
      hp_max: 10, hp_current: 10, current_level: level
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: level)
    sheet.reload
    sheet
  end

  describe 'Movimento Rápido (Bárbaro nv 5+)' do
    it 'emite modifier de speed quando bárbaro está no nível 5 sem armadura pesada' do
      sheet = build_sheet_with_klass(klass_api: 'barbarian', klass_name: 'Bárbaro', level: 5)
      mods = described_class.new(sheet, context: { equipment: { ac: { armor_category: 'none' } } }).produce

      speed_mods = mods.select { |m| m.target.to_s == 'speed' }
      expect(speed_mods).not_to be_empty,
        "Bárbaro nv 5 deveria emitir modifier 'speed' de Fast Movement (+10 ft equivalente).\n" \
        "  Bug raiz: producer lia rule[:features] mas ClassRules define rule[:feature_rules]."
      expect(speed_mods.first.value).to eq(10) # 3 m * 3.28 ≈ 10 ft
    end

    it 'NÃO emite quando bárbaro está abaixo do nível 5' do
      sheet = build_sheet_with_klass(klass_api: 'barbarian', klass_name: 'Bárbaro', level: 4)
      mods = described_class.new(sheet, context: { equipment: { ac: { armor_category: 'none' } } }).produce
      expect(mods.select { |m| m.target.to_s == 'speed' }).to be_empty
    end
  end

  describe 'Movimento sem Armadura (Monge)' do
    it 'aplica tabela bonus_ft_by_level no nível 2 (+10 ft)' do
      sheet = build_sheet_with_klass(klass_api: 'monk', klass_name: 'Monge', level: 2)
      mods = described_class.new(sheet, context: { equipment: { ac: { armor_category: 'none' } } }).produce
      speed_mods = mods.select { |m| m.target.to_s == 'speed' }
      expect(speed_mods.first&.value).to eq(10)
    end

    it 'aplica +15 ft no nível 6' do
      sheet = build_sheet_with_klass(klass_api: 'monk', klass_name: 'Monge', level: 6)
      mods = described_class.new(sheet, context: { equipment: { ac: { armor_category: 'none' } } }).produce
      expect(mods.find { |m| m.target.to_s == 'speed' }&.value).to eq(15)
    end

    it 'NÃO aplica se monge está usando armadura' do
      sheet = build_sheet_with_klass(klass_api: 'monk', klass_name: 'Monge', level: 6)
      mods = described_class.new(sheet, context: { equipment: { ac: { armor_category: 'medium' } } }).produce
      expect(mods.select { |m| m.target.to_s == 'speed' }).to be_empty
    end
  end
end
