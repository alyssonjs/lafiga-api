# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix B8 do relatorio de auditoria de steps: o AvatarEditService nao
# persistia o flag `avatarUserEdited`. Agora persiste em
# `sheet.avatar_customization['_userEdited']` (aceita raiz ou aninhado), e
# `read` devolve a flag explicitamente para o front hidratar sem heuristica.
RSpec.describe CharacterSheetEdits::AvatarEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  describe '#read' do
    it 'devolve avatarUserEdited=false por default (campo nao persistido)' do
      out = described_class.new(character: character, data: {}).read
      expect(out['avatarUserEdited']).to be(false)
      expect(out['avatarCustomization']).to eq({})
    end

    it 'devolve avatarUserEdited=true quando _userEdited esta persistido' do
      sheet.update!(avatar_customization: { 'hair' => 'red', '_userEdited' => true })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['avatarUserEdited']).to be(true)
      expect(out['avatarCustomization']).to include('hair' => 'red', '_userEdited' => true)
    end
  end

  describe '#apply!' do
    it 'persiste avatarCustomization com merge raso (preserva keys nao incluidas)' do
      sheet.update!(avatar_customization: { 'hair' => 'red', 'eyes' => 'blue' })
      described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'gold' }
      }).call
      sheet.reload
      expect(sheet.avatar_customization).to include('hair' => 'gold', 'eyes' => 'blue')
    end

    it 'persiste avatarUserEdited=true vindo na raiz do payload' do
      described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'red' },
        'avatarUserEdited' => true
      }).call
      sheet.reload
      expect(sheet.avatar_customization['_userEdited']).to be(true)
      expect(sheet.avatar_customization['hair']).to eq('red')
    end

    it 'aceita avatarUserEdited aninhado em avatarCustomization (compat)' do
      described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'red', '_userEdited' => true }
      }).call
      sheet.reload
      expect(sheet.avatar_customization['_userEdited']).to be(true)
      # _userEdited nao deve aparecer duplicado nas keys de chibi
      expect(sheet.avatar_customization['hair']).to eq('red')
    end

    it 'coerce string truthy/falsy para boolean' do
      described_class.new(character: character, data: { 'avatarUserEdited' => 'true' }).call
      sheet.reload
      expect(sheet.avatar_customization['_userEdited']).to be(true)

      described_class.new(character: character, data: { 'avatarUserEdited' => 'false' }).call
      sheet.reload
      expect(sheet.avatar_customization['_userEdited']).to be(false)
    end

    it 'no-op quando payload nao traz nem customizacao nem flag' do
      sheet.update!(avatar_customization: { 'hair' => 'red' })
      described_class.new(character: character, data: {}).call
      sheet.reload
      expect(sheet.avatar_customization).to eq('hair' => 'red')
    end

    # Gap G10.1 do relatorio de auditoria de steps
    context 'G10.1 — deep_merge preserva sub-hashes nao enviados' do
      it 'PATCH parcial em outfitColors.primary nao apaga secondary/accent' do
        sheet.update!(avatar_customization: {
          'outfitColors' => { 'primary' => 'red', 'secondary' => 'blue', 'accent' => 'gold' }
        })
        described_class.new(character: character, data: {
          'avatarCustomization' => { 'outfitColors' => { 'primary' => 'green' } }
        }).call
        sheet.reload
        expect(sheet.avatar_customization['outfitColors']).to eq(
          'primary' => 'green', 'secondary' => 'blue', 'accent' => 'gold'
        )
      end

      it 'preserva keys irmas top-level' do
        sheet.update!(avatar_customization: { 'hair' => 'red', 'eyes' => 'blue' })
        described_class.new(character: character, data: {
          'avatarCustomization' => { 'hair' => 'gold' }
        }).call
        sheet.reload
        expect(sheet.avatar_customization).to include('hair' => 'gold', 'eyes' => 'blue')
      end
    end

    # ZX4 do segundo audit (parte 1/3): payload com `{ avatarUserEdited: null }`
    # vinha do front quando d.avatarUserEdited era undefined (`?? null`).
    # Antes, isso caia no primeiro branch e devolvia nil — pulando o fallback
    # nested em `_userEdited`. Resultado: char antigo (so com nested flag)
    # perdia o sinal a cada save sem flag explicita.
    context 'ZX4 — null na raiz cai no fallback nested' do
      it 'mantem _userEdited persistido quando payload envia null explicito' do
        sheet.update!(avatar_customization: { 'hair' => 'red', '_userEdited' => true })
        described_class.new(character: character.reload, data: {
          'avatarCustomization' => { 'hair' => 'red' },
          'avatarUserEdited' => nil
        }).call
        sheet.reload
        # Anti-bug ZX4: flag preservada (NAO virou nil, NAO foi sobrescrita)
        expect(sheet.avatar_customization['_userEdited']).to be(true)
      end

      it 'cai no fallback nested quando raiz veio nil mas avatarCustomization tem _userEdited' do
        described_class.new(character: character, data: {
          'avatarCustomization' => { 'hair' => 'red', '_userEdited' => true },
          'avatarUserEdited' => nil
        }).call
        sheet.reload
        expect(sheet.avatar_customization['_userEdited']).to be(true)
      end
    end

    it 'roundtrip: apply -> read preserva flag e dados' do
      svc1 = described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'gold', 'outfit' => 'wizard-robe' },
        'avatarUserEdited' => true
      })
      svc1.call

      out = described_class.new(character: character.reload, data: {}).read
      expect(out['avatarUserEdited']).to be(true)
      expect(out['avatarCustomization']).to include('hair' => 'gold', 'outfit' => 'wizard-robe')
    end
  end
end
