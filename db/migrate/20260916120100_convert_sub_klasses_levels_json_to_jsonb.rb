# frozen_string_literal: true

# `levels_json` — a REGRA da sub-classe — deixa de ser TEXT e passa a jsonb.
#
# Por que agora: a página do compêndio vai gravar NÍVEL A NÍVEL. Com TEXT,
# `saved_change_to_levels_json?` compara strings (qualquer reserialização vira
# "mudou", e é ele que vai disparar a propagação para as fichas), não dá para
# consultar por conteúdo, e o banco aceita lixo — todo leitor faz
# `JSON.parse(...) rescue []`, então JSON partido some no meio da ficha sem erro.
#
# ⚠️ Passo de dados ANTES do tipo: um `USING levels_json::jsonb` cru explodiria na
# primeira linha inválida e — pior, porque passa calado — converteria o `'{}'`
# histórico num OBJETO onde os 14 leitores esperam lista.
class ConvertSubKlassesLevelsJsonToJsonb < ActiveRecord::Migration[6.0]
  def up
    normaliza_conteudo
    change_column :sub_klasses, :levels_json, :jsonb,
                  using: 'levels_json::jsonb', default: [], null: false
  end

  def down
    change_column :sub_klasses, :levels_json, :text,
                  using: 'levels_json::text', default: nil, null: true
  end

  private

  # Tudo que não for uma LISTA JSON vira `[]` — inclui NULL, string vazia, o
  # `'{}'` e as linhas partidas.
  def normaliza_conteudo
    require 'json'

    select_all('SELECT id, levels_json FROM sub_klasses').each do |linha|
      bruto = linha['levels_json']
      valor = begin
        bruto.nil? ? nil : JSON.parse(bruto)
      rescue JSON::ParserError
        :invalido
      end
      next if valor.is_a?(Array)

      say("sub_klass #{linha['id']}: #{valor == :invalido ? 'JSON inválido' : valor.class} → []", true)
      execute("UPDATE sub_klasses SET levels_json = '[]' WHERE id = #{linha['id'].to_i}")
    end
  end
end
