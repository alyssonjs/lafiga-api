# frozen_string_literal: true

require 'rails_helper'

# Regressão: "Poção de Cura" adicionada 2× virava 2 linhas distintas em vez de
# somar a quantidade. O `create` agora empilha itens idênticos não-equipados.
RSpec.describe 'Api::V1::Player::SheetItemsController create — stacking', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Stack Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def post_item(attrs)
    post '/api/v1/player/sheet_items',
         params: { sheet_item: { sheet_id: sheet.id }.merge(attrs) },
         headers: headers,
         as: :json
    response
  end

  it 'soma a quantidade ao adicionar o MESMO item de catálogo (item_index) duas vezes' do
    r1 = post_item(item_index: 'spec-pocao-cura', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 1, source: 'manual')
    expect(r1).to have_http_status(:created), -> { r1.body }

    r2 = post_item(item_index: 'spec-pocao-cura', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 10, source: 'manual')
    expect(r2).to have_http_status(:ok), -> { r2.body }

    rows = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pocao-cura')
    expect(rows.count).to eq(1)
    expect(rows.first.quantity).to eq(11)

    body = r2.parsed_body['sheet_item']
    expect(body['id']).to eq(rows.first.id)
    expect(body['quantity']).to eq(11)
  end

  it 'soma item custom (sem item_index resolvível) pelo nome + categoria' do
    r1 = post_item(item_name: 'Bugiganga Inédita ZZ', category: 'Tesouros', quantity: 2, source: 'manual')
    expect(r1).to have_http_status(:created), -> { r1.body }
    first_id = r1.parsed_body['sheet_item']['id']

    r2 = post_item(item_name: 'bugiganga inédita zz', category: 'Tesouros', quantity: 3, source: 'manual')
    expect(r2).to have_http_status(:ok), -> { r2.body }

    rows = SheetItem.where(sheet_id: sheet.id).where('LOWER(item_name) = ?', 'bugiganga inédita zz')
    expect(rows.count).to eq(1)
    expect(rows.first.quantity).to eq(5)
    expect(r2.parsed_body['sheet_item']['id']).to eq(first_id)
  end

  it 'NÃO empilha em itens equipados (a instância equipada é distinta)' do
    weapon = SheetItem.create!(
      sheet: sheet, item_name: 'Adaga Spec', item_index: 'spec-adaga', category: 'Armas',
      quantity: 1, equipped: true, slot: 'main_hand', source: 'test'
    )

    r = post_item(item_index: 'spec-adaga', item_name: 'Adaga Spec', category: 'Armas', quantity: 1, source: 'manual')
    expect(r).to have_http_status(:created), -> { r.body }

    expect(SheetItem.where(sheet_id: sheet.id, item_index: 'spec-adaga', equipped: true).count).to eq(1)
    expect(SheetItem.where(sheet_id: sheet.id, item_index: 'spec-adaga', equipped: false).count).to eq(1)
    expect(weapon.reload.quantity).to eq(1)
  end

  it 'itens diferentes continuam em linhas separadas' do
    post_item(item_index: 'spec-corda', item_name: 'Corda de Cânhamo', category: 'Aventura', quantity: 1, source: 'manual')
    post_item(item_index: 'spec-tocha', item_name: 'Tocha', category: 'Aventura', quantity: 1, source: 'manual')

    expect(SheetItem.where(sheet_id: sheet.id, item_index: %w[spec-corda spec-tocha]).count).to eq(2)
  end

  # ── Estado por-instância: NÃO empilhar (senão compartilhariam 1 contador) ──
  it 'NÃO empilha itens com cargas (varinhas/cajados) — instâncias independentes' do
    attrs = { item_index: 'spec-varinha', item_name: 'Varinha de Mísseis Mágicos', category: 'Itens Mágicos',
              quantity: 1, source: 'manual', props_json: { charges: { current: 7, max: 7 }, magical: true } }
    r1 = post_item(attrs)
    expect(r1).to have_http_status(:created), -> { r1.body }
    r2 = post_item(attrs)
    expect(r2).to have_http_status(:created), -> { r2.body }

    rows = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-varinha')
    expect(rows.count).to eq(2)
    expect(rows.pluck(:quantity)).to all(eq(1))
  end

  it 'NÃO empilha itens sintonizados (attuned) — instâncias independentes' do
    attrs = { item_index: 'spec-anel', item_name: 'Anel de Proteção', category: 'Itens Mágicos',
              quantity: 1, source: 'manual', props_json: { attuned: true, magical: true } }
    post_item(attrs)
    post_item(attrs)
    expect(SheetItem.where(sheet_id: sheet.id, item_index: 'spec-anel').count).to eq(2)
  end

  it 'NÃO empilha quando as anotações (notes) divergem' do
    post_item(item_index: 'spec-pergaminho', item_name: 'Pergaminho', category: 'Consumíveis', quantity: 1, source: 'manual', notes: 'do bruxo')
    post_item(item_index: 'spec-pergaminho', item_name: 'Pergaminho', category: 'Consumíveis', quantity: 1, source: 'manual', notes: 'do mago')
    expect(SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pergaminho').count).to eq(2)
  end

  it 'retorna 422 para input inválido (sem item_name), sem 500 pelo with_lock' do
    r = post_item(item_index: 'spec-sem-nome', category: 'Aventura', quantity: 1, source: 'manual')
    expect(r).to have_http_status(:unprocessable_entity), -> { r.body }
    expect(r.parsed_body['errors']).to be_present
  end

  # ── Separação por origem: create do jogador não mescla na pilha dm_grant ──
  it 'NÃO mescla a adição manual do jogador na pilha de auditoria do DM (dm_grant)' do
    granted = SheetItem.create!(
      sheet: sheet, item_index: 'spec-pocao-dm', item_name: 'Poção de Cura', category: 'Consumíveis',
      quantity: 1, equipped: false, source: 'dm_grant'
    )

    r = post_item(item_index: 'spec-pocao-dm', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 1, source: 'manual')
    expect(r).to have_http_status(:created), -> { r.body }

    expect(granted.reload.quantity).to eq(1) # pilha do DM intacta
    manual = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pocao-dm', source: 'manual')
    expect(manual.count).to eq(1)
    expect(manual.first.quantity).to eq(1)
  end
end
