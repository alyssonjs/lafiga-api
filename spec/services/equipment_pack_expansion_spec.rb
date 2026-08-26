# frozen_string_literal: true

require 'rails_helper'

# Pacote de equipamento vira ITENS REAIS na mochila.
#
# Antes, o pacote entrava como uma linha de texto e os itens dentro dele não
# existiam em lugar nenhum: peso da carga errado, venda impossível, e nada
# ligado ao catálogo.
RSpec.describe CharacterProvisioningService, '#expand_equipment_pick', type: :service do
  let(:svc) { described_class.new(user: create(:user)) }
  let(:base) do
    { sheet_id: 1, category: 'class', equipped: false, slot: nil, source: 'class',
      notes: nil, created_at: Time.current, updated_at: Time.current }
  end

  let!(:mochila) { Item.create!(api_index: 'mochila', name: 'Mochila', kind: 'gear', value_gp: 2, weight_kg: 2.5) }
  let!(:tocha)   { Item.create!(api_index: 'tocha', name: 'Tocha', kind: 'consumable', category: 'supply', weight_kg: 0.5) }
  let!(:pacote) do
    Item.create!(api_index: 'pacote-teste', name: 'Pacote de Teste', kind: 'gear', category: 'pack',
                 props: { 'contents' => [
                   { 'item_index' => 'mochila', 'name' => 'Mochila', 'quantity' => 1, 'raw' => 'uma mochila' },
                   { 'item_index' => 'tocha', 'name' => 'Tocha', 'quantity' => 10, 'raw' => '10 tochas' },
                 ] })
  end

  def expandir(nome, qtd = 1, idx: nil)
    svc.send(:expand_equipment_pick, base: base, item_index: idx, item_name: nome, quantity: qtd, props: {})
  end

  it 'o pacote SOME e entram os itens reais, ligados ao catálogo' do
    linhas = expandir('Pacote de Teste')

    expect(linhas.map { |l| l[:item_name] }).to contain_exactly('Mochila', 'Tocha')
    expect(linhas.map { |l| l[:item_id] }).to contain_exactly(mochila.id, tocha.id)
    # O pacote em si não fica na bolsa: o peso está nas peças.
    expect(linhas.map { |l| l[:item_name] }).not_to include('Pacote de Teste')
  end

  it 'a quantidade do conteúdo é respeitada' do
    linhas = expandir('Pacote de Teste')
    expect(linhas.find { |l| l[:item_name] == 'Tocha' }[:quantity]).to eq(10)
  end

  it 'DOIS pacotes dobram cada peça' do
    linhas = expandir('Pacote de Teste', 2)
    expect(linhas.find { |l| l[:item_name] == 'Tocha' }[:quantity]).to eq(20)
  end

  it '⚠️ cada peça diz de onde veio — o jogador vê, e o re-provision sabe o que trocar' do
    linhas = expandir('Pacote de Teste')
    expect(linhas.map { |l| l[:props_json]['from_pack'] }.uniq).to eq(['Pacote de Teste'])
  end

  it 'item normal passa direto — mas ganha o `item_id` que antes ficava nulo' do
    linhas = expandir('Mochila', 2)

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(item_id: mochila.id, item_index: 'mochila', quantity: 2)
  end

  it '⚠️ item desconhecido NÃO some: vira linha por nome, sem link' do
    # Descartar o que não resolve deixaria a ficha silenciosamente incompleta.
    linhas = expandir('Coisa Que Não Existe')

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(item_name: 'Coisa Que Não Existe', item_id: nil)
  end

  it 'resolve por ÍNDICE antes de nome — índice é estável, nome diverge' do
    Item.create!(api_index: 'outra', name: 'Mochila', kind: 'gear')
    linhas = expandir('Mochila', 1, idx: 'mochila')
    expect(linhas.first[:item_id]).to eq(mochila.id)
  end

  it '⚠️ o TOKEN do wizard resolve — não é o api_index do pacote' do
    # O wizard manda `scholar-pack`, o catálogo guarda `pacote-estudioso`.
    # Sem o mapa, o backend procurava um item chamado "scholar-pack", não
    # achava nada, e o pacote NUNCA expandia.
    pacote.update!(api_index: 'pacote-estudioso')
    linhas = svc.send(:expand_equipment_pick, base: base, item_index: 'scholar-pack',
                      item_name: 'scholar-pack', quantity: 1, props: {})

    expect(linhas.size).to eq(2)
    expect(linhas.map { |l| l[:item_name] }).to contain_exactly('Mochila', 'Tocha')
  end

  it 'token que JÁ é api_index passa direto pelo mapa' do
    couro = Item.create!(api_index: 'studded-leather', name: 'Couro Reforçado', kind: 'armor')
    linhas = svc.send(:expand_equipment_pick, base: base, item_index: 'studded-leather',
                      item_name: 'studded-leather', quantity: 1, props: {})

    expect(linhas.first[:item_id]).to eq(couro.id)
  end

  it 'pacote SEM conteúdo (legado) entra como item só, em vez de sumir' do
    vazio = Item.create!(api_index: 'pacote-vazio', name: 'Pacote Vazio', kind: 'gear', category: 'pack')
    linhas = expandir('Pacote Vazio')

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(item_id: vazio.id, item_name: 'Pacote Vazio')
  end
end
