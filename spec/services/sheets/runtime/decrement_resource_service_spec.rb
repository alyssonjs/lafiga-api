require 'rails_helper'

RSpec.describe Sheets::Runtime::DecrementResourceService do
  let(:sheet) { create(:sheet) }

  it 'incrementa o uso de um recurso (delta default = 1)' do
    described_class.call(sheet, key: 'rage')
    expect(sheet.runtime_state.reload.class_resources_used).to eq('rage' => 1)
  end

  it 'acumula em chamadas sucessivas' do
    described_class.call(sheet, key: 'rage')
    described_class.call(sheet, key: 'rage', delta: 2)
    expect(sheet.runtime_state.reload.class_resources_used).to eq('rage' => 3)
  end

  it 'aceita delta negativo (recuperar) e clampa em 0' do
    sheet.runtime!.update!(class_resources_used: { 'ki' => 2 })
    described_class.call(sheet, key: 'ki', delta: -1)
    expect(sheet.runtime_state.reload.class_resources_used).to eq('ki' => 1)
  end

  it 'remove a chave quando o valor cai para 0 (mantem o hash limpo)' do
    sheet.runtime!.update!(class_resources_used: { 'ki' => 1 })
    described_class.call(sheet, key: 'ki', delta: -5)
    expect(sheet.runtime_state.reload.class_resources_used).to eq({})
  end

  it 'aceita keys nao catalogadas (logs warning)' do
    expect(Rails.logger).to receive(:warn).with(/inexistente_xyz/)
    described_class.call(sheet, key: 'inexistente_xyz', delta: 1)
    expect(sheet.runtime_state.reload.class_resources_used).to eq('inexistente_xyz' => 1)
  end
end
