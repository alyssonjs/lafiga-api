require 'rails_helper'

RSpec.describe 'RaceRules YAML integration' do
  it 'applies Aarakocra subrace Falconicos with flight traits' do
    sel = { race_id: 'aarakocra', subrace_id: 'falconicos', choices: {} }
    applied = RaceRules.apply(sel)
    keys = Array(applied[:traits]).map { |t| t[:key] }
    expect(keys).to include('flight_15m_no_med_heavy')
    expect(keys).to include('flight_medium_ok')
  end

  it 'applies Centaur base traits' do
    sel = { race_id: 'centaur', subrace_id: nil, choices: {} }
    applied = RaceRules.apply(sel)
    keys = Array(applied[:traits]).map { |t| t[:key] }
    expect(keys).to include('centaur_charge')
    expect(keys).to include('hooves_1d6_strike')
    expect(keys).to include('equine_build')
  end

  it 'applies Tiefling Infernal lineage traits' do
    sel = { race_id: 'tiefling', subrace_id: 'infernal', choices: {} }
    applied = RaceRules.apply(sel)
    keys = Array(applied[:traits]).map { |t| t[:key] }
    # Base trait
    expect(keys).to include('thaumaturgy_cantrip')
    # Infernal lineage
    expect(keys).to include('legacy_resistance_fire')
    expect(keys).to include('infernal_legacy_variant')
  end
end

