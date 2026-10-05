# frozen_string_literal: true

# MEMBRO PERDIDO (04/10): o Mestre marca o membro que o personagem perdeu — e o desenho dele (o LPC, no mapa, no retrato,
# no inventário) some com o membro. Ver `Sheets::Membros`.
#
# Só no namespace admin, como as sobrescritas: o jogador VÊ (a aparência é dele), a escrita é do mestre.
class Api::V1::Admin::SheetMembrosController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:sheet_id/membros
  # body: { membros: { mao_direito: { estado: "perdido" }, olho_esquerdo: null } }
  #
  # Patch PARCIAL: chave ausente fica como está; `null` devolve o membro.
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
    @sheet.update!(avatar_customization: aparencia)
    sincroniza_tokens!
    render json: { membros: membros }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

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
