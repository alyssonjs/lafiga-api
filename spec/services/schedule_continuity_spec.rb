# frozen_string_literal: true

require 'rails_helper'

# Sessão nova da mesma mesa RETOMA a anterior — sem duplicar o mapa.
#
# O serviço é de abr/2026 e copiava o mapa inteiro, que era o único jeito de a
# mesa continuar de onde parou. A VERTENTE (ago/2026) passou a fazer isso pela
# camada, e a cópia ficou para trás: os dois conviveram, o antigo ganhou, e a
# página de mapas encheu — oito "Novo Mapa (Copia)" idênticos em produção, um
# por sessão criada, o último em 09/09.
RSpec.describe ScheduleContinuity do
  let(:dono)  { create(:user) }
  let(:grupo) { create(:group, name: 'Mesa Contínua', dm_user_id: dono.id) }

  let(:token_criatura) { { 'id' => 'tk-1', 'npcId' => 'npc-9', 'name' => 'Goblin', 'x' => 1, 'y' => 1 } }
  let(:token_cenario)  { { 'id' => 'ob-1', 'name' => 'Barril', 'x' => 2, 'y' => 2 } }

  let(:mapa) do
    create(
      :battle_map,
      user: dono, group: grupo, name: 'Cripta', width: 5, height: 5,
      cells: Array.new(5) { Array.new(5, 'empty') },
      tokens: [token_criatura, token_cenario],
    )
  end

  # Uma mesa só pode ter UMA sessão marcada: as passadas ficam concluídas.
  def sessao(dia, status: :completed, mapa_id: nil)
    create(
      :schedule,
      group: grupo,
      status: status,
      battle_map_id: mapa_id,
      date_dimension: create(:date_dimension, date: Date.parse(dia)),
    )
  end

  describe 'o mapa é REFERENCIADO, não copiado' do
    it '⚠️ criar a sessão seguinte NÃO cria um BattleMap' do
      anterior = sessao('2026-09-01', mapa_id: mapa.id)
      MapBranch.ensure!(schedule: anterior, map: mapa)
      nova = sessao('2026-09-08', status: :waiting)

      expect { described_class.copy_from_prior_session!(nova, current_user: dono) }
        .not_to change(BattleMap, :count)
    end

    it 'a sessão nova aponta para o MESMO mapa da anterior' do
      anterior = sessao('2026-09-01', mapa_id: mapa.id)
      MapBranch.ensure!(schedule: anterior, map: mapa)
      nova = sessao('2026-09-08', status: :waiting)

      described_class.copy_from_prior_session!(nova, current_user: dono)
      expect(nova.reload.battle_map_id).to eq(mapa.id)
    end

    it 'e ganha a camada da vertente, semeada pela sessão ANTERIOR' do
      # É o que a cópia profunda fazia por acidente: carregar o estado da mesa.
      # Agora vem da herança, que é para isso que existe.
      anterior = sessao('2026-09-01', mapa_id: mapa.id)
      camada_ant = MapBranch.ensure!(schedule: anterior, map: mapa)
      camada_ant.update!(tokens: [token_criatura.merge('x' => 4, 'y' => 4)])

      nova = sessao('2026-09-08', status: :waiting)
      described_class.copy_from_prior_session!(nova, current_user: dono)

      camada = ScheduleBattleMap.find_by(schedule_id: nova.id, battle_map_id: mapa.id)
      expect(camada).to be_present
      expect(camada.tokens.first['x']).to eq(4)   # herdou a posição da mesa, não a de fábrica
    end
  end

  describe 'os limites de sempre, preservados' do
    it 'sessão que JÁ tem mapa não é mexida' do
      outro = create(:battle_map, user: dono, group: grupo, name: 'Outro',
                                  width: 5, height: 5, cells: Array.new(5) { Array.new(5, 'empty') })
      sessao('2026-09-01', mapa_id: mapa.id)
      nova = sessao('2026-09-08', status: :waiting, mapa_id: outro.id)

      described_class.copy_from_prior_session!(nova, current_user: dono)
      expect(nova.reload.battle_map_id).to eq(outro.id)
    end

    it 'sem sessão anterior, não há o que retomar' do
      unica = sessao('2026-09-08', status: :waiting)
      expect { described_class.copy_from_prior_session!(unica, current_user: dono) }
        .not_to change(BattleMap, :count)
      expect(unica.reload.battle_map_id).to be_nil
    end

    it 'sessão anterior SEM mapa não inventa vínculo' do
      sessao('2026-09-01')
      nova = sessao('2026-09-08', status: :waiting)

      described_class.copy_from_prior_session!(nova, current_user: dono)
      expect(nova.reload.battle_map_id).to be_nil
    end
  end

  # ===== NPCs ao INICIAR (o caso de 21/09) =====
  #
  # Sessão se cria com antecedência. A #104 foi criada às 11:50; o Mestre montou
  # o exército na sessão anterior à noite e iniciou a #104 às 21:26 — como os
  # NPCs eram copiados na criação, nada veio, e ele recriou 109 NPCs à mão.
  describe 'os NPCs vêm quando a sessão COMEÇA' do
    def camada(sessao) = ScheduleBattleMap.find_by(schedule_id: sessao.id, battle_map_id: mapa.id)
    def token_do(npc, id, x: 1) = { 'id' => id, 'npcId' => "npc-#{npc.id}", 'name' => npc.name, 'x' => x, 'y' => 1 }

    it '⚠️ criar a sessão NÃO copia os NPCs — a anterior pode nem ter sido jogada' do
      anterior = sessao('2026-09-10', mapa_id: mapa.id)
      create(:combat_npc, schedule: anterior, name: 'Orc')
      nova = sessao('2026-09-21', status: :waiting)

      expect { described_class.copy_from_prior_session!(nova, current_user: dono) }
        .not_to change(CombatNpc, :count)
    end

    it '⚠️ o exército montado na anterior DEPOIS de criar a nova vem ao iniciar, com os tokens' do
      anterior = sessao('2026-09-10', mapa_id: mapa.id)
      MapBranch.ensure!(schedule: anterior, map: mapa)
      nova = sessao('2026-09-21', status: :waiting)
      described_class.copy_from_prior_session!(nova, current_user: dono) # 11:50

      # 19:36 — o Mestre monta o exército na anterior
      capitao = create(:combat_npc, schedule: anterior, name: 'Capitão do Exercito Anão', hp_current: 30)
      cavalaria = create(:combat_npc, schedule: anterior, name: 'Cavalaria Anão')
      camada(anterior).update!(tokens: [token_do(capitao, 'tk-cap'), token_do(cavalaria, 'tk-cav', x: 3)])

      described_class.continue_on_start!(nova.reload) # 21:26

      copias = nova.combat_npcs.order(:id)
      expect(copias.map(&:name)).to eq(['Capitão do Exercito Anão', 'Cavalaria Anão'])
      expect(copias.first.hp_current).to eq(30)
      expect(copias.map(&:source_npc_id)).to eq([capitao.id, cavalaria.id])
      # e os tokens apontam para as CÓPIAS desta sessão, não para os NPCs da anterior
      expect(camada(nova).tokens.map { |t| t['npcId'] }).to match_array(copias.map { |n| "npc-#{n.id}" })
    end

    it 'token herdado com a camada é REAPONTADO, não duplicado' do
      anterior = sessao('2026-09-10', mapa_id: mapa.id)
      orc = create(:combat_npc, schedule: anterior, name: 'Orc')
      MapBranch.ensure!(schedule: anterior, map: mapa).update!(tokens: [token_do(orc, 'tk-orc')])
      nova = sessao('2026-09-21', status: :waiting)
      described_class.copy_from_prior_session!(nova, current_user: dono) # herda o token com o id antigo

      described_class.continue_on_start!(nova.reload)

      tokens = camada(nova).tokens
      expect(tokens.size).to eq(1)
      expect(tokens.first['npcId']).to eq("npc-#{nova.combat_npcs.first.id}")
    end

    it 'o token do NPC que o Mestre TIROU da anterior não fica órfão na nova; o do PC fica' do
      anterior = sessao('2026-09-10', mapa_id: mapa.id)
      orc = create(:combat_npc, schedule: anterior, name: 'Orc')
      goblin = create(:combat_npc, schedule: anterior, name: 'Goblin')
      pc = { 'id' => 'tk-pc', 'characterId' => '42', 'name' => 'Thorin', 'x' => 0, 'y' => 0 }
      MapBranch.ensure!(schedule: anterior, map: mapa)
               .update!(tokens: [token_do(orc, 'tk-orc'), token_do(goblin, 'tk-gob'), pc])
      nova = sessao('2026-09-21', status: :waiting)
      described_class.copy_from_prior_session!(nova, current_user: dono)

      # o goblin morre e sai da anterior depois de a nova ser criada
      goblin.destroy!
      camada(anterior).update!(tokens: [token_do(orc, 'tk-orc'), pc])

      described_class.continue_on_start!(nova.reload)

      ids = camada(nova).tokens.map { |t| t['id'] }
      expect(ids).to match_array(%w[tk-orc tk-pc])
      expect(camada(nova).tokens.find { |t| t['id'] == 'tk-pc' }).to eq(pc)
    end

    it 'iniciar de novo não duplica — a sessão já tem os NPCs dela' do
      anterior = sessao('2026-09-10')
      create(:combat_npc, schedule: anterior, name: 'Orc')
      nova = sessao('2026-09-21', status: :waiting)

      described_class.continue_on_start!(nova)
      expect { described_class.continue_on_start!(nova.reload) }.not_to change(CombatNpc, :count)
    end

    it 'sessão que JÁ tem NPCs dela não é mexida — o elenco é do Mestre' do
      anterior = sessao('2026-09-10', mapa_id: mapa.id)
      create(:combat_npc, schedule: anterior, name: 'Orc')
      nova = sessao('2026-09-21', status: :waiting)
      create(:combat_npc, schedule: nova, name: 'Dragão preparado')

      expect { described_class.continue_on_start!(nova) }.not_to change(CombatNpc, :count)
      expect(nova.combat_npcs.pluck(:name)).to eq(['Dragão preparado'])
    end

    it 'sessão CANCELADA no meio não é a anterior' do
      jogada = sessao('2026-09-10')
      create(:combat_npc, schedule: jogada, name: 'Orc da jogada')
      cancelada = sessao('2026-09-15', status: :cancelled)
      create(:combat_npc, schedule: cancelada, name: 'Orc da cancelada')
      nova = sessao('2026-09-21', status: :waiting)

      described_class.continue_on_start!(nova)

      expect(nova.combat_npcs.pluck(:name)).to eq(['Orc da jogada'])
    end

    it 'sessão FUTURA não é a anterior' do
      create(:combat_npc, schedule: sessao('2026-09-10'), name: 'Orc do passado')
      # (concluída só porque a mesa não pode ter duas sessões MARCADAS; o que
      # importa aqui é a data, que vem DEPOIS da nova)
      create(:combat_npc, schedule: sessao('2026-09-28'), name: 'Orc do futuro')
      nova = sessao('2026-09-21', status: :waiting)

      expect(described_class.prior_session_for(nova).date_dimension.date).to eq(Date.parse('2026-09-10'))
      described_class.continue_on_start!(nova)
      expect(nova.combat_npcs.pluck(:name)).to eq(['Orc do passado'])
    end
  end
end
