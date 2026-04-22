require 'rails_helper'

# Kit 1.PoC: endpoint público que serve catálogos canônicos de escolhas de
# classe (api/config/class_choices/*.yml) para o front consumir, eliminando
# a duplicação entre dados estáticos no front e validação no backend.
RSpec.describe "Api::V1::Public::ClassChoices", type: :request do
  describe "GET /api/v1/public/class_choices/:id" do
    context "metamagic (PoC)" do
      it "returns 200 with the full canonical metamagic catalog" do
        get "/api/v1/public/class_choices/metamagic"
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['catalog']).to eq('metamagic')
        expect(json['entries']).to be_an(Array)
        expect(json['entries'].size).to eq(8)
      end

      it "each entry exposes slug, name_pt, name_en, description, mechanical_summary, cost" do
        get "/api/v1/public/class_choices/metamagic"
        json = JSON.parse(response.body)
        first = json['entries'].first
        %w[slug name_pt name_en description mechanical_summary cost classes].each do |key|
          expect(first).to have_key(key), "expected entry to expose #{key}"
        end
      end

      it "includes aliases for backward-compat mapping (legacy backend names)" do
        get "/api/v1/public/class_choices/metamagic"
        json = JSON.parse(response.body)
        careful = json['entries'].find { |e| e['slug'] == 'mm-careful' }
        expect(careful).to be_present
        expect(careful['aliases']).to include('Suturar Magia')
      end

      it "all PoC slugs are present in canonical kebab-case" do
        get "/api/v1/public/class_choices/metamagic"
        json = JSON.parse(response.body)
        slugs = json['entries'].map { |e| e['slug'] }
        expect(slugs).to match_array(%w[
          mm-careful mm-distant mm-empowered mm-extended
          mm-heightened mm-quickened mm-subtle mm-twinned
        ])
      end
    end

    context "catálogo inexistente" do
      it "returns 404 with descriptive error" do
        get "/api/v1/public/class_choices/nonexistent_catalog"
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to match(/não encontrado/i)
      end
    end

    context "id mal-formado" do
      it "constraint da route rejeita uppercase/hyphen → cai no application#not_found global" do
        # A constraint da route /[a-z_][a-z0-9_]*/ não casa com 'INVALID-name'
        # → request cai na rota catch-all global '/*a' → application#not_found.
        # Notamos que essa rota global do projeto retorna 200 com body
        # { "error": "not_found" } (legado, fora do escopo do Kit 1).
        # Asserimos via body para que o catálogo NUNCA seja servido com nomes inválidos.
        get "/api/v1/public/class_choices/INVALID-name"
        json = JSON.parse(response.body) rescue {}
        expect(json['catalog']).to be_nil
        expect(json['entries']).to be_nil
      end
    end
  end
end
