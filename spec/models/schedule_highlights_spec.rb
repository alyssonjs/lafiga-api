# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Schedule, type: :model do
  describe 'scheduling availability by group' do
    let(:group) { create(:group) }
    let(:other_group) { create(:group) }
    let(:date_a) { create(:date_dimension, date: Date.current + 10.days) }
    let(:date_b) { create(:date_dimension, date: Date.current + 15.days) }

    it 'blocks a second open session for the same group even on another date' do
      create(:schedule, group: group, date_dimension: date_a, status: :waiting)

      schedule = build(:schedule, group: group, date_dimension: date_b, status: :waiting)

      expect(schedule).not_to be_valid
      expect(schedule.errors[:base]).to include('Este grupo já possui uma sessão marcada para acontecer.')
    end

    it 'allows scheduling after prior sessions are completed or cancelled' do
      create(:schedule, group: group, date_dimension: date_a, status: :completed)
      create(:schedule, group: other_group, date_dimension: date_b, status: :cancelled)

      expect(build(:schedule, group: group, date_dimension: date_b, status: :waiting)).to be_valid
      expect(build(:schedule, group: other_group, date_dimension: date_a, status: :waiting)).to be_valid
    end
  end

  describe 'highlights normalization (passo 5)' do
    # Construímos um Schedule sem persistir para focar na normalização do
    # atributo `highlights`. Save real exigiria DateDimension/Group disponíveis
    # — fora do escopo deste spec.
    let(:schedule) { Schedule.new }

    it 'aceita array de hashes válidos com chaves string ou symbol' do
      schedule.highlights = [
        { 'text' => 'Derrotou o boss', 'type' => 'combat' },
        { text: 'Negociou trégua', type: 'social' }
      ]
      schedule.valid?

      expect(schedule.highlights).to eq([
        { 'text' => 'Derrotou o boss', 'type' => 'combat' },
        { 'text' => 'Negociou trégua', 'type' => 'social' }
      ])
    end

    it 'usa narrative como tipo padrão quando o type é desconhecido' do
      schedule.highlights = [{ 'text' => 'Achou um mapa', 'type' => 'magic-realism' }]
      schedule.valid?

      expect(schedule.highlights.first['type']).to eq('narrative')
    end

    it 'aceita strings simples e converte para hashes narrative' do
      schedule.highlights = ['Encontrou pista importante']
      schedule.valid?

      expect(schedule.highlights).to eq([
        { 'text' => 'Encontrou pista importante', 'type' => 'narrative' }
      ])
    end

    it 'descarta entradas vazias ou sem texto' do
      schedule.highlights = [
        { 'text' => '', 'type' => 'combat' },
        nil,
        { 'type' => 'narrative' },
        { 'text' => '   ', 'type' => 'social' },
        { 'text' => 'Mantém' }
      ]
      schedule.valid?

      expect(schedule.highlights).to eq([
        { 'text' => 'Mantém', 'type' => 'narrative' }
      ])
    end

    it 'aceita lista vazia (limpa highlights)' do
      schedule.highlights = []
      # Como os outros casos do describe (linhas 17/27/34/49), so executamos
      # `valid?` para disparar o callback de normalizacao — `be_valid` quebra
      # porque o Schedule sem date_dimension/group/title falha em validacoes
      # nao-relacionadas ao callback `normalize_highlights` que estamos testando.
      schedule.valid?
      expect(schedule.highlights).to eq([])
    end
  end
end
