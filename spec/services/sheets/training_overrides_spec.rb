# frozen_string_literal: true

require 'rails_helper'

# Horas de treino CASO A CASO: o catálogo diz o padrão, o mestre crava a exceção
# para UM personagem. "Ferramentas de ferreiro custam 120h, mas o filho do
# ferreiro aprende em 80."
RSpec.describe Sheets::TrainingOverrides do
  let!(:ferreiro) do
    Proficiency.create!(api_index: 'tool-ferreiro', name: 'Ferramentas de ferreiro',
                        category: 'tool', sub_category: 'artisan',
                        metadata: { 'trainable' => true, 'training_hours' => 120 })
  end

  describe '.sanitize' do
    it 'grava as horas, o motivo e o PADRÃO do catálogo no momento' do
      # `default` é o que deixa a ficha dizer "o catálogo pede 120, o Mestre pôs
      # 80" — e continuar a dizê-lo mesmo que o catálogo mude depois.
      limpo, erros = described_class.sanitize(
        { 'tool-ferreiro' => { 'hours' => 80, 'note' => 'cresceu na forja' } }, actor_id: 7,
      )
      expect(erros).to eq([])
      expect(limpo['tool-ferreiro']).to include(
        'hours' => 80, 'default' => 120, 'note' => 'cresceu na forja', 'by_user_id' => 7,
      )
    end

    it '⚠️ recusa chave que não existe no CATÁLOGO' do
      # Sem isto, um erro de digitação gravaria horas para uma proficiência que
      # ninguém tem, e o ajuste ficaria invisível para sempre.
      _, erros = described_class.sanitize({ 'tool-inventada' => { 'hours' => 10 } })
      expect(erros.join).to match(/não catalogada/)
    end

    it '`nil` é o gesto de SOLTAR — volta a valer o padrão' do
      limpo, = described_class.sanitize({ 'tool-ferreiro' => nil })
      expect(limpo).to eq('tool-ferreiro' => nil)
    end

    it 'recusa horas não positivas' do
      _, erros = described_class.sanitize({ 'tool-ferreiro' => { 'hours' => 0 } })
      expect(erros.join).to match(/Horas inválidas/)
    end

    it 'aceita o número solto, sem hash' do
      limpo, = described_class.sanitize({ 'tool-ferreiro' => 45 })
      expect(limpo.dig('tool-ferreiro', 'hours')).to eq(45)
    end
  end

  describe '.merge' do
    it 'é PARCIAL: chave ausente fica, chave nil sai' do
      # Substituir o hash inteiro faria dois mestres a editar ao mesmo tempo
      # apagarem ajuste alheio.
      atual = { 'a' => { 'hours' => 1 }, 'b' => { 'hours' => 2 } }
      expect(described_class.merge(atual, 'b' => nil)).to eq('a' => { 'hours' => 1 })
      expect(described_class.merge(atual, 'c' => { 'hours' => 3 }).keys).to match_array(%w[a b c])
    end
  end

  describe '.hours_for' do
    it 'a sobrescrita VENCE o catálogo' do
      expect(described_class.hours_for({ 'tool-ferreiro' => { 'hours' => 80 } }, ferreiro)).to eq(80)
    end

    it 'sem sobrescrita, vale o padrão do catálogo' do
      expect(described_class.hours_for({}, ferreiro)).to eq(120)
    end

    it '⚠️ sem nenhum dos dois, `nil` — que é "por definir", não "de graça"' do
      ferreiro.update!(metadata: { 'trainable' => true })
      expect(described_class.hours_for({}, ferreiro)).to be_nil
    end
  end

  describe '.describe' do
    it 'diz as horas efetivas, o padrão e que foi cravado' do
      d = described_class.describe({ 'tool-ferreiro' => { 'hours' => 80, 'note' => 'forja' } }, ferreiro)
      expect(d).to include('hours' => 80, 'catalog_hours' => 120, 'overridden' => true, 'note' => 'forja')
    end

    it 'sem sobrescrita, marca que NÃO foi cravado' do
      d = described_class.describe({}, ferreiro)
      expect(d).to include('hours' => 120, 'overridden' => false)
    end

    it '⚠️ proficiência NÃO treinável não gera linha nenhuma' do
      ferreiro.update!(metadata: {})
      expect(described_class.describe({}, ferreiro)).to be_nil
    end
  end
end
