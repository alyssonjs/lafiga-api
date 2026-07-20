# frozen_string_literal: true

require 'rails_helper'

# Gate anti-sorteio de FEATURES (fighting_style/metamagic/invocations/pact_boon).
# Em RSpec `strict_required_choices?` é sempre true (pula o auto-pick), então
# stubamos false para exercitar o branch de fallback e provar que:
#   - allow_auto_fill: false (interativo) → NÃO preenche (guard forçaria a escolha)
#   - allow_auto_fill: true  (import/gerador) → preenche DETERMINÍSTICO (1ª opção, nunca sample)
RSpec.describe LevelUpService, 'gate anti-sorteio de features (ensure_level_requirements!)' do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "feat_af_#{SecureRandom.hex(4)}@example.com", username: "feataf#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race) { Race.find_by(api_index: 'human') || Race.create!(name: 'Humano', api_index: 'human') }
  let(:fighter) { Klass.find_by(api_index: 'fighter') }

  def build_fighter_l1
    character = Character.create!(user: user, name: "Ftr #{SecureRandom.hex(2)}", background: 'Soldado')
    sheet = Sheet.create!(character: character, race_id: race.id,
                          str: 16, dex: 12, con: 14, int: 10, wis: 10, cha: 8,
                          hp_max: 12, hp_current: 12,
                          metadata: { 'class_choices' => { 'per_level' => { '1' => { 'skills' => %w[Atletismo Intimidação] } } } })
    sk = SheetKlass.create!(sheet: sheet, klass: fighter, level: 1)
    [sheet, sk]
  end

  before do
    skip 'Klass fighter ausente' unless fighter
    rule = ClassRules.find('fighter') || {}
    skip 'fighter sem fighting_style em required_choices_at_level L1' unless rule.dig(:required_choices_at_level, 1, :fighting_style)
    allow(LevelUpGuardService).to receive(:strict_required_choices?).and_return(false)
  end

  it 'allow_auto_fill: false (interativo) NÃO auto-preenche fighting_style' do
    sheet, sk = build_fighter_l1
    svc = LevelUpService.new(sheet_id: sheet.id, klass_id: fighter.id, levels: 1, allow_auto_fill: false)
    svc.send(:ensure_level_requirements!, sk, 1)
    sheet.reload
    expect(sheet.metadata.dig('class_choices', 'fighting_style')).to be_blank
    expect(sheet.metadata.dig('class_choices', 'per_level', '1', 'fighting_style')).to be_blank
  end

  it 'allow_auto_fill: true (import) auto-preenche fighting_style de forma DETERMINÍSTICA' do
    sheet, sk = build_fighter_l1
    opts = ClassRules.find('fighter').dig(:required_choices_at_level, 1, :fighting_style, :options)
    expected_first = Array(opts).first

    svc = LevelUpService.new(sheet_id: sheet.id, klass_id: fighter.id, levels: 1, allow_auto_fill: true)
    svc.send(:ensure_level_requirements!, sk, 1)
    sheet.reload
    picked = Array(sheet.metadata.dig('class_choices', 'per_level', '1', 'fighting_style')).first
    expect(picked).to be_present
    expect(picked).to eq(expected_first) # 1ª opção, nunca sorteada
  end
end
