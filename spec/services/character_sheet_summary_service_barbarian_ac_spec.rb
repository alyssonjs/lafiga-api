# frozen_string_literal: true

require 'rails_helper'

# Defesa sem Armadura do Bárbaro (PHB): CA = 10 + DES + CON quando sem armadura.
# Bug: `EquipmentRules.ac_for` devolvia só 10+DES, e nada somava CON ao número da
# CA do summary — mesmo gap já corrigido para o Monge. Isso vazava para os
# consumidores da CA do backend (ex.: seed de AC do combatente em
# `combat_combatants_controller`), enquanto a ficha WEB mascarava via `computeAC`.
#
# Diferente do Monge, o Bárbaro MANTÉM a Defesa sem Armadura usando escudo, então
# a CA final soma o +2 do escudo por cima de 10+DES+CON (paridade com `computeAC`).
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "barb_ac_#{SecureRandom.hex(4)}@example.com",
      username: "barb#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:barbarian) do
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'
      k.hit_die = 12
      k.subclass_level = 3
    end
  end
  let(:fighter) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end
  let(:character) { Character.create!(user: user, name: "Barb #{SecureRandom.hex(2)}", background: 'Soldier') }

  # DES 14 (+2), CON 16 (+3) → base de Defesa sem Armadura = 10 + 2 + 3 = 15.
  def build_sheet(klass:)
    sheet = Sheet.create!(
      character: character, race: race,
      str: 16, dex: 14, con: 16, int: 10, wis: 10, cha: 10,
      hp_max: 12, hp_current: 12, current_level: 3,
      metadata: {},
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 3)
    sheet
  end

  def ac_of(sheet)
    cmd = described_class.call(sheet_id: sheet.id, sync: false)
    summary = cmd.respond_to?(:result) ? cmd.result : cmd
    (summary[:equipment] || {})[:ac] || {}
  end

  context 'Bárbaro sem armadura' do
    it 'aplica CA = 10 + DES + CON (não apenas 10 + DES)' do
      ac = ac_of(build_sheet(klass: barbarian))
      expect(ac[:ac]).to eq(15) # 10 + 2 DES + 3 CON
      expect(ac[:source].to_s).to include('Defesa sem Armadura')
    end
  end

  context 'Bárbaro sem armadura mas com escudo' do
    it 'mantém a Defesa sem Armadura e soma o +2 do escudo (10 + DES + CON + 2)' do
      sheet = build_sheet(klass: barbarian)
      # A proficiência em escudo é ortogonal a este teste (foco = matemática da CA);
      # o bárbaro mínimo não tem proficiências provisionadas, então pulamos a
      # validação de equip.
      shield = SheetItem.new(sheet: sheet, item_name: 'Escudo', item_index: 'escudo',
                             category: 'Armaduras', slot: 'shield', equipped: true)
      shield.save!(validate: false)
      ac = ac_of(sheet)
      expect(ac[:ac]).to eq(17) # 10 + 2 DES + 3 CON + 2 Escudo
      expect(ac[:source].to_s).to include('Escudo')
      expect(ac[:source].to_s).to include('Defesa sem Armadura')
    end
  end

  context 'Bárbaro VESTINDO armadura' do
    it 'não aplica a Defesa sem Armadura (usa a CA da armadura, sem somar CON)' do
      sheet = build_sheet(klass: barbarian)
      SheetItem.create!(sheet: sheet, item_name: 'Armadura de Placas', item_index: 'plate',
                        category: 'Armaduras', slot: 'armor', equipped: true)
      ac = ac_of(sheet)
      expect(ac[:ac]).to eq(18) # Placas (18), sem DES (cap 0), sem CON extra
      expect(ac[:source].to_s).not_to include('Defesa sem Armadura')
    end
  end

  context 'classe SEM Defesa sem Armadura de CON (Guerreiro)' do
    it 'não soma CON à CA (fica em 10 + DES)' do
      ac = ac_of(build_sheet(klass: fighter))
      expect(ac[:ac]).to eq(12) # 10 + 2 DES, sem CON
    end
  end
end
