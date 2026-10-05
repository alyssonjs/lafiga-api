# frozen_string_literal: true

# MEMBRO PERDIDO (04/10): o Mestre marca o membro que o personagem perdeu — e o desenho dele (o LPC, no mapa, no retrato,
# no inventário) some com o membro. As SUBSTITUIÇÕES (05/10): a prótese, o gancho, a lâmina, a perna de pau e o
# tapa-olho, com os efeitos e a arma natural. Ver `Sheets::Membros`.
#
# Só no namespace admin, como as sobrescritas: o jogador VÊ (a aparência é dele) e mexe só no visual da substituição
# (`Player::SheetMembrosController`); o resto é do mestre.
class Api::V1::Admin::SheetMembrosController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:sheet_id/membros
  # body: { membros: { mao_direito: { estado: "perdido" }, olho_esquerdo: null,
  #                    braco_esquerdo: { estado: "substituido", substituto: { tipo: "protese", material: "metal",
  #                                      cor: "gold", efeitos: [{ kind: "ability_bonus", ability: "str", value: 2 }] } } } }
  #
  # Patch PARCIAL: chave ausente fica como está; `null` devolve o membro. Quando a mão se vai, o que ela segurava cai
  # (`desequipados`: os nomes, para a mesa saber).
  def update
    return render(json: { errors: 'Informe `membros`' }, status: :unprocessable_entity) unless params.key?(:membros)

    bruto = params[:membros]
    bruto = bruto.to_unsafe_h if bruto.respond_to?(:to_unsafe_h)
    aparencia = (@sheet.avatar_customization || {}).deep_stringify_keys
    limpo, erros = Sheets::Membros.sanitize(bruto, actor_id: @current_user&.id, previous: aparencia[Sheets::Membros::CHAVE] || {})
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    membros = Sheets::Membros.merge(aparencia[Sheets::Membros::CHAVE], limpo)
    if membros.empty?
      aparencia.delete(Sheets::Membros::CHAVE)
    else
      aparencia[Sheets::Membros::CHAVE] = membros
    end
    desequipados = []
    Sheet.transaction do
      @sheet.update!(avatar_customization: aparencia)
      desequipados = solta_o_que_nao_cabe!(membros)
    end
    sincroniza_tokens!
    render json: { membros: membros, desequipados: desequipados }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  # As mãos que sobram seguram o que cabe: sem nenhuma, nada; com uma, UM objeto — o da mão principal (a versátil passa
  # a uma mão; a de duas mãos cai), senão o primeiro que houver. Devolve os nomes do que caiu.
  def solta_o_que_nao_cabe!(membros)
    livres = Sheets::Membros.maos_livres(membros)
    return [] if livres >= 2

    nas_maos = @sheet.sheet_items.where(equipped: true, slot: SheetItem::SLOTS_DAS_MAOS).to_a
    fica = nil
    if livres == 1
      fica = nas_maos.find { |i| i.slot == 'main_hand' } || nas_maos.first
      if fica&.segura_com_duas_maos?
        props = (fica.props_json || {}).dup
        if props['using_two_hands']
          props.delete('using_two_hands')
          fica.update_columns(props_json: props)
        end
        fica = nil if fica.segura_com_duas_maos?
      end
    end
    caem = nas_maos.reject { |i| i == fica }
    caem.each { |i| i.update_columns(equipped: false, slot: nil) }
    caem.map(&:item_name)
  end

  # O token do personagem nos mapas leva a aparência (a foto): sem isto, a mesa só veria o membro sumir no próximo
  # carregamento do mapa. Best-effort — o membro já está gravado.
  def sincroniza_tokens!
    character = @sheet.character
    return unless character

    BattleMapCharacterCustomization.sync!(character: character, actor: @current_user)
  rescue StandardError => e
    Rails.logger.warn("SheetMembros: sync dos tokens falhou p/ sheet ##{@sheet.id}: #{e.class}: #{e.message}")
  end

  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
