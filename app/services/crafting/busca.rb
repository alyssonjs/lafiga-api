# frozen_string_literal: true

module Crafting
  # Busca por nome sem acento e sem caixa — "pocao" acha "Poção".
  #
  # `translate` do próprio Postgres: a extensão `unaccent` não está no schema
  # (o controller de proficiências já tropeçou nisso e tem recuo).
  module Busca
    COM = 'áàâãäéèêëíìîïóòôõöúùûüçñ'
    SEM = 'aaaaaeeeeiiiiooooouuuucn'

    module_function

    def nome(rel, coluna, termo)
      t = termo.to_s.strip
      return rel if t.empty?

      rel.where("translate(lower(#{coluna}), '#{COM}', '#{SEM}') LIKE ?", "%#{dobrar(t)}%")
    end

    # Quem COMEÇA com o termo vem antes de quem só o contém.
    def ordem(coluna, termo)
      t = termo.to_s.strip
      return Arel.sql("#{coluna} ASC") if t.empty?

      Arel.sql(ActiveRecord::Base.sanitize_sql_array(
        ["CASE WHEN translate(lower(#{coluna}), '#{COM}', '#{SEM}') LIKE ? THEN 0 ELSE 1 END, #{coluna} ASC",
         "#{dobrar(t)}%"],
      ))
    end

    def dobrar(t)
      ActiveRecord::Base.sanitize_sql_like(t.downcase.tr(COM, SEM))
    end
  end
end
