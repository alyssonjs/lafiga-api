# frozen_string_literal: true

require 'rails_helper'

# FIACAO, nao mecanica: o `SpendUseService` ja tem spec proprio. Aqui o que se
# prova e que o descanso REALMENTE chama a recuperacao — servico certo e handler
# nao ligado dao "pronto" falso.
RSpec.describe 'descanso restaura usos de item' do
  let(:sheet) { create(:sheet, current_level: 5) }
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 5) }

  def item_com_usos!(recarga)
    sufixo = SecureRandom.hex(3)
    Item.create!(api_index: "spec-uses-#{sufixo}", name: "Varinha #{sufixo}", kind: 'tool',
                 category: 'kit', source: 'test',
                 props: { 'uses_max' => 7, **(recarga ? { 'uses_recharge' => recarga } : {}) })
    SheetItem.create!(sheet: sheet, item_name: "Varinha #{sufixo}",
                      item_index: "spec-uses-#{sufixo}", category: 'tools',
                      quantity: 1, source: 'test')
  end

  it 'descanso LONGO devolve carga de recarga longa' do
    varinha = item_com_usos!('long')
    SheetItems::SpendUseService.new(item: varinha, amount: 3).call

    Sheets::Runtime::ApplyLongRestService.call(sheet)

    expect(varinha.reload.uses_remaining).to eq(7)
  end

  it 'descanso CURTO devolve carga de recarga curta' do
    varinha = item_com_usos!('short')
    SheetItems::SpendUseService.new(item: varinha, amount: 3).call

    Sheets::Runtime::ApplyShortRestService.call(sheet)

    expect(varinha.reload.uses_remaining).to eq(7)
  end

  it 'descanso CURTO nao devolve carga de recarga longa' do
    varinha = item_com_usos!('long')
    SheetItems::SpendUseService.new(item: varinha, amount: 3).call

    Sheets::Runtime::ApplyShortRestService.call(sheet)

    expect(varinha.reload.uses_remaining).to eq(4)
  end

  it 'nenhum descanso devolve uso de kit consumivel (sem token de recarga)' do
    kit = item_com_usos!(nil)
    SheetItems::SpendUseService.new(item: kit, amount: 3).call

    Sheets::Runtime::ApplyShortRestService.call(sheet)
    Sheets::Runtime::ApplyLongRestService.call(sheet)

    expect(kit.reload.uses_remaining).to eq(4)
  end
end
