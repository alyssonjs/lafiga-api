# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Catálogo de companheiros', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  let!(:cavalo) do
    CompanionTemplate.create!(
      slug: 'cavalo-teste', name: 'Cavalo de Teste', companion_type: 'mount',
      origin: 'purchased', creature_type: 'Fera', size: 'Large',
      ac: 10, hp_max: 13, speed: '18 m', carry_capacity: 480,
      stats: { 'str' => 16, 'dex' => 10, 'con' => 12, 'int' => 2, 'wis' => 11, 'cha' => 7 },
      attacks: [{ 'name' => 'Cascos', 'damage' => '2d4+3' }],
      flags: { 'shares_senses' => false }
    )
  end

  let!(:coruja) do
    CompanionTemplate.create!(
      slug: 'coruja-teste', name: 'Coruja de Teste', companion_type: 'familiar',
      origin: 'spell', origin_spell_id: 'sp-find-familiar', size: 'Tiny',
      flags: { 'shares_senses' => true, 'deliver_touch_spells' => true }
    )
  end

  describe 'quem pode CRIAR' do
    it 'o mestre cria' do
      post '/api/v1/admin/companion_templates',
           params: { companion_template: { name: 'Grifo do DM', companion_type: 'greater_mount' } },
           headers: bearer_headers_for(dm_user)

      expect(response).to have_http_status(:created)
      expect(CompanionTemplate.find_by(slug: 'grifo-do-dm')).to be_present
    end

    # 403, nao 401: 401 dispara logout global no apiClient.
    it 'o jogador comum recebe 403 e nada e criado' do
      expect do
        post '/api/v1/admin/companion_templates',
             params: { companion_template: { name: 'Dragao do jogador', companion_type: 'mount' } },
             headers: bearer_headers_for(player)
      end.not_to change(CompanionTemplate, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'leitura publica' do
    it 'lista no shape que o front consome (camelCase, bandeiras achatadas)' do
      get '/api/v1/public/companion_templates'

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body['companion_templates']
      linha = corpo.find { |t| t['templateId'] == 'coruja-teste' }

      expect(linha['type']).to eq('familiar')
      expect(linha['sharesSenses']).to be(true)
      expect(linha['deliverTouchSpells']).to be(true)
      expect(linha['originSpellId']).to eq('sp-find-familiar')
    end

    it 'filtra por tipo' do
      get '/api/v1/public/companion_templates', params: { type: 'mount' }

      ids = response.parsed_body['companion_templates'].map { |t| t['templateId'] }
      expect(ids).to include('cavalo-teste')
      expect(ids).not_to include('coruja-teste')
    end
  end

  # ⚠️ Array de HASHES em strong params: `attacks: []` cru descartaria o
  # conteudo silenciosamente e o companheiro nasceria sem ataque nenhum.
  it 'persiste ataques e acoes especiais (hashes dentro de array)' do
    patch "/api/v1/admin/companion_templates/#{cavalo.slug}",
          params: { companion_template: {
            attacks: [{ name: 'Coice', damage: '2d6+4', damageType: 'contundente' }],
            special_actions: [{ name: 'Desviar', actionCost: 'action', description: 'Vantagem em CA.' }],
          } },
          headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:ok)
    cavalo.reload
    expect(cavalo.attacks.first['name']).to eq('Coice')
    expect(cavalo.attacks.first['damageType']).to eq('contundente')
    expect(cavalo.special_actions.first['actionCost']).to eq('action')
  end

  it 'recusa um tipo que o front nao sabe desenhar' do
    post '/api/v1/admin/companion_templates',
         params: { companion_template: { name: 'Coisa', companion_type: 'kraken' } },
         headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end

RSpec.describe 'Proficiencias do companheiro', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }

  it 'grava pericias e resistencias e devolve no shape do front' do
    post '/api/v1/admin/companion_templates',
         params: { companion_template: {
           name: 'Urso do DM', companion_type: 'beast_companion',
           skill_proficiencies: %w[Percepção Furtividade],
           save_proficiencies: %w[str con],
         } },
         headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:created)

    get '/api/v1/public/companion_templates'
    linha = response.parsed_body['companion_templates'].find { |t| t['templateId'] == 'urso-do-dm' }
    expect(linha['skillProficiencies']).to eq(%w[Percepção Furtividade])
    expect(linha['saveProficiencies']).to eq(%w[str con])
  end

  # ⚠️ `ability`/`proficient` sao o que torna o bonus DERIVADO. Sem eles nos
  # strong params o ataque volta a ser um numero copiado que envelhece.
  it 'preserva de onde o bonus do ataque sai' do
    tpl = CompanionTemplate.create!(slug: 'urso-x', name: 'Urso X', companion_type: 'beast_companion')

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: {
            attacks: [{ name: 'Mordida', damage: '1d8+4', damageType: 'perfurante',
                        ability: 'str', proficient: true }],
          } }.to_json,
          headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:ok)
    expect(tpl.reload.attacks.first['ability']).to eq('str')
    expect(tpl.attacks.first['proficient']).to be(true)
  end

  # ⚠️ Corpo NAO-JSON entrega "false" como STRING, e o front decide por
  # `=== false`: sem normalizar, desligar o Prof no editor nao desligava nada.
  it 'a string "false" nao vira proficiencia concedida' do
    tpl = CompanionTemplate.create!(slug: 'urso-y', name: 'Urso Y', companion_type: 'beast_companion')

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: {
            attacks: [{ name: 'Coice', damage: '1d4', ability: 'str', proficient: 'false' }],
          } },
          headers: bearer_headers_for(dm_user)

    expect(tpl.reload.attacks.first['proficient']).to be(false)
  end
