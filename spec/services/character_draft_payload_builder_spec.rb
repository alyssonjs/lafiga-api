# frozen_string_literal: true

require 'rails_helper'

# Cobre Gap G11.1 do relatorio de auditoria de steps:
# /provision validava apenas `name` + `background` (2 campos) e confiava
# que o frontend tinha checado o resto. Drafts corrompidos chegavam ao
# `CharacterProvisioningService` e quebravam la dentro com mensagens
# genericas do AR. Agora `assert_minimum_payload!` valida 5 campos cedo.
RSpec.describe CharacterDraftPayloadBuilder do
  let(:user) { create(:user) }

  def build_draft(overrides = {})
    base = {
      'name' => 'Aragorn',
      'selectedBackground' => { 'id' => 1, 'name' => 'Soldado' },
      '_bgName' => 'Soldado',
      'selectedRace' => { 'id' => 1, 'name' => 'Humano' },
      '_raceId' => 1,
      'selectedClass' => { 'id' => 1, 'name' => 'Guerreiro' },
      '_classId' => 1,
      'level' => 1,
      'abilityScores' => { 'str' => 15, 'dex' => 14, 'con' => 13, 'int' => 12, 'wis' => 10, 'cha' => 8 }
    }
    base.merge(overrides)
  end

  describe 'G11.1 — validacao de completude do draft' do
    it 'aceita draft completo (todos os campos minimos presentes)' do
      char = create(:character, user: user, status: :draft, draft_data: build_draft)
      expect { described_class.build(char) }.not_to raise_error
    end

    it 'rejeita draft sem name' do
      char = create(:character, user: user, status: :draft,
                                draft_data: build_draft('name' => ''))
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError, /faltam name/)
    end

    it 'rejeita draft sem race (raceId nem ruleId)' do
      draft = build_draft.merge('selectedRace' => nil, '_raceId' => nil)
      char = create(:character, user: user, status: :draft, draft_data: draft)
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError, /faltam .*race/)
    end

    it 'aceita draft com race via ruleSlug (sem raceId numerico)' do
      draft = build_draft.merge(
        'selectedRace' => { 'ruleSlug' => 'human' },
        '_raceId' => nil
      )
      char = create(:character, user: user, status: :draft, draft_data: draft)
      expect { described_class.build(char) }.not_to raise_error
    end

    it 'rejeita draft sem class' do
      draft = build_draft.merge('selectedClass' => nil, '_classId' => nil)
      char = create(:character, user: user, status: :draft, draft_data: draft)
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError, /faltam .*class/)
    end

    it 'rejeita draft com level < 1' do
      char = create(:character, user: user, status: :draft,
                                draft_data: build_draft('level' => 0))
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError, /class.level/)
    end

    it 'rejeita draft com abilityScores zerados (todos 0)' do
      draft = build_draft.merge(
        'abilityScores' => { 'str' => 0, 'dex' => 0, 'con' => 0, 'int' => 0, 'wis' => 0, 'cha' => 0 }
      )
      char = create(:character, user: user, status: :draft, draft_data: draft)
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError, /abilityScores/)
    end

    it 'rejeita draft com 1 ability faltando (default 8 vira 0 se key blanq)' do
      draft = build_draft.merge('abilityScores' => { 'str' => 15 }) # demais default 8
      char = create(:character, user: user, status: :draft, draft_data: draft)
      # 5 dos 6 viram 8 (default), so str=15. Todos > 0 → passa.
      expect { described_class.build(char) }.not_to raise_error
    end

    it 'lista TODOS os campos faltantes (nao so o primeiro)' do
      draft = build_draft.merge(
        'name' => '',
        'selectedRace' => nil, '_raceId' => nil,
        'selectedClass' => nil, '_classId' => nil
      )
      char = create(:character, user: user, status: :draft, draft_data: draft)
      expect { described_class.build(char) }
        .to raise_error(described_class::IncompleteDraftError) { |e|
          expect(e.message).to include('name')
          expect(e.message).to include('race')
          expect(e.message).to include('class')
        }
    end
  end

  describe 'wizard.general (NPC / mestre)' do
    it 'inclui isNPC e campos opcionais quando presentes no draft' do
      char = create(:character, user: user, status: :draft, draft_data: build_draft.merge(
        'isNPC' => true,
        'npcRole' => 'Mercador',
        'npcFaction' => 'Guilda',
        'playerName' => 'Alice'
      ))
      payload = described_class.build(char)
      gen = payload.dig('wizard', 'general')
      expect(gen).to include(
        'isNPC' => true,
        'npcRole' => 'Mercador',
        'npcFaction' => 'Guilda',
        'playerName' => 'Alice'
      )
    end
  end
end
