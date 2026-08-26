# frozen_string_literal: true

require 'rails_helper'

# Matéria-prima no catálogo: um `kind: material` sub-dividido por `category`.
RSpec.describe 'Api::V1::Public::Equipment matérias-primas', type: :request do
  let!(:essencia) do
    Item.create!(api_index: 'mat-extrato-vegetal', name: 'Extrato Vegetal', kind: 'material',
                 category: 'essence', value_gp: 0.5, props: { 'unit' => 'ml' })
  end
  let!(:parte) do
    Item.create!(api_index: 'mat-pecanha', name: 'Peçonha', kind: 'material',
                 category: 'monster-part', value_gp: 5, props: { 'unit' => 'un' })
  end
  let!(:gema) do
    Item.create!(api_index: 'mat-gema-olho-de-tigre', name: 'Gema Olho de Tigre',
                 kind: 'material', category: 'gem')
  end
  # Vizinho de outra família: prova que o balde não vaza.
  let!(:ferramenta) do
    Item.create!(api_index: 'tool-x', name: 'Kit de Alquimia', kind: 'tool', category: 'artisan')
  end

  def indices(resp) = resp['equipment'].map { |e| e['index'] }

  describe 'GET /equipment_categories/materials' do
    it 'serve toda a matéria-prima e NADA além dela' do
      get '/api/v1/public/equipment_categories/materials'

      expect(response).to have_http_status(:ok)
      idx = indices(response.parsed_body)
      expect(idx).to contain_exactly('mat-extrato-vegetal', 'mat-pecanha', 'mat-gema-olho-de-tigre')
      expect(idx).not_to include('tool-x')
    end

    it '⚠️ o item SERIALIZA — o ramo genérico lista os kinds e devolve nil fora dele' do
      # Sem 'material' naquela lista, o balde acharia os 3 e o payload viria
      # vazio: foi assim que 11 livros ficaram sem aba.
      get '/api/v1/public/equipment_categories/materials'

      eq = response.parsed_body['equipment'].find { |e| e['index'] == 'mat-extrato-vegetal' }
      expect(eq).to be_present
      expect(eq['name']).to eq('Extrato Vegetal')
      expect(eq['equipment_category']).to eq('index' => 'materials', 'name' => 'Matérias-Primas')
      expect(eq['gear_category']).to eq('essence')
    end

    it 'a UNIDADE viaja: essência se compra por ml, não por peça' do
      get '/api/v1/public/equipment_categories/materials'

      eq = response.parsed_body['equipment'].find { |e| e['index'] == 'mat-extrato-vegetal' }
      expect(eq['material_unit']).to eq('ml')
    end
  end

  describe 'ervas e venenosas (2ª leva)' do
    let!(:erva) do
      Item.create!(api_index: 'herb-covette', name: 'Covette', kind: 'material',
                   category: 'herb', value_gp: 5,
                   props: {
                     'plant_type' => 'arvore',
                     'foraging' => { 'locations' => ['colina'], 'seasons' => %w[primavera verao outono inverno],
                                     'chance' => 1.0, 'dc' => 12, 'yield' => '2d4 punhados de casca',
                                     'tool' => 'kit-de-herbalismo' },
                     'preparation' => { 'method' => 'Maceração', 'usage' => ['ingestao'],
                                        'effect' => 'Elimina bactérias em 20 litros de água.' },
                   })
    end
    let!(:venenosa) do
      Item.create!(api_index: 'vherb-lagrima-de-viuva', name: 'Lágrima de viúva', kind: 'material',
                   category: 'poison-herb', value_gp: 5,
                   props: { 'foraging' => { 'tool' => 'kit-de-veneno', 'dc' => 12 } })
    end

    it 'a família poison-herb tem balde próprio' do
      get '/api/v1/public/equipment_categories/materials-poison-herb'
      expect(indices(response.parsed_body)).to contain_exactly('vherb-lagrima-de-viuva')
      # ...e a erva medicinal não vaza para lá.
      get '/api/v1/public/equipment_categories/materials-herb'
      expect(indices(response.parsed_body)).to include('herb-covette')
      expect(indices(response.parsed_body)).not_to include('vherb-lagrima-de-viuva')
    end

    it '⚠️ colheita e preparo VIAJAM no payload — dado que não chega à ficha não existe' do
      get '/api/v1/public/equipment_categories/materials'
      eq = response.parsed_body['equipment'].find { |e| e['index'] == 'herb-covette' }
      expect(eq['foraging']).to include('dc' => 12, 'tool' => 'kit-de-herbalismo')
      expect(eq['foraging']['seasons']).to eq(%w[primavera verao outono inverno])
      expect(eq['preparation']).to include('method' => 'Maceração')
      expect(eq['preparation']['effect']).to match(/bactérias/)
    end
  end

  describe 'obras de arte — TESOURO, kind próprio' do
    let!(:jarro) do
      Item.create!(api_index: 'art-jarro-de-prata', name: 'Jarro de prata', kind: 'treasure',
                   category: 'art', value_gp: 25, weight_kg: 1.0,
                   props: { 'unit' => 'un', 'art_tier' => 25 })
    end

    it 'tem balde próprio e a FAIXA viaja — é por ela que o mestre sorteia o saque' do
      get '/api/v1/public/equipment_categories/treasure'
      expect(indices(response.parsed_body)).to contain_exactly('art-jarro-de-prata')
      expect(response.parsed_body['equipment'].first['art_tier']).to eq(25)
    end

    it '⚠️ NÃO é matéria-prima: não vaza para a aba de insumos' do
      # Obra de arte não se consome para fabricar nada. A gema fica em
      # material/gem de propósito — essa SIM entra em receita.
      get '/api/v1/public/equipment_categories/materials'
      expect(indices(response.parsed_body)).not_to include('art-jarro-de-prata')
    end

    it '⚠️ o item SERIALIZA — o ramo genérico lista os kinds e devolve nil fora dele' do
      get '/api/v1/public/equipment_categories/treasure'
      eq = response.parsed_body['equipment'].first
      expect(eq).to be_present
      expect(eq['equipment_category']).to eq('index' => 'treasure', 'name' => 'Obras de Arte')
    end

    it '⚠️ o peso sai em LB pelo fator do LIVRO — 1 kg guardado vira 2 lb servido' do
      # A planilha da fonte dá lb; o banco é canônico em kg. Gravar o número da
      # planilha faria a obra pesar o dobro.
      get '/api/v1/public/equipment_categories/treasure'
      expect(response.parsed_body['equipment'].first['weight']).to eq(2.0)
    end
  end

  describe 'gemas — matéria-prima COM efeito de encaixe' do
    let!(:rubi) do
      Item.create!(api_index: 'gem-rubi', name: 'Rubi', kind: 'material', category: 'gem',
                   value_gp: 1000, weight_kg: 0.0,
                   props: { 'unit' => 'un', 'gem_tier' => 5,
                            'gem_power' => 'Fogo interior',
                            'gem_weapon_effect' => '+1d6 de dano de fogo.',
                            'gem_apparel_effect' => 'Resistência a fogo.' })
    end
    # Gema que só serve em vestuário: 3 das 52 da tabela são assim.
    let!(:so_vestuario) do
      Item.create!(api_index: 'gem-perola-negra', name: 'Pérola Negra', kind: 'material',
                   category: 'gem', value_gp: 500,
                   props: { 'gem_tier' => 4, 'gem_apparel_effect' => 'Visão no escuro 9 m.' })
    end

    it '⚠️ tier e os DOIS efeitos viajam — sem eles a gema é só um preço' do
      # O encaixe é a mecânica inteira da gema: se o efeito não chega à ficha,
      # o jogador não tem como saber o que ganhou ao engastá-la.
      get '/api/v1/public/equipment_categories/materials-gem'
      eq = response.parsed_body['equipment'].find { |e| e['index'] == 'gem-rubi' }
      expect(eq['gem_tier']).to eq(5)
      expect(eq['gem_power']).to eq('Fogo interior')
      expect(eq['gem_weapon_effect']).to match(/dano de fogo/)
      expect(eq['gem_apparel_effect']).to match(/Resistência/)
    end

    it 'gema sem efeito de arma vem com a chave nula, não com string vazia' do
      get '/api/v1/public/equipment_categories/materials-gem'
      eq = response.parsed_body['equipment'].find { |e| e['index'] == 'gem-perola-negra' }
      expect(eq['gem_weapon_effect']).to be_nil
      expect(eq['gem_apparel_effect']).to eq('Visão no escuro 9 m.')
    end

    it 'continua sendo INSUMO: aparece na aba de matérias-primas' do
      # Ao contrário da obra de arte, a gema entra em receita — por isso ficou
      # em `material/gem` e não virou tesouro.
      get '/api/v1/public/equipment_categories/materials'
      expect(indices(response.parsed_body)).to include('gem-rubi')
    end
  end

  describe 'sub-abas por família' do
    it 'materials-essence traz só as essências' do
      get '/api/v1/public/equipment_categories/materials-essence'
      expect(indices(response.parsed_body)).to contain_exactly('mat-extrato-vegetal')
    end

    it 'materials-gem traz só as gemas' do
      get '/api/v1/public/equipment_categories/materials-gem'
      expect(indices(response.parsed_body)).to contain_exactly('mat-gema-olho-de-tigre')
    end

    it 'monster-part usa hífen na categoria e underscore na rota' do
      get '/api/v1/public/equipment_categories/materials-monster-part'
      expect(indices(response.parsed_body)).to contain_exactly('mat-pecanha')
    end

    it 'família inventada não vira balde silencioso' do
      get '/api/v1/public/equipment_categories/materials-inexistente'
      expect(response.parsed_body['equipment']).to eq([])
    end
  end

  describe 'os baldes vizinhos não absorvem matéria-prima' do
    it ':gear e :tools continuam sem ela' do
      get '/api/v1/public/equipment_categories/adventuring-gear'
      expect(indices(response.parsed_body)).not_to include('mat-extrato-vegetal')

      get '/api/v1/public/equipment_categories/tools'
      expect(indices(response.parsed_body)).not_to include('mat-pecanha')
    end
  end
