require 'rails_helper'

RSpec.describe "Api::V1::Public::Equipment", type: :request do
  describe "GET /api/v1/public/weapon_properties/:id" do
    it "returns locally-resolved finesse property with known weapons" do
      get "/api/v1/public/weapon_properties/finesse"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['index']).to eq('finesse')
      names = Array(json['weapons']).map { |w| w['index'] }
      expect(names).to include('rapier')
    end
  end

  describe "GET /api/v1/public/equipment/:id" do
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
    it "lists simple weapons from local catalog" do
      get "/api/v1/public/equipment_categories/simple-weapons"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      idxs = Array(json['equipment']).map { |e| e['index'] }
      expect(idxs).to include('dagger')
    end
  end
end

