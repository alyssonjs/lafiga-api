# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapSessionLayer do
  let(:dm)     { create(:user, role: Role.find_by(name: 'DM') || create(:role, name: 'DM')) }
  let(:group)  { create(:group, dm_user: dm) }
  let(:sessao) { create(:schedule, group: group, created_by_user: dm) }

  let(:cenario) { { 'id' => 'obj-1', 'assetId' => 7 } }
  let(:heroi)   { { 'id' => 'tk-1', 'characterId' => '101' } }
  let(:map)     { create(:battle_map, user: dm, tokens: [cenario]) }
  let!(:link)   { ScheduleBattleMap.create!(schedule: sessao, battle_map: map, position: 0, tokens: [heroi]) }

  def com_sessao = described_class.for(map: map, schedule_id: sessao.id)
  def sem_sessao = described_class.for(map: map, schedule_id: nil)

  describe 'leitura' do
    it 'com sessao devolve cenario do mapa + criaturas da mesa' do
      expect(com_sessao.tokens.map { |t| t['id'] }).to contain_exactly('obj-1', 'tk-1')
    end

    it 'sem sessao devolve o mapa cru (Map Builder edita o tabuleiro)' do
      expect(sem_sessao.tokens.map { |t| t['id'] }).to contain_exactly('obj-1')
      expect(sem_sessao).not_to be_session_scoped
    end
  end

  describe 'escrita' do
    it 'criatura vai para a MESA, sem tocar no mapa' do
      outro = { 'id' => 'tk-2', 'characterId' => '202' }
      com_sessao.update!(tokens: [cenario, heroi, outro])

      expect(link.reload.tokens.map { |t| t['id'] }).to contain_exactly('tk-1', 'tk-2')
      expect(map.reload.tokens.map { |t| t['id'] }).to contain_exactly('obj-1')
    end

    it 'REGRESSAO: mover criatura numa sessao nao muda a outra' do
      sessao_b = create(:schedule, group: create(:group, dm_user: dm), created_by_user: dm)
      link_b = ScheduleBattleMap.create!(schedule: sessao_b, battle_map: map, position: 0,
                                         tokens: [{ 'id' => 'tk-b', 'characterId' => '999' }])

      com_sessao.update!(tokens: [cenario, heroi.merge('x' => 9)])

      expect(link_b.reload.tokens.map { |t| t['id'] }).to contain_exactly('tk-b')
    end

    it 'cenario arrastado numa sessao muda o TABULEIRO (vale para todas)' do
      com_sessao.update!(tokens: [cenario.merge('x' => 5), heroi])

      expect(map.reload.tokens.first['x']).to eq(5)
    end

    # O mapa da factory e 5x5; a nevoa precisa ter esse formato nos dois lados.
    let(:nevoa) { Array.new(5) { Array.new(5, false) } }

    it 'nevoa fica na mesa' do
      com_sessao.update!(fog: nevoa)

      expect(link.reload.fog.size).to eq(5)
      expect(map.reload.fog).to be_nil
    end

    it 'sem sessao grava no mapa, como antes' do
      sem_sessao.update!(fog: nevoa)

      expect(map.reload.fog.size).to eq(5)
    end

    it 'a camada recusa nevoa torta, igual ao mapa' do
      expect { com_sessao.update!(fog: [[true]]) }
        .to raise_error(ActiveRecord::RecordInvalid, /altura do mapa/)
    end

    it 'recusa campo que nao e de mesa (paredes sao do tabuleiro)' do
      expect { com_sessao.update!(walls: []) }.to raise_error(ArgumentError, /walls/)
    end
  end
end
