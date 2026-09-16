# frozen_string_literal: true

require 'rails_helper'

# FASE 5 — a edição do mestre chega às fichas que JÁ existem.
#
# ⚠️ O caso que este spec existe para trancar não é "o snapshot atualiza"; é o
# oposto: `ClassRules.apply` clampa `first(choose)` em DOIS sítios, então
# recompor pela regra APAGA a escolha do jogador quando o mestre reduz `choose`
# ou tira uma opção do catálogo. Some do snapshot, sem erro e sem aviso.
RSpec.describe Klasses::ResyncSummaries do
  let(:klass) do
    Klass.find_by(api_index: 'fighter') ||
      Klass.create!(name: 'Guerreiro SO', api_index: 'fighter', hit_die: 10)
  end

  # ⚠️ As opções saem da REGRA em runtime, não de uma lista escrita à mão aqui:
  # a grafia das perícias é a do catálogo, e cravá-la no spec seria inventar uma
  # quinta grafia do mesmo conceito.
  let(:opcoes) { Array(ClassRules.find('fighter')&.dig(:skill_proficiencies, :options)).map(&:to_s) }
  let(:escolhidas) { opcoes.first(2) }

  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

  before do
    klass.update_columns(subclass_level: 3)
    sheet.sheet_klasses.create!(klass: klass, level: 3)
    sheet.update_columns(
      metadata: { 'class_choices' => { 'per_level' => { '1' => { 'skills' => escolhidas } } } }
    )
    ClassSummaryRebuilder.call(sheet.reload)
  end

  def snapshot
    (sheet.reload.metadata || {})['class_summary'] || {}
  end

  it 'a ficha começa com a escolha do jogador materializada' do
    expect(escolhidas.size).to eq(2)
    expect(snapshot['skills']).to match_array(escolhidas)
  end

  # ⚠️ MEDIDO: o pipeline NORMALIZA a proficiência ao materializar o snapshot —
  # "Armadura de runas" entra na regra e sai da ficha como "armadura_de_runas".
  # É a quinta grafia do mesmo conceito neste projeto; o spec assere a forma que
  # a ficha realmente guarda, não a que eu gostaria que ela guardasse.
  it 'repõe o snapshot quando a regra da classe muda' do
    klass.update_columns(rules: { 'armor_proficiencies' => ['Armadura de runas'] })

    r = described_class.call(klass_id: klass.id)

    expect(r.mudadas).to eq(1)
    expect(snapshot['armor_proficiencies']).to include('armadura_de_runas')
  end

  # ⚠️ O clamp: com `choose: 1`, `ClassRules.apply` devolve UMA perícia. Sem a
  # união preservadora, a segunda escolha do jogador sumiria daqui.
  it 'não derruba a perícia escolhida quando o mestre REDUZ `choose`' do
    klass.update_columns(rules: { 'skill_proficiencies' => { 'choose' => 1, 'options' => opcoes } })

    described_class.call(klass_id: klass.id)

    expect(snapshot['skills']).to match_array(escolhidas)
  end

  # ⚠️ RELATADA e MANTIDA. `ClassRules.apply` não filtra pelo catálogo, então a
  # perícia fora das `options` só sumiria se ESTE serviço a tirasse — e tirar a
  # escolha de um jogador porque o mestre mexeu no catálogo é o estrago que o
  # resync existe para não fazer. Quem decide é o mestre, com o relatório na mão.
  it 'e a opção que a regra deixou de oferecer sai RELATADA, sem ser apagada' do
    sobrevivente, removida = escolhidas
    klass.update_columns(
      rules: { 'skill_proficiencies' => { 'choose' => 2, 'options' => (opcoes - [removida]) } }
    )

    r = described_class.call(klass_id: klass.id)

    relato = r.detalhes.find { |d| d[:removidos].present? }
    expect(relato).to be_present
    expect(relato[:removidos]).to include(removida)
    expect(relato[:campo]).to eq('skills')
    expect(snapshot['skills']).to include(sobrevivente, removida)
  end

  it 'com `dry_run` mede e não grava' do
    klass.update_columns(rules: { 'armor_proficiencies' => ['Armadura de runas'] })

    r = described_class.call(klass_id: klass.id, dry_run: true)

    expect(r.mudadas).to eq(1)
    expect(snapshot['armor_proficiencies']).not_to include('armadura_de_runas')
  end

  it 'é idempotente — a segunda passagem não muda nada' do
    klass.update_columns(rules: { 'armor_proficiencies' => ['Armadura de runas'] })
    described_class.call(klass_id: klass.id)

    segunda = described_class.call(klass_id: klass.id)

    expect(segunda.mudadas).to eq(0)
  end

  it 'o escopo respeita a classe pedida' do
    outra = Klass.find_by(api_index: 'wizard') ||
            Klass.create!(name: 'Mago SO', api_index: 'wizard', hit_die: 6)

    r = described_class.call(klass_id: outra.id, dry_run: true)

    expect(r.vistas).to eq(0)
  end
end
