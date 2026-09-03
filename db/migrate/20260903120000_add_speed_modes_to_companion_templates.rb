# Deslocamento MULTI-MODO no modelo de companheiro.
#
# ⚠️ O dado numérico EXISTE no bestiário (`{walk: 50, swim: 25, climb: 25}`) e o
# tradutor o achatava numa string ("15 m, natação 7,5 m, escalada 7,5 m"). Na
# invocação, `velocidade_em_pes` lê só o PRIMEIRO número — natação e escalada
# sumiam do combate. `combat_npcs.speed_modes` já existe desde 31/08 com leitor
# pronto no front; faltava carregar o dado até lá.
#
# Em PÉS, como `combat_npcs.speed_modes` e `MonsterSpeed`: uma unidade só em
# todo o caminho. A string de exibição passa a ser DERIVADA daqui.
class AddSpeedModesToCompanionTemplates < ActiveRecord::Migration[6.0]
  def change
    add_column :companion_templates, :speed_modes, :jsonb, default: {}
  end
end
