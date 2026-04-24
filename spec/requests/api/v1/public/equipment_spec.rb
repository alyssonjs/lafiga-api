require 'rails_helper'

RSpec.describe "Api::V1::Public::Equipment", type: :request do
  describe "GET /api/v1/public/weapon_properties/:id" do
    before do
      # Controller resolves from DB; ensure at least one finesse weapon exists.
      Item.find_or_initialize_by(api_index: 'spec-rapier-finesse').tap do |it|
        it.assign_attributes(
          name: 'Rapieira (spec)',
          kind: :weapon,
          category: 'martial',
          props: { 'properties' => %w[finesse], 'type' => 'melee', 'hands' => 1 }
        )
        it.save!
      end
    end

    it "returns locally-resolved finesse property with known weapons" do
      get "/api/v1/public/weapon_properties/finesse"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['index']).to eq('finesse')
      names = Array(json['weapons']).map { |w| w['index'] }
      expect(names).to include('spec-rapier-finesse')
    end
  end

  describe "GET /api/v1/public/equipment/:id" do
    before do
      # O controller resolve via `Item.find_by(api_index: 'longsword')`.
      # Sem o seed completo do catalogo (db:seed nao roda no test env), o
      # endpoint devolvia 404. Inserimos o item necessario aqui.
      Item.find_or_initialize_by(api_index: 'longsword').tap do |it|
        it.assign_attributes(
          name: 'Espada Longa',
          kind: :weapon,
          category: 'martial',
          props: { 'properties' => %w[versatile], 'type' => 'melee', 'hands' => 1, 'versatile' => true, 'damage_die' => '1d8', 'versatile_die' => '1d10' }
        )
        it.save!
      end
    end

    it "returns local equipment for longsword with versatile" do
      get "/api/v1/public/equipment/longsword"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['index']).to eq('longsword')
      props = Array(json['properties']).map { |p| p['index'] }
      expect(props).to include('versatile')
    end
  end

  describe "GET /api/v1/public/equipment_categories/:id" do
    before do
      # Mesmo motivo do describe anterior: precisamos de pelo menos uma arma
      # simples no DB para o endpoint listar. Catalogo PT-BR usa slug 'adaga'.
      Item.find_or_initialize_by(api_index: 'adaga').tap do |it|
        it.assign_attributes(
          name: 'Adaga',
          kind: :weapon,
          category: 'simple',
          props: { 'properties' => %w[finesse light thrown], 'type' => 'melee', 'hands' => 1, 'damage_die' => '1d4' }
        )
        it.save!
      end
    end

    it "lists simple weapons from local catalog" do
      get "/api/v1/public/equipment_categories/simple-weapons"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      idxs = Array(json['equipment']).map { |e| e['index'] }
      # Catálogo local usa slugs em PT-BR
      expect(idxs).to include('adaga')
    end
  end

  describe "GET /api/v1/public/equipment_list/:category" do
    before do
      Item.find_or_initialize_by(api_index: 'arco-longo-spec').tap do |it|
        it.assign_attributes(
          name: 'Arco Longo',
          kind: :weapon,
          category: 'martial',
          props: { 'properties' => %w[ammunition heavy two-handed], 'type' => 'ranged', 'hands' => 2, 'damage_die' => '1d8' }
        )
        it.save!
      end
    end

    it "returns non-empty equipment payloads for paginated list (Item records, not index strings)" do
      get "/api/v1/public/equipment_list/martial-weapons", params: { page: 1 }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      rows = Array(json['equipment'])
      expect(rows).not_to be_empty
      idxs = rows.map { |e| e['index'] }
      expect(idxs).to include('arco-longo-spec')
      expect(rows.first['name']).to be_present
    end
  end
end

