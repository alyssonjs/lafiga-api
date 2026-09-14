# frozen_string_literal: true

require 'rails_helper'

# CA do summary com o ESCUDO do catálogo e o Estilo de Luta Defesa (14/09/2026).
#
# A Amani (Paladina, Cota de Malha + "Escudo Grande" +3 criado no editor + Estilo
# de Luta Defesa) tinha dois defeitos no servidor: o escudo valia +2 (o editor
# grava `ac_base`, a conta lia `ac_bonus`) e a Defesa entrava DUAS vezes — a
# ficha grava "Defesa" no nível 1 e "fs-defense" no 2. A CA do combate vem daqui.
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "pal_ac_#{SecureRandom.hex(4)}@example.com",
      username: "pal#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:paladin) do
    Klass.find_or_create_by!(api_index: 'paladin') do |k|
      k.name = 'Paladino'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end
  let(:character) { Character.create!(user: user, name: "Amani #{SecureRandom.hex(2)}", background: 'Hermit') }

  # DES 10: a Cota de Malha (16) não soma DES de qualquer jeito.
  def ficha(metadata: {})
    sheet = Sheet.create!(
      character: character, race: race,
      str: 16, dex: 10, con: 14, int: 10, wis: 12, cha: 14,
      hp_max: 40, hp_current: 40, current_level: 4,
      metadata: metadata,
    )
    SheetKlass.create!(sheet: sheet, klass: paladin, level: 4)
    sheet
  end

  # Proficiência é ortogonal ao teste (foco = matemática da CA), como no spec do Bárbaro.
  def equipar!(sheet, nome, index, slot)
    SheetItem.new(sheet: sheet, item_name: nome, item_index: index, category: 'Armaduras',
                  slot: slot, equipped: true).save!(validate: false)
  end

  def ac_of(sheet)
    cmd = described_class.call(sheet_id: sheet.id, sync: false)
    summary = cmd.respond_to?(:result) ? cmd.result : cmd
    (summary[:equipment] || {})[:ac] || {}
  end

  before do
    Item.find_or_initialize_by(api_index: 'escudo-grande')
        .update!(name: 'Escudo Grande', kind: :shield, category: 'shield',
                 props: { 'ac_base' => 3, 'dex_cap' => 0, 'equip_slot' => 'shield' })
  end

  it '⚠️ a Amani: Cota de Malha 16 + Escudo Grande 3 + Defesa 1 = 20' do
    sheet = ficha(metadata: {
      'class_choices' => {
        'per_level' => {
          '1' => { 'fighting_style' => ['Defesa'] },
          '2' => { 'fighting_style' => ['fs-defense'] },
        },
      },
    })
    equipar!(sheet, 'Cota de Malha', 'chain-mail', 'armor')
    equipar!(sheet, 'Escudo Grande', 'escudo-grande', 'shield')

    ac = ac_of(sheet)

    expect(ac[:ac]).to eq(20)
    expect(ac[:source].to_s).to include('Escudo')
    expect(ac[:source].to_s).to include('Estilo de Luta')
  end

  it 'sem estilo de luta, o Escudo Grande sozinho: 16 + 3 = 19' do
    sheet = ficha
    equipar!(sheet, 'Cota de Malha', 'chain-mail', 'armor')
    equipar!(sheet, 'Escudo Grande', 'escudo-grande', 'shield')

    expect(ac_of(sheet)[:ac]).to eq(19)
  end

  it 'item mágico que define a CA base (sem armadura) repõe o bônus do escudo do CATÁLOGO' do
    MagicItem.find_or_create_by!(slug: 'braceletes-ca-base-spec') do |mi|
      mi.name = 'Braceletes de Defesa'
      mi.category = 'gear'
      mi.rarity = 'rare'
      mi.requires_attunement = false
      mi.effects = [{ 'kind' => 'set_ac_base', 'value' => 13 }]
    end
    sheet = ficha
    SheetItem.new(sheet: sheet, item_name: 'Braceletes de Defesa', item_index: 'braceletes-ca-base-spec',
                  category: 'Itens Mágicos', slot: 'gloves', equipped: true,
                  props_json: { 'magic_item_slug' => 'braceletes-ca-base-spec' }).save!(validate: false)
    equipar!(sheet, 'Escudo Grande', 'escudo-grande', 'shield')

    # 13 dos braceletes + 0 de DES + 3 do Escudo Grande. Com o +2 fixo dava 15.
    expect(ac_of(sheet)[:ac]).to eq(16)
  end
end
