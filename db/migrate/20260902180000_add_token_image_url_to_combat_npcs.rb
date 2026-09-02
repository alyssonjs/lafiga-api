# O companheiro invocado leva o PNG do token consigo. Sem esta coluna, o
# desenho que o Mestre subiu no catálogo morria no `SummonCompanionService`: o
# familiar entrava no combate como quadrado cinza, igual a todos os outros.
#
# URL e não anexo: a imagem já vive no `companion_templates` (ActiveStorage) —
# o NPC só aponta para ela, como o mapa faz com os assets.
class AddTokenImageUrlToCombatNpcs < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_npcs, :token_image_url, :string
  end
end
