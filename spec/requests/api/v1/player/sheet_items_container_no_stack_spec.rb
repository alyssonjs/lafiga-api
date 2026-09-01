# frozen_string_literal: true

require 'rails_helper'

# RECIPIENTE nunca empilha: cada aljava guarda uma munição diferente, em
# quantidade diferente, e a munição aponta para o ID DELA. Numa linha
# "Aljava ×2" as duas unidades são o mesmo id — equipar uma equipava as duas.
RSpec.describe 'SheetItems — recipiente não empilha', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Aljava Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def post_item(attrs)
    post '/api/v1/player/sheet_items',
         params: { sheet_item: { sheet_id: sheet.id }.merge(attrs) },
         headers: headers, as: :json
    response
  end

  # ⚠️ `props_json` IGUAL nas duas, de propósito: a linha real da mesa é
  # `{"weight_lb" => 1}` e é o `normalize_stack_props` que compara. Sem repetir
  # as props, o empilhamento nem chegava a ser tentado e o teste passava pelo
  # motivo errado — o guard podia ser removido sem quebrar nada.
  ALJAVA = { item_index: 'aljava', item_name: 'Aljava', category: 'Itens Gerais',
             quantity: 1, source: 'manual', props_json: { weight_lb: 1 } }.freeze

  it 'duas aljavas viram DUAS linhas, cada uma com quantidade 1' do
    post_item(ALJAVA)
    post_item(ALJAVA)

    linhas = SheetItem.where(sheet_id: sheet.id, item_index: 'aljava')
    expect(linhas.count).to eq(2)
    expect(linhas.map(&:quantity)).to eq([1, 1])
  end

  it 'equipar uma aljava NÃO equipa a outra' do
    post_item(ALJAVA)
    post_item(ALJAVA)
    primeira, segunda = SheetItem.where(sheet_id: sheet.id, item_index: 'aljava').order(:id).to_a

    post "/api/v1/player/sheet_items/#{primeira.id}/equip",
         params: { slot: 'back' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    expect(primeira.reload.equipped).to be true
    expect(segunda.reload.equipped).to be false
  end

  it '⚠️ item comum CONTINUA empilhando (a regra é só p/ recipiente)' do
    pocao = { item_index: 'spec-pocao-x', item_name: 'Poção X', category: 'Poções',
              source: 'manual', props_json: { weight_lb: 1 } }
    post_item(pocao.merge(quantity: 1))
    post_item(pocao.merge(quantity: 2))

    linhas = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pocao-x')
    expect(linhas.count).to eq(1)
    expect(linhas.first.quantity).to eq(3)
  end

  it '⚠️ "bolsa PO" (dinheiro) NÃO é recipiente — o nome não pode barrar o empilhamento' do
    # O leitor tolerante do `bag?` casa por nome e pegaria esta linha; separar
    # uma pilha de 120 moedas em 120 linhas foi o desastre que a medição evitou.
    bolsa = { item_name: 'bolsa PO', category: 'Itens Gerais', source: 'manual',
              props_json: { weight_lb: 0 } }
    post_item(bolsa.merge(quantity: 40))
    post_item(bolsa.merge(quantity: 80))

    linhas = SheetItem.where(sheet_id: sheet.id, item_name: 'bolsa PO')
    expect(linhas.count).to eq(1)
    expect(linhas.first.quantity).to eq(120)
  end

  it 'o merge explícito também recusa aljavas' do
    post_item(ALJAVA)
    post_item(ALJAVA)
    a, b = SheetItem.where(sheet_id: sheet.id, item_index: 'aljava').order(:id).to_a

    expect {
      SheetItems::MergeStacksService.new(sheet: sheet, source_id: a.id, target_id: b.id).call
    }.to raise_error(SheetItems::MergeStacksService::InvalidMerge, /conteúdo próprio/)
  end
end
