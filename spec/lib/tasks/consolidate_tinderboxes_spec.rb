# frozen_string_literal: true

# Caixa de fogo: UM item de catálogo, com usos — como o Kit de Primeiros
# Socorros.
#
# Havia SETE entradas de catálogo ("Caixa de fogo", "x10", "10x", "10", "x9",
# "6", "(4)"): seis clones sem categoria, peso nem preço, nascidos do
# `ItemResolver`, que cria registro novo quando o nome digitado não casa. Os
# jogadores usavam o NOME para contar o que gastavam, porque não havia onde.
#
# A rake `dnd:consolidate_tinderboxes` reponta e apaga; ela é de uma vez só e
# já correu. O que fica em risco a longo prazo é o TETO: se alguém tirar a
# caixa da tabela de semeadura, `uses_max` some no próximo banco novo e a
# feature morre em silêncio — a caixa volta a ser um item sem contador, e nada
# quebra ruidosamente. Estes testes são a catraca disso.
require 'rails_helper'

RSpec.describe 'caixa de fogo — usos declarados' do
  SEED_RAKE = Rails.root.join('lib/tasks/seed_item_uses.rake').freeze
  CONSOLIDATE_RAKE = Rails.root.join('lib/tasks/consolidate_tinderboxes.rake').freeze

  it 'a caixa esta na tabela de semeadura, com teto e sem recarga' do
    linha = File.read(SEED_RAKE).lines.find { |l| l.include?("'caixa-de-fogo'") }

    expect(linha).not_to be_nil, 'a caixa saiu de ITEM_USES_SEED — o teto morre no proximo banco novo'
    # [nome, api_index, category, custo po, peso kg, usos, recarga]
    expect(linha).to include('10')
    # Descanso nao repoe isca nem pederneira: acaba e compra-se outra, como o kit.
    expect(linha).to match(/,\s*nil\s*\]/)
  end

  it 'os dados do PHB da caixa estao na linha (5 pp = 0,5 po; 0,5 kg)' do
    linha = File.read(SEED_RAKE).lines.find { |l| l.include?("'caixa-de-fogo'") }

    expect(linha).to include('0.5')
  end

  it 'a rake reponta ANTES de apagar — apagar primeiro deixa item orfao' do
    src = File.read(CONSOLIDATE_RAKE)
    reponta = src.index('si.update!')
    apaga = src.index('item.destroy!')

    expect(reponta).not_to be_nil
    expect(apaga).not_to be_nil
    expect(reponta).to be < apaga
  end

  it 'a rake seleciona por item_id, nao por item_index — a FK e no id' do
    src = File.read(CONSOLIDATE_RAKE)

    expect(src).to include('SheetItem.where(item_id: item.id)')
  end

  it 'a rake e DRY RUN por omissao — migracao nao corre por acidente' do
    src = File.read(CONSOLIDATE_RAKE)

    expect(src).to include("apply = ENV['APPLY'].present?")
    expect(src).to match(/next unless apply/)
  end

  it 'cheio nao grava chave: ausente JA significa cheio' do
    src = File.read(CONSOLIDATE_RAKE)

    expect(src).to match(/props\.delete\('uses_remaining'\)/)
  end

  describe 'a caixa canonica, uma vez semeada' do
    let!(:caixa) do
      Item.create!(api_index: 'caixa-de-fogo', name: 'Caixa de fogo', kind: 'gear',
                   category: 'equipment', weight_kg: 0.5, value_gp: 0.5,
                   props: { 'uses_max' => 10 })
    end
    let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

    it 'a linha da ficha expoe teto e restante no inventario' do
      si = SheetItem.create!(sheet: sheet, item_name: 'Caixa de fogo', item_index: 'caixa-de-fogo',
                             item_id: caixa.id, category: 'equipment', quantity: 1, source: 'test',
                             props_json: { 'uses_remaining' => 6 })

      json = si.as_inventory_json

      expect(json[:uses_props]).to eq({ 'uses_max' => 10 })
      expect(json[:uses_remaining]).to eq(6)
    end

    it 'sem a chave gravada, a caixa esta CHEIA' do
      si = SheetItem.create!(sheet: sheet, item_name: 'Caixa de fogo', item_index: 'caixa-de-fogo',
                             item_id: caixa.id, category: 'equipment', quantity: 1, source: 'test')

      expect(si.uses_remaining).to eq(10)
    end
  end
end
