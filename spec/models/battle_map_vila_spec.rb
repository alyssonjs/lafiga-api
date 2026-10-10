# frozen_string_literal: true

require 'rails_helper'

# A CASCA do mapa da vila (L1.2; plano B3 e D5): o `BattleMap` de sempre, com `map_kind 'vila'` e o conteúdo em
# `mapa_blocos`. Nunca a matriz `cells` de um mapa grande.
RSpec.describe BattleMap, 'em blocos' do
  it 'a casca da vila é em blocos e não tem cells' do
    mapa = build(:battle_map, :vila)

    expect(mapa).to be_valid
    expect(mapa).to be_blocos
  end

  it 'recusa cells num mapa em blocos' do
    mapa = build(:battle_map, :vila, cells: Array.new(100) { Array.new(100, 'empty') })

    expect(mapa).not_to be_valid
    expect(mapa.errors[:cells].join).to include('em blocos')
  end

  it 'em blocos só a vila, e a vila só em blocos' do
    expect(build(:battle_map, :vila, map_kind: 'battle')).not_to be_valid
    expect(build(:battle_map, map_kind: 'vila')).not_to be_valid
    expect(build(:battle_map, armazenamento: 'disquete')).not_to be_valid
  end

  it 'o mapa de sempre continua igual: inteiro, com cells' do
    mapa = build(:battle_map)

    expect(mapa).to be_valid
    expect(mapa.armazenamento).to eq('inteiro')
    expect(mapa).not_to be_blocos
  end

  it 'apagar a casca apaga os blocos' do
    bloco = create(:mapa_bloco)

    bloco.battle_map.destroy!

    expect(MapaBloco.count).to eq(0)
  end

  it 'o serializador diz o armazenamento, a semente, quem gerou e o setor' do
    mapa = create(:battle_map, :vila, versao_do_gerador: 1, versao_dos_biomas: 2)

    expect(BattleMapSerializer.serialize(mapa, mode: :slim)).to include(
      mapKind: 'vila', armazenamento: 'blocos', semente: 11, versaoDoGerador: 1, versaoDosBiomas: 2, setorId: nil,
    )
  end

  it 'as versões da geração são inteiros positivos, ou vazias (o mapa de sempre, a casca ainda não gerada)' do
    expect(build(:battle_map, :vila)).to be_valid
    expect(build(:battle_map, :vila, versao_do_gerador: 0)).not_to be_valid
    expect(build(:battle_map, :vila, versao_dos_biomas: 1.5)).not_to be_valid
  end
end
