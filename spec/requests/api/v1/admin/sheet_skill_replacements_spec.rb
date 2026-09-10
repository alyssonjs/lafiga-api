require 'rails_helper'

# SOBREPOSIÇÃO de perícia — a subclasse concede o que o personagem já escolheu.
#
# ⚠️ Pela regra de 5e, feature que concede algo que você já tem deixa-o escolher
# outra coisa. A aplicação não detectava, e a escolha ficava DESPERDIÇADA em
# silêncio — o personagem com uma perícia a menos e nada a dizer porquê.
#
# Caso real que motivou isto (medido, 1 em toda a base): Avalon Mellion escolheu
# Arcanismo no nível 1 como mago, e Navegação Planar concedeu Arcanismo no 2º.
RSpec.describe 'Api::V1::Admin::SheetSkillReplacements', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  let(:klass) do
    Klass.find_by(api_index: 'wizard') || create(:klass, name: 'Mago', api_index: 'wizard', hit_die: 6)
  end
  let(:sub_klass) do
    SubKlass.create!(
      name: 'Navegação Planar SO', api_index: 'navegacao-planar-so', klass: klass,
      levels_json: [{ 'level' => 2, 'grants' => { 'proficiencies' => { 'skills' => ['Arcanismo'] } } }].to_json
    )
  end
  let(:sheet) do
    s = create(:sheet, character: create(:character, user: create(:user)))
    s.update_column(:metadata, {
      'class_choices' => { 'per_level' => { '1' => { 'skills' => %w[Arcanismo Investigação] } } },
      'background_summary' => { 'skills' => %w[História Persuasão] },
      'race_summary' => { 'skills' => ['Percepção'] }
    })
    create(:sheet_klass, sheet: s, klass: klass, level: 4, sub_klass: sub_klass)
    s
  end

  def repor(payload)
    patch "/api/v1/admin/sheets/#{sheet.id}/skill_replacements",
          params: { skill_replacements: payload }.to_json, headers: headers
  end

  describe 'detecção' do
    it 'aponta a perícia sobreposta e de que subclasse veio', :aggregate_failures do
      sobre = Sheets::SkillOverlaps.detect(sheet)
      expect(sobre.size).to eq(1)
      expect(sobre.first).to include('skill' => 'Arcanismo', 'subclass' => 'Navegação Planar SO')
    end

    it '⚠️ as opções excluem o que ele JÁ TEM de qualquer fonte', :aggregate_failures do
      # A primeira versão só olhava classe e subclasse, e oferecia "História" —
      # que ele tem do antecedente. Escolher lá desperdiçaria de novo.
      opcoes = Sheets::SkillOverlaps.detect(sheet).first['options']
      expect(opcoes).to include('Intuição')
      expect(opcoes).not_to include('História')     # antecedente
      expect(opcoes).not_to include('Investigação') # a outra escolha de classe
      expect(opcoes).not_to include('Arcanismo')    # a própria sobreposta
    end

    it 'sem subclasse que conceda perícia, não há sobreposição' do
      outra = create(:sheet, character: create(:character, user: create(:user)))
      outra.update_column(:metadata, { 'class_choices' => { 'per_level' => { '1' => { 'skills' => ['Arcanismo'] } } } })
      expect(Sheets::SkillOverlaps.detect(outra)).to eq([])
    end
  end

  describe 'PATCH — repor' do
    it 'grava a troca e a sobreposição fica resolvida', :aggregate_failures do
      repor({ 'Arcanismo' => 'Intuição' })

      expect(response).to have_http_status(:ok)
      expect(corpo['skill_replacements']).to eq({ 'Arcanismo' => 'Intuição' })
      expect(corpo['skill_overlaps'].first['replacement']).to eq('Intuição')
    end

    it '⚠️ a ficha passa a ter as SEIS perícias', :aggregate_failures do
      repor({ 'Arcanismo' => 'Intuição' })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      skills = sum.dig(:proficiencies, :skills)

      # A reposição toma o lugar da desperdiçada na CLASSE…
      expect(skills[:class]).to contain_exactly('Intuição', 'Investigação')
      # …e o Arcanismo continua na ficha, pela SUBCLASSE, que é de onde veio.
      expect(skills[:subclass]).to include('Arcanismo')
      # ⚠️ A perícia de RAÇA não entra por `race_summary.skills` neste fixture
      # (vem das regras de raça, que a ficha sintética não tem) — este teste
      # governa a troca de classe/subclasse, e é isso que afere.
      todas = skills.values.flatten.uniq
      expect(todas).to contain_exactly(
        'Intuição', 'Investigação', 'História', 'Persuasão', 'Arcanismo'
      )
      # O ganho é o que importa: antes eram 4 distintas, agora são 5.
      expect(todas.size).to eq(5)
    end

    it '⚠️ recusa perícia fora das opções' do
      repor({ 'Arcanismo' => 'Acrobacia' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('não é uma opção')
    end

    it '⚠️ recusa repor o que NÃO está sobreposto' do
      # Sem isto o endpoint viraria um jeito de trocar qualquer perícia de
      # classe por qualquer outra, sem regra nenhuma.
      repor({ 'Investigação' => 'Intuição' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('não está sobreposta')
    end

    it '`null` desfaz a reposição', :aggregate_failures do
      repor({ 'Arcanismo' => 'Intuição' })
      repor({ 'Arcanismo' => nil })
      expect(corpo['skill_replacements']).to eq({})

      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(sum.dig(:proficiencies, :skills, :class)).to include('Arcanismo')
    end

    it '⚠️ a escolha ORIGINAL não é reescrita — a troca fica ao lado', :aggregate_failures do
      # Sobrescrever `class_choices...skills` faria a sobreposição desaparecer,
      # e ninguém saberia que houve reposição nem poderia desfazer.
      repor({ 'Arcanismo' => 'Intuição' })
      escolhas = sheet.reload.metadata.dig('class_choices', 'per_level', '1', 'skills')
      expect(escolhas).to eq(%w[Arcanismo Investigação])
    end
  end

  describe 'autorização' do
    it 'jogador não repõe' do
      player = create(:user, role: Role.find_or_create_by!(name: 'Player'))
      patch "/api/v1/admin/sheets/#{sheet.id}/skill_replacements",
            params: { skill_replacements: { 'Arcanismo' => 'Intuição' } }.to_json,
            headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end
end
