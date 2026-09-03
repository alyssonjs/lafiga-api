# frozen_string_literal: true

require 'rails_helper'

# INVOCAR o companion da ficha para o tracker — Fase 6 do `bruxo-plano.md`.
#
# ⚠️ POR QUE NAO PELO `create` DE NPC. Aquele endpoint e so-DM, e com razao: NPC
# e do Mestre. Um INVOCADO nao e — familiar do Pacto da Corrente e morto-vivo do
# patrono da Morte sao convocados pelo JOGADOR e obedecem a ele. A autorizacao
# aqui e outra e mais estreita: dono do personagem + companion na ficha DELE.
RSpec.describe 'Invocar companion para o combate', type: :request do
  let(:dono) { create(:user) }
  let(:outro) { create(:user) }
  let(:group) { create(:group) }
  let(:schedule) { create(:schedule, group: group) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:pc) { create(:character, user: dono, group: group, name: 'Ainor') }
  let!(:sheet) { create(:sheet, character: pc, race: race, sub_race: sub_race, companions: [familiar]) }

  let(:familiar) do
    {
      'id' => 'cmp-1', 'name' => 'Diabrete', 'type' => 'familiar',
      'ac' => 13, 'hpMax' => 10, 'hpCurrent' => 10, 'profBonus' => 2,
      'speed' => '20 ft, voo 40 ft',
      'stats' => { 'str' => 6, 'dex' => 17, 'con' => 13, 'int' => 11, 'wis' => 12, 'cha' => 14 },
      'attacks' => [
        { 'name' => 'Ferroada', 'attackBonus' => '+5', 'damage' => '1d4+3', 'damageType' => 'perfurante', 'range' => '1,5 m' },
      ],
      'description' => 'Resistencia a frio.',
    }
  end

  def invocar(user, character_id: pc.id, companion_id: 'cmp-1')
    post "/api/v1/player/schedules/#{schedule.id}/combat_npcs/summon",
         params: { character_id: character_id, companion_id: companion_id },
         headers: bearer_headers_for(user), as: :json
  end

  describe 'quem pode invocar' do
    it 'o DONO do personagem invoca, e o NPC nasce COM DONO' do
      invocar(dono)

      expect(response).to have_http_status(:created), response.body
      npc = CombatNpc.find_by(schedule: schedule, name: 'Diabrete')
      expect(npc.owner_character_id).to eq(pc.id)
      expect(npc.summoned_ally?).to be true
    end

    it 'OUTRO jogador nao invoca o companion alheio' do
      invocar(outro)

      expect(response).to have_http_status(:forbidden)
      expect(CombatNpc.where(schedule: schedule).count).to eq(0)
    end

    it 'companion que nao esta na ficha nao invoca' do
      invocar(dono, companion_id: 'nao-existe')

      expect(response).to have_http_status(:forbidden)
      expect(CombatNpc.where(schedule: schedule).count).to eq(0)
    end

    it 'personagem de OUTRA mesa nao invoca aqui' do
      # ⚠️ A ficha COM o mesmo companion e obrigatoria: sem ela o pedido cairia
      # em "companion nao encontrado" e o teste passaria verde sem nunca
      # exercitar a regra de mesa (falso positivo pego por reversao em 29/08).
      de_fora = create(:character, user: dono, group: create(:group))
      create(:sheet, character: de_fora, race: race, sub_race: sub_race, companions: [familiar])

      invocar(dono, character_id: de_fora.id)

      expect(response).to have_http_status(:forbidden)
      expect(CombatNpc.where(schedule: schedule).count).to eq(0)
    end
  end

  describe 'os dados do companion viram o NPC' do
    it 'copia PV, CA, atributos e ataques' do
      invocar(dono)

      npc = CombatNpc.find_by(schedule: schedule, name: 'Diabrete')
      expect(npc.hp_max).to eq(10)
      expect(npc.hp_current).to eq(10)
      expect(npc.ac).to eq(13)
      expect(npc.proficiency_bonus).to eq(2)
      expect(npc.stats['dex']).to eq(17)
      expect(npc.attacks.first['name']).to eq('Ferroada')
      expect(npc.attacks.first['damage_dice']).to eq('1d4+3')
    end

    # ⚠️ FALLBACK. Companheiro antigo so tem a string, e dela sai o andar — o
    # VOO 40 do diabrete some. Era este o defeito: o multi-modo morria aqui.
    it 'sem modos declarados, le a velocidade do TEXTO (e perde o voo)' do
      invocar(dono)
      npc = CombatNpc.find_by(schedule: schedule, name: 'Diabrete')
      expect(npc.speed).to eq(20)
      expect(npc.speed_modes).to eq({})
    end

    it 'com modos declarados, o VOO chega ao combate' do
      sheet.update!(companions: [familiar.merge('speedModes' => { 'walk' => 20, 'fly' => 40 })])

      invocar(dono)
      npc = CombatNpc.find_by(schedule: schedule, name: 'Diabrete')
      expect(npc.speed_modes).to eq({ 'walk' => 20, 'fly' => 40 })
      # O inteiro do `speed` passa a sair do ANDAR declarado, nao do texto.
      expect(npc.speed).to eq(20)
    end

    it 'modo zerado nao entra — ausente e ausente' do
      sheet.update!(companions: [familiar.merge('speedModes' => { 'walk' => 30, 'fly' => 0, 'swim' => nil })])

      invocar(dono)
      expect(CombatNpc.find_by(schedule: schedule, name: 'Diabrete').speed_modes).to eq({ 'walk' => 30 })
    end

    it 'ficha com hpCurrent 0 invoca com PV CHEIO, nao morto' do
      sheet.update!(companions: [familiar.merge('hpCurrent' => 0)])
      invocar(dono)
      expect(CombatNpc.find_by(schedule: schedule, name: 'Diabrete').hp_current).to eq(10)
    end
  end

  describe 'entra no TRACKER quando ha combate' do
    let!(:cs) { schedule.create_combat_state!(active: true, current_turn_index: 0, round: 2) }
    let!(:comb_pc) do
      cs.combat_combatants.create!(position: 0, combatable: pc, name: pc.name, initiative: 17)
    end
    let!(:comb_goblin) do
      goblin = CombatNpc.create!(schedule: schedule, name: 'Goblin', hp_current: 7, hp_max: 7, ac: 15)
      cs.combat_combatants.create!(position: 1, combatable: goblin, name: 'Goblin', initiative: 9)
    end

    it 'vira combatente com a iniciativa DO DONO' do
      # Entrar com iniciativa `nil` TRAVA o avanco de turno (o guard recusa
      # virar enquanto alguem nao rolou).
      invocar(dono)

      linha = cs.combat_combatants.find_by(combatable: CombatNpc.find_by(name: 'Diabrete'))
      expect(linha).to be_present
      expect(linha.initiative).to eq(17)
      expect(linha.tie_break_dex).to eq(17)
    end

    it 'ANEXA no fim e NAO mexe no turno corrente' do
      # Reordenar aqui mandaria a mesa de volta ao topo da rodada
      # (`SortInitiativePositionsService` zera `current_turn_index`).
      cs.update!(current_turn_index: 1)

      invocar(dono)

      expect(cs.reload.current_turn_index).to eq(1)
      expect(cs.combat_combatants.order(:position).last.name).to eq('Diabrete')
      expect(comb_pc.reload.position).to eq(0)
    end

    it 'emite combatant_upserted (senao so aparece apos reload)' do
      # `npc_upserted` sozinho nao atualiza o tracker: o reducer de combate
      # escuta `combatant_upserted`.
      eventos = []
      allow(ActionCable.server).to receive(:broadcast) do |_stream, payload|
        eventos << (payload[:event] || payload['event']).to_s
      end

      invocar(dono)

      expect(eventos).to include('combatant_upserted')
    end

    it 'invocar duas vezes nao duplica a linha do tracker' do
      invocar(dono)
      invocar(dono)

      expect(cs.combat_combatants.where(name: 'Diabrete').count).to eq(1)
    end
  end

  describe 'SEM combate ativo' do
    it 'cria o NPC mas nao inventa tracker' do
      invocar(dono)

      expect(response).to have_http_status(:created)
      expect(CombatNpc.find_by(schedule: schedule, name: 'Diabrete')).to be_present
      expect(CombatCombatant.count).to eq(0)
    end
  end

  describe 'idempotencia' do
    it 'dois cliques nao colocam dois familiares no tracker' do
      # Com dois iguais, nenhum e "o" familiar — o jogador nao saberia em qual
      # gastar a reacao.
      invocar(dono)
      invocar(dono)

      expect(response).to have_http_status(:created)
      expect(CombatNpc.where(schedule: schedule, name: 'Diabrete').count).to eq(1)
    end
  end
end
