# frozen_string_literal: true

require 'rails_helper'

# APRENDIZADO — proficiência que o personagem ainda NÃO tem e está a treinar.
#
# "eu como mestre quero poder adicionar uma nova perícia que o personagem esteja
# aprendendo e as horas necessárias e as que ele já tem (...) ao concluir, a
# perícia deve ser incluída na lista de perícias do personagem informando que
# foi aprendida."
#
# ⚠️ O irmão `Sheets::Training.describe` cobre outra coisa: o treino de uma
# proficiência que o personagem JÁ tem. Este é o caminho de aquisição.
RSpec.describe 'Sheets::Training — aprendizado', type: :service do
  let(:pericia) do
    Proficiency.find_by(api_index: 'skill-furtividade') ||
      Proficiency.create!(api_index: 'skill-furtividade', name: 'Furtividade', category: 'skill')
  end
  let(:ferramenta) do
    Proficiency.find_by(api_index: 'tool-ferreiro') ||
      Proficiency.create!(api_index: 'tool-ferreiro', name: 'Ferramentas de ferreiro',
                          category: 'tool', sub_category: 'artisan')
  end

  def treino(**attrs)
    { pericia.api_index => { 'learning' => true }.merge(attrs.stringify_keys) }
  end

  describe 'a lista do card' do
    it 'traz nome, horas e a barra de progresso' do
      linha = Sheets::Training.learning_list(
        treino(hours_required: 40, hours_trained: 10)
      ).first

      expect(linha).to include(
        'name' => 'Furtividade', 'category' => 'skill',
        'hours_required' => 40, 'hours_trained' => 10,
        'percent' => 25, 'remaining' => 30, 'complete' => false
      )
    end

    it 'marca CONCLUÍDA quando as horas fecham', :aggregate_failures do
      linha = Sheets::Training.learning_list(treino(hours_required: 20, hours_trained: 20)).first
      expect(linha['complete']).to be(true)
      expect(linha['percent']).to eq(100)
    end

    it '⚠️ passar das horas não estoura a barra' do
      linha = Sheets::Training.learning_list(treino(hours_required: 20, hours_trained: 50)).first
      expect(linha['percent']).to eq(100)
      expect(linha['remaining']).to eq(0)
    end

    it '⚠️ sem horas definidas NÃO é concluída — nem tem barra' do
      # "Por definir" não pode virar "já aprendeu" por omissão: seria dar a
      # proficiência de graça.
      linha = Sheets::Training.learning_list(treino(hours_trained: 999)).first
      expect(linha['complete']).to be(false)
      expect(linha).not_to have_key('percent')
    end

    it 'em curso vem antes de concluída — é o que o mestre vai mexer' do
      nomes = Sheets::Training.learning_list(
        { pericia.api_index => { 'learning' => true, 'hours_required' => 20, 'hours_trained' => 20 },
          ferramenta.api_index => { 'learning' => true, 'hours_required' => 40, 'hours_trained' => 1 } }
      ).map { |l| l['name'] }
      expect(nomes).to eq(['Ferramentas de ferreiro', 'Furtividade'])
    end

    it '⚠️ treino de proficiência que ele JÁ tem não entra no card' do
      # Sem a marca `learning`, a linha é o outro caminho (o crachá na ficha).
      sem_marca = { pericia.api_index => { 'hours_required' => 40, 'hours_trained' => 10 } }
      expect(Sheets::Training.learning_list(sem_marca)).to eq([])
    end

    it 'chave fora do catálogo é ignorada, não rebenta' do
      expect(Sheets::Training.learning_list({ 'nao-existe' => { 'learning' => true } })).to eq([])
    end

    it 'treino vazio devolve lista vazia' do
      expect(Sheets::Training.learning_list({})).to eq([])
      expect(Sheets::Training.learning_list(nil)).to eq([])
    end
  end

  describe 'as concluídas, por categoria' do
    it 'agrupa só o que fechou' do
      mapa = Sheets::Training.completed_by_category(
        { pericia.api_index => { 'learning' => true, 'hours_required' => 20, 'hours_trained' => 20 },
          ferramenta.api_index => { 'learning' => true, 'hours_required' => 40, 'hours_trained' => 10 } }
      )
      expect(mapa).to eq({ 'skill' => ['Furtividade'] })
    end
  end

  describe 'o mestre grava a marca' do
    it 'aceita `learning` e guarda como booleano' do
      limpo, erros = Sheets::Training.sanitize(
        { pericia.api_index => { 'learning' => 'true', 'hours_required' => '40' } }
      )
      expect(erros).to be_empty
      expect(limpo[pericia.api_index]['learning']).to be(true)
      expect(limpo[pericia.api_index]['hours_required']).to eq(40)
    end

    it '⚠️ `learning: false` SOLTA a marca — a linha deixa de ser aprendizado' do
      limpo, = Sheets::Training.sanitize(
        { pericia.api_index => { 'learning' => 'false' } },
        previous: { pericia.api_index => { 'learning' => true, 'hours_trained' => 10 } }
      )
      expect(limpo[pericia.api_index]).not_to have_key('learning')
      expect(limpo[pericia.api_index]['hours_trained']).to eq(10)
    end

    it 'campo ausente não mexe na marca — patch parcial vale aqui também' do
      limpo, = Sheets::Training.sanitize(
        { pericia.api_index => { 'hours_trained' => '25' } },
        previous: { pericia.api_index => { 'learning' => true, 'hours_required' => 40 } }
      )
      expect(limpo[pericia.api_index]['learning']).to be(true)
      expect(limpo[pericia.api_index]['hours_required']).to eq(40)
      expect(limpo[pericia.api_index]['hours_trained']).to eq(25)
    end

    it 'recusa proficiência fora do catálogo' do
      _, erros = Sheets::Training.sanitize({ 'inventada' => { 'learning' => true } })
      expect(erros.join).to include('não catalogada')
    end
  end
end
