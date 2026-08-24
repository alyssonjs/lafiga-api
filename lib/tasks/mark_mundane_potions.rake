# frozen_string_literal: true

namespace :dnd do
  desc 'Marca as pocoes mundanas com `category: potion` (idempotente)'
  # Os 17 consumiveis do catalogo tinham TODOS `category: nil` — pocao, cantil,
  # tocha e racao no mesmo balde. Sem marcador, a aba Pocoes so via item magico
  # e as pocoes apareciam como "consumiveis" em Itens Gerais.
  #
  # O nome e o UNICO sinal disponivel, entao ele roda UMA VEZ para produzir dado
  # estrutural. Dai em diante quem manda e a categoria — nao a heuristica.
  task mark_mundane_potions: :environment do
    marcadas = []
    ja_ok = 0

    Item.where(kind: 'consumable').find_each do |item|
      nome = item.name.to_s.strip
      # `Poção`/`Pocao` no COMEÇO do nome. "Pedra Elemental" e "Coração de
      # Elemental" contem acentos parecidos e NAO podem entrar.
      eh_pocao = nome.match?(/\A(po[çc][ãa]o|potion)\b/i)

      if item.category == 'potion'
        ja_ok += 1
        next
      end
      next unless eh_pocao

      item.update!(category: 'potion')
      marcadas << nome
    end

    puts "[dnd:mark_mundane_potions] marcadas=#{marcadas.size} ja_ok=#{ja_ok}"
    marcadas.each { |n| puts "  #{n}" }
  end
end
