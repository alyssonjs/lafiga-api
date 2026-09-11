# frozen_string_literal: true

# OVERLAY de regras de raça no banco.
#
# A mecânica de raça vive em `config/race_rules.yml`, lido em runtime por
# `RaceRules.apply`. Isso torna o catálogo editável só por deploy — e uma raça
# criada apenas no banco levanta `ArgumentError: race not found` no
# provisioning, medido.
#
# ⚠️ `rules_json` guarda o MESMO formato do nó YAML (`size`, `speed`, `ability`,
# `languages`, `proficiencies`, `traits`, e `custom_traits` para definições
# próprias da raça). Formato igual é o que permite ao leitor tratar as duas
# origens sem tradutor no meio — tradutor é onde nascem as divergências.
#
# Vazio = a raça vale exatamente o que o YAML diz. É o que garante a paridade:
# com todos os overlays vazios, nada muda.
class AddRulesJsonToRaces < ActiveRecord::Migration[6.0]
  def change
    add_column :races, :rules_json, :jsonb, null: false, default: {}
    add_column :sub_races, :rules_json, :jsonb, null: false, default: {}
  end
end
