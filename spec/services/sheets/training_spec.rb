# frozen_string_literal: true

require 'rails_helper'

# Treino de proficiência: quantas horas o personagem precisa e quantas já fez.
# Duas camadas, e o mestre manda nas duas — o catálogo diz o padrão, a ficha diz
# a exceção deste personagem e o progresso dele.
RSpec.describe Sheets::Training do
  let!(:lira) do
    Proficiency.create!(api_index: 'tool-lira', name: 'Lira', category: 'tool',
                        sub_category: 'instrument',
                        metadata: { 'trainable' => true, 'training_hours' => 60 })
  end

  def aplica(atual, patch)
    limpo, erros = described_class.sanitize(patch, actor_id: 7, previous: atual)
    raise "erros: #{erros.inspect}" if erros.any?

    described_class.merge(atual, limpo)
  end

  describe 'o fluxo da mesa' do
    it 'exceção, progresso sessão a sessão, e conclusão' do
      t = aplica({}, 'tool-lira' => { 'hours_required' => 25, 'note' => 'tocava desde criança' })
      expect(described_class.describe(t, lira)).to include(
        'hours_required' => 25, 'hours_trained' => 0, 'remaining' => 25, 'complete' => false,
      )

      t = aplica(t, 'tool-lira' => { 'hours_trained' => 10 })
      expect(described_class.describe(t, lira)).to include('remaining' => 15, 'complete' => false)

      t = aplica(t, 'tool-lira' => { 'hours_trained' => 25 })
      expect(described_class.describe(t, lira)).to include('remaining' => 0, 'complete' => true)
    end

    it '⚠️ patch parcial DENTRO da linha: mandar só as horas feitas não apaga a exceção' do
      # Dois gestos diferentes em dias diferentes. Se o segundo apagasse o
      # primeiro, o mestre perderia o ajuste sem perceber.
      t = aplica({}, 'tool-lira' => { 'hours_required' => 25, 'note' => 'desde criança' })
      t = aplica(t, 'tool-lira' => { 'hours_trained' => 10 })
      expect(t.dig('tool-lira', 'hours_required')).to eq(25)
      expect(t.dig('tool-lira', 'note')).to eq('desde criança')
    end

    it 'soltar SÓ a exceção volta ao catálogo e PRESERVA as horas já feitas' do
      t = aplica({}, 'tool-lira' => { 'hours_required' => 25, 'hours_trained' => 25 })
      t = aplica(t, 'tool-lira' => { 'hours_required' => '' })
      d = described_class.describe(t, lira)
      expect(d['hours_required']).to eq(60)   # o padrão do catálogo
      expect(d['hours_trained']).to eq(25)    # o treino não se perde
      expect(d['overridden']).to be(false)
    end

    it '`nil` na chave apaga a linha inteira' do
      t = aplica({}, 'tool-lira' => { 'hours_trained' => 10 })
      expect(described_class.merge(t, 'tool-lira' => nil)).to eq({})
    end
  end

  describe 'guardas' do
    it '⚠️ recusa chave que não existe no CATÁLOGO' do
      _, erros = described_class.sanitize({ 'tool-inventada' => { 'hours_trained' => 10 } })
      expect(erros.join).to match(/não catalogada/)
    end

    it 'recusa hora negativa, mas ZERO é válido em horas feitas' do
      # Zero horas treinadas é o estado inicial legítimo de quem começou agora.
      _, erros = described_class.sanitize({ 'tool-lira' => { 'hours_trained' => -1 } })
      expect(erros).not_to be_empty
      limpo, ok = described_class.sanitize({ 'tool-lira' => { 'hours_trained' => 0 } })
      expect(ok).to eq([])
      expect(limpo.dig('tool-lira', 'hours_trained')).to eq(0)
    end
  end

  describe '#describe' do
    it '⚠️ sem horas definidas, `complete` é nil — não `true`' do
      # "Por definir" não pode virar "já sabe" por omissão.
      lira.update!(metadata: { 'trainable' => true })
      d = described_class.describe({}, lira)
      expect(d['complete']).to be_nil
      expect(d).not_to have_key('remaining')
    end

    it 'proficiência NÃO treinável não gera linha nenhuma' do
      lira.update!(metadata: {})
      expect(described_class.describe({}, lira)).to be_nil
    end

    it 'guarda o padrão do catálogo do MOMENTO em que o mestre mexeu' do
      t = aplica({}, 'tool-lira' => { 'hours_required' => 25 })
      lira.update!(metadata: { 'trainable' => true, 'training_hours' => 999 })
      # A ficha continua a saber que, quando se cravou, o catálogo pedia 60.
      expect(t.dig('tool-lira', 'default')).to eq(60)
    end
  end
end
