# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 6G — Validação opcional de movement ledger contra speed_ft.
RSpec.describe Combat::ValidateMovementLedgerPayload, '.cap_violations (Fase 6G)', type: :service do
  let(:ledger) do
    [
      { 'kind' => 'map', 'ft' => 25, 'tokenId' => 'pc-1', 'prevCol' => 0, 'prevRow' => 0 },
      { 'kind' => 'map', 'ft' => 10, 'tokenId' => 'pc-1', 'prevCol' => 5, 'prevRow' => 0 },
      { 'kind' => 'map', 'ft' => 30, 'tokenId' => 'npc-1', 'prevCol' => 10, 'prevRow' => 5 }
    ]
  end

  it 'sinaliza token que ultrapassou speed × multiplier' do
    speeds = {
      'pc-1' => { speed_ft: 30, multiplier: 1 },     # 25+10=35 > 30 → violação
      'npc-1' => { speed_ft: 40, multiplier: 1 }     # 30 ≤ 40 → ok
    }
    violations = described_class.cap_violations(ledger, speeds)

    expect(violations.length).to eq(1)
    expect(violations.first['tokenId']).to eq('pc-1')
    expect(violations.first['total_ft']).to eq(35.0)
    expect(violations.first['cap_ft']).to eq(30)
  end

  it 'multiplier=2 acomoda Disparada (dobra speed efetivo)' do
    speeds = { 'pc-1' => { speed_ft: 30, multiplier: 2 } }   # cap = 60 ft
    violations = described_class.cap_violations(ledger, speeds)
    expect(violations).to be_empty
  end

  it 'ignora tokens fora do map (manual entries não contam)' do
    manual_ledger = [
      { 'kind' => 'manual', 'ft' => 100 }   # sem tokenId
    ]
    violations = described_class.cap_violations(manual_ledger, { 'pc-1' => { speed_ft: 30 } })
    expect(violations).to be_empty
  end

  it 'speed=0 é skipado (sem dados → não valida)' do
    speeds = { 'pc-1' => { speed_ft: 0 } }
    violations = described_class.cap_violations(ledger, speeds)
    expect(violations).to be_empty
  end

  it 'token não presente em combatant_speeds é skipado' do
    speeds = {}
    violations = described_class.cap_violations(ledger, speeds)
    expect(violations).to be_empty
  end

  it 'retorna [] para ledger vazio ou nil' do
    expect(described_class.cap_violations([], { 'pc-1' => { speed_ft: 30 } })).to eq([])
    expect(described_class.cap_violations(nil, { 'pc-1' => { speed_ft: 30 } })).to eq([])
  end
end
