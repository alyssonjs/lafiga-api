# frozen_string_literal: true

require 'rails_helper'

# Usos de kit e cargas de item magico: o contador vive na INSTANCIA
# (`sheet_items.props_json['uses_remaining']`) e o teto vem do item BASE
# (`items.props['uses_max']`). Ausencia da chave = cheio, para nao ter de
# semear contador em toda ficha que ja existe.
RSpec.describe SheetItems::SpendUseService do
  let(:user)      { create(:user) }
  let(:race)      { create(:race) }
  let(:sub_race)  { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Kit Spec PC') }
  let!(:sheet)    { create(:sheet, character: character, race: race, sub_race: sub_race) }

  # Kit consumivel: dez usos, SEM recarga (descanso nao repoe atadura).
  let!(:kit_base) do
    Item.create!(api_index: 'kit-spec-sos', name: 'Kit Spec SOS', kind: 'tool',
                 category: 'kit', props: { 'uses_max' => 10 }, source: 'test')
  end
  let!(:kit) do
    SheetItem.create!(sheet: sheet, item_name: 'Kit Spec SOS', item_index: 'kit-spec-sos',
                      category: 'tools', quantity: 1, source: 'test')
  end

  describe 'teto vindo do item base' do
    it 'trata a chave ausente como cheio' do
      expect(kit.uses_max).to eq(10)
      expect(kit.uses_remaining).to eq(10)
      expect(kit.props_json.to_h['uses_remaining']).to be_nil
    end

    it 'gasta e persiste o restante' do
      described_class.new(item: kit, amount: 1).call
      expect(kit.reload.uses_remaining).to eq(9)
    end

    it 'gasta varios de uma vez' do
      described_class.new(item: kit, amount: 3).call
      expect(kit.reload.uses_remaining).to eq(7)
    end

    it 'recusa gastar mais do que resta' do
      described_class.new(item: kit, amount: 9).call
      expect { described_class.new(item: kit, amount: 2).call }
        .to raise_error(described_class::InvalidUse)
      expect(kit.reload.uses_remaining).to eq(1)
    end

    it 'recusa item sem usos declarados' do
      comum = SheetItem.create!(sheet: sheet, item_name: 'Corda', item_index: 'corda-spec',
                                category: 'gear', quantity: 1, source: 'test')
      expect { described_class.new(item: comum, amount: 1).call }
        .to raise_error(described_class::InvalidUse)
    end
  end

  describe 'recuperacao no descanso' do
    before { described_class.new(item: kit, amount: 4).call }

    it 'NAO devolve usos de kit sem token de recarga' do
      Sheets::Runtime::ItemUses.restore_all!(sheet.reload, kind: :long)
      expect(kit.reload.uses_remaining).to eq(6)
    end

    it 'devolve cargas de item com recarga longa, so no descanso longo' do
      kit_base.update!(props: kit_base.props.merge('uses_recharge' => 'long'))

      Sheets::Runtime::ItemUses.restore_all!(sheet.reload, kind: :short)
      expect(kit.reload.uses_remaining).to eq(6)

      Sheets::Runtime::ItemUses.restore_all!(sheet.reload, kind: :long)
      expect(kit.reload.uses_remaining).to eq(10)
    end

    it 'devolve carga de recarga curta nos DOIS descansos' do
      kit_base.update!(props: kit_base.props.merge('uses_recharge' => 'short'))

      Sheets::Runtime::ItemUses.restore_all!(sheet.reload, kind: :short)
      expect(kit.reload.uses_remaining).to eq(10)
    end

    it 'apaga a chave ao restaurar (ausente = cheio)' do
      kit_base.update!(props: kit_base.props.merge('uses_recharge' => 'long'))
      Sheets::Runtime::ItemUses.restore_all!(sheet.reload, kind: :long)
      expect(kit.reload.props_json.to_h['uses_remaining']).to be_nil
    end
  end

  it 'expoe o contador no JSON de inventario' do
    described_class.new(item: kit, amount: 2).call
    json = kit.reload.as_inventory_json
    expect(json[:uses_props]).to include('uses_max' => 10)
    expect(json[:uses_remaining]).to eq(8)
  end
end
