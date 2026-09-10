# frozen_string_literal: true

# Treino de proficiência numa ficha: horas necessárias (exceção deste
# personagem) e horas já feitas — que o MESTRE conta, sessão a sessão.
#
# Irmão de `SheetDmOverridesController`: mesmo gate, mesmo gesto de patch
# parcial, mesma ideia de marca que fica registrada.
class Api::V1::Admin::SheetTrainingController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:id/training
  # body: { training: { 'tool-lira': { hours_trained: 12, hours_required: 25,
  #                                    note: '...' },
  #                     'tool-alaude': null } }
  #
  # Patch PARCIAL em DOIS níveis: chave ausente fica como está, chave com `null`
  # apaga a linha inteira — e, dentro da linha, campo ausente também fica. Mandar
  # só `hours_trained` não pode apagar a exceção de horas cravada noutro dia.
  def update
    bruto = params[:training]
    return render(json: { errors: 'Informe `training`' }, status: :unprocessable_entity) if bruto.blank?

    limpo, erros = Sheets::Training.sanitize(
      bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : bruto,
      actor_id: @current_user&.id,
      previous: (@sheet.training || {})
    )
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    @sheet.update!(training: Sheets::Training.merge(@sheet.training, limpo))
    render json: { training: @sheet.training }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE — solta TUDO; a ficha volta inteira ao padrão do catálogo.
  def destroy
    @sheet.update!(training: {})
    render json: { training: {} }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # ⚠️ `params[:id]` primeiro: a rota é `member`, então o Rails nomeia o
  # parâmetro `:id`, não `:sheet_id`. Mesma leitura tolerante do irmão.
  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
