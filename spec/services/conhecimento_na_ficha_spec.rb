# frozen_string_literal: true

require 'rails_helper'

# CONHECIMENTO — a categoria houserule da mesa (o capacete de conexão com o
# mecha que o Valac estuda).
#
# ⚠️ O buraco que este spec tranca: treino concluído e concessão do Mestre são
# roteados por categoria para um bucket da ficha. Categoria sem destino no mapa
# não some com erro — some CALADA: o jogador treina 120 horas, a barra chega a
# 100%, e o conhecimento não aparece em lado nenhum.
RSpec.describe 'Conhecimento na ficha', type: :model do
  let(:user) { create(:user) }
  let(:sheet) { create(:sheet, character: create(:character, user: user)) }

  let!(:conhecimento) do
    Proficiency.find_or_initialize_by(api_index: 'knowledge-interface-neural').tap do |p|
      p.update!(name: 'Interface Neural do Mecha', category: 'knowledge',
                metadata: { 'trainable' => true, 'training_hours' => 120 })
    end
  end

  def proficiencias_da_ficha
    # `SimpleCommand` faz `call` devolver o COMANDO; o hash vem em `result`. E
    # `sync: false` como nos outros specs do serviço: com sync o `call` grava HP e
    # concede features, efeito colateral que nada tem a ver com proficiência.
    CharacterSheetSummaryService.new(sheet_id: sheet.id, sync: false).call.result[:proficiencies]
  end

  describe 'o catálogo aceita a categoria' do
    it 'grava com `knowledge` e sem sub-categoria' do
      expect(conhecimento).to be_persisted
      expect(conhecimento.category).to eq('knowledge')
    end

    it '⚠️ e continua recusando categoria inventada — a lista branca não afrouxou' do
      invalida = Proficiency.new(api_index: 'x-bug', name: 'X', category: 'nao_existe')

      expect(invalida).not_to be_valid
      expect(invalida.errors[:category]).to be_present
    end
  end

  describe 'treino por horas' do
    it 'com as horas cumpridas, o conhecimento ENTRA na ficha' do
      sheet.update!(training: {
                      conhecimento.api_index => { 'hours_required' => 120, 'hours_trained' => 120,
                                                  'learning' => true }
                    })

      expect(proficiencias_da_ficha[:knowledge]).to include('Interface Neural do Mecha')
    end

    # ⚠️ Sem as horas cumpridas NÃO entra. "Está a treinar" não pode virar "já
    # sabe" — seria dar a proficiência de graça.
    it 'a meio do treino, não entra' do
      sheet.update!(training: {
                      conhecimento.api_index => { 'hours_required' => 120, 'hours_trained' => 40,
                                                  'learning' => true }
                    })

      expect(proficiencias_da_ficha[:knowledge]).to eq([])
    end

    it 'e não vaza para os outros buckets' do
      sheet.update!(training: {
                      conhecimento.api_index => { 'hours_required' => 120, 'hours_trained' => 120,
                                                  'learning' => true }
                    })
      prof = proficiencias_da_ficha

      expect(prof[:tools]).not_to include('Interface Neural do Mecha')
      expect(prof[:languages]).not_to include('Interface Neural do Mecha')
    end
  end

  # ⚠️ A razão de o mapa de roteamento ter virado UMA constante: ele estava
  # escrito duas vezes, a 28 linhas de distância. Acrescentar a categoria só numa
  # faria o conhecimento aparecer para quem treinou e sumir para quem o Mestre
  # concedeu — e ninguém repararia até um jogador reclamar.
  describe 'concessão do Mestre' do
    it 'o Mestre concede e o conhecimento entra na MESMA lista' do
      sheet.update!(dm_proficiencies: {
                      conhecimento.api_index => { 'note' => 'estudou com o engenheiro de Vorthek' }
                    })

      expect(proficiencias_da_ficha[:knowledge]).to include('Interface Neural do Mecha')
    end
  end

  describe 'o bucket existe sempre' do
    # ⚠️ Tem de ser Array mesmo vazio: os dois `aplicar_*` PULAM a categoria cujo
    # destino não seja Array, e o conhecimento sumiria sem erro nenhum.
    it 'ficha sem conhecimento nenhum devolve array vazio, não nil' do
      expect(proficiencias_da_ficha[:knowledge]).to eq([])
    end
  end
end
