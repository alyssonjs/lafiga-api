# frozen_string_literal: true

require 'rails_helper'

# Bug guard: SheetItem#has_dual_wielder_feat? checava só substring de nomes
# legados ('dual wielder', 'duas armas', etc.) e NÃO cobria o nome PT-BR
# canônico 'Mestre de Armas Duplas' (api_index `mestre_de_armas_duplas`).
# Resultado: usuário com a façanha ficava bloqueado de equipar arma não-leve
# na mão secundária — backend rejeitava com 'A arma da mão secundária deve
# ser leve'.
RSpec.describe SheetItem, '#has_dual_wielder_feat?' do
  let(:user)      { create(:user) }
  let(:character) { create(:character, user: user) }
  let(:sheet)     { create(:sheet, character: character) }
  let(:item)      { SheetItem.new(sheet: sheet) }

  describe 'reconhece "Mestre de Armas Duplas" (PT-BR oficial)' do
    let!(:feat) do
      Feat.find_or_create_by!(name: 'Mestre de Armas Duplas') do |f|
        f.api_index = 'mestre_de_armas_duplas'
      end
    end

    it 'via associação Sheet#feats por api_index' do
      SheetFeat.create!(sheet: sheet, feat: feat, level_gained: 4)
      sheet.reload
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end

    it 'via metadata.feats com api_index canônico' do
      sheet.update!(metadata: { 'feats' => [{ 'api_index' => 'mestre_de_armas_duplas' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end

    it 'via metadata.feats com nome PT-BR' do
      sheet.update!(metadata: { 'feats' => [{ 'name' => 'Mestre de Armas Duplas' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end
  end

  describe 'reconhece variantes históricas (não regredir)' do
    it 'dual wielder (SRD EN)' do
      sheet.update!(metadata: { 'feats' => [{ 'name' => 'Dual Wielder' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end

    it 'empunhador duplo (PT alternativo)' do
      sheet.update!(metadata: { 'feats' => [{ 'name' => 'Empunhador Duplo' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end

    it 'duas armas (substring histórica)' do
      sheet.update!(metadata: { 'feats' => [{ 'name' => 'Mestre das Duas Armas' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(true)
    end
  end

  describe 'recusa façanhas não relacionadas' do
    it 'Resiliente (não dá dual wielder)' do
      sheet.update!(metadata: { 'feats' => [{ 'name' => 'Resiliente' }] })
      expect(item.send(:has_dual_wielder_feat?)).to eq(false)
    end

    it 'metadata vazio' do
      expect(item.send(:has_dual_wielder_feat?)).to eq(false)
    end
  end
end
