# frozen_string_literal: true

require 'rails_helper'

# D1 — Robustez do feat do Humano Variante no provisionamento. Antes só aplicava
# com `variantHumanASI.mode=='feat'` + featId SLUG. Agora aceita: mode opcional,
# featId top-level (selectedFeat) e featId numérico (DB id → slug).
RSpec.describe 'D1 — Humano Variante: feat robusto', type: :service do
  let(:user) { create(:user) }
  let!(:human) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let!(:variant) { SubRace.find_or_create_by!(race_id: human.id, api_index: 'variant') { |s| s.name = 'Humano Variante' } }
  let!(:klass) { Klass.find_or_create_by!(api_index: 'barbarian') { |k| k.name = 'Bárbaro'; k.hit_die = 12 } }
  let!(:bg) { Background.find_or_create_by!(api_index: 'soldier') { |b| b.name = 'Soldado' } }
  let!(:align) { Alignment.find_or_create_by!(api_index: 'n') { |a| a.name = 'Neutro' } }

  before { RaceRules.reload! }

  def provision(race_choices)
    payload = {
      character: { name: "VH #{SecureRandom.hex(3)}" },
      wizard: {
        meta: { name: 'VH', alignmentKey: align.api_index },
        race: { raceId: human.id, subRaceId: variant.id, ruleId: 'human', subRuleId: 'variant',
                attributes: { str: 15, dex: 13, con: 14, int: 8, wis: 13, cha: 9 }, raceChoices: race_choices },
        klass: { klassId: klass.id, level: 1, classSkillPicks: %w[Atletismo Sobrevivência],
                 classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 12, 'total' => 14 } } } },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index }, equipment: {}, avatar: { customization: {} }
      }
    }
    cmd = CharacterProvisioningService.call(user: user, payload: payload)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') }
    Sheet.where(character_id: cmd.result[:character].id).last
  end

  def feat_names(sheet)
    Array(CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result[:feats]).map { |f| f[:name].to_s }
  end

  it 'forma canônica: variantHumanASI {mode:feat, featId: slug}' do
    sheet = provision('variantHumanASI' => { 'mode' => 'feat', 'featId' => 'atleta', 'choices' => {} }, 'chosenAbilities' => %w[str con])
    expect(feat_names(sheet)).to include('Atleta')
  end

  it 'mode OPCIONAL: variantHumanASI {featId: slug} sem mode' do
    sheet = provision('variantHumanASI' => { 'featId' => 'atleta', 'choices' => {} }, 'chosenAbilities' => %w[str con])
    expect(feat_names(sheet)).to include('Atleta')
  end

  it 'featId TOP-LEVEL: raceChoices.selectedFeat' do
    sheet = provision('selectedFeat' => 'atleta', 'chosenAbilities' => %w[str con])
    expect(feat_names(sheet)).to include('Atleta')
  end

  it 'featId NUMÉRICO (DB id) → normaliza para slug' do
    feat = Feat.find_or_create_by!(api_index: 'atleta') { |f| f.name = 'Atleta' }
    sheet = provision('variantHumanASI' => { 'mode' => 'feat', 'featId' => feat.id, 'choices' => {} }, 'chosenAbilities' => %w[str con])
    expect(feat_names(sheet)).to include('Atleta')
  end

  it 'mode ASI explícito (attributes) → NÃO aplica feat' do
    sheet = provision('variantHumanASI' => { 'mode' => 'attributes', 'featId' => 'atleta' }, 'chosenAbilities' => %w[str con])
    expect(feat_names(sheet)).to be_empty
  end
end
