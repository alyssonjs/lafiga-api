# frozen_string_literal: true

require 'rails_helper'

# CATRACA de custo do snapshot do catálogo (achado da revisão de 29/08).
#
# `build_crafting_json` toca `item.crafting_recipe` (e cada ingrediente toca
# `ingredient_item` e `spell`) POR ITEM. Sem o preload em
# `items_for_category_from_db`, a montagem media **1.767 queries e 1,7 s por
# requisição** num catálogo de produção (946 itens) — e o snapshot é pedido a
# cada boot do modal "+ Novo Item", num box de 1 CPU.
#
# O teto aqui é folgado de propósito (categorias × preloads + versão do cache),
# mas ordens de grandeza ABAIXO do N+1: se alguém rematerializar um balde sem o
# preload, isto estoura muito antes do jogador sentir.
RSpec.describe 'Api::V1::Public::Equipment snapshot — custo', type: :request do
  it 'não faz query POR ITEM (o N+1 da receita não pode voltar)' do
    # Itens com receita são o gatilho: um por família de serialização.
    ferramenta = Item.create!(api_index: 'perf-tool', name: 'Serra de Teste', kind: 'tool', value_gp: 5)
    material = Item.create!(api_index: 'perf-mat', name: 'Tábua de Teste', kind: 'material', value_gp: 1)
    receita = CraftingRecipe.create!(result_item: ferramenta, craft: 'forge', dc: 10)
    CraftingRecipeIngredient.create!(crafting_recipe: receita, ingredient_item: material,
                                     quantity: 2, unit: 'un')

    contador = 0
    contando = ActiveSupport::Notifications.subscribe('sql.active_record') { |*_| contador += 1 }
    get '/api/v1/public/equipment_catalog_snapshot'
    ActiveSupport::Notifications.unsubscribe(contando)

    expect(response).to have_http_status(:ok)
    expect(contador).to be < 120,
      "snapshot fez #{contador} queries — cheiro de N+1 de receita (baseline pós-fix: ~70)"
  end

  it 'a receita continua chegando (o preload não pode mudar o payload)' do
    ferramenta = Item.create!(api_index: 'perf-tool2', name: 'Plaina de Teste', kind: 'tool', value_gp: 5)
    receita = CraftingRecipe.create!(result_item: ferramenta, craft: 'forge', dc: 12)
    CraftingRecipeIngredient.create!(crafting_recipe: receita, quantity: 1, unit: 'un', raw_text: 'Madeira')

    get '/api/v1/public/equipment_catalog_snapshot'

    linha = response.parsed_body.dig('by_category', 'tools')
      &.find { |r| r['index'] == 'perf-tool2' }
    expect(linha).to be_present
    expect(linha.dig('crafting', 'dc')).to eq(12)
    expect(linha.dig('crafting', 'ingredients', 0, 'raw_text')).to eq('Madeira')
  end

  it 'a MESMA versão responde 304 (o cliente não rebaixa o payload de novo)' do
    get '/api/v1/public/equipment_catalog_snapshot'
    etag = response.headers['ETag']
    expect(etag).to be_present

    get '/api/v1/public/equipment_catalog_snapshot', headers: { 'If-None-Match' => etag }
    expect(response).to have_http_status(:not_modified)
  end

  it 'editar um item INVALIDA a versão (o mestre não pode ver catálogo velho)' do
    item = Item.create!(api_index: 'perf-versao', name: 'Cadinho', kind: 'tool', value_gp: 2)
    get '/api/v1/public/equipment_catalog_snapshot'
    etag = response.headers['ETag']

    item.update!(name: 'Cadinho de Ferro')

    get '/api/v1/public/equipment_catalog_snapshot', headers: { 'If-None-Match' => etag }
    expect(response).to have_http_status(:ok), 'a edição devia ter mudado o ETag'
  end
end
