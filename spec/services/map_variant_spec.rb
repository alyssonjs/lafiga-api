# frozen_string_literal: true

require 'rails_helper'

# O mapa da lista é o ORIGINAL; cada mesa que o joga tem a sua VARIANTE
# (ScheduleBattleMap). Estes exemplos prendem os dois sentidos entre eles.
RSpec.describe MapVariant do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }

  let(:arvore)  { { 'id' => 'obj-1', 'name' => 'Arvore', 'x' => 1, 'y' => 1, 'isObject' => true } }
  let(:heroi)   { { 'id' => 'pc-1', 'name' => 'Heroi', 'x' => 2, 'y' => 2, 'characterId' => '7' } }
  let(:goblin)  { { 'id' => 'npc-1', 'name' => 'Goblin', 'x' => 3, 'y' => 3, 'npcId' => '9' } }

  # Formas que o BattleMap VALIDA — dado torto é recusado na promoção.
  let(:medida) do
    { 'id' => 'm1', 'color' => '#ffffff', 'totalFt' => 15.0, 'ownerUserId' => dm.id,
      'points' => [{ 'x' => 0, 'y' => 0 }, { 'x' => 3, 'y' => 0 }] }
  end
  let(:desenho) do
    { 'id' => 'd1', 'color' => '#ffffff', 'widthPx' => 2, 'ownerUserId' => dm.id,
      'points' => [{ 'x' => 0.0, 'y' => 0.0 }, { 'x' => 1.0, 'y' => 1.0 }] }
  end
  let(:area) do
    { 'id' => 'a1', 'shape' => 'sphere', 'sizeFt' => 20, 'color' => '#ff0000',
      'origin' => { 'col' => 2, 'row' => 2 }, 'cells' => [{ 'col' => 2, 'row' => 2 }] }
  end
  let(:projetil) { { 'id' => 'p1', 'col' => 1, 'row' => 1, 'kind' => 'arrow' } }

  let(:map) do
    BattleMap.create!(
      name: 'Original', width: 10, height: 10, cell_size_px: 32, user_id: dm.id,
      cells: Array.new(10) { Array.new(10, 'empty') },
      tokens: [arvore, heroi],
      fog: Array.new(10) { Array.new(10, false) },
      drawings: [], measurements: [], aoe_placements: [], dropped_projectiles: [],
    )
  end

  # ⚠️ Um grupo só pode ter UMA sessão marcada — cada variante nasce na sua mesa.
  def cria_variante(data: Date.new(2026, 9, 1), **attrs)
    dd = DateDimension.find_by(date: data) || create(:date_dimension, date: data)
    grupo = create(:group, dm_user_id: dm.id)
    sched = Schedule.create!(group_id: grupo.id, date_dimension_id: dd.id, title: 'Sessao')
    ScheduleBattleMap.create!(
      { schedule_id: sched.id, battle_map_id: map.id, position: 0,
        tokens: [], fog: map.fog, measurements: [], drawings: [],
        aoe_placements: [], dropped_projectiles: [] }.merge(attrs),
    )
  end

  describe '.promote!' do
    it 'traz névoa, medidas, desenhos e áreas da variante para o original' do
      nevoa = Array.new(10) { Array.new(10, true) }
      link = cria_variante(fog: nevoa, drawings: [desenho], measurements: [medida], aoe_placements: [area])

      described_class.promote!(map: map, schedule_id: link.schedule_id)
      map.reload

      expect(map.fog).to eq(nevoa)
      expect(map.drawings.first['id']).to eq('d1')
      expect(map.measurements.first['id']).to eq('m1')
      expect(map.aoe_placements.first['id']).to eq('a1')
    end

    it '⚠️ NÃO traz criaturas nem projéteis — são daquela noite, não do tabuleiro' do
      link = cria_variante(tokens: [goblin], dropped_projectiles: [projetil])

      described_class.promote!(map: map, schedule_id: link.schedule_id)
      map.reload

      expect(map.tokens.map { |t| t['id'] }).to contain_exactly('obj-1', 'pc-1')
      expect(map.dropped_projectiles).to be_empty
    end

    it '⚠️ não toca no CENÁRIO do tabuleiro (objeto de sessão já grava no mapa)' do
      link = cria_variante(tokens: [goblin])
      antes = map.scenery_tokens

      described_class.promote!(map: map, schedule_id: link.schedule_id)

      expect(map.reload.scenery_tokens).to eq(antes)
    end

    it 'recusa dado torto em vez de o gravar calado (a validação do mapa vale)' do
      link = cria_variante(drawings: [{ 'id' => 'torto' }])

      expect { described_class.promote!(map: map, schedule_id: link.schedule_id) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(map.reload.drawings).to be_empty
    end
  end

  describe '.reset!' do
    it 'devolve a mesa ao estado de fábrica (a semente de quem abre a 1ª vez)' do
      link = cria_variante(
        tokens: [goblin], fog: Array.new(10) { Array.new(10, true) },
        drawings: [desenho], dropped_projectiles: [projetil],
      )

      described_class.reset!(map: map, schedule_id: link.schedule_id)
      link.reload

      # o original tem o herói como criatura → é o que a mesa recebe
      expect(link.tokens.map { |t| t['id'] }).to eq(['pc-1'])
      expect(link.fog).to eq(map.fog)
      expect(link.drawings).to be_empty
      expect(link.dropped_projectiles).to be_empty
    end

    it 'não altera o ORIGINAL (o sentido é só de volta)' do
      link = cria_variante(tokens: [goblin])
      antes = map.attributes.slice('tokens', 'fog', 'drawings')

      described_class.reset!(map: map, schedule_id: link.schedule_id)

      expect(map.reload.attributes.slice('tokens', 'fog', 'drawings')).to eq(antes)
    end
  end

  describe '.list' do
    it 'marca quem DIFERE do original — é o que decide se vale promover' do
      igual = cria_variante(data: Date.new(2026, 8, 1), tokens: map.creature_tokens)
      mexida = cria_variante(data: Date.new(2026, 9, 1), tokens: [goblin])

      resumo = described_class.list(map).index_by { |v| v[:scheduleId] }

      expect(resumo[igual.schedule_id][:differsFromOriginal]).to be false
      expect(resumo[mexida.schedule_id][:differsFromOriginal]).to be true
      expect(resumo[mexida.schedule_id][:creatureCount]).to eq(1)
    end

    it 'ordena da sessão mais RECENTE para a mais antiga' do
      velha = cria_variante(data: Date.new(2026, 1, 5))
      nova = cria_variante(data: Date.new(2026, 9, 5))

      expect(described_class.list(map).map { |v| v[:scheduleId] }).to eq([nova.schedule_id, velha.schedule_id])
    end
  end
end
