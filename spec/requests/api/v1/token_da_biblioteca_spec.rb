# frozen_string_literal: true

# Token da biblioteca nas LISTAGENS: monstros (Mestre e público), NPCs básicos
# e companheiros (Mestre e público).
#
# O `?v=` passou a ser o id do blob da arte, que mora no anexo do asset — uma
# consulta a mais por linha se a listagem não pré-carregar. As listagens vão a
# 500 linhas num box de 1 CPU: o que estes testes guardam é que o número de
# consultas NÃO cresce com o número de linhas, e que trocar a arte chega ao
# front como URL nova.
require 'rails_helper'

RSpec.describe 'token da biblioteca nas listagens', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm) }

  def novo_asset
    create(:map_asset, kind: 'object', category: 'Meus')
  end

  def consultas_em(path, headers = {})
    n = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      n += 1 unless %w[SCHEMA CACHE].include?(payload[:name])
    end
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  CRIADORES = {
    monstro: lambda { |i, asset|
      Monster.create!(slug: "mon-tk-#{i}", name: "Lobo #{i}", source: 'srd',
                      payload: { 'ac' => 13, 'hp' => 11, 'cr' => '1/4' }, token_map_asset_id: asset.id)
    },
    npc: lambda { |i, asset|
      BasicNpc.create!(slug: "npc-tk-#{i}", name: "Guarda #{i}", hp: 11, ac: 16, token_map_asset_id: asset.id)
    },
    companheiro: lambda { |i, asset|
      CompanionTemplate.create!(slug: "cmp-tk-#{i}", name: "Lobo #{i}", companion_type: 'beast_companion',
                                token_map_asset_id: asset.id)
    },
  }.freeze

  [
    ['/api/v1/admin/monsters', :monstro, true],
    ['/api/v1/public/monsters', :monstro, false],
    ['/api/v1/admin/basic_npcs', :npc, true],
    ['/api/v1/admin/companion_templates', :companheiro, true],
    ['/api/v1/public/companion_templates', :companheiro, false],
  ].each do |path, tipo, do_mestre|
    it "⚠️ #{path}: as consultas não crescem com as linhas (sem N+1)" do
      cabecalho = do_mestre ? headers : {}
      CRIADORES[tipo].call(0, novo_asset)
      com_uma = consultas_em(path, cabecalho)

      (1..4).each { |i| CRIADORES[tipo].call(i, novo_asset) }
      com_cinco = consultas_em(path, cabecalho)

      expect(com_cinco).to eq(com_uma), "#{path}: #{com_uma} consultas com 1 linha, #{com_cinco} com 5"
    end
  end

  it '⚠️ trocar a arte do asset chega à listagem como URL NOVA' do
    asset = novo_asset
    CRIADORES[:npc].call(0, asset)

    get '/api/v1/admin/basic_npcs', headers: headers
    antes = response.parsed_body['basic_npcs'].first['token_image_url']

    asset.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\noutra-arte"), filename: 'nova.png', content_type: 'image/png')

    get '/api/v1/admin/basic_npcs', headers: headers
    depois = response.parsed_body['basic_npcs'].first['token_image_url']

    expect(depois).not_to eq(antes)
    expect(depois).to eq(MapAssetSerializer.serialize(asset.reload)[:imageUrl])
  end

  it 'o contrato não muda: mesmas chaves, só o v= é outro' do
    asset = novo_asset
    CRIADORES[:monstro].call(0, asset)

    get '/api/v1/public/monsters'
    linha = response.parsed_body['monsters'].find { |m| m['id'] == 'mon-tk-0' }

    expect(linha['tokenMapAssetId']).to eq(asset.id)
    expect(linha['tokenImageUrl']).to eq("/api/v1/admin/map_assets/#{asset.id}/image?v=#{asset.image.blob.id}")
    expect(linha).not_to have_key('token_map_asset')
  end
end
