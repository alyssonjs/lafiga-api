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

    it 'le a velocidade do TEXTO do companion' do
      # O companion guarda "20 ft, voo 40 ft"; o NPC guarda um inteiro.
      invocar(dono)
      expect(CombatNpc.find_by(schedule: schedule, name: 'Diabrete').speed).to eq(20)
    end

    it 'ficha com hpCurrent 0 invoca com PV CHEIO, nao morto' do
      sheet.update!(companions: [familiar.merge('hpCurrent' => 0)])
      invocar(dono)
      expect(CombatNpc.find_by(schedule: schedule, name: 'Diabrete').hp_current).to eq(10)
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
