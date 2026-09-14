# frozen_string_literal: true

require 'rails_helper'

# ALGIBEIRA como a aljava das MOEDAS (14/09/2026).
#
# O dinheiro de um item vive na lista de algibeiras da ficha (`coin_pouches`),
# ligado ao item por `sheet_item_id` — a MESMA lista que a carteira lê, então o
# total da ficha continua a somar tudo sem uma segunda contagem.
RSpec.describe Sheet, 'algibeira do inventário' do
  let(:sheet) do
    s = create(:sheet)
    s.update!(coins: { 'cp' => 0, 'sp' => 0, 'ep' => 0, 'gp' => 400, 'pp' => 0 })
    s.reload
  end

  def catalogo!(capacidade)
    Item.find_or_initialize_by(api_index: 'algibeira')
        .update!(name: 'Algibeira', kind: 'gear', props: { 'coin_capacity' => capacidade })
  end

  def linha!(nome, index: nil, ficha: sheet)
    SheetItem.create!(sheet: ficha, item_name: nome, item_index: index,
                      category: 'Itens Gerais', quantity: 1, source: 'test')
  end

  let(:algibeira) do
    catalogo!(300)
    linha!('Algibeira', index: 'algibeira')
  end

  def da_algibeira(item)
    sheet.reload.coin_pouches.find { |p| p['sheet_item_id'].to_s == item.id.to_s }
  end

  describe 'quem guarda moedas' do
    it 'a Algibeira do catálogo declara 300' do
      expect(algibeira.coin_capacity).to eq(300)
      expect(algibeira.coin_container?).to be true
    end

    it '⚠️ NUNCA pelo nome: "bolsa PO" (dinheiro solto) e a Bolsa de componentes não guardam' do
      expect(linha!('bolsa PO').coin_container?).to be false
      expect(linha!('Bolsa de componentes').coin_container?).to be false
    end

    it 'recipiente nunca empilha' do
      expect(SheetItem.container_instance?(algibeira)).to be true
    end
  end

  describe '#transfer_coins!' do
    it 'guardar cria a algibeira do item no 1º movimento; o total não muda' do
      sheet.transfer_coins!({ 'gp' => 120 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)

      expect(da_algibeira(algibeira)).to include('gp' => 120, 'name' => 'Algibeira')
      expect(sheet.coin_pouches.first['gp']).to eq(280)
      expect(sheet.wallet_hash['gp']).to eq(400)
    end

    it 'o 2º movimento reaproveita a MESMA algibeira' do
      2.times { sheet.transfer_coins!({ 'gp' => 10 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id) }

      expect(sheet.reload.coin_pouches.size).to eq(2)
      expect(da_algibeira(algibeira)['gp']).to eq(20)
    end

    it 'duas algibeiras no inventário não se confundem na carteira: a segunda vira "Algibeira 2"' do
      outra = linha!('Algibeira', index: 'algibeira')
      sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: outra.id)

      expect(da_algibeira(outra)['name']).to eq('Algibeira 2')
    end

    it '⚠️ teto: passar de 300 é recusado e a algibeira recém-criada NÃO fica para trás' do
      expect {
        sheet.transfer_coins!({ 'gp' => 301 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      }.to raise_error(ArgumentError, /comporta até 300 moedas \(ficaria com 301\)/)

      expect(sheet.reload.coin_pouches.size).to eq(1)
      expect(sheet.wallet_hash['gp']).to eq(400)
    end

    it 'o teto conta PEÇAS de todas as denominações' do
      sheet.set_wallet!('cp' => 250, 'gp' => 400)
      sheet.transfer_coins!({ 'gp' => 200 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)

      expect {
        sheet.transfer_coins!({ 'cp' => 101 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      }.to raise_error(ArgumentError, /ficaria com 301/)
    end

    it '⚠️ o mestre baixou o teto no catálogo: tirar continua possível, pôr não' do
      sheet.transfer_coins!({ 'gp' => 200 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      catalogo!(100)

      expect {
        sheet.transfer_coins!({ 'gp' => 50 }, from_sheet_item_id: algibeira.id, to_pouch_id: 'primary')
      }.not_to raise_error
      expect(da_algibeira(algibeira)['gp']).to eq(150)

      expect {
        sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      }.to raise_error(ArgumentError, /comporta até 100/)
    end

    it 'o teto vale também para o valor digitado direto na algibeira' do
      sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      id = da_algibeira(algibeira)['id']

      expect { sheet.set_pouch_wallet!(id, 'gp' => 301) }.to raise_error(ArgumentError, /comporta até 300/)
    end

    it 'item que não guarda moedas → ArgumentError' do
      bolsa = linha!('bolsa PO')

      expect {
        sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: bolsa.id)
      }.to raise_error(ArgumentError, /não guarda moedas/)
    end

    it '⚠️ item de OUTRA ficha → não encontrado' do
      catalogo!(300)
      item_alheio = linha!('Algibeira', index: 'algibeira', ficha: create(:sheet))

      expect {
        sheet.transfer_coins!({ 'gp' => 1 }, from_pouch_id: 'primary', to_sheet_item_id: item_alheio.id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'apagar a Algibeira' do
    it 'devolve as moedas para a Carteira e a algibeira some da lista' do
      sheet.transfer_coins!({ 'gp' => 120 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)

      algibeira.destroy!

      sheet.reload
      expect(sheet.coin_pouches.size).to eq(1)
      expect(sheet.coin_pouches.first['gp']).to eq(400)
      expect(sheet.wallet_hash['gp']).to eq(400)
    end

    it '⚠️ devolve MESMO que o mestre tenha tirado a capacidade do catálogo depois' do
      sheet.transfer_coins!({ 'gp' => 120 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      Item.find_by(api_index: 'algibeira').update!(props: {})

      SheetItem.find(algibeira.id).destroy!

      expect(sheet.reload.coin_pouches.size).to eq(1)
      expect(sheet.coin_pouches.first['gp']).to eq(400)
    end

    it 'item sem algibeira ligada não mexe na carteira' do
      sheet.transfer_coins!({ 'gp' => 7 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      corda = linha!('Corda')

      expect { corda.destroy! }.not_to(change { sheet.reload.coin_pouches })
    end

    it 'a ficha inteira a ser apagada não tenta devolver (não há para onde)' do
      sheet.transfer_coins!({ 'gp' => 5 }, from_pouch_id: 'primary', to_sheet_item_id: algibeira.id)
      item = SheetItem.find(algibeira.id)
      item.destroyed_by_association = Sheet.reflect_on_association(:sheet_items)

      expect_any_instance_of(Sheet).not_to receive(:release_item_coin_pouch!)
      item.destroy!
    end
  end
end
