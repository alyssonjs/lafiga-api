# frozen_string_literal: true

require 'rails_helper'

# Cobre Gap G3.3 do relatorio de auditoria de steps:
# BackgroundStepService nao tinha invalidate!, entao trocar de background
# mantinha indevidamente backgroundToolChoices/LanguageChoices e os tracos
# (PersonalityTraits/Ideals/Bonds/Flaws) do background anterior.
RSpec.describe CharacterDraftSteps::BackgroundStepService do
  let(:user) { create(:user) }

  def make_char(draft = {})
    create(:character, user: user, status: :draft, draft_data: {
      '_version' => 1,
      '_bgId' => 1,
      '_bgName' => 'Soldado',
      'selectedBackground' => { 'id' => 1, 'name' => 'Soldado' },
      'backgroundToolChoices' => ['Jogo de cartas'],
      'backgroundLanguageChoices' => [],
      'backgroundPersonalityTraits' => ['Mantenho a postura'],
      'backgroundIdeals' => ['Disciplina'],
      'backgroundBonds' => ['Meu pelotao'],
      'backgroundFlaws' => ['Obedeco ordens']
    }.merge(draft))
  end

  describe 'G3.3 — invalidate ao trocar background' do
    it 'limpa choices quando troca para outro bg sem reenviar (force=true)' do
      char = make_char
      svc = described_class.new(
        character: char, force: true,
        data: {
          'backgroundId' => 2,
          'backgroundName' => 'Erudito'
        }
      )
      result = svc.call
      d = result.draft_data

      expect(d['_bgId']).to eq(2)
      expect(d['backgroundToolChoices']).to eq([])
      expect(d['backgroundLanguageChoices']).to eq([])
      expect(d['backgroundPersonalityTraits']).to eq([])
      expect(d['backgroundIdeals']).to eq([])
      expect(d['backgroundBonds']).to eq([])
      expect(d['backgroundFlaws']).to eq([])

      expect(result.cleared_keys).to include(
        'backgroundToolChoices', 'backgroundLanguageChoices',
        'backgroundPersonalityTraits', 'backgroundIdeals',
        'backgroundBonds', 'backgroundFlaws'
      )
    end

    it 'requires_confirmation quando muda de um bg existente para outro (sem force)' do
      char = make_char
      svc = described_class.new(
        character: char,
        data: { 'backgroundId' => 2, 'backgroundName' => 'Erudito' }
      )
      result = svc.call

      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:reason]).to include('Trocar de antecedente')
    end

    it 'PRESERVA choices quando vieram no MESMO PATCH (atomico)' do
      char = make_char
      svc = described_class.new(
        character: char, force: true,
        data: {
          'backgroundId' => 2, 'backgroundName' => 'Erudito',
          'backgroundPersonalityTraits' => ['Curioso'],
          'backgroundIdeals' => ['Conhecimento']
        }
      )
      result = svc.call
      d = result.draft_data

      expect(d['backgroundPersonalityTraits']).to eq(['Curioso'])
      expect(d['backgroundIdeals']).to eq(['Conhecimento'])
      # As outras keys NAO foram enviadas no PATCH e o bg mudou -> zeradas
      expect(d['backgroundBonds']).to eq([])
      expect(d['backgroundFlaws']).to eq([])
    end

    it 'NAO limpa quando o background NAO mudou (apenas atualiza traits)' do
      char = make_char
      svc = described_class.new(
        character: char,
        data: { 'backgroundIdeals' => ['Honra'] }
      )
      result = svc.call
      d = result.draft_data

      expect(d['_bgId']).to eq(1)
      expect(d['backgroundIdeals']).to eq(['Honra'])
      expect(d['backgroundPersonalityTraits']).to eq(['Mantenho a postura']) # preservado
      expect(d['backgroundBonds']).to eq(['Meu pelotao']) # preservado
      expect(result.cleared_keys).to be_empty
      expect(result.requires_confirmation).to be_nil
    end

    it 'NAO requer confirmation quando bg PREV era nil (primeira selecao)' do
      char = create(:character, user: user, status: :draft, draft_data: { '_version' => 1 })
      svc = described_class.new(
        character: char,
        data: { 'backgroundId' => 1, 'backgroundName' => 'Soldado' }
      )
      result = svc.call
      expect(result.requires_confirmation).to be_nil
      expect(result.draft_data['_bgId']).to eq(1)
    end
  end
end
