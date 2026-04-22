# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubklassSlugResolver do
  describe '.normalize' do
    it 'NÃO mapeia berserker (api_index já existe direto no DB pós-Phase 4)' do
      # Antes existia 'berserker' => 'caminho-do-furioso' mas
      # 'caminho-do-furioso' nunca foi seedado. Removido na Phase 4.
      expect(described_class.normalize('berserker')).to eq('berserker')
    end

    it 'mapeia juramentos PT-BR de paladino para api_index SRD do DB (devotion/ancients/vengeance)' do
      # Phase 4 — antes mapeava para 'oath_of_*' que NUNCA foi seedado.
      expect(described_class.normalize('juramento-de-devocao')).to eq('devotion')
      expect(described_class.normalize('juramento-dos-ancioes')).to eq('ancients')
      expect(described_class.normalize('juramento-de-vinganca')).to eq('vengeance')
    end

    it 'mapeia open_hand para mao-aberta' do
      expect(described_class.normalize('open_hand')).to eq('mao-aberta')
    end

    it 'mapeia life para dominio-da-vida (cleric)' do
      expect(described_class.normalize('life')).to eq('dominio-da-vida')
    end

    it 'mapeia atalho legacy evocacao → escola-de-evocacao (import XLSX / provision)' do
      expect(described_class.normalize('evocacao')).to eq('escola-de-evocacao')
    end

    it 'devolve o próprio slug PT-BR para escolas de wizard canônicas (sem alias quebrado evocation)' do
      # Phase 3.0 regression — antes existia 'escola-de-evocacao' => 'evocation'
      # mas 'evocation' nunca foi seedado no DB. Corrigido removendo esse alias.
      expect(described_class.normalize('escola-de-evocacao')).to eq('escola-de-evocacao')
      expect(described_class.normalize('escola-de-abjuracao')).to eq('escola-de-abjuracao')
      expect(described_class.normalize('escola-de-conjuracao')).to eq('escola-de-conjuracao')
    end

    it 'normaliza nome PT exibido no wizard para slug ASCII' do
      expect(described_class.normalize('Círculo da Vida')).to eq('circulo-da-vida')
      expect(described_class.normalize('Caminho do Furioso')).to eq('caminho-do-furioso')
    end

    it 'devolve slug bruto quando não há alias e já está em ASCII' do
      expect(described_class.normalize('mao-aberta')).to eq('mao-aberta')
    end
  end

  describe '.ascii_slug' do
    it 'remove acentos e espaços' do
      expect(described_class.ascii_slug('Coração de Pedra')).to eq('coracao-de-pedra')
    end
  end
end
