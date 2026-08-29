# frozen_string_literal: true

require 'rails_helper'

# ALIADO INVOCADO controlado pelo JOGADOR — Fase 6 do `bruxo-plano.md`, a base
# compartilhada entre o familiar do Pacto da Corrente e o morto-vivo do patrono
# da Morte ("quem vier primeiro constroi").
#
# ⚠️ O NO DA FASE. `player_owns_combatant?` so aceitava combatente cujo
# `combatable` fosse um `Character` do usuario. Um familiar entra no tracker
# como `CombatNpc` — entao o jogador nao conseguia mexer nele, e MENOS AINDA na
# economia de acao dele. A Investida do Familiar e literalmente "abre mao de um
# ataque para o familiar atacar com a REACAO dele": sem posse, a feature nao
# tem como existir.
#
# ⚠️ Nao bastava a allowlist de "efeito em alheio no proprio turno": ela exclui
# `actions_used` DE PROPOSITO (a economia do alvo e do alvo). Posse e o unico
# caminho correto.
RSpec.describe 'Combatente NPC com DONO', type: :request do
  let(:dono) { create(:user) }
  let(:outro) { create(:user) }
  let(:group) { create(:group) }
  let(:schedule) { create(:schedule, group: group) }
  let(:pc) { create(:character, user: dono, group: group) }
  let!(:pc_do_outro) { create(:character, user: outro, group: group) }

  let(:cs) { schedule.create_combat_state!(active: true, current_turn_index: 0, round: 1) }

  # O familiar: NPC da sessao, mas VINCULADO ao personagem que o invocou.
  let(:familiar) do
    CombatNpc.create!(schedule: schedule, name: 'Diabrete', hp_current: 10, hp_max: 10, ac: 13,
                      owner_character: pc)
  end
  let(:npc_do_mestre) do
    CombatNpc.create!(schedule: schedule, name: 'Goblin', hp_current: 7, hp_max: 7, ac: 15)
  end

  # O PC ocupa o turno 0; os NPCs vem depois — assim nenhum teste passa por
  # "efeito em alheio no meu turno" sem querer.
  let!(:comb_pc) do
    cs.combat_combatants.create!(position: 0, combatable: pc, name: pc.name, initiative: 20)
  end
  let!(:comb_familiar) do
    cs.combat_combatants.create!(position: 1, combatable: familiar, name: familiar.name, initiative: 10)
  end
  let!(:comb_goblin) do
    cs.combat_combatants.create!(position: 2, combatable: npc_do_mestre, name: 'Goblin', initiative: 5)
  end

  # `actions_used` exige as QUATRO chaves (validacao do modelo) — o cliente real
  # sempre manda a gaveta inteira.
  def economia(over = {})
    { action: false, bonus_action: false, movement: false, reaction: false }.merge(over)
  end

  def patch_combatant(user, combatant, payload)
    patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
          params: { combatant: payload }, headers: bearer_headers_for(user), as: :json
  end

  describe 'posse' do
    it 'o dono muta a ECONOMIA DE ACAO do familiar (o ponto da feature)' do
      patch_combatant(dono, comb_familiar, { actions_used: economia(reaction: true) })

      expect(response).to have_http_status(:ok), response.body
      expect(comb_familiar.reload.actions_used['reaction']).to be true
    end

    it 'o dono muta o familiar mesmo FORA do turno dele' do
      cs.update!(current_turn_index: 2) # turno do Goblin
      patch_combatant(dono, comb_familiar, { hp_current: 4 })

      expect(response).to have_http_status(:ok)
      expect(comb_familiar.reload.hp_current).to eq(4)
    end

    it 'OUTRO jogador NAO muta a economia do familiar alheio' do
      # Sem esta porta, qualquer um gastaria a reacao do familiar dos outros.
      patch_combatant(outro, comb_familiar, { actions_used: economia(reaction: true) })

      expect(response).to have_http_status(:forbidden)
      expect(comb_familiar.reload.actions_used['reaction']).to be_falsey
    end

    it 'NPC do Mestre (sem dono) segue fechado ao jogador' do
      # A mudanca nao pode abrir o tracker inteiro: so o invocado tem dono.
      patch_combatant(dono, comb_goblin, { actions_used: economia(reaction: true) })

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'o dono viaja no payload' do
    it 'o combatente do familiar expoe `owner_character_id`' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
          headers: bearer_headers_for(dono)

      linha = response.parsed_body['combatants'].find { |c| c['id'] == comb_familiar.id }
      expect(linha['owner_character_id']).to eq(pc.id)
    end

    it 'PC e NPC do Mestre vem sem dono' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
          headers: bearer_headers_for(dono)

      linhas = response.parsed_body['combatants'].index_by { |c| c['id'] }
      expect(linhas[comb_pc.id]['owner_character_id']).to be_nil
      expect(linhas[comb_goblin.id]['owner_character_id']).to be_nil
    end
  end

  describe 'modelo' do
    it 'deriva o usuario a partir do personagem dono' do
      # O usuario e derivavel do personagem; o contrario nao — e o mesmo
      # usuario pode ter dois personagens na mesa.
      expect(familiar.owner_user_id).to eq(dono.id)
      expect(familiar.summoned_ally?).to be true
      expect(npc_do_mestre.summoned_ally?).to be false
    end
  end
end
