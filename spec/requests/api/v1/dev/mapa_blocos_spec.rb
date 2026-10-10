# frozen_string_literal: true

require 'rails_helper'

# As ferramentas de DEV do mapa em blocos (L1.2): o protótipo gera o mundo e o envia em blocos; e um bloco muda de
# propósito, para ver o `bloco_mudou` invalidar só ele. As rotas não existem em produção.
RSpec.describe 'Api::V1::Dev::MapaBlocosController', type: :request do
  let(:dono)    { create(:user) }
  let(:jogador) { create(:user) }
  let(:group)   { create(:group) }
  let!(:pc)     { create(:character, user: jogador, group: group) }
  let(:mapa)    { create(:battle_map, :vila, user: dono, group: group) }

  def arvore(col, lin)
    { id: "arvore-#{col}-#{lin}", tipo: 'arvore', especie: 'carvalho', col: col, lin: lin }
  end

  def envia(blocos, user = dono, geracao: nil)
    corpo = { blocos: blocos }
    corpo[:geracao] = geracao if geracao
    put "/api/v1/dev/battle_maps/#{mapa.id}/blocos", params: corpo, headers: bearer_headers_for(user), as: :json
  end

  def muda(bc, bl, body, user = dono)
    patch "/api/v1/dev/battle_maps/#{mapa.id}/blocos/#{bc}/#{bl}", params: body, headers: bearer_headers_for(user), as: :json
  end

  it 'grava a leva e diz a versão de cada bloco' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [arvore(1, 1)] }, { bc: 2, bl: 2, terreno: { camadas: {} }, objetos: [] }])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['blocos']).to eq([{ 'bc' => 0, 'bl' => 0, 'versao' => 1 }, { 'bc' => 2, 'bl' => 2, 'versao' => 1 }])
    expect(response.parsed_body['meta']).to eq('gravados' => 2, 'iguais' => 0)
    expect(mapa.mapa_blocos.find_by!(bc: 0, bl: 0).objetos.first).to include('id' => 'arvore-1-1', 'col' => 1)
  end

  it 'mudar um bloco sobe a versão dele e avisa só ele' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }, { bc: 1, bl: 0, terreno: { camadas: {} }, objetos: [] }])

    expect { muda(1, 0, { objetos: [arvore(45, 3)] }) }
      .to have_broadcasted_to(MapChannel.stream_name(mapa))
      .with(hash_including(event: 'bloco_mudou', payload: { bc: 1, bl: 0, versao: 2 })).once

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['bloco']).to include('bc' => 1, 'bl' => 0, 'versao' => 2)
  end

  it 'um bloco inválido na leva: 422, e nada gravado' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }, { bc: 1, bl: 0, terreno: { camadas: {} }, objetos: [arvore(1, 1)] }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].join).to include('bloco 1,0')
    expect(mapa.mapa_blocos.count).to eq(0)
  end

  it 'com a geração, o mapa guarda a semente e as versões de quem o gerou' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }], geracao: { semente: 7, versao_do_gerador: 1, versao_dos_biomas: 1 })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['geracao']).to eq('semente' => 7, 'versao_do_gerador' => 1, 'versao_dos_biomas' => 1)
    expect(mapa.reload).to have_attributes(semente: 7, versao_do_gerador: 1, versao_dos_biomas: 1)
  end

  it 'a geração pela metade, ou com versão inválida, é 422 e nada é gravado' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }], geracao: { semente: 7, versao_do_gerador: 1 })
    expect(response).to have_http_status(:unprocessable_entity)

    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }], geracao: { semente: 7, versao_do_gerador: 0, versao_dos_biomas: 1 })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].join).to include('o mapa')

    expect(mapa.mapa_blocos.count).to eq(0)
    expect(mapa.reload.versao_do_gerador).to be_nil
  end

  it 'o carimbo com a folha e o recorte (o formato antigo) é recusado' do
    velho = { id: 'carimbo-0', tipo: 'carimbo', folha: 'ponte', ret: { x: 96, y: 0, w: 96, h: 77 }, x: 32, y: 32 }
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [velho] }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(mapa.mapa_blocos.count).to eq(0)
  end

  it 'só quem escreve no mapa (o dono, o Mestre) grava' do
    envia([{ bc: 0, bl: 0, terreno: { camadas: {} }, objetos: [] }], jogador)
    expect(response).to have_http_status(:forbidden)

    muda(0, 0, { objetos: [] }, jogador)
    expect(response).to have_http_status(:forbidden)
  end

  it 'a leva sem blocos, ou maior que o mapa, é 422' do
    envia([])
    expect(response).to have_http_status(:unprocessable_entity)

    envia(Array.new(10) { |i| { bc: i % 3, bl: i / 3, terreno: { camadas: {} }, objetos: [] } })
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
