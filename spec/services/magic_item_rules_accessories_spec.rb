require 'rails_helper'

# Specs unitárias para `MagicItemRules` cobrindo o pipeline de accessory slots
# (Fase 2.1). Não dependem de `Sheet` real — passamos `equipment:` diretamente
# para isolar a lógica de agregação de efeitos.
RSpec.describe MagicItemRules, type: :service do
  def make_magic_item!(slug:, name:, effects:, category: 'wondrous-item')
    MagicItem.find_or_create_by!(slug: slug) do |mi|
      mi.name = name
      mi.category = category
      mi.rarity = 'rare'
      mi.requires_attunement = false
      mi.effects = effects
    end.tap do |mi|
      mi.update!(effects: effects) if mi.effects != effects
    end
  end

  def equipped_item_for(slug, name)
    { name: name, index: slug, props: { 'magic_item_slug' => slug } }
  end

  let(:sheet_stub) { Object.new } # @sheet só é usado para cair no EquipmentProfileService default

  describe 'accessory slots (Fase 2.1)' do
    it 'agrega resistance vinda de um manto equipado em :cloak' do
      make_magic_item!(slug: 'manto-resistencia-fogo', name: 'Manto da Resistência ao Fogo',
                       effects: [{ 'kind' => 'resistance', 'damage_types' => ['fogo'] }])
      equipment = { equipped: { accessories: { cloak: equipped_item_for('manto-resistencia-fogo', 'Manto') } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:resistances]).to include('fogo')
    end

    it 'agrega save_advantage vinda de um anel equipado em :ring_left' do
      make_magic_item!(slug: 'anel-vontade-inabalavel', name: 'Anel da Vontade Inabalável',
                       effects: [{ 'kind' => 'save_advantage', 'abilities' => %w[wis cha] }])
      equipment = { equipped: { accessories: { ring_left: equipped_item_for('anel-vontade-inabalavel', 'Anel') } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:save_advantages]).to include('wis', 'cha')
    end

    it 'aplica ability_set vindo de uma manopla equipada em :gloves (mantém o maior)' do
      make_magic_item!(slug: 'manopla-forca-gigante-colina', name: 'Manopla da Força do Gigante da Colina',
                       effects: [{ 'kind' => 'ability_set', 'ability' => 'str', 'value' => 19 }])
      equipment = { equipped: { accessories: { gloves: equipped_item_for('manopla-forca-gigante-colina', 'Manopla') } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:ability_sets]).to eq('str' => 19)
    end

    it 'soma speed_bonus vindo de botas equipadas em :boots' do
      make_magic_item!(slug: 'botas-aladas-spec', name: 'Botas Aladas',
                       effects: [
                         { 'kind' => 'speed_bonus', 'value' => 10 },
                         { 'kind' => 'passive_feature', 'name' => 'Asas Mágicas', 'desc' => 'voo' },
                       ])
      equipment = { equipped: { accessories: { boots: equipped_item_for('botas-aladas-spec', 'Botas Aladas') } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:speed_bonus]).to eq(10)
      expect(res[:passive_features].map { |f| f[:name] }).to include('Asas Mágicas')
    end

    it 'agrega múltiplos accessory slots simultaneamente (cloak + ring + boots + gloves + amulet)' do
      make_magic_item!(slug: 'spec-cloak-fire',  name: 'Spec Cloak',  effects: [{ 'kind' => 'resistance', 'damage_types' => ['fogo'] }])
      make_magic_item!(slug: 'spec-ring-wis',    name: 'Spec Ring',   effects: [{ 'kind' => 'save_advantage', 'abilities' => ['wis'] }])
      make_magic_item!(slug: 'spec-boots-speed', name: 'Spec Boots',  effects: [{ 'kind' => 'speed_bonus', 'value' => 10 }])
      make_magic_item!(slug: 'spec-gloves-str',  name: 'Spec Gloves', effects: [{ 'kind' => 'ability_set', 'ability' => 'str', 'value' => 19 }])
      make_magic_item!(slug: 'spec-amulet-con',  name: 'Spec Amulet', effects: [{ 'kind' => 'ability_set', 'ability' => 'con', 'value' => 19 }])

      equipment = { equipped: { accessories: {
        cloak:     equipped_item_for('spec-cloak-fire',  'Spec Cloak'),
        ring_left: equipped_item_for('spec-ring-wis',    'Spec Ring'),
        boots:     equipped_item_for('spec-boots-speed', 'Spec Boots'),
        gloves:    equipped_item_for('spec-gloves-str',  'Spec Gloves'),
        amulet:    equipped_item_for('spec-amulet-con',  'Spec Amulet'),
      } } }

      res = described_class.new(sheet_stub, equipment: equipment).call

      expect(res[:resistances]).to     include('fogo')
      expect(res[:save_advantages]).to include('wis')
      expect(res[:speed_bonus]).to     eq(10)
      expect(res[:ability_sets]).to    eq('str' => 19, 'con' => 19)
    end

    it 'aplica ac_bonus tipado vindo de um anel de proteção (slot ring_right)' do
      make_magic_item!(
        slug: 'spec-anel-protecao',
        name: 'Spec Anel da Proteção',
        category: 'ring',
        effects: [{ 'kind' => 'ac_bonus', 'value' => 1, 'type' => 'magico' }],
      )
      equipment = { equipped: { accessories: { ring_right: equipped_item_for('spec-anel-protecao', 'Spec Anel da Proteção') } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:ac_bonus]).to eq(1)
    end

    it 'usa o maior valor quando dois itens dão ability_set para o mesmo atributo' do
      make_magic_item!(slug: 'spec-glove-str-19', name: 'Spec Glove 19',
                       effects: [{ 'kind' => 'ability_set', 'ability' => 'str', 'value' => 19 }])
      make_magic_item!(slug: 'spec-belt-str-21',  name: 'Spec Belt 21',
                       effects: [{ 'kind' => 'ability_set', 'ability' => 'str', 'value' => 21 }])

      equipment = { equipped: { accessories: {
        gloves: equipped_item_for('spec-glove-str-19', 'Spec Glove 19'),
        belt:   equipped_item_for('spec-belt-str-21',  'Spec Belt 21'),
      } } }

      res = described_class.new(sheet_stub, equipment: equipment).call
      expect(res[:ability_sets]['str']).to eq(21)
    end
  end

  describe 'sem accessories' do
    it 'retorna defaults quando equipped[:accessories] está vazio' do
      equipment = { equipped: { accessories: {} } }
      res = described_class.new(sheet_stub, equipment: equipment).call

      expect(res[:resistances]).to be_empty
      expect(res[:save_advantages]).to be_empty
      expect(res[:ability_sets]).to be_empty
      expect(res[:speed_bonus]).to eq(0)
      expect(res[:passive_features]).to be_empty
      expect(res[:ac_bonus]).to eq(0)
    end
  end
end
