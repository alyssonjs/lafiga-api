require 'rails_helper'

# FASE 1 do editor de raças — o mestre grava a MECÂNICA pela API.
#
# ⚠️ O portão desta fase: uma raça criada pelo editor tem de servir para
# provisionar personagem. Antes do overlay, `RaceRules.apply` levantava
# `ArgumentError: race not found` para qualquer raça que só existisse no banco.
RSpec.describe 'Api::V1::Admin::Races — rules_json', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  after { RaceRules.reload! }

  def cria(payload)
    post '/api/v1/admin/races', params: { race: payload }.to_json, headers: headers
  end

  let(:regras_validas) do
    {
      'size' => 'Médio',
      'speed' => '9m',
      'darkvision' => 18,
      'ability' => { 'type' => 'fixed', 'increases' => [{ 'ability' => 'FOR', 'amount' => 2 }] },
      'languages' => { 'always' => ['Comum'], 'choiceCount' => 1 },
      'traits' => [{ 'key' => 'garra_de_pedra' }],
      'custom_traits' => {
        'garra_de_pedra' => {
          'name' => 'Garra de Pedra',
          'description' => 'Garras naturais que cortam rocha.',
          'grants' => { 'natural_weapon' => { 'name' => 'Garras', 'dice' => '1d6', 'damage_type' => 'cortante', 'ability' => 'STR' } }
        }
      }
    }
  end

  describe 'criar raça com mecânica' do
    it 'grava e devolve o `rules_json`', :aggregate_failures do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })

      expect(response).to have_http_status(:created)
      r = Race.find_by(api_index: 'golem-argila')
      expect(r.rules_json['speed']).to eq('9m')
      expect(r.rules_json.dig('ability', 'increases', 0, 'ability')).to eq('FOR')
    end

    it '⚠️ PORTÃO: `RaceRules.apply` responde para a raça nova', :aggregate_failures do
      # Era exatamente isto que levantava ArgumentError antes do overlay.
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      RaceRules.reload!

      resultado = nil
      expect {
        resultado = RaceRules.apply(race_id: 'golem-argila', subrace_id: nil, choices: {})
      }.not_to raise_error
      expect(resultado[:speed]).to eq('9m')
    end

    it '⚠️ o traço PRÓPRIO entra no catálogo e o ref RESOLVE', :aggregate_failures do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      RaceRules.reload!

      # A definição sobe PREFIXADA pelo dono — a chave é escolhida dentro de
      # uma raça e o catálogo é global (ver `race_rules_overlay_spec`).
      definicao = RaceRules.trait_definitions[:'golem-argila__garra_de_pedra']
      expect(definicao).to be_present
      expect(definicao.dig(:grants, :natural_weapon, :dice)).to eq('1d6')

      # ⚠️ E o ref DENTRO da raça aponta para essa chave. Se só metade fosse
      # reescrita, o traço existiria no catálogo e a ficha não o veria.
      aplicada = RaceRules.apply(race_id: 'golem-argila', subrace_id: nil, choices: {})
      chaves = Array(aplicada[:traits]).map { |t| t[:key] }
      expect(chaves).to eq(['golem-argila__garra_de_pedra'])
      expect(RaceRules.trait_definitions[chaves.first.to_sym]).to be_present
    end

    it 'a leitura devolve o `rules_json` — senão o editor abre vazio' do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      r = Race.find_by(api_index: 'golem-argila')

      get "/api/v1/admin/races/#{r.id}", headers: headers
      expect(corpo.dig('race', 'rules_json', 'speed')).to eq('9m')
    end
  end

  describe '⚠️ o que erraria em silêncio é RECUSADO' do
    it 'chave desconhecida', :aggregate_failures do
      cria({ name: 'X', api_index: 'x1', rules_json: { 'velocidade' => '9m' } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('velocidade')
    end

    it 'canal de grant inventado' do
      # Gravaria e seria IGNORADO: o mestre configurava e não valia, sem nada
      # na tela a dizer porquê.
      cria({ name: 'X', api_index: 'x2', rules_json: {
        'custom_traits' => { 'meu' => { 'name' => 'Meu', 'grants' => { 'superpoder' => {} } } }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('superpoder')
    end

    it 'atributo que não existe' do
      cria({ name: 'X', api_index: 'x3', rules_json: {
        'ability' => { 'type' => 'fixed', 'increases' => [{ 'ability' => 'SORTE', 'amount' => 2 }] }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('SORTE')
    end

    it 'traço sem nome' do
      cria({ name: 'X', api_index: 'x4', rules_json: {
        'custom_traits' => { 'sem_nome' => { 'description' => 'sem nome' } }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '⚠️ nada é gravado quando há erro — não fica meio configurada' do
      cria({ name: 'X', api_index: 'x5', rules_json: { 'speed' => '9m', 'inventado' => 1 } })
      expect(Race.find_by(api_index: 'x5')).to be_nil
    end
  end

  describe 'editar' do
    let!(:raca) { Race.create!(name: 'Anão Teste', api_index: 'anao-teste', rules_json: { 'speed' => '7.5m' }) }

    it 'patch parcial: pedido SEM `rules_json` não mexe nas regras' do
      # O toggle de `playable` continua a funcionar sem apagar a mecânica.
      patch "/api/v1/admin/races/#{raca.id}", params: { race: { playable: false } }.to_json, headers: headers
      expect(raca.reload.rules_json['speed']).to eq('7.5m')
    end

    it '`{}` SOLTA as regras — a raça volta a valer o YAML' do
      patch "/api/v1/admin/races/#{raca.id}", params: { race: { rules_json: {} } }.to_json, headers: headers
      expect(raca.reload.rules_json).to eq({})
    end
  end

  describe 'autorização' do
    it 'jogador não grava regra de raça' do
      player = create(:user, role: Role.find_or_create_by!(name: 'Player'))
      post '/api/v1/admin/races',
           params: { race: { name: 'X', api_index: 'x9', rules_json: { 'speed' => '9m' } } }.to_json,
           headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end
end
