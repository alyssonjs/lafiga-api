# frozen_string_literal: true

require 'rails_helper'

# CINTO DE PERNA (02/09): um por perna, slots próprios
# (`belt_leg_left`/`belt_leg_right`), porque o personagem usa os três ao mesmo
# tempo — cinturão na cintura e um coldre em cada perna.
#
# A diferença que justifica o slot separado é a VOCAÇÃO: no coldre só cabe o que
# se enfia nele — arma PEQUENA (a propriedade `light` do PHB) e consumível.
# Espada longa, aljava, livro e instrumento continuam no cinturão.
RSpec.describe 'SheetItems — cinto de perna', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  def cinto_catalogo!(slug, livres:, consumiveis: 0)
    Item.find_by(api_index: slug) || Item.create!(
      api_index: slug, name: "Cinto #{slug}", kind: 'gear', category: 'belt',
      props: { 'belt_free_slots' => livres, 'belt_consumable_slots' => consumiveis },
    )
  end

  def catalogo!(slug, nome, kind, props = {})
    Item.find_by(api_index: slug) || Item.create!(api_index: slug, name: nome, kind: kind, props: props)
  end

  def linha!(nome, index: nil, qty: 1)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Itens Gerais',
                      quantity: qty, source: 'test')
  end

  def vestir(item, slot)
    post "/api/v1/player/sheet_items/#{item.id}/equip", params: { slot: slot }, headers: headers, as: :json
  end

  def prender(item, cinto)
    post "/api/v1/player/sheet_items/#{item.id}/stow_on_belt",
         params: { belt_id: cinto&.id }, headers: headers, as: :json
  end

  # Coldre vestido na perna esquerda, com 1 vaga livre e 1 de consumível.
  let(:coldre) do
    c = linha!('Coldre de coxa', index: cinto_catalogo!('coldre-perna', livres: 1, consumiveis: 1).api_index)
    vestir(c, 'belt_leg_left')
    c.reload
  end

  describe 'os slots existem, um por perna' do
    it 'aceita vestir nas DUAS pernas, e cada uma leva o seu' do
      esq = linha!('Coldre esq.', index: cinto_catalogo!('coldre-perna', livres: 1).api_index)
      dir = linha!('Coldre dir.', index: 'coldre-perna')

      vestir(esq, 'belt_leg_left')
      expect(response).to have_http_status(:ok), -> { response.body }
      vestir(dir, 'belt_leg_right')
      expect(response).to have_http_status(:ok), -> { response.body }

      expect(esq.reload.slot).to eq('belt_leg_left')
      expect(dir.reload.slot).to eq('belt_leg_right')
      # ⚠️ Um NÃO desequipa o outro: são pernas diferentes.
      expect(esq.equipped).to be true
      expect(dir.equipped).to be true
    end

    it 'o cinto da CINTURA continua cabendo junto (são três lugares)', :aggregate_failures do
      cintura = linha!('Cinturão', index: cinto_catalogo!('cinturao', livres: 2).api_index)
      perna = linha!('Coldre', index: cinto_catalogo!('coldre-perna', livres: 1).api_index)

      vestir(cintura, 'belt')
      vestir(perna, 'belt_leg_left')

      expect(cintura.reload.equipped).to be true
      expect(perna.reload.equipped).to be true
    end
  end

  describe 'vocação ESTREITA do coldre' do
    it 'ARMA PEQUENA (light) entra' do
      catalogo!('adaga', 'Adaga', 'weapon', { 'light' => true, 'damage_die' => '1d4' })
      adaga = linha!('Adaga', index: 'adaga')

      prender(adaga, coldre)

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(adaga.reload.props_json[SheetItem::BELT_CONTAINER_PROP].to_s).to eq(coldre.id.to_s)
    end

    it 'CONSUMÍVEL entra' do
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocao = linha!('Poção de Cura', index: 'pocao-cura')

      prender(pocao, coldre)

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(pocao.reload.props_json[SheetItem::BELT_CONTAINER_PROP].to_s).to eq(coldre.id.to_s)
    end

    it '⚠️ arma GRANDE NÃO entra — e é esse o motivo do coldre existir' do
      catalogo!('espada-longa-x', 'Espada Longa', 'weapon', { 'damage_die' => '1d8' })
      espada = linha!('Espada Longa', index: 'espada-longa-x')

      prender(espada, coldre)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/armas pequenas e consumíveis/i)
      expect((espada.reload.props_json || {})[SheetItem::BELT_CONTAINER_PROP]).to be_nil
    end

    it '⚠️ ferramenta, livro e aljava ficam para o cinturão' do
      catalogo!('ferramenta-x', 'Ferramentas de Ladrão', 'tool')
      catalogo!('livro-x', 'Livro', 'book')
      [linha!('Ferramentas de Ladrão', index: 'ferramenta-x'), linha!('Livro', index: 'livro-x')].each do |item|
        prender(item, coldre)
        expect(response).to have_http_status(:unprocessable_entity), -> { item.item_name }
      end
    end

    it '⚠️ a MESMA espada entra no cinto da CINTURA — a vocação é do lugar', :aggregate_failures do
      catalogo!('espada-longa-x', 'Espada Longa', 'weapon', { 'damage_die' => '1d8' })
      espada = linha!('Espada Longa', index: 'espada-longa-x')
      cintura = linha!('Cinturão', index: cinto_catalogo!('cinturao', livres: 2).api_index)
      vestir(cintura, 'belt')

      prender(espada, cintura.reload)

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(espada.reload.props_json[SheetItem::BELT_CONTAINER_PROP].to_s).to eq(cintura.id.to_s)
    end
  end

  describe 'vagas' do
    it 'respeita a contagem do catálogo, como o cinturão' do
      catalogo!('adaga', 'Adaga', 'weapon', { 'light' => true })
      a1 = linha!('Adaga', index: 'adaga')
      a2 = linha!('Adaga', index: 'adaga')

      prender(a1, coldre)
      expect(response).to have_http_status(:ok), -> { response.body }
      prender(a2, coldre)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/sem vaga/i)
    end
  end
end
