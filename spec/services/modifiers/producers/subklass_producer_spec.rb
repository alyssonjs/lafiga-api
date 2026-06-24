# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Modifiers::Producers::SubklassProducer, type: :service do
  let(:user) do
    User.create!(
      email: "subprod_#{SecureRandom.hex(4)}@ex.com",
      username: "sp#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end
  let(:character) { Character.create!(user: user, name: "SP #{SecureRandom.hex(4)}", background: 'Sage') }
  let(:race) { Race.find_or_create_by!(api_index: 'elf') { |r| r.name = 'Elfo' } }
  let(:klass) { Klass.find_or_create_by!(api_index: 'ranger') { |k| k.name = 'Patrulheiro' } }

  def make_sub(api_index:, name:, levels_json:)
    sk = SubKlass.find_or_initialize_by(api_index: api_index, klass_id: klass.id)
    sk.name = name
    sk.levels_json = levels_json.to_json
    sk.save!
    sk
  end

  def make_sheet_at_level(sub:, level:)
    sheet = Sheet.create!(
      character: character, race: race,
      str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 10,
      hp_max: 10, hp_current: 10,
      current_level: level,
    )
    SheetKlass.create!(sheet: sheet, klass: klass, sub_klass: sub, level: level)
    sheet.reload
  end

  let(:batedor_levels) do
    [
      { 'level' => 3, 'features' => [{ 'name' => 'Tática de Batedor' }] },
      {
        'level' => 7,
        'features' => [{ 'name' => 'Movimento de Batedor' }],
        'grants' => { 'movement' => { 'walk_bonus_ft' => 10 } },
      },
    ]
  end

  describe '#produce' do
    it 'emite Modifier de speed +10 para Batedor nv 7+ a partir de levels_json' do
      sub = make_sub(api_index: 'batedor_prod', name: 'Batedor', levels_json: batedor_levels)
      sheet = make_sheet_at_level(sub: sub, level: 7)

      mods = described_class.new(sheet).produce

      speed_mods = mods.select { |m| m.target == 'speed' }
      expect(speed_mods.size).to eq(1)
      expect(speed_mods.first.value).to eq(10)
      expect(speed_mods.first.op).to eq(:add)
      expect(speed_mods.first.source_kind).to eq(:subklass)
      expect(speed_mods.first.source).to include('batedor_prod')
    end

    it 'NAO emite o bonus quando o personagem ainda nao chegou no nivel da feature' do
      sub = make_sub(api_index: 'batedor_low', name: 'Batedor', levels_json: batedor_levels)
      sheet = make_sheet_at_level(sub: sub, level: 6)

      mods = described_class.new(sheet).produce
      expect(mods.select { |m| m.target == 'speed' }).to be_empty
    end

    it 'devolve [] quando sheet_klass nao tem sub_klass associada' do
      sheet = Sheet.create!(
        character: character, race: race,
        str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 10,
        hp_max: 10, hp_current: 10,
        current_level: 3,
      )
      SheetKlass.create!(sheet: sheet, klass: klass, level: 3)

      mods = described_class.new(sheet.reload).produce
      expect(mods).to be_empty
    end

    it 'consome grants aninhados dentro de features (formato canonico do Batedor)' do
      sub = make_sub(
        api_index: 'batedor_feat_grants', name: 'Batedor',
        levels_json: [
          {
            'level' => 7,
            'features' => [
              {
                'name' => 'Movimento de Batedor',
                'grants' => { 'movement' => { 'walk_bonus_ft' => 10 } },
              },
            ],
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 7)

      mods = described_class.new(sheet).produce
      speed_mods = mods.select { |m| m.target == 'speed' }
      expect(speed_mods.size).to eq(1)
      expect(speed_mods.first.value).to eq(10)
      expect(speed_mods.first.source).to include('batedor_feat_grants', 'movimento-de-batedor')
    end

    it 'devolve [] quando levels_json nao tem grants de movement' do
      sub = make_sub(
        api_index: 'sub_no_grants', name: 'NoGrants',
        levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'X' }] }],
      )
      sheet = make_sheet_at_level(sub: sub, level: 5)

      mods = described_class.new(sheet).produce
      expect(mods.select { |m| m.target == 'speed' }).to be_empty
    end
  end

  # ─── R5: grants.defenses.* → resistências/imunidades ───────────────────
  describe '#produce — grants.defenses (R5)' do
    it 'emite resistências a partir de grants.defenses.resistance ANINHADO em feature (Bruxo patrono-morte)' do
      sub = make_sub(
        api_index: 'patrono-morte_prod', name: 'A Morte',
        levels_json: [
          {
            'level' => 1,
            'features' => [
              {
                'name' => 'Cria da Não-Vida',
                'grants' => { 'defenses' => { 'resistance' => ['necrótico', 'veneno'] } },
              },
            ],
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 20)

      mods = described_class.new(sheet).produce
      res = mods.select { |m| m.target.start_with?('resistance.') }
      expect(res.map(&:value)).to contain_exactly('necrótico', 'veneno')
      expect(res).to all(have_attributes(op: :grant, source_kind: :subklass))
      expect(res.first.source).to include('patrono-morte_prod', 'cria-da-nao-vida')
    end

    it 'emite resistência + (idioma fica para R4) a partir de feature (Bruxo arcanjo-vingador)' do
      sub = make_sub(
        api_index: 'arcanjo-vingador_prod', name: 'O Arcanjo Vingador',
        levels_json: [
          {
            'level' => 1,
            'features' => [
              {
                'name' => 'Servo dos Anjos',
                'grants' => {
                  'languages' => ['Celestial'],
                  'defenses' => { 'resistance' => ['radiante'] },
                  'proficiencies' => { 'skills' => ['Intuição'] },
                },
              },
            ],
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 20)

      mods = described_class.new(sheet).produce
      expect(mods.select { |m| m.target == 'resistance.radiante' }.map(&:value)).to eq(['radiante'])
      # languages/skills NÃO viram modifier aqui (são R4 em build_proficiencies)
      expect(mods.map(&:target).any? { |t| t.include?('language') }).to be(false)
      expect(mods.map(&:target).any? { |t| t.start_with?('skill.') }).to be(false)
    end

    it 'emite resistência a partir de grants.defenses no NÍVEL DA ROW (Feiticeiro origem-abissal)' do
      sub = make_sub(
        api_index: 'origem-abissal_prod', name: 'Origem Abissal',
        levels_json: [
          {
            'level' => 1,
            'features' => [{ 'name' => 'Linhagem Demoníaca' }],
            'grants' => {
              'languages' => { 'fixed' => ['Abissal'] },
              'defenses' => { 'resistance' => ['fogo'] },
            },
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 20)

      mods = described_class.new(sheet).produce
      expect(mods.select { |m| m.target == 'resistance.fogo' }.map(&:value)).to eq(['fogo'])
    end

    it 'emite imunidade de dano a partir de grants.defenses.immunity' do
      sub = make_sub(
        api_index: 'origem-mutavel_prod', name: 'Origem Mutável',
        levels_json: [
          {
            'level' => 14,
            'features' => [{ 'name' => 'Metabolismo Resistente' }],
            'grants' => { 'defenses' => { 'immunity' => ['doenças', 'veneno'] } },
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 20)

      mods = described_class.new(sheet).produce
      imm = mods.select { |m| m.target.start_with?('damage_immunity.') }
      expect(imm.map(&:value)).to contain_exactly('doenças', 'veneno')
      expect(imm).to all(have_attributes(op: :grant, source_kind: :subklass))
    end

    it 'NAO emite defesas quando o personagem ainda nao alcancou o nivel' do
      sub = make_sub(
        api_index: 'origem-abissal_low', name: 'Origem Abissal',
        levels_json: [
          {
            'level' => 6,
            'features' => [{ 'name' => 'X', 'grants' => { 'defenses' => { 'resistance' => ['fogo'] } } }],
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 3)

      mods = described_class.new(sheet).produce
      expect(mods.select { |m| m.target.start_with?('resistance.') }).to be_empty
    end
  end

  describe 'integration with ModifierResolver — resistências (R5)' do
    it 'bag.granted("resistance") inclui necrótico/veneno (patrono-morte)' do
      sub = make_sub(
        api_index: 'patrono-morte_int', name: 'A Morte',
        levels_json: [
          {
            'level' => 1,
            'features' => [
              { 'name' => 'Cria da Não-Vida', 'grants' => { 'defenses' => { 'resistance' => ['necrótico', 'veneno'] } } },
            ],
          },
        ],
      )
      sheet = make_sheet_at_level(sub: sub, level: 20)

      bag = Modifiers::ModifierResolver.new(sheet, producer_keys: %i[subklass]).call
      expect(bag.granted('resistance')).to contain_exactly('necrótico', 'veneno')
    end
  end

  describe 'integration with ModifierResolver' do
    it 'subklass speed bonus aparece em bag.sum_for_kind(:subklass) e no agregado sum_for' do
      sub = make_sub(api_index: 'batedor_int', name: 'Batedor', levels_json: batedor_levels)
      sheet = make_sheet_at_level(sub: sub, level: 7)

      bag = Modifiers::ModifierResolver.new(sheet, producer_keys: %i[subklass]).call

      expect(bag.sum_for('speed')).to eq(10)
      expect(bag.sum_for_kind('speed', source_kind: :subklass)).to eq(10)
      expect(bag.sum_for_kind('speed', source_kind: :item)).to eq(0)
      expect(bag.sum_for_kind('speed', source_kind: :feat)).to eq(0)
    end
  end
end
