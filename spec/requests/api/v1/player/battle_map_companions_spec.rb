# frozen_string_literal: true

require 'rails_helper'

# O COMPANHEIRO NO MAPA e o MONTAR do jogador (04/10, a mesa: "equipar o companheiro animal que é montaria, que deve
# ficar seguindo o personagem enquanto não estiver em combate. A águia também. E quando o companheiro for montaria,
# deve ter a opção de montar"). A autorização é estreita: o dono do personagem (ou o Mestre), o companheiro da ficha
# DELE, e no token do personagem só os campos da montaria.
RSpec.describe 'O companheiro no mapa e o montar', type: :request do
  let(:player_role) { create(:role, name: 'Player') }
  let(:dm_role) { create(:role, name: 'DM') }
  let(:dono) { create(:user, role: player_role) }
  let(:outro) { create(:user, role: player_role) }
  let(:group) { create(:group) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:pc) { create(:character, user: dono, group: group, name: 'Adimael') }
  let!(:sheet) { create(:sheet, character: pc, race: race, sub_race: sub_race, companions: [lobo, aguia]) }
  let(:lobo) { { 'id' => 'comp-lobo', 'name' => 'Jujubinha', 'type' => 'mount', 'size' => 'Large', 'especie' => 'winter-wolf' } }
  let(:aguia) { { 'id' => 'comp-aguia', 'name' => 'Fura-Olho', 'type' => 'familiar', 'size' => 'Tiny' } }
  let(:map) do
    create(:battle_map, user: create(:user, role: dm_role), width: 8, height: 8, cells: Array.new(8) { Array.new(8, 'empty') })
  end
  let!(:schedule) { create(:schedule, group: group, battle_map: map) }
  # a MESA: as criaturas vivem no vínculo da sessão (`MapSessionLayer`), não no tabuleiro
  let!(:link) do
    ScheduleBattleMap.create!(schedule: schedule, battle_map: map, tokens: [
      { 'id' => 't-pc', 'name' => 'Adimael', 'color' => '#fff', 'x' => 1, 'y' => 1, 'size' => 1, 'characterId' => pc.id.to_s },
      { 'id' => 't-npc', 'name' => 'Goblin', 'color' => '#000', 'x' => 6, 'y' => 6, 'size' => 1, 'npcId' => 'npc-1' },
    ])
  end

  def pede(acao, user, params)
    post "/api/v1/player/battle_maps/#{map.id}/#{acao}", params: { schedule_id: schedule.id }.merge(params),
                                                         headers: bearer_headers_for(user), as: :json
  end

  def token_da_resposta(id)
    response.parsed_body['battle_map']['tokens'].find { |t| t['id'] == id }
  end

  describe 'pôr e tirar o companheiro (companion_token)' do
    it 'o DONO põe o companheiro: o token nasce da ficha (nome, porte, espécie), ligado a ele pelo companheiroDe' do
      expect {
        pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', x: 2, y: 1)
      }.to have_broadcasted_to("map_#{map.id}_s#{schedule.id}").with { |data| data['event'] == 'tokens_patched' }

      expect(response).to have_http_status(:ok), response.body
      token = token_da_resposta('companheiro-comp-lobo')
      expect(token).to include(
        'name' => 'Jujubinha', 'x' => 2, 'y' => 1, 'size' => 2, 'companheiroDe' => pc.id.to_s,
        'companheiroId' => 'comp-lobo', 'especie' => 'winter-wolf', 'imageMode' => 'color',
      )
      expect(token).not_to have_key('characterId')
      # é da MESA, não do tabuleiro: o companheiro é criatura (`companheiroDe`) e vai para o vínculo da sessão
      expect(link.reload.tokens.map { |t| t['id'] }).to include('companheiro-comp-lobo')
      expect(map.reload.tokens.map { |t| t['id'] }).not_to include('companheiro-comp-lobo')
    end

    it 'pôr de novo não duplica; a espécie do pedido vale (a águia, sem espécie na ficha)' do
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-aguia', x: 2, y: 2, especie: 'eagle')
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-aguia', x: 3, y: 3, especie: 'eagle')
      expect(response).to have_http_status(:ok)
      tokens = response.parsed_body['battle_map']['tokens'].select { |t| t['id'] == 'companheiro-comp-aguia' }
      expect(tokens.size).to eq(1)
      expect(tokens.first).to include('especie' => 'eagle', 'size' => 1)
    end

    it 'pôr de novo com OUTRA espécie: o token troca o desenho e fica onde está' do
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-aguia', x: 2, y: 2, especie: 'hawk')
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-aguia', x: 2, y: 2, especie: 'eagle')
      expect(response).to have_http_status(:ok)
      expect(token_da_resposta('companheiro-comp-aguia')).to include('especie' => 'eagle', 'x' => 2, 'y' => 2)
      expect(response.parsed_body['token_mutation']['patches']).to eq([
        { 'tokenId' => 'companheiro-comp-aguia', 'changes' => { 'especie' => 'eagle' }, 'unset' => [] },
      ])
    end

    it 'tirar: o token sai do mapa' do
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', x: 2, y: 1)
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', remover: true)
      expect(response).to have_http_status(:ok)
      expect(token_da_resposta('companheiro-comp-lobo')).to be_nil
    end

    it 'o Mestre põe o companheiro de um jogador' do
      pede('companion_token', create(:user, role: dm_role), character_id: pc.id, companion_id: 'comp-lobo', x: 4, y: 4)
      expect(response).to have_http_status(:ok)
    end

    it 'outro jogador não mexe no companheiro alheio (403)' do
      create(:character, user: outro, group: group)
      pede('companion_token', outro, character_id: pc.id, companion_id: 'comp-lobo', x: 2, y: 1)
      expect(response).to have_http_status(:forbidden)
    end

    it 'o companheiro tem de estar na ficha; fora do mapa ou sem sessão, não vai (422)' do
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-nada', x: 2, y: 1)
      expect(response).to have_http_status(:unprocessable_entity)
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', x: 7, y: 7)
      expect(response).to have_http_status(:unprocessable_entity)
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', x: 1, y: 1, especie: 'Lobo Mau')
      expect(response).to have_http_status(:unprocessable_entity)
      post "/api/v1/player/battle_maps/#{map.id}/companion_token",
           params: { character_id: pc.id, companion_id: 'comp-lobo', x: 2, y: 1 }, headers: bearer_headers_for(dono), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'o companheiro SEGUE o dono (move_token)' do
    before { pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-aguia', x: 2, y: 2, especie: 'eagle') }

    it 'o dono move o token do companheiro dele' do
      pede('move_token', dono, token_id: 'companheiro-comp-aguia', x: 3, y: 2)
      expect(response).to have_http_status(:ok), response.body
      expect(token_da_resposta('companheiro-comp-aguia')).to include('x' => 3, 'y' => 2)
    end

    it 'outro jogador não move (403); o NPC segue só do Mestre' do
      create(:character, user: outro, group: group)
      pede('move_token', outro, token_id: 'companheiro-comp-aguia', x: 3, y: 2)
      expect(response).to have_http_status(:forbidden)
      pede('move_token', dono, token_id: 't-npc', x: 5, y: 5)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'montar e desmontar (mount_token)' do
    let(:montar) do
      { token_id: 't-pc', changes: { montaria: 'winter-wolf', size: 2, tamanhoAPe: 1, montariaCompanheiroId: 'comp-lobo' } }
    end

    it 'o dono MONTA no companheiro: o token dele ganha a montaria e o do companheiro sai, na mesma escrita' do
      pede('companion_token', dono, character_id: pc.id, companion_id: 'comp-lobo', x: 3, y: 1)
      pede('mount_token', dono, montar.merge(remover_companheiro: 'comp-lobo'))
      expect(response).to have_http_status(:ok), response.body
      expect(token_da_resposta('t-pc')).to include('montaria' => 'winter-wolf', 'size' => 2, 'tamanhoAPe' => 1, 'montariaCompanheiroId' => 'comp-lobo')
      expect(token_da_resposta('companheiro-comp-lobo')).to be_nil
      expect(response.parsed_body['token_mutation']['deleteIds']).to eq(['companheiro-comp-lobo'])
    end

    it 'e DESMONTA: a montaria e o tamanho a pé voltam' do
      pede('mount_token', dono, montar)
      pede('mount_token', dono, token_id: 't-pc', changes: { montaria: nil, size: 1, tamanhoAPe: nil, montariaCompanheiroId: nil })
      expect(response).to have_http_status(:ok)
      pc_token = token_da_resposta('t-pc')
      expect(pc_token['size']).to eq(1)
      expect(pc_token.keys).not_to include('montaria', 'tamanhoAPe', 'montariaCompanheiroId')
    end

    it 'só os campos da montaria: o resto é recusado (422)' do
      pede('mount_token', dono, token_id: 't-pc', changes: { name: 'Outro', montaria: 'winter-wolf' })
      expect(response).to have_http_status(:unprocessable_entity)
      pede('mount_token', dono, token_id: 't-pc', changes: { size: 9 })
      expect(response).to have_http_status(:unprocessable_entity)
      pede('mount_token', dono, token_id: 't-pc', changes: { x: 7, size: 2 })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'outro jogador não monta no token alheio (403); token que não é de personagem não monta (422)' do
      create(:character, user: outro, group: group)
      pede('mount_token', outro, montar)
      expect(response).to have_http_status(:forbidden)
      pede('mount_token', dono, token_id: 't-npc', changes: { montaria: 'winter-wolf' })
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