end

RSpec.describe 'Token do companheiro (PNG)', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }

  # PNG 1x1 real — um arquivo inventado nao passa pela validacao de content type.
  def dados_png
    Base64.decode64(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    )
  end

  # Upload multipart (o caminho do editor).
  def png_1x1
    Rack::Test::UploadedFile.new(StringIO.new(dados_png), 'image/png', original_filename: 'token.png')
  end

  # Anexo DIRETO (montar o cenario sem passar por requisicao): o
  # `Rack::Test::UploadedFile` sobre StringIO nao serve aqui — o ActiveStorage
  # chama `open` nele.
  def anexo_direto
    { io: StringIO.new(dados_png), filename: 'token.png', content_type: 'image/png' }
  end

  it 'o Mestre sobe o PNG e ele volta como URL no shape do front' do
    post '/api/v1/admin/companion_templates',
         params: {
           companion_template: { name: 'Lobo Pintado', companion_type: 'beast_companion' },
           token_image: png_1x1,
         },
         headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:created)
    tpl = CompanionTemplate.find_by(slug: 'lobo-pintado')
    expect(tpl.token_image).to be_attached

    # ⚠️ A chave e `image` (nao `tokenImageUrl`): e o campo que o `Companion` da
    # ficha ja tem, entao instanciar o modelo leva o token junto sem tradutor.
    get '/api/v1/public/companion_templates'
    linha = response.parsed_body['companion_templates'].find { |t| t['templateId'] == 'lobo-pintado' }
    expect(linha['image']).to match(%r{/api/v1/public/companion_templates/#{tpl.id}/token_image\?v=\d+})
  end

  it 'serve o blob a QUALQUER UM — o token aparece no mapa da mesa inteira' do
    tpl = CompanionTemplate.create!(slug: 'urso-png', name: 'Urso PNG', companion_type: 'beast_companion')
    tpl.token_image.attach(anexo_direto)

    # Sem token de autenticacao nenhum: e assim que o jogador carrega o desenho.
    get "/api/v1/public/companion_templates/#{tpl.id}/token_image"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
  end

  it 'recusa arquivo que nao e imagem' do
    post '/api/v1/admin/companion_templates',
         params: {
           companion_template: { name: 'Nao Imagem', companion_type: 'mount' },
           token_image: Rack::Test::UploadedFile.new(
             StringIO.new('nao sou imagem'), 'text/plain', original_filename: 'x.txt'
           ),
         },
         headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CompanionTemplate.find_by(slug: 'nao-imagem')).to be_nil
  end

  # ⚠️ Campo ausente significa "nao mexi", nao "apague" — sem um caminho
  # explicito, tirar o PNG seria impossivel pelo editor.
  it 'remove o PNG so quando pedido explicitamente' do
    tpl = CompanionTemplate.create!(slug: 'com-png', name: 'Com PNG', companion_type: 'mount')
    tpl.token_image.attach(anexo_direto)

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: { name: 'Com PNG II' } },
          headers: bearer_headers_for(dm_user)
    expect(tpl.reload.token_image).to be_attached

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: { name: 'Com PNG II' }, remove_token_image: '1' },
          headers: bearer_headers_for(dm_user)
    expect(tpl.reload.token_image).not_to be_attached
  end
end

