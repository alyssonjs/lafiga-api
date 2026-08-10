require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Spells', type: :request do
  let(:admin_role)  { Role.find_or_create_by!(name: 'Admin') }
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:dm)          { create(:user, role: dm_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }
  let(:dm_headers)  { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }

  let!(:spell) do
    Spell.create!(
      api_index: 'test-fireball',
      name: 'Bola De Fogo',
      level: 3,
      school: 'Evocation',
      range: '45 metros',
      components: 'V, S, M',
      material: 'uma pequena bola de morcego',
      ritual: false,
      duration: 'Instantanea',
      concentration: false,
      casting_time: '1 acao',
      desc: 'Uma explosao de fogo brilhante salta...',
      higher_level: 'Quando voce conjura essa magia usando um espaco de magia de 4 nivel ou superior...'
    )
  end

  describe 'GET /api/v1/admin/spells' do
    it 'rejects player with 403' do
      get '/api/v1/admin/spells', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows site-wide DM' do
      get '/api/v1/admin/spells', headers: dm_headers
      expect(response).to have_http_status(:ok)
    end

    it 'lists spells with filters' do
      get '/api/v1/admin/spells', params: { level: 3 }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['spells'].map { |s| s['api_index'] }).to include('test-fireball')
    end

    it 'includes klass_api_indexes per row' do
      get '/api/v1/admin/spells', headers: headers
      row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'test-fireball' }
      expect(row['klass_api_indexes']).to eq([])
    end
  end

  describe 'POST /api/v1/admin/spells' do
    it 'creates a spell and derives api_index when omitted' do
      payload = { spell: { name: 'Magia De Teste Nova', level: 1, school: 'Evocation', desc: 'corpo de descricao' } }
      expect {
        post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      }.to change(Spell, :count).by(1)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['spell']['api_index']).to eq('pt-magia-de-teste-nova')
    end

    it 'returns errors when name is missing' do
      payload = { spell: { level: 1, school: 'Evocation' } }
      post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/admin/spells/:id' do
    it 'updates by api_index' do
      payload = { spell: { desc: 'novo corpo' } }
      patch "/api/v1/admin/spells/#{spell.api_index}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(spell.reload.desc).to eq('novo corpo')
    end

    it 'updates by numeric id' do
      payload = { spell: { range: '60 metros' } }
      patch "/api/v1/admin/spells/#{spell.id}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(spell.reload.range).to eq('60 metros')
    end

    it 'rejects player with 403' do
      payload = { spell: { desc: 'tentativa de hijack' } }
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: payload.to_json,
            headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
      expect(spell.reload.desc).not_to eq('tentativa de hijack')
    end

    it 'allows DM to update' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { desc: 'editado pelo DM' } }.to_json,
            headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(spell.reload.desc).to eq('editado pelo DM')
    end

    it 'syncs klass_api_indexes (Klass SpellSource only)' do
      klass = Klass.find_by(api_index: 'ranger') || Klass.create!(name: 'Patrulheiro', api_index: 'ranger', hit_die: 10)
      payload = { spell: { desc: spell.desc, klass_api_indexes: ['ranger'] } }
      patch "/api/v1/admin/spells/#{spell.api_index}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(
        SpellSource.exists?(source_type: 'Klass', source_id: klass.id, spell_id: spell.id),
      ).to be true
    end

    it 'returns 422 for unknown klass slug in klass_api_indexes' do
      payload = { spell: { desc: spell.desc, klass_api_indexes: ['not-a-real-class-slug'] } }
      patch "/api/v1/admin/spells/#{spell.api_index}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['errors'].join).to include('Classes desconhecidas')
    end
  end

  describe 'combat_data (jsonb mecanico do editor)' do
    let(:combat_payload) do
      {
        resolution: 'saving_throw', save_ability: 'dex', save_success: 'half',
        damage: { dice: '8d6', types: ['fogo'], upcast: { '4' => '9d6', '5' => '10d6' } },
        area: { shape: 'sphere', size_ft: 20 },
        range_ft: 150, target_count: 1,
        duration: { text: '1 minuto', rounds: 10 },
        concentration: true,
        components: { v: true, s: true, m: true, consumed: false },
        inflicts_conditions: [{ key: 'paralyzed', polarity: 'debuff', save: 'wis', repeat_save: true }],
        removes_conditions: %w[charmed petrified]
      }
    end

    it 'persiste o combat_data completo (dano/upcast/area/TR/condicoes)' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { combat_data: combat_payload } }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      cd = spell.reload.combat_data
      expect(cd['resolution']).to eq('saving_throw')
      expect(cd['save_ability']).to eq('dex')
      expect(cd.dig('damage', 'dice')).to eq('8d6')
      expect(cd.dig('damage', 'types')).to eq(['fogo'])
      expect(cd.dig('damage', 'upcast')).to eq({ '4' => '9d6', '5' => '10d6' }) # chaves dinamicas preservadas
      expect(cd.dig('area', 'shape')).to eq('sphere')
      expect(cd['range_ft']).to eq(150)
      expect(cd['inflicts_conditions']).to eq(
        [{ 'key' => 'paralyzed', 'polarity' => 'debuff', 'save' => 'wis', 'repeat_save' => true }],
      )
      expect(cd['removes_conditions']).to eq(%w[charmed petrified])
    end

    it 'retorna o combat_data no corpo da resposta' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { combat_data: combat_payload } }.to_json, headers: headers
      expect(JSON.parse(response.body).dig('spell', 'combat_data', 'save_ability')).to eq('dex')
    end

    it 'strong params: descarta chaves nao permitidas dentro do combat_data' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: {
              spell: { combat_data: {
                resolution: 'saving_throw', evil_key: 'x',
                damage: { dice: '1d6', types: ['fogo'], sneaky: 'y' }
              } }
            }.to_json, headers: headers
      cd = spell.reload.combat_data
      expect(cd).not_to have_key('evil_key')
      expect(cd['damage']).not_to have_key('sneaky')
      expect(cd['resolution']).to eq('saving_throw')
    end

    it 'omitir combat_data NAO apaga o valor existente' do
      spell.update!(combat_data: { 'resolution' => 'spell_attack' })
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { desc: 'so muda a desc' } }.to_json, headers: headers
      expect(spell.reload.combat_data).to eq({ 'resolution' => 'spell_attack' })
    end

    it 'cria magia com combat_data' do
      post '/api/v1/admin/spells',
           params: { spell: {
             name: 'Nova Com Combate', level: 2, school: 'Evocation', desc: 'x',
             combat_data: { resolution: 'saving_throw', save_ability: 'con', damage: { dice: '3d8', types: ['trovao'] } }
           } }.to_json, headers: headers
      expect(response).to have_http_status(:created)
      created = Spell.find_by(name: 'Nova Com Combate')
      expect(created.combat_data.dig('damage', 'dice')).to eq('3d8')
      expect(created.combat_data['save_ability']).to eq('con')
    end
  end

  describe 'DELETE /api/v1/admin/spells/:id' do
    it 'deletes when no SpellSource exists' do
      expect {
        delete "/api/v1/admin/spells/#{spell.api_index}", headers: headers
      }.to change(Spell, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'deletes spell after removing SpellSource (klass links are catalog only)' do
      klass = Klass.first || Klass.create!(name: 'Mago', api_index: 'wizard')
      SpellSource.create!(source_type: 'Klass', source_id: klass.id, spell_id: spell.id, always_prepared: false)
      expect {
        delete "/api/v1/admin/spells/#{spell.api_index}", headers: headers
      }.to change(Spell, :count).by(-1)
        .and change(SpellSource.where(spell_id: spell.id), :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 422 when spell is still on character sheets' do
      create(:sheet_known_spell, spell: spell)
      expect {
        delete "/api/v1/admin/spells/#{spell.api_index}", headers: headers
      }.not_to change(Spell, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('spell_on_sheets')
      expect(body['sheet_known_spells'].to_i).to be >= 1
      expect(body['force_param']).to eq('force=true')
    end

    it 'deletes spell when force=true (known/prepared rows + metadata cleanup)' do
      sheet = create(:sheet, metadata: {
        'spell_selections' => {
          'cantrips' => [],
          'known' => [spell.id.to_s],
          'spellbook' => [],
          'prepared' => [spell.api_index]
        }
      })
      sk = create(:sheet_klass, sheet: sheet)
      create(:sheet_known_spell, sheet_klass: sk, spell: spell)
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: spell.id, auto: false)

      expect {
        delete "/api/v1/admin/spells/#{spell.api_index}?force=true", headers: headers
      }.to change(Spell, :count).by(-1)
      expect(response).to have_http_status(:no_content)

      expect(SheetKnownSpell.where(spell_id: spell.id)).to be_empty
      expect(SheetPreparedSpell.where(spell_id: spell.id)).to be_empty

      meta = sheet.reload.metadata.deep_stringify_keys
      expect(meta.dig('spell_selections', 'known')).to eq([])
      expect(meta.dig('spell_selections', 'prepared')).to eq([])
    end

    it 'rejects player with 403' do
      delete "/api/v1/admin/spells/#{spell.api_index}",
             headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
      expect(Spell.exists?(spell.id)).to be true
    end
  end

  # Pipeline integrado: garante que o que o admin cria/edita aparece imediatamente
  # via Api::V1::Public::Spells (que e o que o front consome em CompendiumSpells e
  # SpellcastingPanel). Falha aqui significa cache stale ou serializer divergente.
  describe 'integration: admin CRUD reflete em Public#show e Public#index' do
    it 'POST -> GET show retorna a magia recem-criada com desc integral' do
      payload = {
        spell: {
          name: 'Magia Pipeline Teste',
          level: 2,
          school: 'Evocation',
          range: '18 metros',
          desc: 'B' * 700,
          higher_level: 'Texto de niveis superiores'
        }
      }
      post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      expect(response).to have_http_status(:created)
      created_id = JSON.parse(response.body).dig('spell', 'id')

      get "/api/v1/public/spells/#{created_id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['spell']['desc'].length).to eq(700)
      expect(body['spell']['higher_level']).to eq('Texto de niveis superiores')
    end

    it 'PATCH -> GET show reflete a edicao' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { desc: 'descricao editada via admin' } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)

      get "/api/v1/public/spells/#{spell.id}"
      expect(JSON.parse(response.body).dig('spell', 'desc')).to eq('descricao editada via admin')
    end
  end
end

RSpec.describe 'Api::V1::Public::Spells view param', type: :request do
  let!(:spell) do
    Spell.create!(
      api_index: 'view-test-spell',
      name: 'View Test Spell',
      level: 1,
      school: 'Evocation',
      desc: 'A' * 600,
      higher_level: 'Em niveis superiores...'
    )
  end

  let!(:short_spell) do
    Spell.create!(
      api_index: 'short-test-spell',
      name: 'Short Test Spell',
      level: 0,
      school: 'Evocation',
      desc: 'curta',
      higher_level: ''
    )
  end

  it 'returns slim desc by default on index' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to be < 250
    expect(row['view']).to eq('slim')
  end

  it 'returns full desc when view=full' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to eq(600)
  end

  it 'show always returns full desc' do
    get "/api/v1/public/spells/#{spell.id}"
    body = JSON.parse(response.body)
    expect(body['spell']['desc'].length).to eq(600)
  end

  it 'slim view sinaliza descriptionTruncated quando trunca (front faz lazy-fetch)' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    truncated = row['description_truncated'] || row['descriptionTruncated']
    expect(truncated).to eq(true)
  end

  it 'slim view NAO trunca nem sinaliza truncated quando desc e curta' do
    get '/api/v1/public/spells', params: { ids: [short_spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'short-test-spell' }
    expect(row['desc']).to eq('curta')
    truncated = row['description_truncated'] || row['descriptionTruncated']
    expect(truncated).not_to eq(true)
  end

  it 'slim view omite higher_level (otimizacao de payload)' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    # higher_level deve estar ausente OU vazio no slim. O front nao depende dele
    # ate o usuario abrir o detalhe (e ai o GET show traz tudo).
    expect(row['higher_level'].to_s).to eq('')
  end

  it 'full view inclui higher_level integral' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['higher_level']).to eq('Em niveis superiores...')
  end
end

RSpec.describe 'Api::V1::Public::Spells view param', type: :request do
  let!(:spell) do
    Spell.create!(
      api_index: 'view-test-spell',
      name: 'View Test Spell',
      level: 1,
      school: 'Evocation',
      desc: 'A' * 600,
      higher_level: 'Em niveis superiores...'
    )
  end

  it 'returns slim desc by default on index' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to be < 250
    expect(row['view']).to eq('slim')
  end

  it 'returns full desc when view=full' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to eq(600)
  end

  it 'show always returns full desc' do
    get "/api/v1/public/spells/#{spell.id}"
    body = JSON.parse(response.body)
    expect(body['spell']['desc'].length).to eq(600)
  end
end