end

# Receita no payload do PRODUTO: a ficha de "como fabricar isto".
RSpec.describe 'Api::V1::Public::Equipment receita de fabricação', type: :request do
  let!(:extrato) do
    Item.create!(api_index: 'mat-extrato-vegetal', name: 'Extrato Vegetal',
                 kind: 'material', category: 'essence', value_gp: 0.5, props: { 'unit' => 'ml' })
  end
  let!(:acido) do
    Item.create!(api_index: 'mat-componente-acido', name: 'Componente Ácido',
                 kind: 'material', category: 'essence', value_gp: 5)
  end
  let!(:pocao) do
    Item.create!(api_index: 'alq-acido', name: 'Ácido', kind: 'consumable', category: 'alchemical')
  end
  let!(:receita) do
    r = CraftingRecipe.create!(result_item: pocao, craft: 'alchemy', dc: 10, days: 2.8,
                               craft_cost_gp: 35, processes: %w[Ativador Água])
    r.ingredients.create!(ingredient_item: extrato, quantity: 25, unit: 'ml', position: 0)
    r.ingredients.create!(ingredient_item: acido, quantity: 5, unit: 'ml',
                          alternative_group: 1, position: 1)
    r.ingredients.create!(raw_text: 'Componente Extra', is_choice: true, quantity: 1,
                          unit: 'un', position: 2)
    r
  end

  def payload_do_acido
    get '/api/v1/public/equipment_categories/consumables'
    response.parsed_body['equipment'].find { |e| e['index'] == 'alq-acido' }
  end

  it 'entrega ofício, CD, dias, custo e processos' do
    c = payload_do_acido['crafting']
    expect(c).to include('craft' => 'alchemy', 'dc' => 10, 'days' => 2.8, 'cost' => 35.0)
    expect(c['processes']).to eq(%w[Ativador Água])
  end

  it '⚠️ o ingrediente carrega o INDEX do item — é o link, não o nome' do
    # Sem o index, o NPC ferreiro teria de casar por nome, e a base já provou
    # (na planilha) que nome é a parte que diverge.
    ing = payload_do_acido['crafting']['ingredients']
    extrato_json = ing.find { |i| i['name'] == 'Extrato Vegetal' }
    expect(extrato_json['item_index']).to eq('mat-extrato-vegetal')
    expect(extrato_json['quantity']).to eq(25.0)
    expect(extrato_json['unit']).to eq('ml')
  end

  it 'ingrediente sem item aparece mesmo assim, marcado como escolha' do
    extra = payload_do_acido['crafting']['ingredients'].find { |i| i['raw_text'].present? }
    expect(extra['name']).to eq('Componente Extra')
    expect(extra['is_choice']).to be(true)
    expect(extra).not_to have_key('item_index')
  end

  it 'a alternativa viaja agrupada' do
    ing = payload_do_acido['crafting']['ingredients'].find { |i| i['name'] == 'Componente Ácido' }
    expect(ing['alternative_group']).to eq(1)
  end

  it 'item SEM receita não ganha a chave — nem sempre há como fabricar' do
    avulso = Item.create!(api_index: 'alq-sem-receita', name: 'Sem Receita',
                          kind: 'consumable', category: 'alchemical')
    get '/api/v1/public/equipment_categories/consumables'
    json = response.parsed_body['equipment'].find { |e| e['index'] == avulso.api_index }
    expect(json).to be_present
    expect(json).not_to have_key('crafting')
  end
