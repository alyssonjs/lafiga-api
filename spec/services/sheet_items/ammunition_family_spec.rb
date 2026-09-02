# frozen_string_literal: true

require 'rails_helper'

# MUNIÇÃO MÁGICA na aljava (02/09).
#
# A aljava declara `ammunition_types: ["flecha", "virote"]` e a validação
# comparava o ÍNDICE INTEIRO da pilha. "flecha-de-fogo" nunca casava — e as
# TRÊS munições mágicas do catálogo (flecha-de-fogo, virote-de-gelo,
# agulhas-de-zarabatana) eram recusadas por TODA aljava do banco.
#
# A comparação passou a ser por FAMÍLIA, e a família vem DECLARADA
# (`sub_category` do item mágico: arrow/bolt/needle) antes de qualquer leitura
# de nome.
RSpec.describe 'munição mágica na aljava', type: :model do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  # ⚠️ `equipment_slot: 'quiver'` é OBRIGATÓRIO: sem ele o
  # `EquipmentRules.ammunition_container_props` devolve nil, a lista de aceitos
  # fica VAZIA e o recipiente aceita qualquer munição — foi o que o primeiro
  # teste desta suíte pegou (a agulha entrando numa aljava de flecha/virote).
  def aljava!(nome: 'Aljava', tipos: %w[flecha virote], capacidade: 20, slug: 'aljava-spec')
    Item.find_or_create_by!(api_index: slug) do |i|
      i.name = nome
      i.kind = 'gear'
      i.props = {
        'equipment_slot' => 'quiver',
        'ammunition_types' => tipos,
        'ammunition_capacity' => capacidade,
      }
    end
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: slug,
                      category: 'gear', quantity: 1, source: 'test')
  end

  def municao!(slug, nome, sub_category: nil, quantidade: 5)
    if sub_category
      MagicItem.find_or_create_by!(slug: slug) do |m|
        m.name = nome
        m.category = 'ammunition'
        m.sub_category = sub_category
        m.rarity = 'uncommon'
      end
    end
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: slug,
                      category: 'Armas', quantity: quantidade, source: 'test')
  end

  describe 'família declarada (sub_category do item mágico)' do
    it '⚠️ a Flecha de Fogo entra na aljava que aceita "flecha"' do
      quiver = aljava!
      flecha = municao!('flecha-de-fogo-spec', 'Flecha de Fogo', sub_category: 'arrow')

      expect(flecha.ammunition_family).to eq('flecha')
      expect {
        SheetItems::AllocateAmmunitionService.new(
          ammunition: flecha, quiver_id: quiver.id, quantity: 5,
        ).call
      }.not_to raise_error
      expect(flecha.reload.ammunition_container_id).to eq(quiver.id.to_s)
    end

    it 'o Virote de Gelo (bolt) também', :aggregate_failures do
      quiver = aljava!
      virote = municao!('virote-de-gelo-spec', 'Virote de Gelo', sub_category: 'bolt')

      expect(virote.ammunition_family).to eq('virote')
      SheetItems::AllocateAmmunitionService.new(
        ammunition: virote, quiver_id: quiver.id, quantity: 5,
      ).call
      expect(virote.reload.ammunition_container_id).to eq(quiver.id.to_s)
    end

    it '⚠️ a AGULHA continua recusada por uma aljava de flecha/virote' do
      quiver = aljava!
      agulha = municao!('agulhas-de-zarabatana-spec', 'Agulhas de Zarabatana', sub_category: 'needle')

      expect(agulha.ammunition_family).to eq('agulha')
      expect {
        SheetItems::AllocateAmmunitionService.new(
          ammunition: agulha, quiver_id: quiver.id, quantity: 5,
        ).call
      }.to raise_error(SheetItems::AllocateAmmunitionService::InvalidAllocation, /não guarda/i)
    end

    it 'e ENTRA no recipiente que declara agulha' do
      porta = aljava!(nome: 'Porta-agulhas', tipos: %w[agulha], slug: 'porta-agulhas-spec')
      agulha = municao!('agulhas-de-zarabatana-spec', 'Agulhas de Zarabatana', sub_category: 'needle')

      expect {
        SheetItems::AllocateAmmunitionService.new(
          ammunition: agulha, quiver_id: porta.id, quantity: 5,
        ).call
      }.not_to raise_error
    end
  end

  describe 'leitor tolerante (munição sem declaração)' do
    it 'resolve pelo índice quando não há item mágico' do
      quiver = aljava!
      comum = municao!('flecha', 'Flechas')

      expect(comum.ammunition_family).to eq('flecha')
      expect {
        SheetItems::AllocateAmmunitionService.new(
          ammunition: comum, quiver_id: quiver.id, quantity: 5,
        ).call
      }.not_to raise_error
    end

    it 'sinônimo EN também resolve (arrow → flecha)' do
      expect(SheetItem.ammunition_family('arrow')).to eq('flecha')
      expect(SheetItem.ammunition_family('crossbow-bolt')).to eq('virote')
      expect(SheetItem.ammunition_family('sling-bullet')).to eq('bala')
    end

    it '⚠️ aljava LEGADA (sem tipos declarados) continua aceitando tudo' do
      quiver = SheetItem.create!(sheet: sheet, item_name: 'Aljava velha', item_index: 'aljava-velha',
                                 category: 'gear', quantity: 1, source: 'test')
      agulha = municao!('agulhas-x', 'Agulhas', sub_category: 'needle')

      expect(quiver.accepted_ammunition_indexes).to be_empty
      expect {
        SheetItems::AllocateAmmunitionService.new(
          ammunition: agulha, quiver_id: quiver.id, quantity: 5,
        ).call
      }.not_to raise_error
    end
  end
end