RSpec.describe 'Mecanica da acao especial', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }
  let!(:tpl) do
    CompanionTemplate.create!(slug: 'lobo-inv', name: 'Lobo Invernal', companion_type: 'beast_companion')
  end

  # ⚠️ `mechanics` e hash ANINHADO num array de hashes: sem as chaves nos strong
  # params o Rails descarta o bloco inteiro e a acao volta a ser so prosa.
  it 'persiste CD, atributo do TR, dado e area' do
    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: {
            special_actions: [{
              name: 'Sopro Gelado', actionCost: 'action', description: 'Cone gelado.',
              mechanics: {
                saveAbility: 'dex', saveDc: 12, halfOnSave: true,
                damage: { dice: '4d8', type: 'frio' },
                area: { shape: 'cone', sizeFt: 15 },
              },
            }],
          } }.to_json,
          headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:ok)
    mec = tpl.reload.special_actions.first['mechanics']
    expect(mec['saveAbility']).to eq('dex')
    expect(mec['saveDc']).to eq(12)
    expect(mec['damage']).to eq({ 'dice' => '4d8', 'type' => 'frio' })
    expect(mec['area']).to eq({ 'shape' => 'cone', 'sizeFt' => 15 })
  end

  it 'acao sem mecanica continua valendo pelo texto' do
    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: {
            special_actions: [{ name: 'Faro Apurado', description: 'Vantagem em Percepcao.' }],
          } }.to_json,
          headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    acao = tpl.reload.special_actions.first
    expect(acao['description']).to eq('Vantagem em Percepcao.')
    expect(acao['mechanics']).to be_nil
  end
end

RSpec.describe 'Deslocamento multi-modo do companheiro', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }

  it 'grava os modos NUMERICOS e devolve no shape do front' do
    post '/api/v1/admin/companion_templates',
         params: { companion_template: {
           name: 'Lobo Aquatico', companion_type: 'mount',
           speed: '15 m, natacao 7,5 m',
           speed_modes: { walk: 50, swim: 25 },
         } }.to_json,
         headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:created)

    get '/api/v1/public/companion_templates'
    linha = response.parsed_body['companion_templates'].find { |t| t['templateId'] == 'lobo-aquatico' }
    expect(linha['speedModes']).to eq({ 'walk' => 50, 'swim' => 25 })
  end
end

RSpec.describe 'Token da BIBLIOTECA de objetos', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }

  def dados_png
    Base64.decode64(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    )
  end

  def anexo_direto
    { io: StringIO.new(dados_png), filename: 'token.png', content_type: 'image/png' }
  end

  let!(:asset) do
    a = MapAsset.new(name: 'Lobo do mapa', kind: 'object', category: 'Meus', user: dm_user)
    a.image.attach(anexo_direto)
    a.save!
    a
  end

  # ⚠️ REFERENCIA, nao copia: 1962 assets na biblioteca, e o token velho
  # mentiria se o Mestre corrigisse o asset depois.
  it 'aponta para o asset e o front recebe a URL dele' do
    post '/api/v1/admin/companion_templates',
         params: { companion_template: {
           name: 'Lobo da Biblioteca', companion_type: 'beast_companion',
           token_map_asset_id: asset.id,
         } }.to_json,
         headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:created)

    get '/api/v1/public/companion_templates'
    linha = response.parsed_body['companion_templates'].find { |t| t['templateId'] == 'lobo-da-biblioteca' }
    expect(linha['image']).to eq("/api/v1/admin/map_assets/#{asset.id}/image?v=#{asset.id}")
  end

  # ⚠️ Uma fonte por vez: com as duas gravadas, a precedencia decidiria em
  # silencio e o Mestre nao saberia qual venceu.
  it 'subir um PNG desfaz a escolha da biblioteca' do
    tpl = CompanionTemplate.create!(
      slug: 'lobo-x', name: 'Lobo X', companion_type: 'beast_companion',
      token_map_asset_id: asset.id
    )

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: {
            companion_template: { name: 'Lobo X' },
            token_image: Rack::Test::UploadedFile.new(
              StringIO.new(dados_png), 'image/png', original_filename: 'meu.png'
            ),
          },
          headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:ok)
    tpl.reload
    expect(tpl.token_image).to be_attached
    expect(tpl.token_map_asset_id).to be_nil
    expect(tpl.token_image_url).to match(%r{/companion_templates/#{tpl.id}/token_image})
  end

  it 'escolher da biblioteca desfaz o PNG proprio' do
    tpl = CompanionTemplate.create!(slug: 'lobo-y', name: 'Lobo Y', companion_type: 'beast_companion')
    tpl.token_image.attach(anexo_direto)

    patch "/api/v1/admin/companion_templates/#{tpl.slug}",
          params: { companion_template: { token_map_asset_id: asset.id } }.to_json,
          headers: bearer_headers_for(dm_user).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:ok)
    expect(tpl.reload.token_map_asset_id).to eq(asset.id)
    expect(tpl.token_image_url).to include("map_assets/#{asset.id}/image")
  end

  it 'sem token nenhum, sem URL' do
    tpl = CompanionTemplate.create!(slug: 'lobo-z', name: 'Lobo Z', companion_type: 'beast_companion')
    expect(tpl.token_image_url).to be_nil
  end
end
