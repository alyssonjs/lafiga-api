# frozen_string_literal: true

require 'rails_helper'

# A LISTA dos mapas da vila de um grupo (L1.2): os mapas em blocos dos setores, numa lista à parte da biblioteca de
# mapas de sempre, que não os mostra.
RSpec.describe 'Api::V1::Player::GroupMapasDaVilaController', type: :request do
  let(:jogador)  { create(:user) }
  let(:estranho) { create(:user) }
  let(:group)    { create(:group) }
  let!(:pc)      { create(:character, user: jogador, group: group) }
  let(:campanha) { Campanhas::Inicia.call(create(:mundo, group: group), regiao: 'argoba') }
  let(:assentamento) { campanha.setores.find_by!(chave: 'assentamento') }
  let!(:vila) { create(:battle_map, :vila, group: group, setor: assentamento, name: 'Assentamento do grupo') }

  def lista(headers: bearer_headers_for(jogador), group_id: group.id, **params)
    get "/api/v1/player/groups/#{group_id}/mapas_da_vila", params: params, headers: headers
  end

  it 'lista os mapas da vila do grupo, com o setor e os blocos que já têm' do
    create(:mapa_bloco, battle_map: vila, bc: 0, bl: 0)
    create(:mapa_bloco, battle_map: vila, bc: 1, bl: 0)

    lista

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['mapas_da_vila']).to eq(
      [{
        'id' => vila.id, 'nome' => 'Assentamento do grupo', 'colunas' => 100, 'linhas' => 100, 'semente' => 11,
        'versao_do_gerador' => nil, 'versao_dos_biomas' => nil, 'lado' => 40, 'blocos' => 2, 'blocos_no_mapa' => 9,
        'setor' => { 'id' => assentamento.id, 'chave' => 'assentamento', 'nome' => 'Assentamento do grupo', 'tipo' => 'assentamento' },
        'atualizado_em' => vila.reload.updated_at.utc.iso8601,
      }],
    )
    expect(response.parsed_body['meta']).to eq('page' => 1, 'per_page' => 50, 'total' => 1)
  end

  it 'não traz os mapas de sempre do grupo, nem a vila de outro grupo' do
    create(:battle_map, group: group)
    create(:battle_map, :vila, group: create(:group))

    lista

    expect(response.parsed_body['mapas_da_vila'].map { |m| m['id'] }).to eq([vila.id])
  end

  it 'a biblioteca de mapas de sempre não mostra a vila' do
    inteiro = create(:battle_map, group: group)

    get '/api/v1/player/battle_maps', headers: bearer_headers_for(jogador)

    expect(response.parsed_body['battle_maps'].map { |m| m['id'] }).to eq([inteiro.id])
  end

  it 'pagina como as outras listas: per_page até 100' do
    lista(page: 2, per_page: 500)

    expect(response.parsed_body['mapas_da_vila']).to eq([])
    expect(response.parsed_body['meta']).to eq('page' => 2, 'per_page' => 100, 'total' => 1)
  end

  it 'quem não é do grupo não vê; o Mestre vê' do
    lista(headers: bearer_headers_for(estranho))
    expect(response).to have_http_status(:not_found)

    mestre = create(:user, role: Role.find_by(name: 'DM') || create(:role, name: 'DM'))
    lista(headers: bearer_headers_for(mestre))
    expect(response).to have_http_status(:ok)
  end
end
