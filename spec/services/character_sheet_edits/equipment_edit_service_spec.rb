# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix B6 do relatorio de auditoria de steps: o EquipmentEditService
# era um "thin passthrough" que apenas gravava metadata.equipment.* e emitia
# warning. Agora aceita opcionalmente `equipmentPicks` para reprovisionar
# `SheetItem`s auto (source='class') de forma idempotente, preservando items
# adicionados pelo jogador via CRUD live.
RSpec.describe CharacterSheetEdits::EquipmentEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  describe '#read' do
    it 'devolve metadata.equipment.* com defaults vazios' do
      out = described_class.new(character: character, data: {}).read
      expect(out['equipmentMode']).to be_nil
      expect(out['equipmentChoices']).to eq([])
      expect(out['equipmentGenericSelections']).to eq({})
    end

    it 'reflete metadata previamente salvo' do
      sheet.update!(metadata: {
        'equipment' => {
          'mode' => 'gold',
          'choices' => [{ 'kind' => 'weapon', 'pick' => 'longsword' }],
          'generic' => { 'instrument' => 'lute' },
          'startingGoldRolled' => 75
        }
      })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['equipmentMode']).to eq('gold')
      expect(out['equipmentChoices'].size).to eq(1)
      expect(out['equipmentGenericSelections']).to eq('instrument' => 'lute')
      expect(out['startingGoldRolled']).to eq(75)
    end
  end

  describe '#apply! sem equipmentPicks (compat legado)' do
    it 'persiste metadata e emite warning de inventario nao alterado' do
      svc = described_class.new(character: character, data: {
        'equipmentMode' => 'preset', 'equipmentChoices' => [{ 'kind' => 'a' }]
      })
      result = svc.call
      sheet.reload

      expect(sheet.metadata.dig('equipment', 'mode')).to eq('preset')
      expect(sheet.metadata.dig('equipment', 'choices')).to eq([{ 'kind' => 'a' }])
      expect(result.warnings.join(' ')).to match(/inventario ao vivo nao alterado/)
    end
  end

  describe '#apply! com equipmentPicks (reprovision)' do
    let!(:player_added) do
      # Item adicionado manualmente pelo jogador via CRUD live — NUNCA tem
      # `provisioning_run_id` em props_json, logo nao deve ser tocado.
      SheetItem.create!(
        sheet: sheet, item_name: 'Pocao de Cura', category: 'consumable',
        quantity: 2, source: 'class', props_json: { 'note' => 'comprada na loja' }
      )
    end

    it 'cria SheetItems com provisioning_run_id e preserva os manuais do jogador' do
      svc = described_class.new(character: character, data: {
        'equipmentMode' => 'preset',
        'equipmentPicks' => [
          { 'item_name' => 'Espada Longa', 'category' => 'weapon', 'quantity' => 1, 'equipped' => true },
          { 'item_name' => 'Escudo', 'category' => 'armor', 'quantity' => 1 }
        ]
      })
      result = svc.call
      sheet.reload

      provisioned = sheet.sheet_items.select { |i| i.props_json&.key?('provisioning_run_id') }
      expect(provisioned.map(&:item_name)).to contain_exactly('Espada Longa', 'Escudo')
      expect(provisioned.detect { |i| i.item_name == 'Espada Longa' }.equipped).to be(true)

      manual = sheet.sheet_items.detect { |i| i.item_name == 'Pocao de Cura' }
      expect(manual).to be_present
      expect(manual.quantity).to eq(2)

      # Sem warning — reprovisionou
      expect(result.warnings.join(' ')).not_to match(/inventario ao vivo nao alterado/)
    end

    it 'reprovision e idempotente: chamada subsequente substitui o lote anterior' do
      data = {
        'equipmentPicks' => [{ 'item_name' => 'Adaga', 'quantity' => 1 }]
      }
      described_class.new(character: character, data: data).call
      sheet.reload
      first_run_count = sheet.sheet_items.count
      first_provisioned_id = sheet.sheet_items.detect { |i| i.item_name == 'Adaga' }&.id

      described_class.new(character: character, data: data).call
      sheet.reload
      expect(sheet.sheet_items.count).to eq(first_run_count) # mesmo total
      new_id = sheet.sheet_items.detect { |i| i.item_name == 'Adaga' }&.id
      expect(new_id).not_to eq(first_provisioned_id) # mas e um novo registro (run_id mudou)
    end

    it 'preserva equipped/slot/notes em re-edicao do mesmo item' do
      described_class.new(character: character, data: {
        'equipmentPicks' => [{ 'item_name' => 'Cota de Malha', 'category' => 'armor', 'quantity' => 1 }]
      }).call
      sheet.reload
      cota = sheet.sheet_items.detect { |i| i.item_name == 'Cota de Malha' }
      cota.update!(equipped: true, slot: 'armor', notes: 'reforcada')

      described_class.new(character: character, data: {
        'equipmentPicks' => [{ 'item_name' => 'Cota de Malha', 'category' => 'armor', 'quantity' => 1 }]
      }).call
      sheet.reload
      cota_new = sheet.sheet_items.detect { |i| i.item_name == 'Cota de Malha' }
      expect(cota_new.equipped).to be(true)
      expect(cota_new.slot).to eq('armor')
      expect(cota_new.notes).to eq('reforcada')
    end

    # ZX5 do segundo audit: antes era `delete_all` + `insert_all` SEM transacao
    # interna, com rescue silenciador. Se o insert quebrasse (validacao,
    # exception transient), o delete ja tinha rodado e o usuario perdia o
    # inventario inteiro com so um warning. Agora encapsulamos em savepoint.
    describe 'ZX5 — atomicidade entre delete_all e insert_all' do
      it 'rollback: prior items preservados quando insert falha (StandardError)' do
        # Seed: 2 items auto-provisionados que deveriam ser preservados se o
        # reprovision falhar.
        run_id = SecureRandom.uuid
        SheetItem.create!(sheet: sheet, item_name: 'Anel da Sorte',
                          source: 'class', quantity: 1,
                          props_json: { 'provisioning_run_id' => run_id })
        SheetItem.create!(sheet: sheet, item_name: 'Capa Elfica',
                          source: 'class', quantity: 1,
                          props_json: { 'provisioning_run_id' => run_id })
        prior_count = sheet.sheet_items.where(source: 'class').count
        expect(prior_count).to be >= 3 # 2 acima + Pocao de Cura (manual, mas same source)

        # Stub para forçar exception no insert_all (mesma forma que aconteceria
        # numa migracao quebrada / coluna nova nao-nullable / etc).
        allow(SheetItem).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, 'boom')

        result = described_class.new(character: character.reload, data: {
          'equipmentPicks' => [{ 'item_name' => 'Espada Longa', 'category' => 'weapon', 'quantity' => 1 }]
        }).call

        sheet.reload
        # Anti-bug ZX5: items prior PRESERVADOS (rollback do savepoint)
        expect(sheet.sheet_items.where(source: 'class').count).to eq(prior_count)
        expect(sheet.sheet_items.find_by(item_name: 'Anel da Sorte')).to be_present
        expect(sheet.sheet_items.find_by(item_name: 'Capa Elfica')).to be_present
        # Item manual NUNCA tocado
        expect(sheet.sheet_items.find_by(item_name: 'Pocao de Cura')).to be_present
        # Warn reportado para a UI saber que reprovision falhou
        expect(result.warnings.join(' ')).to match(/reprovision de equipment falhou/)
      end
    end

    it 'equipmentPicks vazio remove todos os auto-provisionados sem mexer nos manuais' do
      described_class.new(character: character, data: {
        'equipmentPicks' => [{ 'item_name' => 'Adaga', 'quantity' => 1 }]
      }).call
      sheet.reload
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Adaga' }).to be_present

      described_class.new(character: character, data: {
        'equipmentPicks' => []
      }).call
      sheet.reload
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Adaga' }).to be_nil
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Pocao de Cura' }).to be_present
    end
  end
end
