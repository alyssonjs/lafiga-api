# frozen_string_literal: true

# O VISUAL da substituição (05/10, a mesa: "o mestre ou o player vai poder caracterizar o membro substituído — metálico,
# madeira"): o dono da ficha troca o MATERIAL e a COR do membro que o Mestre já substituiu. O tipo, os efeitos e a arma
# ficam como o Mestre gravou (`Admin::SheetMembrosController`). Ver `Sheets::Membros.sanitize_visual`.
class Api::V1::Player::SheetMembrosController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet

  # PATCH /api/v1/player/sheets/:id/membros
  # body: { membros: { braco_esquerdo: { material: "madeira", cor: "oak" } } }
  def update
    return render(json: { errors: 'Informe `membros`' }, status: :unprocessable_entity) unless params.key?(:membros)

    bruto = params[:membros]
    bruto = bruto.to_unsafe_h if bruto.respond_to?(:to_unsafe_h)
    membros = nil
    erros = []
    Sheet.transaction do
      sheet = Sheet.lock.find(@sheet.id)
      aparencia = (sheet.avatar_customization || {}).deep_stringify_keys
      atual = aparencia[Sheets::Membros::CHAVE] || {}
      mexidos, erros = Sheets::Membros.sanitize_visual(bruto, atual)
      raise ActiveRecord::Rollback if erros.any?

      membros = atual.merge(mexidos)
      sheet.update!(avatar_customization: aparencia.merge(Sheets::Membros::CHAVE => membros))
      @sheet = sheet
    end
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    sincroniza_tokens!
    render json: { membros: membros }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def sincroniza_tokens!
    character = @sheet.character
    return unless character

    BattleMapCharacterCustomization.sync!(character: character, actor: @current_user)
  rescue StandardError => e
    Rails.logger.warn("SheetMembros (jogador): sync dos tokens falhou p/ sheet ##{@sheet.id}: #{e.class}: #{e.message}")
  end

  # O dono da ficha (ou o Mestre).
  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
    return if @sheet.character&.user_id == @current_user.id
    return if Group.user_is_dm?(@current_user)

    render json: { error: 'Not found' }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
