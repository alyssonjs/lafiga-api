# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix B1.1 do relatorio de auditoria de steps: GeneralEditService
# historicamente persistia apenas `name` e descartava silenciosamente
# `playerName`, `isNPC`, `npcRole`, `npcFaction`, `npcLocation`, `npcStatus`,
# `dmNotes`. `read` devolvia `isNPC: false` hardcoded. Agora roundtripamos
# todos esses campos via `sheet.metadata['general']`.
RSpec.describe CharacterSheetEdits::GeneralEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active, name: 'Antigo') }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race, current_level: 3) }

  describe '#apply!' do
    it 'persiste o nome no character e nao toca metadata se so vier name' do
      svc = described_class.new(character: character, data: { 'name' => 'Novo Nome' })
      svc.call
      character.reload
      sheet.reload
      expect(character.name).to eq('Novo Nome')
      expect((sheet.metadata || {})['general']).to be_nil
    end

    it 'persiste todos os campos NPC/player/notes em metadata.general' do
      svc = described_class.new(character: character, data: {
        'name' => 'Novo',
        'playerName' => 'Alysson',
        'isNPC' => true,
        'npcRole' => 'Vilao',
        'npcFaction' => 'Culto da Sombra',
        'npcLocation' => 'Torre Negra',
        'npcStatus' => 'alive',
        'dmNotes' => 'Tem medo de gatos.'
      })
      svc.call

      sheet.reload
      gen = sheet.metadata['general']
      expect(gen).to include(
        'playerName' => 'Alysson',
        'isNPC' => true,
        'npcRole' => 'Vilao',
        'npcFaction' => 'Culto da Sombra',
        'npcLocation' => 'Torre Negra',
        'npcStatus' => 'alive',
        'dmNotes' => 'Tem medo de gatos.'
      )
    end

    it 'coerce isNPC string "true"/"false" para boolean' do
      svc = described_class.new(character: character, data: { 'isNPC' => 'true' })
      svc.call
      sheet.reload
      expect(sheet.metadata.dig('general', 'isNPC')).to eq(true)

      svc2 = described_class.new(character: character.reload, data: { 'isNPC' => 'false' })
      svc2.call
      sheet.reload
      expect(sheet.metadata.dig('general', 'isNPC')).to eq(false)
    end

    it 'preserva campos NPC anteriores quando recebe PATCH parcial' do
      sheet.update!(metadata: { 'general' => { 'playerName' => 'Old', 'dmNotes' => 'mantem' } })

      svc = described_class.new(character: character, data: { 'playerName' => 'New' })
      svc.call

      sheet.reload
      expect(sheet.metadata.dig('general', 'playerName')).to eq('New')
      expect(sheet.metadata.dig('general', 'dmNotes')).to eq('mantem')
    end
  end

  describe '#read' do
    it 'devolve nome do character e nivel do sheet' do
      out = described_class.new(character: character, data: {}).read
      expect(out).to include('name' => 'Antigo', 'level' => 3, 'isNPC' => false)
    end

    it 'devolve campos persistidos em metadata.general (roundtrip)' do
      sheet.update!(metadata: {
        'general' => {
          'playerName' => 'Alysson', 'isNPC' => true, 'npcRole' => 'Patrono',
          'npcFaction' => 'Conclave', 'npcLocation' => 'Capital',
          'npcStatus' => 'dead', 'dmNotes' => 'Reincarnou.'
        }
      })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out).to include(
        'playerName' => 'Alysson', 'isNPC' => true, 'npcRole' => 'Patrono',
        'npcFaction' => 'Conclave', 'npcLocation' => 'Capital',
        'npcStatus' => 'dead', 'dmNotes' => 'Reincarnou.'
      )
    end
  end
end
