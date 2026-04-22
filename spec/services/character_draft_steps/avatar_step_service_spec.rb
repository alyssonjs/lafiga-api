# frozen_string_literal: true

require 'rails_helper'

# Espelho do AvatarEditService spec, agora cobrindo o AvatarStepService no
# modo CREATION. Bug B8 (paridade creation/edit) — flag persistida no draft
# em `merged['avatarUserEdited']`. ZX4 do segundo audit — `null` na raiz cai
# no fallback nested.
RSpec.describe CharacterDraftSteps::AvatarStepService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :draft) }

  describe '#apply!' do
    it 'persiste avatarUserEdited=true vindo na raiz do payload' do
      svc = described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'red' },
        'avatarUserEdited' => true
      })
      result = svc.call
      expect(result.draft_data['avatarUserEdited']).to be(true)
      expect(result.draft_data.dig('avatarCustomization', 'hair')).to eq('red')
    end

    it 'aceita avatarUserEdited aninhado em avatarCustomization (compat legado)' do
      svc = described_class.new(character: character, data: {
        'avatarCustomization' => { 'hair' => 'red', '_userEdited' => true }
      })
      result = svc.call
      expect(result.draft_data['avatarUserEdited']).to be(true)
    end

    it 'no-op quando payload nao traz nem customizacao nem flag' do
      character.update!(draft_data: { 'avatarCustomization' => { 'hair' => 'red' } })
      svc = described_class.new(character: character, data: {})
      result = svc.call
      expect(result.draft_data.dig('avatarCustomization', 'hair')).to eq('red')
    end

    # ZX4 do segundo audit (parte 1/3): payload com `{ avatarUserEdited: nil }`
    # vinha do front (legado de `?? null`). Antes, isso caia no primeiro branch
    # e devolvia nil — pulando o fallback aninhado em `_userEdited`.
    context 'ZX4 — null na raiz cai no fallback nested' do
      it 'mantem avatarUserEdited previo quando payload envia null explicito SEM nested flag' do
        character.update!(draft_data: { 'avatarCustomization' => { 'hair' => 'red' }, 'avatarUserEdited' => true })
        svc = described_class.new(character: character.reload, data: {
          'avatarCustomization' => { 'hair' => 'red' },
          'avatarUserEdited' => nil
        })
        result = svc.call
        # Anti-bug ZX4: flag previa preservada (NAO virou nil/false silenciosamente)
        expect(result.draft_data['avatarUserEdited']).to be(true)
      end

      it 'cai no fallback nested quando raiz veio nil mas avatarCustomization tem _userEdited' do
        svc = described_class.new(character: character, data: {
          'avatarCustomization' => { 'hair' => 'red', '_userEdited' => true },
          'avatarUserEdited' => nil
        })
        result = svc.call
        expect(result.draft_data['avatarUserEdited']).to be(true)
      end
    end

    # Gap G10.1 do relatorio de auditoria: deep_merge preserva sub-hashes
    it 'G10.1 — deep_merge preserva sub-hashes nao enviados' do
      character.update!(draft_data: {
        'avatarCustomization' => {
          'outfitColors' => { 'primary' => 'red', 'secondary' => 'blue', 'accent' => 'gold' }
        }
      })
      svc = described_class.new(character: character.reload, data: {
        'avatarCustomization' => { 'outfitColors' => { 'primary' => 'green' } }
      })
      result = svc.call
      expect(result.draft_data.dig('avatarCustomization', 'outfitColors')).to eq(
        'primary' => 'green', 'secondary' => 'blue', 'accent' => 'gold'
      )
    end
  end
end