end

# Receita gravada JUNTO do item pelo editor do mestre.
RSpec.describe 'Api::V1::Admin::CatalogItems receita', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }
  let!(:extrato) do
    Item.create!(api_index: 'mat-extrato-vegetal', name: 'Extrato Vegetal',
                 kind: 'material', category: 'essence', value_gp: 0.5)
  end

  def criar(crafting)
    post '/api/v1/admin/catalog_items',
         params: { item: { api_index: 'alq-teste', kind: 'consumable', name: 'Poção Teste',
                           category: 'potion', props: {}, crafting: crafting } },
         headers: bearer_headers_for(dm), as: :json
  end

  let(:receita_base) do
    { craft: 'alchemy', dc: 14, days: 3, craft_cost_gp: 60, processes: %w[Calor],
      ingredients: [{ item_index: 'mat-extrato-vegetal', name: 'Extrato Vegetal',
                      quantity: 30, unit: 'ml' }] }
  end

  it 'grava item e receita numa gravação só' do
    expect { criar(receita_base) }.to change(CraftingRecipe, :count).by(1)
    expect(response).to have_http_status(:created)

    r = Item.find_by(api_index: 'alq-teste').crafting_recipe
    expect(r.dc).to eq(14)
    expect(r.processes).to eq(%w[Calor])
    expect(r.ingredients.first.ingredient_item).to eq(extrato)
  end

  it 'ingrediente sem material vira TEXTO LIVRE — nunca descartado' do
    criar(receita_base.merge(ingredients: [{ item_index: nil, name: 'Componente Extra',
                                             quantity: 1, unit: 'un', is_choice: true }]))
    ing = Item.find_by(api_index: 'alq-teste').crafting_recipe.ingredients.first
    expect(ing.raw_text).to eq('Componente Extra')
    expect(ing.is_choice).to be(true)
  end

  it 'editar REESCREVE a lista — ingrediente removido não fica pendurado' do
    criar(receita_base)
    patch '/api/v1/admin/catalog_items/alq-teste',
          params: { item: { name: 'Poção Teste', category: 'potion', props: {},
                            crafting: receita_base.merge(
                              ingredients: [{ item_index: nil, name: 'Outro', quantity: 2, unit: 'g' }],
                            ) } },
          headers: bearer_headers_for(dm), as: :json

    ings = Item.find_by(api_index: 'alq-teste').crafting_recipe.ingredients
    expect(ings.map(&:display_name)).to eq(['Outro'])
  end

  it '⚠️ OMITIR `crafting` preserva a receita — editor de arma não destrói nada' do
    criar(receita_base)
    patch '/api/v1/admin/catalog_items/alq-teste',
          params: { item: { name: 'Renomeada', category: 'potion', props: {} } },
          headers: bearer_headers_for(dm), as: :json

    expect(Item.find_by(api_index: 'alq-teste').crafting_recipe).to be_present
  end

  it '`crafting: null` APAGA a receita' do
    criar(receita_base)
    expect {
      patch '/api/v1/admin/catalog_items/alq-teste',
            params: { item: { name: 'Poção Teste', category: 'potion', props: {}, crafting: nil } },
            headers: bearer_headers_for(dm), as: :json
    }.to change(CraftingRecipe, :count).by(-1)
  end
end
