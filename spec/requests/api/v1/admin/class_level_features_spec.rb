# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin class/subclass level features', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user).merge('Content-Type' => 'application/json') }
  let(:player_headers) { bearer_headers_for(player).merge('Content-Type' => 'application/json') }

  describe 'class level features' do
    let!(:klass) { create(:klass, name: 'Patrulheiro Spec', api_index: 'spec-ranger-editor') }

    it 'allows a DM to create a class feature at a level' do
      expect do
        post "/api/v1/admin/klasses/#{klass.api_index}/level_features",
             params: {
               feature: {
                 level: 3,
                 name: 'Tatica de Campo',
                 description: 'Texto criado pelo mestre.',
               },
             }.to_json,
             headers: dm_headers
      end.to change(Feature, :count).by(1)

      expect(response).to have_http_status(:created), -> { response.body }
      level = klass.class_levels.find_by!(level: 3)
      feature = level.features.first
      expect(feature.name).to eq('Tatica de Campo')
      expect(feature.description).to eq('Texto criado pelo mestre.')
      expect(feature.category).to eq('class_feature')
      expect(feature.dm_customized).to eq(true)
    end

    it 'allows a DM to edit an existing class feature description and public reads use the override' do
      level = ClassLevel.create!(klass: klass, level: 1, prof_bonus: 2, ability_score_bonuses: 0)
      allow(DndTranslations).to receive(:translated_feature_description).and_return('Texto vindo do YAML')
      feature = Feature.create!(
        api_index: 'spec-feature-with-yaml-translation',
        name: 'Inimigo Favorecido',
        description: 'texto antigo',
      )
      level.features << feature

      patch "/api/v1/admin/klasses/#{klass.api_index}/level_features/#{feature.id}",
            params: {
              feature: {
                level: 1,
                name: 'Inimigo Favorecido',
                description: 'Texto customizado pelo DM.',
              },
            }.to_json,
            headers: dm_headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(feature.reload.description).to eq('Texto customizado pelo DM.')
      expect(feature.dm_customized).to eq(true)

      get "/api/v1/public/klasses/#{klass.api_index}/levels"
      public_feature = response.parsed_body['class_levels'].first['features'].first
      expect(public_feature['description']).to eq('Texto customizado pelo DM.')
    end

    it 'allows a DM to remove a class feature from a level without deleting canonical features' do
      level = ClassLevel.create!(klass: klass, level: 2, prof_bonus: 2, ability_score_bonuses: 0)
      other_level = ClassLevel.create!(klass: klass, level: 3, prof_bonus: 2, ability_score_bonuses: 0)
      feature = Feature.create!(
        api_index: 'spec-canonical-feature-remove',
        name: 'Feature Canonica',
        description: 'Texto canonico.',
        dm_customized: false,
      )
      level.features << feature
      other_level.features << feature

      delete "/api/v1/admin/klasses/#{klass.api_index}/level_features/#{feature.id}",
             params: { feature: { level: 2 } }.to_json,
             headers: dm_headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(level.reload.features).not_to include(feature)
      expect(other_level.reload.features).to include(feature)
      expect(Feature.exists?(feature.id)).to eq(true)

      get "/api/v1/public/klasses/#{klass.api_index}/levels"
      level_2 = response.parsed_body['class_levels'].find { |row| row['level'] == 2 }
      level_3 = response.parsed_body['class_levels'].find { |row| row['level'] == 3 }
      expect(level_2['features'].map { |row| row['id'] }).not_to include(feature.id)
      expect(level_3['features'].map { |row| row['id'] }).to include(feature.id)
    end

    it 'rejects plain players' do
      post "/api/v1/admin/klasses/#{klass.api_index}/level_features",
           params: { feature: { level: 2, name: 'Nao pode', description: 'x' } }.to_json,
           headers: player_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'subclass level features' do
    let!(:klass) { create(:klass, name: 'Guerreiro Spec', api_index: 'spec-fighter-editor') }
    let!(:sub_klass) { create(:sub_klass, klass: klass, name: 'Campeao Spec', api_index: 'spec-campeao-editor') }

    it 'allows a DM to create and then edit a subclass feature' do
      post "/api/v1/admin/sub_klasses/#{sub_klass.api_index}/level_features",
           params: {
             feature: {
               level: 3,
               name: 'Golpe Memoravel',
               description: 'Primeira versao.',
             },
           }.to_json,
           headers: dm_headers

      expect(response).to have_http_status(:created), -> { response.body }
      feature_id = response.parsed_body.dig('feature', 'id')
      feature = Feature.find(feature_id)
      expect(feature.category).to eq('subclass_feature')
      expect(sub_klass.sub_klass_levels.find_by!(level: 3).features).to include(feature)

      patch "/api/v1/admin/sub_klasses/#{sub_klass.api_index}/level_features/#{feature_id}",
            params: {
              feature: {
                level: 7,
                name: 'Golpe Memoravel',
                description: 'Segunda versao.',
              },
            }.to_json,
            headers: dm_headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(feature.reload.description).to eq('Segunda versao.')
      expect(sub_klass.sub_klass_levels.find_by!(level: 7).features).to include(feature)
      old_level_features = sub_klass.sub_klass_levels.find_by(level: 3)&.features&.to_a || []
      expect(old_level_features).not_to include(feature)
    end

    it 'allows a DM to remove a DM-created subclass feature from a level' do
      level = SubKlassLevel.create!(sub_klass: sub_klass, level: 3)
      feature = Feature.create!(
        api_index: 'spec-custom-subclass-feature-remove',
        name: 'Golpe Removivel',
        description: 'Sai do nivel.',
        category: :subclass_feature,
        dm_customized: true,
      )
      level.features << feature

      delete "/api/v1/admin/sub_klasses/#{sub_klass.api_index}/level_features/#{feature.id}",
             params: { feature: { level: 3 } }.to_json,
             headers: dm_headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(level.reload.features).not_to include(feature)
      expect(Feature.exists?(feature.id)).to eq(false)
    end
  end
end
