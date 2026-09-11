require 'rails_helper'

# FASE 4 — o que muda numa raça chegar às fichas que JÁ existem.
#
# ⚠️ Medido numa ficha real antes de escrever isto: a ficha ficava INCOERENTE
# consigo mesma. A mecânica propaga ao vivo (o `RaceProducer` lê
# `RaceRules.apply` a cada summary, então a resistência nova aparece em combate
# na hora), mas a vitrine fica presa no `race_summary` materializado no
# provisionamento. O personagem passava a resistir a contundente e a lista de
# traços não mencionava porquê.
RSpec.describe Races::ResyncSummaries, type: :service do
  let!(:anao) { Race.find_by(api_index: 'dwarf') || Race.create!(name: 'Anão', api_index: 'dwarf') }

  after do
    anao.update_columns(rules_json: {})
    RaceRules.reload!
  end

  def ficha(race_summary)
    Sheet.create!(character: create(:character), race_id: anao.id, race_summary: race_summary)
  end

  describe 'o que a regra manda' do
    it 'repõe o deslocamento', :aggregate_failures do
      s = ficha({ 'speed_ft' => 25 })
      anao.update!(rules_json: { 'speed' => 40 })
      RaceRules.reload!

      expect(described_class.call(race_id: anao.id).mudadas).to be_positive
      expect(s.reload.race_summary['speed_ft']).to eq(40)
    end

    # ⚠️ A lista vem de `RaceRules.apply` + `trait_definitions`, NÃO das linhas
    # `race_traits`: um traço PRÓPRIO criado no editor vive só no `rules_json`
    # e não tem linha nenhuma na tabela.
    it 'traz o traço PRÓPRIO, que não tem linha em `race_traits`', :aggregate_failures do
      s = ficha({ 'traits' => [{ 'name' => 'Velho' }] })
      anao.update!(rules_json: {
                     'traits' => [{ 'key' => 'pele_de_pedra' }],
                     'custom_traits' => { 'pele_de_pedra' => {
                       'name' => 'Pele de Pedra', 'description' => 'Resistência a contundente.'
                     } }
                   })
      RaceRules.reload!
      described_class.call(race_id: anao.id)

      nomes = Array(s.reload.race_summary['traits']).map { |t| t['name'] }
      expect(nomes).to include('Pele de Pedra')
      expect(nomes).not_to include('Velho')
    end

    # 🐞 12 descrições degradaram-se quando isto foi medido pela primeira vez: o
    # `<dano>` fica à vista se não houver `RaceTrait.metadata` para interpolar —
    # e o traço próprio nunca tem. Aqui a descrição vai JÁ resolvida pelo ref.
    it '⚠️ interpola `<dano>` a partir do ref, sem deixar o placeholder à vista' do
      s = ficha({})
      anao.update!(rules_json: {
                     'traits' => [{ 'key' => 'sopro', 'damage' => 'Ácido' }],
                     'custom_traits' => { 'sopro' => {
                       'name' => 'Sopro', 'description' => 'Causa dano de <dano>.'
                     } }
                   })
      RaceRules.reload!
      described_class.call(race_id: anao.id)

      expect(Array(s.reload.race_summary['traits']).first['description']).to eq('Causa dano de Ácido.')
    end
  end

  # ⚠️ O ponto mais perigoso: recompor o snapshot só pela regra APAGA as
  # escolhas do jogador. Medido no Anão real — a ferramenta escolhida vive em
  # `proficiencies.tools.fixed` e o YAML só a tem em `choices`.
  describe 'escolhas do jogador' do
    it 'a ferramenta escolhida SOBREVIVE ao resync' do
      s = ficha({ 'proficiencies' => { 'tools' => { 'fixed' => ['Ferramentas de ferreiro'] } } })
      described_class.call(race_id: anao.id)

      expect(s.reload.race_summary.dig('proficiencies', 'tools', 'fixed')).to include('Ferramentas de ferreiro')
    end

    it 'mas proficiência que a regra JÁ NÃO dá sai' do
      s = ficha({ 'proficiencies' => { 'tools' => { 'fixed' => ['Ferramenta Inventada'] } } })
      described_class.call(race_id: anao.id)

      expect(Array(s.reload.race_summary.dig('proficiencies', 'tools', 'fixed'))).not_to include('Ferramenta Inventada')
    end

    it 'o idioma escolhido sobrevive' do
      s = ficha({ 'languages' => %w[Comum Anão Élfico] })
      described_class.call(race_id: anao.id)

      expect(s.reload.race_summary['languages']).to include('Élfico')
    end
  end

  describe 'segurança' do
    it 'é IDEMPOTENTE — a segunda passada não muda nada' do
      ficha({ 'speed_ft' => 25 })
      described_class.call(race_id: anao.id)
      expect(described_class.call(race_id: anao.id).mudadas).to eq(0)
    end

    it 'DRY_RUN mede e NÃO grava', :aggregate_failures do
      s = ficha({ 'speed_ft' => 99 })
      rel = described_class.call(race_id: anao.id, dry_run: true)

      expect(rel.mudadas).to be_positive
      expect(s.reload.race_summary['speed_ft']).to eq(99)
    end

    # Inventar regra para uma raça sem nó seria pior do que deixar como está.
    it 'raça sem regra nenhuma é deixada em paz', :aggregate_failures do
      orfa = Race.create!(name: 'Sem Regra', api_index: 'sem-regra-nenhuma')
      s = Sheet.create!(character: create(:character), race_id: orfa.id, race_summary: { 'speed_ft' => 13 })

      expect(described_class.call(race_id: orfa.id).mudadas).to eq(0)
      expect(s.reload.race_summary['speed_ft']).to eq(13)
    end

    # ⚠️ O override em `metadata['race_summary']` VENCE a coluna na leitura.
    # Deixá-lo para trás faria o resync não ter efeito nenhum nessas fichas.
    it 'repõe também o override em `metadata`' do
      s = ficha({ 'speed_ft' => 25 })
      s.update_columns(metadata: { 'race_summary' => { 'speed_ft' => 25 } })
      anao.update!(rules_json: { 'speed' => 40 })
      RaceRules.reload!

      described_class.call(race_id: anao.id)
      expect(s.reload.metadata.dig('race_summary', 'speed_ft')).to eq(40)
    end
  end
end
