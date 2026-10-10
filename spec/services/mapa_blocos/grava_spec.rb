# frozen_string_literal: true

require 'rails_helper'

# Gravar blocos (L1.2): a versão só sobe quando o conteúdo muda, e só o bloco que mudou avisa (`bloco_mudou`). Uma
# leva com um bloco inválido não grava nada.
RSpec.describe MapaBlocos::Grava do
  let(:mapa) { create(:battle_map, :vila) }

  def arvore(col, lin)
    { 'id' => "arvore-#{col}-#{lin}", 'tipo' => 'arvore', 'especie' => 'pinheiro', 'col' => col, 'lin' => lin }
  end

  def leva(*objetos_por_bloco)
    objetos_por_bloco.map { |(bc, bl, objetos)| { bc: bc, bl: bl, terreno: { 'camadas' => {} }, objetos: objetos } }
  end

  it 'cria os blocos na versão 1 e avisa cada um' do
    expect { described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]], [1, 0, []])) }
      .to have_broadcasted_to(MapChannel.stream_name(mapa)).exactly(2).times

    expect(mapa.mapa_blocos.order(:bc).map { |b| [b.bc, b.versao] }).to eq([[0, 1], [1, 1]])
  end

  it 'regravar igual não muda a versão nem avisa' do
    described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]]))

    r = nil
    expect { r = described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]])) }
      .not_to have_broadcasted_to(MapChannel.stream_name(mapa))
    expect(r.map(&:mudou)).to eq([false])
    expect(mapa.mapa_blocos.pluck(:versao)).to eq([1])
  end

  it 'só o bloco que mudou sobe de versão e avisa, com bc, bl e versão' do
    described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]], [1, 0, []]))

    expect { described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]], [1, 0, [arvore(41, 2)]])) }
      .to have_broadcasted_to(MapChannel.stream_name(mapa))
      .with(hash_including(event: 'bloco_mudou', payload: { bc: 1, bl: 0, versao: 2 })).once

    expect(mapa.mapa_blocos.order(:bc).map { |b| [b.bc, b.versao] }).to eq([[0, 1], [1, 2]])
  end

  it 'uma leva com um bloco inválido não grava nada' do
    expect { described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]], [1, 0, [arvore(1, 1)]])) }
      .to raise_error(ActiveRecord::RecordInvalid)

    expect(mapa.mapa_blocos.count).to eq(0)
  end

  it 'mudar só os objetos guarda o terreno que já estava' do
    grama = Base64.strict_encode64("\xFF".b * 211)
    described_class.call(mapa, bc: 0, bl: 0, terreno: { 'camadas' => { 'Grass' => grama } }, objetos: [])

    described_class.call(mapa, bc: 0, bl: 0, objetos: [arvore(2, 2)])

    bloco = mapa.mapa_blocos.find_by!(bc: 0, bl: 0)
    expect(bloco.terreno).to eq('camadas' => { 'Grass' => grama })
    expect(bloco.versao).to eq(2)
  end

  it 'quem grava o mundo diz quem o gerou: a semente e as versões vão para o mapa' do
    geracao = { semente: 42, versao_do_gerador: 1, versao_dos_biomas: 3 }

    described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]]), geracao: geracao)

    expect(mapa.reload).to have_attributes(semente: 42, versao_do_gerador: 1, versao_dos_biomas: 3)
  end

  it 'a geração vai com a leva: um bloco inválido desfaz as duas' do
    expect do
      described_class.varios(mapa, leva([0, 0, [arvore(1, 1)]], [1, 0, [arvore(1, 1)]]), geracao: { semente: 42, versao_do_gerador: 1, versao_dos_biomas: 1 })
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(mapa.reload).to have_attributes(semente: 11, versao_do_gerador: nil)
  end

  it 'recusa mapa que não é em blocos' do
    inteiro = create(:battle_map)

    expect { described_class.call(inteiro, bc: 0, bl: 0, objetos: []) }.to raise_error(ArgumentError, /em blocos/)
  end
end
