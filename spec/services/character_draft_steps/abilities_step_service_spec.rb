# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix ZX1 do segundo audit: PATCH parcial em creation zerava atributos
# nao enviados para 8 (default point-buy) — divergente de AbilitiesEditService
# que faz merge por chave. Cliente que enviasse so `{ str: 15 }` perdia DEX/CON/
# INT/WIS/CHA salvos previamente.
RSpec.describe CharacterDraftSteps::AbilitiesStepService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :draft) }

  describe '#apply!' do
    context 'PATCH parcial (ZX1 — paridade com edit)' do
      before do
        character.update!(draft_data: {
          'abilityScores' => { 'str' => 15, 'dex' => 14, 'con' => 13, 'int' => 12, 'wis' => 10, 'cha' => 8 }
        })
      end

      it 'preserva atributos NAO enviados no PATCH' do
        svc = described_class.new(character: character, data: { 'abilityScores' => { 'str' => 16 } })
        result = svc.call

        scores = result.draft_data['abilityScores']
        expect(scores['str']).to eq(16) # alterado
        expect(scores['dex']).to eq(14) # preservado
        expect(scores['con']).to eq(13) # preservado
        expect(scores['int']).to eq(12) # preservado
        expect(scores['wis']).to eq(10) # preservado
        expect(scores['cha']).to eq(8)  # preservado
      end

      it 'aceita chaves simbol ou string' do
        svc = described_class.new(character: character, data: { 'abilityScores' => { dex: 15 } })
        result = svc.call

        expect(result.draft_data['abilityScores']['dex']).to eq(15)
        expect(result.draft_data['abilityScores']['str']).to eq(15) # preservado
      end

      it 'PATCH atomico com varias chaves substitui as 6 sem afetar previa' do
        svc = described_class.new(character: character, data: {
          'abilityScores' => { 'str' => 8, 'dex' => 14, 'con' => 14, 'int' => 12, 'wis' => 10, 'cha' => 15 }
        })
        result = svc.call

        scores = result.draft_data['abilityScores']
        expect(scores).to eq('str' => 8, 'dex' => 14, 'con' => 14, 'int' => 12, 'wis' => 10, 'cha' => 15)
      end
    end

    context 'creation fresh (sem prev)' do
      it 'preenche atributos ausentes com POINT_BUY_MIN' do
        svc = described_class.new(character: character, data: { 'abilityScores' => { 'str' => 15 } })
        result = svc.call

        scores = result.draft_data['abilityScores']
        expect(scores['str']).to eq(15)
        expect(scores['dex']).to eq(8)
        expect(scores['con']).to eq(8)
        expect(scores['int']).to eq(8)
        expect(scores['wis']).to eq(8)
        expect(scores['cha']).to eq(8)
      end

      it 'aceita PATCH sem abilityScores como no-op (mantem default 8)' do
        svc = described_class.new(character: character, data: {})
        result = svc.call

        expect(result.draft_data['abilityScores']).to eq(
          'str' => 8, 'dex' => 8, 'con' => 8, 'int' => 8, 'wis' => 8, 'cha' => 8
        )
      end
    end

    context 'limites' do
      it 'clampa para HARD_MAX (20)' do
        svc = described_class.new(character: character, data: { 'abilityScores' => { 'str' => 25 } })
        result = svc.call
        expect(result.draft_data['abilityScores']['str']).to eq(20)
      end

      it 'clampa para POINT_BUY_MIN (8)' do
        svc = described_class.new(character: character, data: { 'abilityScores' => { 'str' => 5 } })
        result = svc.call
        expect(result.draft_data['abilityScores']['str']).to eq(8)
      end
    end

    context 'point-buy validation' do
      it 'NAO emite warn quando total = 27' do
        svc = described_class.new(character: character, data: {
          'abilityScores' => { 'str' => 15, 'dex' => 14, 'con' => 13, 'int' => 12, 'wis' => 10, 'cha' => 8 }
        })
        result = svc.call
        expect(result.warnings).to be_empty
      end

      it 'emite warn quando total != 27' do
        # 14+13+12+11+10+9 = 7+5+4+3+2+1 = 22 (todas <=15 entram no point-buy check)
        svc = described_class.new(character: character, data: {
          'abilityScores' => { 'str' => 14, 'dex' => 13, 'con' => 12, 'int' => 11, 'wis' => 10, 'cha' => 9 }
        })
        result = svc.call
        expect(result.warnings.first).to include('point-buy total != 27')
      end
    end
  end
end
