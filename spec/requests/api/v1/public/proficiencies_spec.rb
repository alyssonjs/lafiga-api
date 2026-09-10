# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# O endpoint existe para o FRONT consumir em vez de redeclarar. Eram TRÊS listas
# rivais de idioma, e o próprio `languageCatalog.ts` registrava que nunca tinham
# sido reconciliadas.
RSpec.describe 'GET /api/v1/public/proficiencies' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.destroy_all
    Rake::Task['dnd:seed_proficiency_languages'].reenable
    Rake::Task['dnd:seed_proficiency_languages'].invoke
  end

  # ⚠️ Método, não `let`: `let` memoiza, e um exemplo que faz DOIS `get` lia o
  # corpo do primeiro nos dois. O filtro por categoria "passava" mostrando os
  # idiomas.
  def corpo = JSON.parse(response.body)

  it 'devolve o catálogo com contagem por categoria' do
    get '/api/v1/public/proficiencies'
    expect(response).to have_http_status(:ok)
    expect(corpo['meta']['total']).to eq(27)
    expect(corpo['meta']['categories']).to eq('language' => 27)
  end

  it 'filtra por categoria' do
    get '/api/v1/public/proficiencies', params: { category: 'language' }
    expect(corpo['proficiencies'].map { |p| p['category'] }.uniq).to eq(['language'])

    get '/api/v1/public/proficiencies', params: { category: 'tool' }
    expect(corpo['proficiencies']).to eq([])
  end

  it '⚠️ as grafias aceitas viajam junto' do
    # Sem os apelidos o consumidor teria de reimplementar a resolução — que é
    # exatamente como as quatro grafias de "Veículos terrestres" nasceram.
    get '/api/v1/public/proficiencies', params: { category: 'language' }
    giria = corpo['proficiencies'].find { |p| p['api_index'] == 'lang-giria-de-ladrao' }
    expect(giria['aliases']).to include('thieves cant', 'giria de ladrao')
  end

  it 'a estrutura que o front precisa para agrupar e para os dialetos' do
    get '/api/v1/public/proficiencies', params: { category: 'language' }
    subs = corpo['proficiencies'].group_by { |p| p['sub_category'] }.transform_values(&:size)
    expect(subs).to include('standard' => 8, 'primordial_dialect' => 4, 'class_secret' => 2, 'racial' => 2)

    primordial = corpo['proficiencies'].find { |p| p['name'] == 'Primordial' }
    expect(primordial['metadata']['dialects']).to match_array(%w[lang-aquan lang-auran lang-ignan lang-terran])
  end

  it 'não publicado fica de fora' do
    Proficiency.find_by(api_index: 'lang-esfinge').update!(published: false)
    get '/api/v1/public/proficiencies', params: { category: 'language' }
    expect(corpo['proficiencies'].map { |p| p['api_index'] }).not_to include('lang-esfinge')
  end
end
