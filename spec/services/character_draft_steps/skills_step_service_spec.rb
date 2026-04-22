# frozen_string_literal: true

require 'rails_helper'

# Cobre Gaps G6.1 (validacao de skills contra catalogo da classe) e G6.2
# (expertise so em skills com proficiencia) do relatorio de auditoria.
RSpec.describe CharacterDraftSteps::SkillsStepService do
  let(:user) { create(:user) }

  # Guerreiro tem skill_proficiencies: { choose: 2, options: [...] }
  # Bardo tem skill_proficiencies: { choose: 3, options: :any }
  # ClassRules.find usa as chaves do CLASS_RULES (em ingles: 'fighter', 'bard',
  # ...). Klass.api_index DEVE bater com essa chave (assim funciona em prod).
  let!(:guerreiro) do
    Klass.find_or_create_by!(api_index: 'fighter') { |r| r.name = 'Guerreiro'; r.hit_die = 10 }
  end
  let!(:bardo) do
    Klass.find_or_create_by!(api_index: 'bard') { |r| r.name = 'Bardo'; r.hit_die = 8 }
  end

  describe 'G6.1 — validacao de skills (warn-soft)' do
    it 'aceita skills validas do catalogo do Guerreiro sem warning' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => guerreiro.api_index,
        'selectedClass' => { 'id' => guerreiro.api_index }
      })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['Atletismo', 'Intimidação']
      })
      result = svc.call
      expect(result.warnings).to be_empty
      expect(result.draft_data['selectedSkills']).to eq(['Atletismo', 'Intimidação'])
    end

    it 'warn quando excede o count maximo da classe' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => guerreiro.api_index,
        'selectedClass' => { 'id' => guerreiro.api_index }
      })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['Atletismo', 'Intimidação', 'Acrobacia', 'Sobrevivência']
      })
      result = svc.call
      expect(result.warnings).to include(/maximo permitido.*2/)
      # Mesmo com warn, persiste (soft validation)
      expect(result.draft_data['selectedSkills'].size).to eq(4)
    end

    it 'warn quando contem skill fora do catalogo' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => guerreiro.api_index,
        'selectedClass' => { 'id' => guerreiro.api_index }
      })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['Atletismo', 'Arcanismo'] # Arcanismo nao e do Guerreiro
      })
      result = svc.call
      expect(result.warnings).to include(/fora do catalogo.*Arcanismo/)
    end

    it 'NAO warn para Bardo (options=:any aceita qualquer skill)' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => bardo.api_index,
        'selectedClass' => { 'id' => bardo.api_index }
      })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['Atletismo', 'Arcanismo', 'Sobrevivência']
      })
      result = svc.call
      expect(result.warnings).to be_empty
    end

    it 'sem classe selecionada, nao valida (silencioso)' do
      char = create(:character, user: user, status: :draft, draft_data: { '_version' => 1 })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['SkillInventada', 'OutroLixo']
      })
      result = svc.call
      expect(result.warnings).to be_empty
      expect(result.draft_data['selectedSkills']).to eq(['SkillInventada', 'OutroLixo'])
    end
  end

  describe 'G6.2 — expertise so em skills com proficiencia' do
    it 'aceita expertise quando e subset de selectedSkills' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => bardo.api_index, 'selectedClass' => { 'id' => bardo.api_index },
        'selectedSkills' => ['Atletismo', 'Persuasão'],
        'level1Choices' => { 'skills' => ['Atletismo', 'Persuasão'] }
      })
      svc = described_class.new(character: char, data: {
        'expertise' => ['Persuasão']
      })
      result = svc.call
      expect(result.warnings).to be_empty
      expect(result.draft_data.dig('level1Choices', 'expertise')).to eq(['Persuasão'])
    end

    it 'warn quando expertise contem skill ausente em selectedSkills' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => bardo.api_index, 'selectedClass' => { 'id' => bardo.api_index },
        'selectedSkills' => ['Atletismo'],
        'level1Choices' => { 'skills' => ['Atletismo'] }
      })
      svc = described_class.new(character: char, data: {
        'expertise' => ['Persuasão'] # nao tem proficiencia
      })
      result = svc.call
      expect(result.warnings).to include(/sem proficiencia.*Persuasão/)
    end

    it 'PATCH atomico (skills + expertise juntos) NAO disparar orfa' do
      char = create(:character, user: user, status: :draft, draft_data: {
        '_version' => 1,
        '_classId' => bardo.api_index, 'selectedClass' => { 'id' => bardo.api_index }
      })
      svc = described_class.new(character: char, data: {
        'selectedSkills' => ['Atletismo', 'Persuasão'],
        'expertise' => ['Persuasão']
      })
      result = svc.call
      expect(result.warnings).to be_empty
    end
  end
end
