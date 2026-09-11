require 'rails_helper'

# FASE 1 do editor de classes — a fronteira de escrita e a sobreposição.
#
# ⚠️ O que esta fase fecha, medido na fase 0:
#   · o controller admitia `rules: {}` no `permit` (forma livre, sem validação);
#   · `KlassDbRulesContract` existia e tinha ZERO chamadas no caminho de escrita;
#   · `ClassRules.find` era REPLACE-ALL quando `rules` estava presente.
# Juntos: um PATCH com meia classe apagava a outra metade, em silêncio, para
# todos os personagens dela.
RSpec.describe 'Api::V1::Admin::Klasses — rules', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }
  let!(:guerreiro) do
    Klass.find_by(api_index: 'fighter') || Klass.create!(name: 'Guerreiro', api_index: 'fighter', hit_die: 10)
  end

  after { Klass.where(id: guerreiro.id).update_all(rules: nil) }

  def patch_regras(regras)
    patch "/api/v1/admin/klasses/#{guerreiro.id}",
          params: { klass: { rules: regras } }.to_json, headers: headers
  end

  describe '⚠️ sobreposição por chave, não replace-all' do
    it 'gravar UMA chave não apaga o resto da classe', :aggregate_failures do
      antes = ClassRules.find('fighter')
      expect(antes[:features_level1]).to be_present

      patch_regras({ 'hit_die' => 12 })
      expect(response).to have_http_status(:ok)

      depois = ClassRules.find('fighter')
      expect(depois[:hit_die]).to eq('d12')
      # 🐞 Era isto que sumia: com replace-all, tudo o que não fosse `hit_die`
      # desaparecia da classe.
      expect(depois[:features_level1]).to eq(antes[:features_level1])
      expect(depois[:skill_proficiencies]).to eq(antes[:skill_proficiencies])
      expect(depois.dig(:subclass, :choose_level)).to eq(antes.dig(:subclass, :choose_level))
    end

    it 'soltar a chave devolve o valor da regra em código' do
      original = ClassRules.find('fighter')[:hit_die]
      patch_regras({ 'hit_die' => 12 })
      expect(ClassRules.find('fighter')[:hit_die]).to eq('d12')

      patch_regras({})
      expect(ClassRules.find('fighter')[:hit_die]).to eq(original)
    end

    it 'a lista gravada VENCE inteira, não soma à do livro' do
      patch_regras({ 'armor_proficiencies' => ['pesada'] })
      expect(ClassRules.find('fighter')[:armor_proficiencies]).to eq(['pesada'])
    end

    # ⚠️ Chave de topo, não `deep_merge`. Uma lista no topo não distingue os
    # dois (o `deep_merge` do Rails também substitui array); quem distingue é
    # o HASH ANINHADO: com `deep_merge`, as opções do livro sobreviveriam por
    # baixo e o mestre que apagasse uma vê-la-ia voltar sem explicação.
    it '⚠️ objeto aninhado é substituído INTEIRO, não fundido', :aggregate_failures do
      do_livro = ClassRules.find('fighter').dig(:subclass, :options)
      expect(do_livro.keys.size).to be > 1

      patch_regras({ 'subclass' => { 'choose_level' => 4,
                                     'options' => { 'so_esta' => { 'name' => 'Só Esta' } } } })

      depois = ClassRules.find('fighter')[:subclass]
      expect(depois['choose_level'] || depois[:choose_level]).to eq(4)
      opcoes = depois['options'] || depois[:options]
      expect(opcoes.keys.map(&:to_s)).to eq(['so_esta'])
    end
  end

  describe '⚠️ o que erraria em silêncio é RECUSADO' do
    it 'chave desconhecida', :aggregate_failures do
      patch_regras({ 'velocidade' => 9 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join(' ')).to include('velocidade')
    end

    it 'atributo que não existe' do
      patch_regras({ 'saving_throws' => %w[FOR BANANA] })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join(' ')).to include('BANANA')
    end

    it '`choose` maior que o número de opções' do
      patch_regras({ 'skill_proficiencies' => { 'choose' => 5, 'options' => %w[Atletismo] } })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'nada fica gravado pela metade quando há erro', :aggregate_failures do
      patch_regras({ 'hit_die' => 12, 'velocidade' => 9 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(guerreiro.reload.read_attribute(:rules)).to be_blank
    end
  end

  describe 'grafia canônica' do
    # ⚠️ A fase 0 mediu as duas grafias em desacordo nas 13, e
    # `SavingThrowsCatalog` só cobre EN→PT — não atravessa `Força` → `FOR`.
    # Este é o escritor canônico que faltava.
    it 'nomes por extenso entram como SIGLA', :aggregate_failures do
      patch_regras({ 'saving_throws' => ['Força', 'Constituição'] })
      expect(guerreiro.reload.read_attribute(:rules)['saving_throws']).to eq(%w[FOR CON])
    end

    # A regra guarda `"d10"`; a coluna guarda `10`. Aceita as duas e grava a
    # forma da regra.
    it 'dado de vida entra como `dN` venha número ou texto', :aggregate_failures do
      patch_regras({ 'hit_die' => 8 })
      expect(guerreiro.reload.read_attribute(:rules)['hit_die']).to eq('d8')
      patch_regras({ 'hit_die' => 'd6' })
      expect(guerreiro.reload.read_attribute(:rules)['hit_die']).to eq('d6')
    end
  end

  describe 'omitir ≠ esvaziar' do
    it 'PATCH sem falar de `rules` não mexe no que estava lá', :aggregate_failures do
      patch_regras({ 'hit_die' => 12 })
      patch "/api/v1/admin/klasses/#{guerreiro.id}",
            params: { klass: { name: 'Guerreiro' } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(guerreiro.reload.read_attribute(:rules)['hit_die']).to eq('d12')
    end
  end
end
