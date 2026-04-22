# frozen_string_literal: true

require 'rails_helper'

# P2.16 — Paladino Canalizar Divindade (PHB):
# - 1 uso a partir do nivel 3 (recarga em descanso curto ou longo).
# - Diferente do clerigo, NAO escala em usos com o nivel
#   (apenas adiciona opcoes via Juramento).
RSpec.describe ClassRules, '#derive_feature_rules — Paladino: Canalizar Divindade (P2.16)' do
  let(:rule) { ClassRules::CLASS_RULES[:paladin] }

  def derive(level:)
    described_class.derive_feature_rules(
      rule: rule,
      level: level,
      picks: {},
      ability_scores: { str: 16, dex: 10, con: 14, int: 8, wis: 10, cha: 16 },
      equipment: {}
    )
  end

  it 'NAO expoe channel_divinity abaixo do nivel 3' do
    [1, 2].each do |lvl|
      out = derive(level: lvl)
      expect(out[:resources][:channel_divinity]).to be_nil, "nv #{lvl} nao deveria ter channel_divinity"
    end
  end

  it 'expoe channel_divinity = 1 uso a partir do nivel 3 (PHB)' do
    [3, 5, 11, 17, 20].each do |lvl|
      out = derive(level: lvl)
      expect(out[:resources][:channel_divinity]).to eq(uses: 1, recharge: 'SR'), "nv #{lvl}"
    end
  end

  it 'NAO escala em usos com o nivel (paladino != clerigo)' do
    out_3  = derive(level: 3)
    out_20 = derive(level: 20)
    expect(out_3[:resources][:channel_divinity][:uses]).to eq(1)
    expect(out_20[:resources][:channel_divinity][:uses]).to eq(1)
  end

  it 'recarga eh em descanso curto (SR), alinhada com config/class_resources.yml' do
    out = derive(level: 3)
    expect(out[:resources][:channel_divinity][:recharge]).to eq('SR')
    yaml_recharge = Sheets::Runtime::ResourceCatalog.recharge_for('channel_divinity')
    expect(yaml_recharge).to eq('short')
  end
end

# Regressao: clerigo continua escalando 1->2->3 (PHB).
RSpec.describe ClassRules, '#derive_feature_rules — Clerigo: regressao Canalizar Divindade' do
  let(:rule) { ClassRules::CLASS_RULES[:cleric] }

  def derive(level:)
    described_class.derive_feature_rules(
      rule: rule,
      level: level,
      picks: {},
      ability_scores: { str: 10, dex: 10, con: 14, int: 10, wis: 16, cha: 12 },
      equipment: {}
    )
  end

  it 'mantem escala 1@2 / 2@6 / 3@18 (sem regressao)' do
    expect(derive(level: 2)[:resources][:channel_divinity][:uses]).to eq(1)
    expect(derive(level: 6)[:resources][:channel_divinity][:uses]).to eq(2)
    expect(derive(level: 17)[:resources][:channel_divinity][:uses]).to eq(2)
    expect(derive(level: 18)[:resources][:channel_divinity][:uses]).to eq(3)
  end
end
