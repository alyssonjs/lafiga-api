# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterDraftSteps::RaceStepService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :draft) }

  it 'merges raceId/raceChoices into draft_data' do
    svc = described_class.new(character: character, data: {
      'raceId' => '7',
      'raceChoices' => { 'chosenLanguages' => ['Anão'] }
    })
    result = svc.call

    expect(result.draft_data['_raceId']).to eq('7')
    expect(result.draft_data.dig('selectedRace', 'id')).to eq('7')
    expect(result.draft_data['raceChoices']).to eq('chosenLanguages' => ['Anão'])
  end

  it 'clears raceChoices/subrace/feat when race changes' do
    character.update!(draft_data: {
      '_raceId' => '7',
      'selectedRace' => { 'id' => '7' },
      'selectedSubrace' => { 'id' => '12' },
      'raceChoices' => { 'chosenSkills' => ['Atletismo'] },
      '_featId' => 'feat-magic-initiate'
    })
    svc = described_class.new(character: character, data: { 'raceId' => '8', 'raceChoices' => {} }, force: true)
    result = svc.call

    expect(result.draft_data['raceChoices']).to eq({})
    expect(result.draft_data['selectedSubrace']).to be_nil
    expect(result.draft_data['_featId']).to be_nil
    expect(result.cleared_keys).to include('raceChoices', 'selectedSubrace', 'selectedFeat')
  end

  it 'flags requires_confirmation on destructive race switch without force' do
    character.update!(draft_data: {
      '_raceId' => '7', 'selectedRace' => { 'id' => '7' }, '_featId' => 'feat-tough'
    })
    svc = described_class.new(character: character, data: { 'raceId' => '8' })
    result = svc.call

    expect(result.requires_confirmation).to be_present
    expect(result.requires_confirmation[:cleared]).to include('selectedFeat')
  end

  it 'persists gender into avatarCustomization for the race step picker (ZS7 normalizes PT->EN)' do
    svc = described_class.new(character: character, data: { 'raceId' => '7', 'gender' => 'feminino' })
    result = svc.call
    expect(result.draft_data.dig('avatarCustomization', 'gender')).to eq('female')
  end

  it 'ZS7 — normaliza variantes (M, masc, masculino, Male) para `male`' do
    %w[M m masc Masc masculino MASCULINO Male MALE homem].each do |variant|
      svc = described_class.new(character: character, data: { 'raceId' => '7', 'gender' => variant })
      result = svc.call
      expect(result.draft_data.dig('avatarCustomization', 'gender')).to eq('male'),
        "esperava 'male' para variante #{variant.inspect}"
    end
  end

  describe 'G2.4 — clear condicional ao prev ter conteudo' do
    it 'NAO reporta cleared para campos que prev nao tinha (anão -> halfling sem feat antes)' do
      character.update!(draft_data: {
        '_raceId' => '7', 'selectedRace' => { 'id' => '7' }
        # SEM raceChoices, sem selectedSubrace, sem selectedFeat
      })
      svc = described_class.new(character: character, data: { 'raceId' => '8' })
      result = svc.call

      # prev nao tinha nada destes -> nada a "perder" -> requires_confirmation nil
      expect(result.cleared_keys).to be_empty
      expect(result.requires_confirmation).to be_nil
    end

    it 'so reporta cleared para campos que prev TINHA conteudo' do
      character.update!(draft_data: {
        '_raceId' => '7', 'selectedRace' => { 'id' => '7' },
        'selectedSubrace' => { 'id' => '12' }
        # SEM raceChoices, SEM selectedFeat
      })
      svc = described_class.new(character: character, data: { 'raceId' => '8' })
      result = svc.call

      expect(result.cleared_keys).to include('selectedSubrace')
      expect(result.cleared_keys).not_to include('raceChoices')
      expect(result.cleared_keys).not_to include('selectedFeat')
      # NAO precisa confirmation porque selectedFeat (o unico com confirm: destructive)
      # nao foi reportado.
      expect(result.requires_confirmation).to be_nil
    end

    it 'reporta cleared p/ raceChoices+subrace+feat quando todos prev tinham conteudo' do
      character.update!(draft_data: {
        '_raceId' => '7', 'selectedRace' => { 'id' => '7' },
        'selectedSubrace' => { 'id' => '12' },
        'raceChoices' => { 'chosenLanguages' => ['Anão'] },
        '_featId' => 'feat-magic-initiate'
      })
      svc = described_class.new(character: character, data: { 'raceId' => '8' })
      result = svc.call

      expect(result.cleared_keys).to include('raceChoices', 'selectedSubrace', 'selectedFeat')
      expect(result.requires_confirmation).to be_present
    end
  end
end
