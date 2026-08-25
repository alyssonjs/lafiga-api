# frozen_string_literal: true

require 'rails_helper'

# Um mapa numa sessão é uma VERTENTE do original, daquele grupo, que atravessa
# as sessões da mesa:
#   - a primeira vez que a mesa adiciona o mapa, recebe o estado de fábrica;
#   - a sessão seguinte herda a ANTERIOR, não o original;
#   - outra mesa no mesmo mapa parte do original, sem ver o ramo alheio.
RSpec.describe MapBranch do
  let(:dono)  { create(:user) }
  let(:grupo) { create(:group, name: 'Mesa Ramo', dm_user_id: dono.id) }
  let(:outra_mesa) { create(:group, name: 'Outra Mesa', dm_user_id: dono.id) }

  let(:token_criatura) { { 'id' => 'tk-1', 'npcId' => 'npc-9', 'name' => 'Goblin', 'x' => 1, 'y' => 1 } }
  let(:token_cenario)  { { 'id' => 'ob-1', 'name' => 'Barril', 'x' => 2, 'y' => 2 } }
  # Formas válidas pelo modelo — um stub torto reprova na validação, não na regra.
  let(:aoe) do
    [{ 'id' => 'aoe-1', 'shape' => 'sphere', 'sizeFt' => 20.0, 'color' => '#f00',
       'origin' => { 'col' => 1, 'row' => 1 }, 'cells' => [{ 'col' => 1, 'row' => 1 }] }]
  end
  def desenho(id) = { 'id' => id, 'color' => '#fff', 'widthPx' => 2, 'ownerUserId' => 1,
                      'points' => [{ 'x' => 0.0, 'y' => 0.0 }, { 'x' => 1.0, 'y' => 1.0 }] }
  def medida(id) = { 'id' => id, 'color' => '#0f0', 'totalFt' => 10.0, 'ownerUserId' => 1,
                     'points' => [{ 'x' => 0, 'y' => 0 }, { 'x' => 1, 'y' => 1 }] }

  let(:mapa) do
    create(
      :battle_map,
      user: dono, group: grupo, width: 5, height: 5,
      cells: Array.new(5) { Array.new(5, 'empty') },
      tokens: [token_criatura, token_cenario],
      aoe_placements: aoe,
      drawings: [desenho('d1')],
      measurements: [medida('m1')],
    )
  end

  def sessao(dia, group: grupo)
    # Uma mesa só pode ter UMA sessão marcada: as do passado ficam concluídas.
    create(
      :schedule,
      group: group,
      status: :completed,
      date_dimension: create(:date_dimension, date: Date.parse(dia)),
    )
  end

  describe 'primeira sessão da mesa com o mapa' do
    it 'recebe o estado do ORIGINAL' do
      link = described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)

      expect(link.aoe_placements).to eq(aoe)
      expect(link.drawings.size).to eq(1)
      expect(link.measurements.size).to eq(1)
    end

    it 'REGRESSAO: o CENÁRIO não é copiado — apareceria duas vezes' do
      # `MapSessionLayer#tokens` soma cenário do mapa + tokens da camada.
      link = described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)

      expect(link.tokens.map { |t| t['id'] }).to eq(['tk-1'])
      camada = MapSessionLayer.for(map: mapa.reload, schedule_id: link.schedule_id)
      expect(camada.tokens.map { |t| t['id'] }).to match_array(%w[ob-1 tk-1])
    end
  end

  describe 'instrumentação — o post-mortem de 24/08 foi impossível sem isto' do
    it 'loga a criação da camada com a ORIGEM da semente' do
      logs = []
      allow(Rails.logger).to receive(:info) { |m| logs << m }

      described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)

      linha = logs.grep(/"kind":"map_branch"/).last
      expect(linha).to include('"event":"layer_created"')
      expect(linha).to include('"seed_source":"original"')
      expect(linha).to include('"seed_tokens":1')
    end

    it 'AVISA quando a camada nasce vazia num mapa que TEM criaturas' do
      # É legal pelo design — a sessão anterior pode ter limpado o tabuleiro —
      # mas é exatamente a anomalia da sessão 71, e merece saltar num grep.
      s1 = sessao('2026-08-01')
      primeira = described_class.ensure!(schedule: s1, map: mapa)
      primeira.update!(tokens: [])

      avisos = []
      allow(Rails.logger).to receive(:warn) { |m| avisos << m }

      described_class.ensure!(schedule: sessao('2026-08-08'), map: mapa)

      linha = avisos.grep(/"kind":"map_branch"/).last
      expect(linha).to include('"event":"layer_created_empty_while_map_has_creatures"')
      expect(linha).to include(%("seed_source":"schedule_#{s1.id}"))
    end
  end

  describe 'sessão seguinte da mesma mesa' do
    it 'REGRESSAO: herda a ANTERIOR, não o original' do
      s1 = sessao('2026-08-01')
      primeira = described_class.ensure!(schedule: s1, map: mapa)
      primeira.update!(
        tokens: [token_criatura.merge('x' => 9)],
        aoe_placements: [],
        drawings: [desenho('d1'), desenho('d2')],
      )

      segunda = described_class.ensure!(schedule: sessao('2026-08-08'), map: mapa)

      expect(segunda.tokens.first['x']).to eq(9)      # onde a mesa parou
      expect(segunda.aoe_placements).to eq([])        # e NÃO os 'aoe' do original
      expect(segunda.drawings.size).to eq(2)
    end

    it '"anterior" é pela DATA da sessão, não pela linha tocada por último' do
      antiga = described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)
      recente = described_class.ensure!(schedule: sessao('2026-08-08'), map: mapa)
      recente.update!(drawings: [desenho('recente')])
      antiga.update!(drawings: [desenho('antiga')]) # tocada DEPOIS, mas é anterior

      nova = described_class.ensure!(schedule: sessao('2026-08-15'), map: mapa)

      expect(nova.drawings.first['id']).to eq('recente')
    end

    it 'herda os SEIS campos de mesa' do
      s1 = sessao('2026-08-01')
      described_class.ensure!(schedule: s1, map: mapa).update!(
        tokens: [token_criatura], fog: Array.new(5) { Array.new(5, true) },
        measurements: [medida('m9')], drawings: [desenho('d9')],
        aoe_placements: [aoe.first.merge('id' => 'a9')], dropped_projectiles: [{ 'id' => 'p9' }],
      )

      nova = described_class.ensure!(schedule: sessao('2026-08-08'), map: mapa)

      expect(nova.fog).to eq(Array.new(5) { Array.new(5, true) })
      expect(nova.measurements.first['id']).to eq('m9')
      expect(nova.dropped_projectiles.first['id']).to eq('p9')
    end
  end

  describe 'isolamento' do
    it 'REGRESSAO: OUTRA mesa parte do original, sem ver o ramo alheio' do
      described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)
        .update!(drawings: [desenho('segredo-da-mesa-1')])

      alheia = described_class.ensure!(schedule: sessao('2026-08-05', group: outra_mesa), map: mapa)

      expect(alheia.drawings.map { |d| d['id'] }).to eq(['d1'])
    end

    it 'REGRESSAO: mexer na sessão NAO muda o mapa original' do
      link = described_class.ensure!(schedule: sessao('2026-08-01'), map: mapa)
      link.update!(aoe_placements: [], drawings: [])

      expect(mapa.reload.aoe_placements).to eq(aoe)
      expect(mapa.drawings.size).to eq(1)
    end
  end

  describe 'idempotência' do
    it 'chamar de novo devolve a camada existente, sem reiniciar o estado' do
      s = sessao('2026-08-01')
      described_class.ensure!(schedule: s, map: mapa).update!(drawings: [])

      de_novo = described_class.ensure!(schedule: s, map: mapa)

      expect(de_novo.drawings).to eq([])
      expect(ScheduleBattleMap.where(schedule_id: s.id, battle_map_id: mapa.id).count).to eq(1)
    end
  end
end
