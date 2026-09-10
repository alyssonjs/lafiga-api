# frozen_string_literal: true

# Conjuração INATA e atrelação a raça/talento/feature.
#
# ⚠️ A tabela `spell_sources` já existia e já era AUTORIDADE para classe (1.074
# linhas) e subclasse (228). Isto NÃO cria uma rival: liga os campos que o
# desenho original previu e nunca usou (`uses_per_long_rest`,
# `uses_per_short_rest`, `ability_override` — 0 linhas cada) e acrescenta o que
# falta para o pedido.
#
# O comentário do próprio modelo já listava os tipos pretendidos:
#   ['Klass','SubKlass','Race','SubRace','Feature','Background']
# Race, SubRace, Feature e Feat nunca chegaram a ser usados.
class AddCastingFieldsToSpellSources < ActiveRecord::Migration[6.0]
  def change
    # COMO se conjura. `with_slot` é o default porque é o que as 1.302 linhas
    # existentes (listas de classe) significam.
    add_column :spell_sources, :casting_mode, :string, null: false, default: 'with_slot'
    # Para `casting_mode: 'resource'` — o Monge das Sombras gasta 2 Chi.
    add_column :spell_sources, :resource_key, :string
    add_column :spell_sources, :resource_cost, :integer

    # ⚠️ As duas lições pagas nas proficiências, aqui desde o dia 1:
    #
    # `grant_mode` — o Alto Elfo ESCOLHE 1 truque da lista do mago; tratar pool
    # como concessão faz o índice mentir (custou-nos 237 linhas erradas lá).
    add_column :spell_sources, :grant_mode, :string, null: false, default: 'fixed'
    add_column :spell_sources, :choose_count, :integer
    # `origin` — re-semear não pode apagar o que o mestre atrelou à mão.
    add_column :spell_sources, :origin, :string, null: false, default: 'derived'

    add_index :spell_sources, %i[source_type source_id]
    add_index :spell_sources, :casting_mode
  end
end
