# frozen_string_literal: true

# Ferramentas de DESENVOLVIMENTO do mapa em blocos (09/10; L1.2). As rotas só existem fora de produção
# (`config/routes.rb`), e pedem quem escreve no mapa (`BattleMap#writable_by?`: o dono, o Mestre).
#
# - O protótipo (`/dev/mapa-lpc?vila=1`) gera o mundo e o envia em blocos (`PUT`), até o gerador do servidor (L1.3),
#   com a identidade da geração (a semente e as versões do gerador e dos biomas: a C0).
# - Um bloco muda de propósito (`PATCH`), para ver o `bloco_mudou` invalidar só ele.
#
# Os blocos vêm como JSON livre (terreno e objetos); a forma é conferida no modelo (`MapaBloco`), como no
# `battle_maps_controller`.
class Api::V1::Dev::MapaBlocosController < ApplicationController
  before_action :authorize_request
  before_action :set_mapa

  # PUT /api/v1/dev/battle_maps/:battle_map_id/blocos
  #   body: { blocos: [{ bc, bl, terreno, objetos }], geracao?: { semente, versao_do_gerador, versao_dos_biomas } }
  # → { blocos: [{ bc, bl, versao }], geracao: { semente, versao_do_gerador, versao_dos_biomas },
  #     meta: { gravados, iguais } }. Tudo ou nada.
  def update_all
    corpo = params.to_unsafe_h
    lista = Array(corpo[:blocos])
    if lista.empty? || lista.size > blocos_no_mapa
      return render json: { errors: ["a leva deve ter de 1 a #{blocos_no_mapa} blocos"] }, status: :unprocessable_entity
    end

    resultados = MapaBlocos::Grava.varios(
      @mapa, lista.map { |b| item(b) }, ator: @current_user, geracao: geracao(corpo[:geracao]),
    )
    render json: {
      blocos: resultados.map { |r| { bc: r.bloco.bc, bl: r.bloco.bl, versao: r.bloco.versao } },
      geracao: @mapa.slice(*MapaBlocos::Grava::CAMPOS_DA_GERACAO),
      meta: { gravados: resultados.count(&:mudou), iguais: resultados.count { |r| !r.mudou } },
    }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: [erro_de(e.record)] }, status: :unprocessable_entity
  rescue ArgumentError, TypeError
    render json: { errors: ['cada bloco precisa de bc e bl inteiros, e a geração de três inteiros'] },
           status: :unprocessable_entity
  end

  # PATCH /api/v1/dev/battle_maps/:battle_map_id/blocos/:bc/:bl   body: { terreno?, objetos? }
  # → { bloco: { bc, bl, versao, terreno, objetos, mudou } }
  def update
    corpo = params.to_unsafe_h
    r = MapaBlocos::Grava.call(
      @mapa, bc: Integer(params[:bc]), bl: Integer(params[:bl]), terreno: corpo[:terreno], objetos: corpo[:objetos],
      ator: @current_user,
    )
    render json: { bloco: r.bloco.para_api.merge(mudou: r.mudou) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ArgumentError, TypeError
    render json: { errors: ['bc e bl são inteiros'] }, status: :unprocessable_entity
  end

  private

  def set_mapa
    @mapa = BattleMap.find_by(id: params[:battle_map_id])
    return render json: { errors: 'Not found' }, status: :not_found unless @mapa
    return render json: { errors: 'Sem permissão' }, status: :forbidden unless @mapa.writable_by?(@current_user)
    return if @mapa.blocos?

    render json: { errors: 'Este mapa não é em blocos.' }, status: :unprocessable_entity
  end

  def blocos_no_mapa
    MapaBloco.blocos_no_mapa(@mapa)
  end

  def item(bloco)
    { bc: Integer(bloco['bc']), bl: Integer(bloco['bl']), terreno: bloco['terreno'], objetos: bloco['objetos'] }
  end

  # a identidade da geração, inteira ou nada (sem ela, o mapa guarda a que tinha)
  def geracao(valor)
    return nil if valor.blank?

    MapaBlocos::Grava::CAMPOS_DA_GERACAO.to_h { |campo| [campo, Integer(valor[campo])] }
  end

  def erro_de(registro)
    return "o mapa: #{registro.errors.full_messages.join('; ')}" unless registro.is_a?(MapaBloco)

    "bloco #{registro.bc},#{registro.bl}: #{registro.errors.full_messages.join('; ')}"
  end
end
