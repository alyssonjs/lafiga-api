# frozen_string_literal: true

require 'rails_helper'

# Descoberta server-side dos Bardos que podem tocar o Acorde Distrativo.
#
# O foco destas specs é a fronteira ALVO × ECONOMIA: quem nem podia ser
# oferecido some em silêncio (senão todo combatente viraria log a cada
# conjuração), mas quem estava apto e caiu só por falta de recurso precisa
# aparecer em `blocked` — foi o silêncio desse caso que pareceu bug em 19/08,
# com o Bardo de 5/5 dados gastos.
RSpec.describe Combat::DistractingChordCandidates do
  # O modelo valida o shape completo da gaveta de economia.
  ACOES = { 'action' => false, 'bonus_action' => false, 'movement' => false }.freeze

  subject(:evaluation) do
    described_class.evaluate(schedule: schedule, combat_state: cs, caster: caster_cc)
  end

  let(:schedule) { create(:schedule) }
  let(:cs) { create(:combat_state, schedule: schedule, round: 3) }
  let(:caster_cc) do
    create(:combat_combatant, :npc, combat_state: cs, combatable: create(:combat_npc, schedule: schedule), position: 0)
  end

  it 'sem conjurador, sem estado ou sem sessão devolve listas vazias' do
    expect(described_class.evaluate(schedule: nil, combat_state: cs, caster: caster_cc))
      .to eq(eligible: [], blocked: [])
    expect(described_class.evaluate(schedule: schedule, combat_state: cs, caster: nil))
      .to eq(eligible: [], blocked: [])
  end

  it 'o próprio conjurador nunca é candidato a se interromper' do
    expect(evaluation[:eligible].map { |c| c[:character_id] }).not_to include(caster_cc.combatable_id.to_s)
  end

  it 'quem não é Bardo do Virtuosismo não vira aviso — sairia log a cada conjuração' do
    outro = create(:character, group: schedule.group)
    create(:combat_combatant, :pc, combat_state: cs, combatable: outro, position: 1)
    expect(evaluation[:blocked]).to be_empty
  end

  # ⚠️ Regra da mesa: a reação recarrega na VIRADA DA RODADA. A flag crua
  # `actions_used.reaction` só é limpa no turno DO REATOR, então entre a virada e
  # a vez dele ela fica presa em `true` — e quem age ANTES dele na iniciativa
  # (o conjurador!) via o Bardo como "já reagiu" a rodada inteira. Foi o bug do
  # Ainor (18/08) reintroduzido no servidor.
  describe 'recarga da reação na virada da rodada' do
    let(:bardo) { create(:character, group: schedule.group) }
    let!(:bardo_cc) do
      cc = create(:combat_combatant, :pc, combat_state: cs, combatable: bardo, position: 1)
      cc.update!(actions_used: ACOES.merge('reaction' => true), turn_state: { 'reactionUsedRound' => 2 })
      cc
    end
    let(:svc) { described_class.new(schedule: schedule, combat_state: cs, caster: caster_cc) }

    it 'carimbo de rodada PASSADA libera, mesmo com a flag crua ainda true' do
      # cs.round == 3, carimbo == 2.
      expect(svc.send(:reaction_available?, bardo_cc.reload)).to be true
    end

    it 'carimbo da rodada ATUAL bloqueia', :aggregate_failures do
      bardo_cc.update!(turn_state: { 'reactionUsedRound' => 3 })
      expect(svc.send(:reaction_available?, bardo_cc.reload)).to be false
    end

    it 'flag falsa libera sempre — nem precisa de carimbo' do
      bardo_cc.update!(actions_used: ACOES.merge('reaction' => false), turn_state: {})
      expect(svc.send(:reaction_available?, bardo_cc.reload)).to be true
    end

    it 'flag true SEM carimbo bloqueia (não dá para datar o uso)' do
      bardo_cc.update!(actions_used: ACOES.merge('reaction' => true), turn_state: {})
      expect(svc.send(:reaction_available?, bardo_cc.reload)).to be false
    end
  end
end
