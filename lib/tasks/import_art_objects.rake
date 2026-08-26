# frozen_string_literal: true

# Importa as obras de arte do DMG (tabela de objetos de arte).
#
# `kind: treasure` — categoria PRÓPRIA. Obra de arte não é matéria-prima: não
# se consome para fabricar nada.
#
#   bin/rails dnd:import_art_objects            # importa/atualiza
#   DRY_RUN=1 bin/rails dnd:import_art_objects  # só relata
#
# Fonte: `db/data/art_seed.json`. Idempotente por `api_index`.
#
# ⚠️ O peso já vem em KG no seed: a planilha dá em lb e a conversão acontece na
# geração (fator 2.0 do LIVRO, `EquipmentRules::LB_PER_KG`, não o físico
# 2.20462). Gravar o número da planilha faria a obra pesar o dobro.
namespace :dnd do
  desc 'Importa as obras de arte do DMG'
  task import_art_objects: :environment do
    dry = ENV['DRY_RUN'].present?
    seed = JSON.parse(File.read(Rails.root.join('db', 'data', 'art_seed.json')))
    stats = Hash.new(0)
    puts "== import_art_objects #{'(DRY RUN)' if dry} =="

    seed.each do |a|
      item = Item.find_by(api_index: a['api_index'])
      if item
        # ⚠️ Migração: a primeira versão importou como `material/art`. Obra de
        # arte não é insumo de nada, então o kind mudou — sem esta linha as 48
        # já importadas ficariam presas na aba errada.
        if item.kind != 'treasure'
          item.update!(kind: 'treasure') unless dry
          stats[:migradas_de_material] += 1
        end
        mudou = {}
        mudou[:name]      = a['name']      if item.name.blank?
        mudou[:category]  = a['category']  if item.category != a['category']
        mudou[:value_gp]  = a['value_gp']  if item.value_gp.blank?
        mudou[:weight_kg] = a['weight_kg'] if item.weight_kg.blank? && a['weight_kg']
        # A faixa é do catálogo; o resto do props (edições do mestre) fica.
        novos = item.props.to_h.merge(a['props'])
        mudou[:props] = novos if novos != item.props.to_h
        item.update!(mudou) if mudou.any? && !dry
        stats[mudou.any? ? :atualizadas : :intactas] += 1
      else
        Item.create!(api_index: a['api_index'], name: a['name'], kind: 'treasure',
                     category: a['category'], value_gp: a['value_gp'],
                     weight_kg: a['weight_kg'], source: a['source'],
                     props: a['props']) unless dry
        stats[:criadas] += 1
      end
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-14s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
