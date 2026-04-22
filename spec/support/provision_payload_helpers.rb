# frozen_string_literal: true

module ProvisionPayloadHelpers
  # Payload mínimo L1 Bárbaro + Humano Padrão (sem subclasse ainda) — espelha o contrato do front.
  def minimal_l1_barbarian_provision_payload(race:, sub_race:, klass:, background:, alignment:)
    {
      character: {
        name: "RSpec Barb #{SecureRandom.hex(3)}",
        background: background.name
      },
      wizard: {
        meta: {
          name: 'RSpec Barb',
          alignmentKey: alignment.api_index
        },
        race: {
          raceId: race.id,
          subRaceId: sub_race.id,
          ruleId: race.api_index,
          subRuleId: sub_race.api_index,
          attributes: { str: 16, dex: 14, con: 14, int: 8, wis: 10, cha: 10 },
          raceChoices: { chosenLanguages: ['Anão'] }
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Intimidação],
          classPicksByLevel: {
            '1' => {
              'hp' => { 'dieResult' => 12, 'total' => 14, 'method' => 'average' }
            }
          }
        },
        background: {
          backgroundName: background.name,
          backgroundKey: background.api_index
        },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end
end

RSpec.configure do |config|
  config.include ProvisionPayloadHelpers, type: :request
end
