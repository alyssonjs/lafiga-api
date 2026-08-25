# frozen_string_literal: true

require 'rails_helper'

# Regiões do mapa (Fase 1).
#
# A regra que este spec existe para travar: `dmNotes` NUNCA sai no payload do
# mapa. O payload alimenta o broadcast estrutural, que manda o mesmo conteúdo
# para a mesa inteira — um vazamento aqui é silencioso e chega a todos os
# jogadores de uma vez.
RSpec.describe 'Api::V1::Player::BattleMaps regiões', type: :request do
  let(:dm_role)  { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)       { create(:user, role: dm_role) }
  let(:outro_dm) { create(:user, role: dm_role) }
  let(:jogador)  { create(:user) }
  let(:map)      { create(:battle_map, user: dm) }

  let(:vila) do
    {
      'id' => 'reg-1',
      'name' => 'Vila Zesfenir',
      'kind' => 'village',
      'rects' => [{ 'col' => 4, 'row' => 4, 'w' => 3, 'h' => 2 }],
      'biome' => 'floresta',
      'playerNotes' => 'Ferreiro e estalagem.',
      'dmNotes' => 'O ferreiro é um espião.',
    }
  end

  def patch_regions(regioes, user: dm)
    patch "/api/v1/player/battle_maps/#{map.id}",
          params: { battle_map: { regions: regioes } },
          headers: bearer_headers_for(user), as: :json
  end

  it 'nasce vazio e persiste o que o mestre desenha' do
    expect(map.regions).to eq([])

    patch_regions([vila])
    expect(response).to have_http_status(:ok)

    gravada = map.reload.regions.first
    expect(gravada['name']).to eq('Vila Zesfenir')
    expect(gravada['rects']).to eq([{ 'col' => 4, 'row' => 4, 'w' => 3, 'h' => 2 }])
    expect(gravada['biome']).to eq('floresta')
  end

  it 'o payload do mapa traz a região SEM a nota do mestre' do
    patch_regions([vila])

    get "/api/v1/player/battle_maps/#{map.id}", headers: bearer_headers_for(dm)
    regiao = response.parsed_body['battle_map']['regions'].first

    expect(regiao['name']).to eq('Vila Zesfenir')
    expect(regiao['playerNotes']).to eq('Ferreiro e estalagem.')
    expect(regiao).not_to have_key('dmNotes')
    # E a nota não aparece em lado nenhum do corpo — nem por outro caminho.
    expect(response.body).not_to include('espião')
  end

  it 'nem para o próprio mestre: o funil é o mesmo para toda a gente' do
    patch_regions([vila])

    get "/api/v1/player/battle_maps/#{map.id}", headers: bearer_headers_for(dm)
    expect(response.body).not_to include('espião')
  end

  it 'a resposta da MUTAÇÃO também não carrega região nenhuma' do
    patch_regions([vila])

    expect(response.parsed_body['battle_map']).not_to have_key('regions')
    expect(response.body).not_to include('espião')
  end

  describe 'GET /regions — a única porta de saída da nota' do
    before { patch_regions([vila]) }

    it 'devolve a nota para quem pode escrever no mapa' do
      get "/api/v1/player/battle_maps/#{map.id}/regions", headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['regions'].first['dmNotes']).to eq('O ferreiro é um espião.')
    end

    it 'recusa quem não pode escrever' do
      get "/api/v1/player/battle_maps/#{map.id}/regions", headers: bearer_headers_for(jogador)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('espião')
    end
  end

  describe 'a nota sobrevive a uma reescrita vinda do cliente' do
    before { patch_regions([vila]) }

    # Este é o cenário real: o cliente recebeu a região SEM a nota (o serializer
    # cortou) e devolve a sua cópia ao renomear. Sem a fusão, renomear apagaria
    # o que o mestre escreveu — e ele só descobriria muito depois.
    it 'renomear pela cópia do cliente NÃO apaga a nota' do
      copia_do_cliente = vila.except('dmNotes').merge('name' => 'Vila Zesfenir (queimada)')
      patch_regions([copia_do_cliente])

      gravada = map.reload.regions.first
      expect(gravada['name']).to eq('Vila Zesfenir (queimada)')
      expect(gravada['dmNotes']).to eq('O ferreiro é um espião.')
    end

    it 'mas o mestre consegue REESCREVER a nota quando manda o campo' do
      patch_regions([vila.merge('dmNotes' => 'O ferreiro fugiu.')])

      expect(map.reload.regions.first['dmNotes']).to eq('O ferreiro fugiu.')
    end

    it 'e consegue APAGAR mandando o campo a null' do
      patch_regions([vila.merge('dmNotes' => nil)])

      expect(map.reload.regions.first).not_to have_key('dmNotes')
    end

    it 'apagar a região leva a nota junto' do
      patch_regions([])

      expect(map.reload.regions).to eq([])
    end
  end

  it 'região é mudança ESTRUTURAL — o mapa inteiro é retransmitido' do
    # Sem isto, o mestre desenha uma região e a mesa só a vê ao recarregar.
    expect(MapRealtime::Broadcaster).to receive(:map_updated).at_least(:once)
    patch_regions([vila])
  end

  it 'duplicar o mapa leva as regiões — são cenário, não encontro' do
    map.update!(regions: [vila])

    post "/api/v1/player/battle_maps/#{map.id}/duplicate", headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:created)

    copia = BattleMap.find(response.parsed_body['battle_map']['id'])
    expect(copia.regions.first['name']).to eq('Vila Zesfenir')
    expect(copia.regions.first['dmNotes']).to eq('O ferreiro é um espião.')
    # E os arrays não podem ser o MESMO objeto: editar a cópia não pode mexer no original.
    copia.update!(regions: [vila.merge('name' => 'Outra')])
    expect(map.reload.regions.first['name']).to eq('Vila Zesfenir')
  end

  it 'lixo no array não derruba o serializer' do
    map.update_column(:regions, ['nao sou um hash', nil, vila])

    get "/api/v1/player/battle_maps/#{map.id}", headers: bearer_headers_for(dm)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['battle_map']['regions'].size).to eq(1)
  end
end
