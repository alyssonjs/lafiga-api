# frozen_string_literal: true

# Horas de treino cravadas pelo MESTRE numa ficha, caso a caso.
#
# Irmão de `SheetDmOverridesController`: mesmo gate, mesmo gesto de patch
# parcial, mesma ideia de "marca que fica registrada". O que muda é a forma do
# dado — ali é lista branca de números soltos, aqui é um mapa indexado por
# `proficiency.api_index`.
class Api::V1::Admin::SheetTrainingOverridesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:sheet_id/training_overrides
  # body: { training_overrides: { 'tool-ferramentas-de-ferreiro': { hours: 80, note: '...' },
  #                               'tool-lira': null } }
  #
  # Patch PARCIAL: chave ausente fica como está, chave com `null` é removida —
  # o gesto de "solta, volta a valer o padrão do catálogo". Substituir o hash
  # inteiro obrigaria o front a reenviar tudo, e dois mestres a editar ao mesmo
  # tempo apagariam ajuste alheio.
  def update
    bruto = params[:training_overrides]
    if bruto.blank?
      return render(json: { errors: 'Informe `training_overrides`' }, status: :unprocessable_entity)
    end

    limpo, erros = Sheets::TrainingOverrides.sanitize(
      bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : bruto,
      actor_id: @current_user&.id,
      previous: (@sheet.training_overrides || {})
    )
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    @sheet.update!(training_overrides: Sheets::TrainingOverrides.merge(@sheet.training_overrides, limpo))
    render json: { training_overrides: @sheet.training_overrides }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE — solta TODAS; a ficha volta inteira ao padrão do catálogo.
  def destroy
    @sheet.update!(training_overrides: {})
    render json: { training_overrides: {} }, status: :ok
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
