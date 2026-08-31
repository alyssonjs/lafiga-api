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
          props: {
            'properties' => %w[versatile],
            'type' => 'melee',
            'hands' => 1,
            'versatile' => true,
            'damage_die' => '1d8',
            'versatile_die' => '1d10',
            'chibi_weapon_svg_id' => 'sword-long',
            'card_icon_id' => 'dagger'
          }
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
      expect(json['chibi_weapon_svg_id']).to eq('sword-long')
      expect(json['card_icon_id']).to eq('dagger')
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

  describe "GET /api/v1/public/equipment_catalog_snapshot" do
    before do
      Item.find_or_initialize_by(api_index: 'spec-snapshot-pack').tap do |it|
        it.assign_attributes(
          name: 'Pacote Spec',
          kind: :gear,
          category: 'pack',
          props: { 'contents' => ['Tocha'] }
        )
        it.save!
      end
    end

    it "returns by_category including packs (gear+category pack, not kind pack)" do
      get "/api/v1/public/equipment_catalog_snapshot"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      packs = Array(json.dig('by_category', 'packs'))
      idxs = packs.map { |e| e['index'] }
      expect(idxs).to include('spec-snapshot-pack')
      expect(packs.first.dig('equipment_category', 'index')).to eq('equipment-packs')
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

    it "lists packs under equipment_list/packs (kind gear + category pack)" do
      Item.find_or_initialize_by(api_index: 'spec-equipment-list-pack').tap do |it|
        it.assign_attributes(name: 'Pacote List Spec', kind: :gear, category: 'pack', props: {})
        it.save!
      end
      get "/api/v1/public/equipment_list/packs"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      idxs = Array(json['equipment']).map { |e| e['index'] }
      expect(idxs).to include('spec-equipment-list-pack')
    end
  end
  # FOCO ARCANO no catálogo (31/08). Sem esta linha no serializer, o mestre
  # marca a caixa no editor, o item vira foco na FICHA, e a listagem do
  # compêndio não mostra nada — ele fica sem saber o que já marcou.
  describe "flag de foco arcano na listagem" do
    before do
      Item.find_or_initialize_by(api_index: 'spec-orbe-foco').tap do |it|
        it.assign_attributes(name: 'Orbe Rúnico (spec)', kind: :gear,
                             category: 'equipment', props: { 'arcane_focus' => true })
        it.save!
      end
      Item.find_or_initialize_by(api_index: 'spec-corda-comum').tap do |it|
        it.assign_attributes(name: 'Corda Comum (spec)', kind: :gear, category: 'equipment')
        it.save!
      end
    end

    it "emite `arcane_focus: true` no item marcado" do
      get "/api/v1/public/equipment/spec-orbe-foco"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['arcane_focus']).to be true
    end

    it "não emite nada no item comum — ausência é a resposta \"não é foco\"" do
      get "/api/v1/public/equipment/spec-corda-comum"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['arcane_focus']).to be_nil
    end
  end

end
