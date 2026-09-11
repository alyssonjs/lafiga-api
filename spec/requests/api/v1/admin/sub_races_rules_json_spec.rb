require 'rails_helper'

# FASE 2 do editor de raças — a SUB-RAÇA ganha mecânica pela mesma página.
#
# ⚠️ É na sub-raça que mora quase toda a mecânica que distingue um Anão da
# Colina de um das Montanhas: `ability` em 13 das 27, `traits` em 25.
RSpec.describe 'Api::V1::Admin::SubRaces — rules_json', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  let!(:anao) { Race.find_by(api_index: 'dwarf') || Race.create!(name: 'Anão', api_index: 'dwarf') }

  after { RaceRules.reload! }

  def cria(payload)
    post '/api/v1/admin/sub_races', params: { sub_race: payload }.to_json, headers: headers
  end

  describe 'criar sub-raça com mecânica' do
    let(:regras) do
      {
        'ability' => { 'type' => 'fixed', 'increases' => [{ 'ability' => 'FOR', 'amount' => 2 }] },
        # ⚠️ Declarar `custom_traits` não basta: sem o REF na lista, a
        # definição existe no catálogo e a ficha nunca a vê.
        'traits' => [{ 'key' => 'darkvision', 'range' => 90 }, { 'key' => 'casca_de_ferro' }],
        'custom_traits' => { 'casca_de_ferro' => { 'name' => 'Casca de Ferro' } }
      }
    end

    it '⚠️ PORTÃO: `apply` responde para a sub-raça nova e traz a regra dela', :aggregate_failures do
      cria({ name: 'Anão de Ferro', api_index: 'iron', race_id: anao.id, rules_json: regras })
      expect(response).to have_http_status(:created)
      RaceRules.reload!

      out = nil
      expect { out = RaceRules.apply(race_id: 'dwarf', subrace_id: 'iron', choices: {}) }.not_to raise_error
      expect(out[:ability]).to be_present
      chaves = Array(out[:traits]).map { |t| t[:key] }
      expect(chaves).to include('dwarf__iron__casca_de_ferro')
    end

    it 'a resposta do create vem no envelope `sub_race`', :aggregate_failures do
      # 🐞 antes devolvia o objeto CRU: o cliente lia `data.sub_race` e recebia
      # `undefined` — o front nunca sabia o id da sub-raça que acabara de criar.
      cria({ name: 'Anão de Ferro', api_index: 'iron', race_id: anao.id, rules_json: regras })
      expect(corpo['sub_race']).to be_present
      expect(corpo.dig('sub_race', 'rules_json', 'ability', 'type')).to eq('fixed')
    end

    it '⚠️ os traços da RAÇA continuam a valer — sub-raça SOMA, não substitui' do
      antes = Array(RaceRules.apply(race_id: 'dwarf')[:traits]).map { |t| t[:key] }
      cria({ name: 'Anão de Ferro', api_index: 'iron', race_id: anao.id, rules_json: regras })
      RaceRules.reload!

      depois = Array(RaceRules.apply(race_id: 'dwarf', subrace_id: 'iron')[:traits]).map { |t| t[:key] }
      expect(depois).to include(*antes)
    end
  end

  describe '⚠️ `rules_base` da sub-raça' do
    let!(:colina) do
      SubRace.find_by(race_id: anao.id, api_index: 'hill') ||
        SubRace.create!(name: 'Anão da Colina', api_index: 'hill', race_id: anao.id)
    end

    it 'vem do nó da SUB-raça, não do da raça', :aggregate_failures do
      get "/api/v1/admin/races/#{anao.id}", headers: headers

      linha = corpo['sub_races'].find { |sr| sr['api_index'] == 'hill' }
      expect(linha).to be_present
      base = linha['rules_base']
      # O nó do YAML da sub-raça tem `ability` própria; o da raça tem `speed`.
      expect(base['ability']).to be_present
      expect(base).not_to have_key('speed')
    end

    it 'NÃO traz o overlay — é a base' do
      colina.update!(rules_json: { 'speed' => 40 })
      RaceRules.reload!

      get "/api/v1/admin/races/#{anao.id}", headers: headers
      linha = corpo['sub_races'].find { |sr| sr['api_index'] == 'hill' }
      expect(linha.dig('rules_base', 'speed')).to be_nil
      expect(linha.dig('rules_json', 'speed')).to eq(40)
    ensure
      colina.update_columns(rules_json: {})
      RaceRules.reload!
    end
  end

  describe '⚠️ apagar sub-raça em uso' do
    let!(:colina) do
      SubRace.find_by(race_id: anao.id, api_index: 'hill') ||
        SubRace.create!(name: 'Anão da Colina', api_index: 'hill', race_id: anao.id)
    end

    it 'é RECUSADO com mensagem legível — há FK de `sheets`', :aggregate_failures do
      personagem = create(:character)
      Sheet.create!(character: personagem, race_id: anao.id, sub_race_id: colina.id)

      delete "/api/v1/admin/sub_races/#{colina.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join(' ')).to include('em uso por 1 ficha')
      expect(SubRace.exists?(colina.id)).to be(true)
    end

    it 'passa quando ninguém depende dela' do
      solta = SubRace.create!(name: 'Descartável', api_index: 'descartavel', race_id: anao.id)
      delete "/api/v1/admin/sub_races/#{solta.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(SubRace.exists?(solta.id)).to be(false)
    end
  end
end
