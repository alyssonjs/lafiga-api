# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feat spellcasting prerequisite' do
  let(:user) { create(:user) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }

  def build_sheet_with_klass(klass)
    character = create(:character, user: user, status: :active)
    sheet = create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      str: 10,
      dex: 12,
      con: 13,
      int: 12,
      wis: 20,
      cha: 12,
      metadata: {
        'class_choices' => {
          'per_level' => {
            '4' => { 'asi' => { 'mode' => 'feat', 'featId' => 'conjurador_de_batalha' } }
          }
        },
        'class_summary' => {
          'name' => klass.name,
          'armor_proficiencies' => [],
          'weapon_proficiencies' => []
        }
      }
    )
    create(:sheet_klass, sheet: sheet, klass: klass, level: 7)
    sheet
  end

  it 'aceita Conjurador de Batalha quando a classe tem progressao de magia no catalogo' do
    cleric = create(:klass, api_index: "cleric_prereq_#{SecureRandom.hex(4)}", name: 'Clérigo', spellcasting_ability: 'wis')
    class_level = ClassLevel.create!(klass: cleric, level: 7, prof_bonus: 3, ability_score_bonuses: 0)
    Spellcasting.create!(
      class_level: class_level,
      level: 4,
      cantrips_known: 4,
      spells_known: nil,
      spell_slots: { '1' => 4, '2' => 3, '3' => 3, '4' => 1 }.to_json
    )
    sheet = build_sheet_with_klass(cleric)

    expect(FeatRules.check_prerequisites('conjurador_de_batalha', sheet)).to eq(true)

    cmd = FeatAssignmentService.call(sheet: sheet, feat_id: 'conjurador_de_batalha', level_gained: 4)
    expect(cmd).to be_success
    expect(sheet.reload.sheet_feats.joins(:feat).where(feats: { api_index: 'conjurador_de_batalha' }).count).to eq(1)
  end

  it 'falha prerequisito sem abortar a transacao externa' do
    fighter = create(:klass, api_index: "fighter_prereq_#{SecureRandom.hex(4)}", name: 'Guerreiro')
    sheet = build_sheet_with_klass(fighter)

    ActiveRecord::Base.transaction do
      cmd = FeatAssignmentService.call(sheet: sheet, feat_id: 'conjurador_de_batalha', level_gained: 4)
      expect(cmd).not_to be_success

      sheet.update!(metadata: sheet.metadata.merge('transaction_survived' => true))
    end

    expect(sheet.reload.metadata['transaction_survived']).to eq(true)
    expect(sheet.sheet_feats.count).to eq(0)
  end
end
