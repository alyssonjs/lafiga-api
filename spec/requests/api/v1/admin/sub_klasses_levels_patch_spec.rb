# frozen_string_literal: true

require 'rails_helper'

# A FRONTEIRA da regra de sub-classe.
#
# ⚠️ Enquanto `levels_json` esteve no `permit`, gravar um nível pela página
# apagava os outros dezenove — o mesmo buraco que a fase 1 fechou em
# `klasses.rules`. Aqui provamos as duas metades: o cru não entra mais, e o
# patch toca só o nível que nomeou.
RSpec.describe 'Api::V1::Admin::SubKlasses levels_patch', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  let(:klass) do
    Klass.find_by(api_index: 'fighter') || create(:klass, name: 'Guerreiro', api_index: 'fighter', hit_die: 10)
  end

  let(:niveis_iniciais) do
    [
      { 'level' => 0, 'rules' => { 'superiority_dice' => { 'die_start' => 'd8' } } },
      { 'level' => 3, 'features' => [{ 'name' => 'Combate Superior', 'description' => 'velha' }],
        'grants' => { 'proficiencies' => { 'tools' => ['Ferramentas de ferreiro'] } } },
      { 'level' => 7, 'features' => [{ 'name' => 'Conhecer a Manobra', 'description' => 'sétimo' }] },
      { 'level' => 10, 'features' => [{ 'name' => 'Melhoria de Manobras', 'description' => 'décimo' }] }
    ]
  end

  let(:sub) do
    SubKlass.create!(name: 'Mestre de Batalha SO', api_index: 'mestre-de-batalha-so',
                     klass: klass, levels_json: niveis_iniciais)
  end

  def patch_sub(corpo_json)
    patch "/api/v1/admin/sub_klasses/#{sub.id}", params: corpo_json.to_json, headers: headers
  end

  describe 'granularidade' do
    it 'um patch no nível 3 deixa os outros três níveis intactos' do
      patch_sub(sub_klass: { levels_patch: { set: [{ level: 3, features: [{ name: 'Combate Superior', description: 'nova' }] }] } })

      expect(response).to have_http_status(:ok)
      sub.reload
      expect(sub.linhas_de_nivel.map { |l| l['level'] }).to eq([0, 3, 7, 10])
      expect(sub.linhas_de_nivel.find { |l| l['level'] == 3 }['features'].first['description']).to eq('nova')
      expect(sub.linhas_de_nivel.find { |l| l['level'] == 7 })
        .to eq(niveis_iniciais.find { |l| l['level'] == 7 })
      expect(sub.linhas_de_nivel.first['rules']['superiority_dice']['die_start']).to eq('d8')
    end

    it 'preserva a chave que o patch não nomeou dentro do mesmo nível' do
      patch_sub(sub_klass: { levels_patch: { set: [{ level: 3, features: [{ name: 'X' }] }] } })

      sub.reload
      expect(sub.linhas_de_nivel.find { |l| l['level'] == 3 }['grants'])
        .to eq('proficiencies' => { 'tools' => ['Ferramentas de ferreiro'] })
    end

    it 'recusa o patch inteiro quando uma linha é inválida — e não grava nada' do
      patch_sub(sub_klass: { levels_patch: { set: [{ level: 3, features: [{ name: 'ok' }] }, { level: 99 }] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].first).to include('`level` inválido')
      expect(sub.reload.linhas_de_nivel).to eq(niveis_iniciais)
    end
  end

  describe 'o campo cru não entra mais' do
    it 'ignora `levels_json` no corpo do pedido' do
      patch_sub(sub_klass: { levels_json: [{ 'level' => 1, 'features' => [] }], description: 'nova descrição' })

      expect(response).to have_http_status(:ok)
      sub.reload
      expect(sub.description).to eq('nova descrição')
      expect(sub.linhas_de_nivel).to eq(niveis_iniciais)
    end
  end

  describe 'carimbo de edição' do
    it 'carimba `edited_at` ao gravar níveis — é o que protege do import' do
      expect(sub.edited_at).to be_nil

      patch_sub(sub_klass: { levels_patch: { set: [{ level: 3, features: [{ name: 'Nova' }] }] } })

      expect(sub.reload.edited_at).to be_present
    end

    it 'não carimba quando o pedido não fala de níveis' do
      patch_sub(sub_klass: { description: 'só o texto' })

      expect(response).to have_http_status(:ok)
      expect(sub.reload.edited_at).to be_nil
    end
  end

  describe 'o que deriva da regra' do
    it 'sincroniza as features do nível editado' do
      patch_sub(sub_klass: { levels_patch: { set: [{ level: 3, features: [{ name: 'Manobra Nova', description: 'texto' }] }] } })

      expect(response).to have_http_status(:ok)
      nomes = sub.reload.sub_klass_levels.find_by(level: 3)&.features&.pluck(:name)
      expect(nomes).to include('Manobra Nova')
    end

    it 'não cria SubKlassLevel para a linha de nível 0 (metadados de rules)' do
      patch_sub(sub_klass: { levels_patch: { rules: { superiority_dice: { die_start: 'd10' } } } })

      expect(response).to have_http_status(:ok)
      expect(sub.reload.sub_klass_levels.pluck(:level)).not_to include(0)
      expect(sub.linhas_de_nivel.first['rules']['superiority_dice']['die_start']).to eq('d10')
    end
  end

  describe 'show' do
    it 'devolve a base do livro ao lado do que está gravado' do
      get "/api/v1/admin/sub_klasses/#{sub.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(corpo['sub_klass']).to have_key('levels_base')
      expect(corpo['sub_klass']['levels_json'].map { |l| l['level'] }).to eq([0, 3, 7, 10])
    end
  end
end
