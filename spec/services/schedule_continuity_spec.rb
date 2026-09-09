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
end
