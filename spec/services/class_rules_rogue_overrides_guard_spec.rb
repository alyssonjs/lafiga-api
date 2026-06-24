# frozen_string_literal: true

require 'rails_helper'

# Regressao: os overrides de Ladino (reliable_talent / slippery_mind /
# uncanny_dodge / elusive) so podem ser injetados em proficiency_overrides
# quando a feature de fato existe em feature_rules.
#
# Bug original: o guard usava `fr[:key]&.dig(:available_at).to_i <= level`.
# Para uma classe sem a feature, `nil&.dig(...).to_i => 0` e `0 <= level`
# eh sempre verdadeiro (level >= 0), entao um Bardo puro recebia os quatro
# overrides — inclusive slippery_mind, que concede TR de SAB (canonicamente
# errado: Bardo so tem TR de DES e CAR).
ROGUE_OVERRIDE_KEYS = %i[reliable_talent slippery_mind uncanny_dodge elusive].freeze

RSpec.describe ClassRules, '#derive_feature_rules — guard dos overrides de Ladino' do
  def derive(rule:, level:)
    described_class.derive_feature_rules(
      rule: rule,
      level: level,
      picks: {},
      ability_scores: { str: 10, dex: 16, con: 14, int: 10, wis: 10, cha: 16 },
      equipment: {}
    )
  end

  context 'Bardo puro (sem nenhuma feature de Ladino)' do
    let(:rule) { ClassRules::CLASS_RULES[:bard] }

    it 'NAO injeta nenhum override de Ladino em nenhum nivel' do
      [1, 5, 11, 15, 18, 20].each do |lvl|
        po = derive(rule: rule, level: lvl)[:proficiency_overrides]
        ROGUE_OVERRIDE_KEYS.each do |key|
          expect(po).not_to have_key(key), "nv #{lvl}: Bardo nao deveria receber #{key}"
        end
      end
    end

    it 'NAO concede proficiencia em TR de SAB via slippery_mind (Bardo: so DES e CAR)' do
      po = derive(rule: rule, level: 20)[:proficiency_overrides]
      expect(po[:slippery_mind]).to be_nil
    end
  end

  context 'Ladino (features presentes)' do
    let(:rule) { ClassRules::CLASS_RULES[:rogue] }

    it 'NAO expoe os overrides abaixo do nivel canonico' do
      po4  = derive(rule: rule, level: 4)[:proficiency_overrides]
      po10 = derive(rule: rule, level: 10)[:proficiency_overrides]
      po14 = derive(rule: rule, level: 14)[:proficiency_overrides]
      po17 = derive(rule: rule, level: 17)[:proficiency_overrides]

      expect(po4).not_to have_key(:uncanny_dodge)    # antes do nv 5
      expect(po10).not_to have_key(:reliable_talent)  # antes do nv 11
      expect(po14).not_to have_key(:slippery_mind)    # antes do nv 15
      expect(po17).not_to have_key(:elusive)          # antes do nv 18
    end

    it 'concede uncanny_dodge a partir do nivel 5' do
      expect(derive(rule: rule, level: 5)[:proficiency_overrides][:uncanny_dodge]).to be(true)
    end

    it 'concede reliable_talent (d20_min_floor: 10) a partir do nivel 11' do
      expect(derive(rule: rule, level: 11)[:proficiency_overrides][:reliable_talent]).to eq(d20_min_floor: 10)
    end

    it 'concede slippery_mind (TR de SAB) a partir do nivel 15' do
      expect(derive(rule: rule, level: 15)[:proficiency_overrides][:slippery_mind]).to eq(grant_save_proficiency: 'WIS')
    end

    it 'concede elusive a partir do nivel 18' do
      expect(derive(rule: rule, level: 18)[:proficiency_overrides][:elusive]).to be(true)
    end

    it 'no nivel 20 expoe os quatro overrides' do
      po = derive(rule: rule, level: 20)[:proficiency_overrides]
      expect(po[:uncanny_dodge]).to be(true)
      expect(po[:reliable_talent]).to eq(d20_min_floor: 10)
      expect(po[:slippery_mind]).to eq(grant_save_proficiency: 'WIS')
      expect(po[:elusive]).to be(true)
    end
  end
end
