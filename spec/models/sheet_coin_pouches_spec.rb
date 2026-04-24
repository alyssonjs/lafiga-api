# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sheet, 'coin_pouches' do
  let(:sheet) do
    s = create(:sheet)
    s.update!(coins: { 'cp' => 2, 'sp' => 0, 'ep' => 0, 'gp' => 7, 'pp' => 0 })
    s.reload
  end

  it 'mantem coins como soma das algibeiras apos salvar' do
    expect(sheet.wallet_hash['gp']).to eq(7)
    expect(sheet.wallet_hash['cp']).to eq(2)
    expect(sheet.coin_pouches.length).to eq(1)
  end

  it 'set_wallet! atualiza a algibeira primaria' do
    sheet.set_wallet!({ gp: 3, cp: 0 })
    expect(sheet.wallet_hash['gp']).to eq(3)
    expect(sheet.coin_pouches.first['gp']).to eq(3)
  end

  it 'add_coin_pouch! acrescenta algibeira vazia e preserva saldos' do
    sheet.add_coin_pouch!('Reserva do navio')
    expect(sheet.coin_pouches.size).to eq(2)
    expect(sheet.wallet_hash['gp']).to eq(7)
    expect(sheet.coin_pouches.last['name']).to eq('Reserva do navio')
  end

  it 'set_pouch_wallet! altera uma algibeira especifica' do
    sheet.add_coin_pouch!('Bolsa')
    second_id = sheet.coin_pouches.last['id']
    sheet.set_pouch_wallet!(second_id, { gp: 4, cp: 0, sp: 0, ep: 0, pp: 0 })
    expect(sheet.wallet_hash['gp']).to eq(7 + 4)
  end

  it 'destroy_coin_pouch! remove algibeira vazia' do
    sheet.add_coin_pouch!('Vazia')
    extra_id = sheet.coin_pouches.last['id']
    sheet.destroy_coin_pouch!(extra_id)
    expect(sheet.coin_pouches.size).to eq(1)
  end

  it 'transfer_pouch_coins! move moedas entre algibeiras' do
    sheet.add_coin_pouch!('Cofre')
    primary = sheet.coin_pouches.first['id']
    cofre_id = sheet.coin_pouches.last['id']
    sheet.set_pouch_wallet!(cofre_id, { gp: 5, cp: 0, sp: 0, ep: 0, pp: 0 })
    sheet.transfer_pouch_coins!(cofre_id, primary, { gp: 2 })
    sheet.reload
    expect(sheet.coin_pouches.last['gp']).to eq(3)
    expect(sheet.coin_pouches.first['gp']).to eq(7 + 2)
  end

  it 'transfer_pouch_coins! falha se pedir mais do que ha na origem' do
    sheet.add_coin_pouch!('Cofre')
    cofre_id = sheet.coin_pouches.last['id']
    sheet.set_pouch_wallet!(cofre_id, { gp: 1, cp: 0, sp: 0, ep: 0, pp: 0 })
    expect do
      sheet.transfer_pouch_coins!(cofre_id, sheet.coin_pouches.first['id'], { gp: 5 })
    end.to raise_error(ArgumentError, /Saldo insuficiente/)
  end
end

RSpec.describe AlgibeiraCoinParser do
  it 'detecta item de algibeira com po' do
    name = 'Uma algibeira contendo 15 po'
    expect(AlgibeiraCoinParser.pouch_coin_item?(name)).to be(true)
    w = AlgibeiraCoinParser.parse_pouch_wallet(name)
    expect(w['gp']).to eq(15)
  end

  it 'nao confunde item sem moeda' do
    expect(AlgibeiraCoinParser.pouch_coin_item?('Algibeira vazia')).to be(false)
  end
end
