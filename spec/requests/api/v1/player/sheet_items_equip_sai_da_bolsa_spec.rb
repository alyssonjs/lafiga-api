require 'rails_helper'

# O que vai à MÃO sai da bolsa — menos o consumível, que sai UMA unidade.
#
# ⚠️ Antes, a linha equipada mantinha `props_json['bag_sheet_item_id']` e a tela
# listava o item DENTRO da mochila e na mão ao mesmo tempo. O peso contava
# certo; quem mentia era a bolsa. Medido em dados reais: 3 linhas assim.
RSpec.describe 'Api::V1::Player::SheetItems — equipar sai da bolsa', type: :request do
  let(:user) { create(:user, role: Role.find_or_create_by!(name: 'Player')) }
  let(:character) { create(:character, user: user) }
  let(:sheet) { create(:sheet, character: character) }
  let(:headers) { bearer_headers_for(user) }
  let(:corpo) { JSON.parse(response.body) }

  let!(:mochila) do
    SheetItem.create!(sheet_id: sheet.id, item_name: 'Mochila', quantity: 1,
                      equipped: true, slot: 'back')
  end

  def linha(nome, quantidade: 1, kind: 'gear')
    item = Item.create!(api_index: "eq-#{nome.parameterize}-#{SecureRandom.hex(3)}", name: nome, kind: kind)
    SheetItem.create!(
      sheet_id: sheet.id, item_id: item.id, item_index: item.api_index,
      item_name: nome, quantity: quantidade,
      props_json: { SheetItem::BAG_CONTAINER_PROP => mochila.id }
    )
  end

  def equipar(si, slot: 'main_hand', props: {})
    post "/api/v1/player/sheet_items/#{si.id}/equip",
         params: { slot: slot, props_json: props }.to_json,
         headers: headers.merge('Content-Type' => 'application/json')
  end

  describe 'item comum' do
    it '⚠️ SAI da bolsa ao ir para a mão', :aggregate_failures do
      si = linha('Bastão')
      equipar(si)

      expect(response).to have_http_status(:ok)
      expect(si.reload.equipped).to be(true)
      expect(si.props_json[SheetItem::BAG_CONTAINER_PROP]).to be_nil
    end

    it 'a empunhadura declarada é gravada' do
      si = linha('Bastão')
      equipar(si, props: { using_two_hands: true })
      expect(si.reload.props_json['using_two_hands']).to be(true)
    end
  end

  describe '⚠️ consumível: sai UMA unidade, o resto fica' do
    it 'a pilha divide-se', :aggregate_failures do
      si = linha('Poção de Cura', quantidade: 5, kind: 'consumable')
      equipar(si)

      expect(response).to have_http_status(:ok)
      # A linha original fica na bolsa com 4.
      expect(si.reload.quantity).to eq(4)
      expect(si.equipped).to be(false)
      expect(si.props_json[SheetItem::BAG_CONTAINER_PROP]).to eq(mochila.id)

      # E nasce uma linha de 1 na mão, fora da bolsa.
      na_mao = SheetItem.where(sheet_id: sheet.id, equipped: true, slot: 'main_hand').first
      expect(na_mao.quantity).to eq(1)
      expect(na_mao.item_name).to eq('Poção de Cura')
      expect(na_mao.props_json[SheetItem::BAG_CONTAINER_PROP]).to be_nil
    end

    it 'consumível ÚNICO não se divide — sai inteiro', :aggregate_failures do
      si = linha('Poção Rara', quantidade: 1, kind: 'consumable')
      equipar(si)

      expect(si.reload.equipped).to be(true)
      expect(si.quantity).to eq(1)
      expect(si.props_json[SheetItem::BAG_CONTAINER_PROP]).to be_nil
      expect(SheetItem.where(sheet_id: sheet.id, item_name: 'Poção Rara').count).to eq(1)
    end

    it '⚠️ item comum com quantidade > 1 NÃO se divide' do
      # Cinco adagas vão todas para a mão? Não: a pilha inteira muda de sítio.
      # Dividir só faz sentido para o que se saca uma unidade de cada vez.
      si = linha('Adaga', quantidade: 3)
      equipar(si)

      expect(si.reload.quantity).to eq(3)
      expect(si.equipped).to be(true)
    end
  end
end
