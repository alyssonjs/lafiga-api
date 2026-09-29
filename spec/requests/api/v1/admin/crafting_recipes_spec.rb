# frozen_string_literal: true

require 'rails_helper'

# O catálogo de receitas que o Mestre escreve na Oficina.
RSpec.describe 'Api::V1::Admin::CraftingRecipes', type: :request do
  let(:dm) { create(:user, role: Role.find_or_create_by!(name: 'DM')) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  def corpo = JSON.parse(response.body)

  let(:espada) { oficina_item('esp-longa', 'Espada Longa', kind: 'weapon', category: 'martial') }
  let(:ferro) { oficina_item('mat-lingote-ferro', 'Lingote de Ferro') }
  let(:couro) { oficina_item('mat-couro', 'Couro Curtido') }
  let(:tecido) { oficina_item('mat-tecido', 'Tecido') }

  def cria(extra = {})
    post '/api/v1/admin/crafting_recipes', headers: headers, params: {
      crafting_recipe: {
        result_item_id: espada.id, craft: 'forge', tool_api_index: 'tool-ferreiro', dc: 13, days: 5,
        notes: 'forja quente',
        ingredients: [{ item_id: ferro.id, quantity: 3, unit: 'un' },
                      { item_id: couro.id, quantity: 1, unit: 'un', alternative_group: 1 },
                      { item_id: tecido.id, quantity: 1, unit: 'un', alternative_group: 1 }],
      }.merge(extra),
    }.to_json
  end

  it '⚠️ só o Mestre' do
    get '/api/v1/admin/crafting_recipes', headers: bearer_headers_for(create(:user))
    expect(response).to have_http_status(:forbidden)
  end

  it 'cria receita de QUALQUER item, com ofício, ferramenta e alternativa', :aggregate_failures do
    cria
    expect(response).to have_http_status(:created)
    r = corpo['crafting_recipe']
    expect(r).to include('craft' => 'forge', 'tool_api_index' => 'tool-ferreiro', 'dc' => 13, 'days' => 5.0,
                         'notes' => 'forja quente')
    expect(r['product']).to include('name' => 'Espada Longa', 'kind' => 'weapon')
    expect(r['ingredients'].map { |i| [i['name'], i['quantity'], i['alternative_group']] })
      .to eq([['Lingote de Ferro', 3.0, nil], ['Couro Curtido', 1.0, 1], ['Tecido', 1.0, 1]])
  end

  it 'a segunda receita do mesmo item responde 422 com o id da primeira' do
    cria
    primeira = corpo.dig('crafting_recipe', 'id')
    cria
    expect(response).to have_http_status(:unprocessable_entity)
    expect(corpo['crafting_recipe_id']).to eq(primeira)
  end

  it 'editar REESCREVE os ingredientes' do
    cria
    patch "/api/v1/admin/crafting_recipes/#{corpo.dig('crafting_recipe', 'id')}", headers: headers,
          params: { crafting_recipe: { craft: 'forge', ingredients: [{ item_id: ferro.id, quantity: 4, unit: 'un' }] } }.to_json
    expect(corpo.dig('crafting_recipe', 'ingredients').map { |i| [i['name'], i['quantity']] })
      .to eq([['Lingote de Ferro', 4.0]])
  end

  it '⚠️ não apaga receita com criação em andamento', :aggregate_failures do
    cria
    receita = CraftingRecipe.find(corpo.dig('crafting_recipe', 'id'))
    sheet = create(:sheet, character: create(:character, user: create(:user)))
    sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Espada Longa', days_required: 5)

    delete "/api/v1/admin/crafting_recipes/#{receita.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(CraftingRecipe.exists?(receita.id)).to be(true)
  end

  it 'lista com busca SEM acento e paginação', :aggregate_failures do
    cria
    oficina_receita(produto: oficina_item('alq-pocao', 'Poção de Cura', kind: 'consumable', category: 'potion'),
                    ingredientes: [])
    get '/api/v1/admin/crafting_recipes', params: { q: 'pocao' }, headers: headers
    expect(corpo['crafting_recipes'].map { |r| r.dig('product', 'name') }).to eq(['Poção de Cura'])
    expect(corpo['meta']).to include('page' => 1, 'total' => 1)
  end

  it 'busca de itens: todos os tipos, quem começa com o termo primeiro, e se já tem receita', :aggregate_failures do
    cria
    oficina_item('mag-espada-flamejante', 'Uma Espada Flamejante', kind: 'magic_item', category: 'weapon')
    get '/api/v1/admin/crafting_recipes/items', params: { q: 'espada' }, headers: headers

    nomes = corpo['items'].map { |i| i['name'] }
    expect(nomes).to eq(['Espada Longa', 'Uma Espada Flamejante'])
    expect(corpo['items'].first['recipe_id']).to be_present
    expect(corpo['items'].last['recipe_id']).to be_nil
  end
end
