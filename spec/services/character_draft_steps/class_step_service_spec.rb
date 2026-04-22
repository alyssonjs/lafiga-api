# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix B4.1 do relatorio de auditoria de steps: o invalidate! do
# ClassStepService historicamente sobrescrevia level1Choices/subclass/etc
# sempre que o classId mudava — incluindo o caso de PATCH atomico
# {classId, level1Choices} (criacao fresh ou troca consciente do cliente),
# fazendo o cliente perder dados que acabou de enviar.
RSpec.describe CharacterDraftSteps::ClassStepService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :draft) }

  describe '#apply!' do
    it 'merges classId/subclassId/level1Choices into draft_data' do
      svc = described_class.new(character: character, data: {
        'classId' => 'cl-2',
        'subclassId' => 'sub-1',
        'level1Choices' => { 'instruments' => %w[lute flute drum] }
      })
      result = svc.call

      expect(result.draft_data['_classId']).to eq('cl-2')
      expect(result.draft_data.dig('selectedClass', 'id')).to eq('cl-2')
      expect(result.draft_data.dig('selectedSubclass', 'id')).to eq('sub-1')
      expect(result.draft_data['level1Choices']).to eq('instruments' => %w[lute flute drum])
    end

    # ZX2 do segundo audit: PATCH parcial em level1Choices (mesma classe)
    # historicamente substituia o hash inteiro — perdia skills/expertise/etc
    # ja salvas. Agora deep_merge: paridade com ProgressionEditService::B7.1
    # e com ClassEditService (que faz `row1.merge!(...)` na mesma classe).
    context 'ZX2 — PATCH parcial level1Choices (mesma classe) faz deep_merge' do
      before do
        character.update!(draft_data: {
          '_classId' => 'cl-2',
          'selectedClass' => { 'id' => 'cl-2' },
          'level1Choices' => {
            'skills' => %w[athletics acrobatics],
            'expertise' => ['athletics'],
            'instruments' => %w[lute]
          }
        })
      end

      it 'preserva chaves nao enviadas no patch parcial' do
        svc = described_class.new(character: character, data: {
          'classId' => 'cl-2',
          'level1Choices' => { 'fighting_style' => ['defense'] }
        }, force: true)
        result = svc.call

        l1 = result.draft_data['level1Choices']
        expect(l1['fighting_style']).to eq(['defense'])     # nova
        expect(l1['skills']).to eq(%w[athletics acrobatics]) # preservada
        expect(l1['expertise']).to eq(['athletics'])        # preservada
        expect(l1['instruments']).to eq(%w[lute])           # preservada
      end

      it 'sobrescreve chave existente quando reenviada' do
        svc = described_class.new(character: character, data: {
          'classId' => 'cl-2',
          'level1Choices' => { 'skills' => %w[arcana history] }
        }, force: true)
        result = svc.call

        l1 = result.draft_data['level1Choices']
        expect(l1['skills']).to eq(%w[arcana history])  # sobrescrita
        expect(l1['expertise']).to eq(['athletics'])    # preservada (nao veio)
        expect(l1['instruments']).to eq(%w[lute])       # preservada
      end

      it 'permite zerar uma chave especifica via array vazio' do
        svc = described_class.new(character: character, data: {
          'classId' => 'cl-2',
          'level1Choices' => { 'expertise' => [] }
        }, force: true)
        result = svc.call

        l1 = result.draft_data['level1Choices']
        expect(l1['expertise']).to eq([])
        expect(l1['skills']).to eq(%w[athletics acrobatics]) # preservada
      end
    end
  end

  describe '#invalidate! (B4.1)' do
    let(:initial_draft) do
      {
        '_classId' => 'cl-2',
        'selectedClass' => { 'id' => 'cl-2' },
        'selectedSubclass' => { 'id' => 'sub-1' },
        'level1Choices' => { 'instruments' => %w[lute flute drum] },
        'levelChoices' => [{ 'level' => 1, 'hp' => 8, 'featureChoices' => {}, 'complete' => true }],
        'spellSelections' => { 'cantrips' => %w[vicious_mockery], 'known' => [], 'spellbook' => [], 'prepared' => [] }
      }
    end

    it 'limpa level1Choices/subclass/spellSelections quando muda classe SEM enviar novas escolhas' do
      character.update!(draft_data: initial_draft)
      svc = described_class.new(character: character, data: { 'classId' => 'cl-1' }, force: true)
      result = svc.call

      expect(result.draft_data['level1Choices']).to eq({})
      expect(result.draft_data['selectedSubclass']).to be_nil
      expect(result.draft_data['levelChoices']).to eq([])
      expect(result.draft_data['spellSelections']).to eq('cantrips' => [], 'known' => [], 'spellbook' => [], 'prepared' => [])
      expect(result.cleared_keys).to include('level1Choices', 'selectedSubclass', 'levelChoices', 'spellSelections')
    end

    it 'PRESERVA level1Choices quando enviadas no MESMO PATCH da troca de classe' do
      character.update!(draft_data: initial_draft)
      svc = described_class.new(
        character: character,
        data: {
          'classId' => 'cl-3',
          'level1Choices' => { 'fighting_style' => ['defense'] }
        },
        force: true
      )
      result = svc.call

      expect(result.draft_data['level1Choices']).to eq('fighting_style' => ['defense'])
      # subclass nao veio no PATCH -> apaga (e pediria confirm. se nao force)
      expect(result.draft_data['selectedSubclass']).to be_nil
      expect(result.cleared_keys).not_to include('level1Choices')
      expect(result.cleared_keys).to include('selectedSubclass')
    end

    it 'PRESERVA subclassId tambem quando enviado no mesmo PATCH' do
      character.update!(draft_data: initial_draft)
      svc = described_class.new(
        character: character,
        data: { 'classId' => 'cl-3', 'subclassId' => 'sub-9' },
        force: true
      )
      result = svc.call

      expect(result.draft_data.dig('selectedSubclass', 'id')).to eq('sub-9')
      expect(result.cleared_keys).not_to include('selectedSubclass')
    end

    it 'criacao fresh (prev_id nil): nao apaga o que apply! acabou de colocar' do
      # draft vazio, usuario seleciona classe + escolhas pela primeira vez
      svc = described_class.new(character: character, data: {
        'classId' => 'cl-2',
        'level1Choices' => { 'instruments' => %w[lute flute drum] }
      })
      result = svc.call

      expect(result.draft_data['level1Choices']).to eq('instruments' => %w[lute flute drum])
      # Nao requer confirmacao em criacao fresh.
      expect(result.requires_confirmation).to be_nil
    end

    it 'flags requires_confirmation em troca destrutiva sem force' do
      character.update!(draft_data: initial_draft)
      svc = described_class.new(character: character, data: { 'classId' => 'cl-1' })
      result = svc.call

      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:cleared]).to include('level1Choices')
    end

    # Gap G8.2 do relatorio de auditoria de steps
    context 'G8.2 — invalidate equipment ao trocar classe' do
      let(:draft_with_equipment) do
        initial_draft.merge(
          'equipmentMode' => 'preset',
          'equipmentChoices' => [{ 'kind' => 'weapon', 'pick' => 'longsword' }],
          'equipmentGenericSelections' => { 'instrument' => 'lute' },
          'startingGoldRolled' => 75
        )
      end

      it 'limpa equipment_* quando troca classe SEM enviar novas escolhas' do
        character.update!(draft_data: draft_with_equipment)
        svc = described_class.new(character: character, data: { 'classId' => 'cl-1' }, force: true)
        result = svc.call

        expect(result.draft_data['equipmentMode']).to be_nil
        expect(result.draft_data['equipmentChoices']).to eq([])
        expect(result.draft_data['equipmentGenericSelections']).to eq({})
        expect(result.draft_data['startingGoldRolled']).to be_nil
        expect(result.cleared_keys).to include(
          'equipmentMode', 'equipmentChoices', 'equipmentGenericSelections', 'startingGoldRolled'
        )
      end

      # Nota: nao ha teste de "PRESERVA equipment_* no MESMO PATCH" porque
      # `ClassStepService.apply!` NAO trata equipment fields (esses sao do
      # EquipmentStepService). O `invalidate!` checa `data.key?` apenas como
      # safeguard defensiva — se o cliente algum dia mandar PATCH atomico
      # incluindo equipment, o invalidate! nao apagaria a chave, mas o
      # `apply!` tampouco preencheria com o valor novo. Em prática o cliente
      # faz 2 PATCHes em sequencia: /step/class (limpa equipment) +
      # /step/equipment (repoe). Esse e o contrato real.
    end
  end
end
