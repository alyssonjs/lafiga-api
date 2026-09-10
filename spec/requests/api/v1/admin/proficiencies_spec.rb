# frozen_string_literal: true

require 'rails_helper'

# Gestão do catálogo de proficiências — a tela que faltava.
#
# ⚠️ O que este spec prende, acima de tudo: proficiência é referenciada por
# STRING na ficha, não por chave estrangeira. O banco NÃO impede apagar uma
# linha em uso — ela some e as fichas que a citavam ficam órfãs em silêncio.
# Por decisão de produto (10/09/2026) o mestre pode apagar mesmo assim, mas a
# resposta tem de dizer o preço.
RSpec.describe 'Api::V1::Admin::Proficiencies', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM')     || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:mestre)      { create(:user, role: dm_role) }
  let(:jogador)     { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(mestre).merge('Content-Type' => 'application/json') }

  let!(:lira) do
    p = Proficiency.create!(api_index: 'tool-lira', name: 'Lira', category: 'tool', sub_category: 'instrument')
    p.add_alias!('Lira')
    p
  end

  def corpo = JSON.parse(response.body)

  describe 'o gate é de MESTRE' do
    it 'jogador não entra' do
      get '/api/v1/admin/proficiencies', headers: bearer_headers_for(jogador)
      expect(response).to have_http_status(:forbidden)
    end

    it 'sem credencial, 401' do
      get '/api/v1/admin/proficiencies'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'mestre entra' do
      get '/api/v1/admin/proficiencies', headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET index' do
    it 'lista com apelidos e contagem de uso' do
      get '/api/v1/admin/proficiencies', headers: headers
      linha = corpo['proficiencies'].find { |p| p['api_index'] == 'tool-lira' }
      expect(linha['aliases']).to eq(['lira'])
      expect(linha['usage_count']).to eq(0)
      expect(corpo['meta']).to include('total', 'categories', 'in_use')
    end

    it 'filtra por categoria' do
      Proficiency.create!(api_index: 'lang-comum', name: 'Comum', category: 'language', sub_category: 'standard')
      get '/api/v1/admin/proficiencies', params: { category: 'language' }, headers: headers
      expect(corpo['proficiencies'].map { |p| p['category'] }.uniq).to eq(['language'])
    end
  end

  describe 'POST create' do
    it 'deriva o api_index do nome e da categoria' do
      post '/api/v1/admin/proficiencies', headers: headers, params: {
        proficiency: { name: 'Ferramentas de Bruxaria', category: 'tool', sub_category: 'kit' },
      }.to_json
      expect(response).to have_http_status(:created)
      expect(corpo['proficiency']['api_index']).to eq('tool-ferramentas-de-bruxaria')
    end

    it 'recusa categoria inválida' do
      post '/api/v1/admin/proficiencies', headers: headers, params: {
        proficiency: { name: 'X', category: 'inventada' },
      }.to_json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '⚠️ o PRÓPRIO NOME vira apelido — senão a linha nasce invisível' do
      # A resolução é toda por apelido: sem o do próprio nome,
      # `Proficiency.resolve('Cravo')` devolveria nil para uma "Cravo" que
      # existe no catálogo, e nenhum leitor a acharia.
      post '/api/v1/admin/proficiencies', headers: headers, params: {
        proficiency: { name: 'Cravo', category: 'tool', sub_category: 'instrument' },
      }.to_json
      expect(Proficiency.resolve('Cravo')&.name).to eq('Cravo')
    end

    it 'aceita apelidos junto' do
      post '/api/v1/admin/proficiencies', headers: headers, params: {
        proficiency: { name: 'Cravo', category: 'tool', sub_category: 'instrument',
                       aliases: ['Clavicórdio'] },
      }.to_json
      expect(corpo['proficiency']['aliases']).to include('cravo', 'clavicordio')
    end
  end

  describe 'PATCH update' do
    it 'acrescenta apelido sem perder os que já havia' do
      patch "/api/v1/admin/proficiencies/#{lira.id}", headers: headers, params: {
        proficiency: { aliases: ['Lyra'] },
      }.to_json
      expect(corpo['proficiency']['aliases']).to match_array(%w[lira lyra])
    end

    it '⚠️ apelido que já é de OUTRA linha não muda de dono em silêncio' do
      outra = Proficiency.create!(api_index: 'tool-harpa', name: 'Harpa', category: 'tool', sub_category: 'instrument')
      patch "/api/v1/admin/proficiencies/#{outra.id}", headers: headers, params: {
        proficiency: { aliases: ['Lira'] },
      }.to_json
      expect(corpo['proficiency']['warnings'].join).to match(/já aponta para/)
      expect(Proficiency.resolve('Lira')).to eq(lira)
    end

    it 'aceita o api_index como identificador, além do id' do
      patch '/api/v1/admin/proficiencies/tool-lira', headers: headers, params: {
        proficiency: { name: 'Lira élfica' },
      }.to_json
      expect(response).to have_http_status(:ok)
      expect(lira.reload.name).to eq('Lira élfica')
    end

    it '⚠️ renomear NÃO órfã a ficha antiga — o apelido velho fica' do
      # O vínculo é por string. Se o nome antigo deixasse de resolver, toda
      # ficha que o citava ficava órfã em silêncio.
      patch "/api/v1/admin/proficiencies/#{lira.id}", headers: headers, params: {
        proficiency: { name: 'Lira élfica' },
      }.to_json
      expect(Proficiency.resolve('Lira')&.id).to eq(lira.id)
      expect(Proficiency.resolve('Lira élfica')&.id).to eq(lira.id)
    end
  end

  describe '⚠️ DELETE — AVISA, não bloqueia' do
    it 'sem uso, apaga limpo' do
      delete "/api/v1/admin/proficiencies/#{lira.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(corpo['orphaned_sheets']).to eq(0)
      expect(corpo).not_to have_key('warning')
      expect(Proficiency.find_by(id: lira.id)).to be_nil
    end

    it 'EM USO, apaga mesmo assim — e diz quantas fichas ficaram órfãs' do
      # É a diferença deliberada em relação ao `admin/feats#destroy`, que recusa.
      # O mestre decide; o servidor tem de dizer o preço em vez de só sumir com
      # a linha.
      allow(Proficiencies::UsageCounter).to receive(:by_proficiency_id).and_return(lira.id => 3)

      delete "/api/v1/admin/proficiencies/#{lira.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(corpo['orphaned_sheets']).to eq(3)
      expect(corpo['warning']).to eq('sheets_orphaned')
      expect(corpo['deleted']['name']).to eq('Lira')
      expect(Proficiency.find_by(id: lira.id)).to be_nil
    end

    it 'apagar leva os apelidos junto' do
      delete "/api/v1/admin/proficiencies/#{lira.id}", headers: headers
      expect(ProficiencyAlias.where(proficiency_id: lira.id)).to be_empty
    end
  end
end
