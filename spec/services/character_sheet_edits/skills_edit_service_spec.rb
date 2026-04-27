# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterSheetEdits::SkillsEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:guerreiro) do
    Klass.find_or_create_by!(api_index: 'fighter') { |r| r.name = 'Guerreiro'; r.hit_die = 10 }
  end
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: guerreiro, level: 3) }

  describe 'G6.1 — validacao de skills' do
    it 'aceita skills validas do catalogo do Guerreiro sem warning' do
      svc = described_class.new(character: character, data: {
        'selectedSkills' => ['Atletismo', 'Intimidação']
      })
      result = svc.call
      expect(result.warnings).to be_empty
      sheet.reload
      expect(sheet.metadata.dig('class_choices', 'per_level', '1', 'skills')).to eq(['Atletismo', 'Intimidação'])
    end

    it 'warn quando excede o count maximo' do
      svc = described_class.new(character: character, data: {
        'selectedSkills' => ['Atletismo', 'Intimidação', 'Acrobacia']
      })
      result = svc.call
      expect(result.warnings).to include(/maximo.*2/)
    end

    it 'warn quando contem skill fora do catalogo' do
      svc = described_class.new(character: character, data: {
        'selectedSkills' => ['Atletismo', 'Arcanismo']
      })
      result = svc.call
      expect(result.warnings).to include(/fora do catalogo.*Arcanismo/)
    end
  end

  describe '#read' do
    it 'expõe expertise a partir de per_level[1].expertise_skills (provision / ladino)' do
      sheet.update!(metadata: {
        'class_choices' => {
          'per_level' => {
            '1' => {
              'skills' => %w[Furtividade Percepção],
              'expertise_skills' => %w[Furtividade Percepção]
            }
          }
        }
      })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['expertise']).to eq(%w[Furtividade Percepção])
    end

    it 'une expertise e expertise_skills quando ambos existem' do
      sheet.update!(metadata: {
        'class_choices' => {
          'per_level' => {
            '1' => {
              'skills' => %w[Atletismo Intimidação],
              'expertise' => ['Atletismo'],
              'expertise_skills' => ['Intimidação']
            }
          }
        }
      })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['expertise']).to contain_exactly('Atletismo', 'Intimidação')
    end
  end

  describe 'G6.2 — expertise so em skills com proficiencia' do
    it 'warn quando expertise contem skill ausente em selectedSkills' do
      sheet.update!(metadata: {
        'class_choices' => { 'per_level' => { '1' => { 'skills' => ['Atletismo'] } } }
      })
      svc = described_class.new(character: character.reload, data: {
        'expertise' => ['Persuasão']
      })
      result = svc.call
      expect(result.warnings).to include(/sem proficiencia.*Persuasão/)
    end

    it 'PATCH atomico (skills + expertise) NAO disparar orfa' do
      svc = described_class.new(character: character, data: {
        'selectedSkills' => ['Atletismo', 'Intimidação'],
        'expertise' => ['Atletismo']
      })
      result = svc.call
      expect(result.warnings).to be_empty
    end

    it 'persiste expertise_skills junto com expertise no metadata' do
      sheet.update!(metadata: {
        'class_choices' => { 'per_level' => { '1' => { 'skills' => %w[A B] } } }
      })
      svc = described_class.new(character: character.reload, data: {
        'selectedSkills' => %w[Atletismo Intimidação],
        'expertise' => %w[Atletismo Intimidação]
      })
      expect(svc.call.warnings).to be_empty
      sheet.reload
      row = sheet.metadata.dig('class_choices', 'per_level', '1')
      expect(row['expertise']).to eq(%w[Atletismo Intimidação])
      expect(row['expertise_skills']).to eq(%w[Atletismo Intimidação])
    end
  end
end
