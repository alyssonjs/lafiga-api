# frozen_string_literal: true

# Proficiências que o MESTRE concede avulsamente a um personagem.
#
# ⚠️ Existe porque não havia caminho nenhum. O formulário de proficiências edita
# o CATÁLOGO; o passo de Perícias do wizard só oferece as da classe e grava em
# `class_choices.per_level['1'].skills` — o que faria a perícia constar como
# vinda da classe, que é mentira na ficha.
#
# Irmão de `SheetDmOverridesController` e `SheetTrainingController`: mesmo gate,
# mesmo gesto de patch parcial, mesma ideia de marca que fica registrada.
class Api::V1::Admin::SheetDmProficienciesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:id/dm_proficiencies
  # body: { dm_proficiencies: { 'skill-furtividade': { note: '...' },
  #                             'tool-ferreiro': null } }
  #
  # Chave ausente fica como está; chave com `null` retira a concessão.
  def update
    bruto = params[:dm_proficiencies]
    if bruto.blank?
      return render(json: { errors: 'Informe `dm_proficiencies`' }, status: :unprocessable_entity)
    end

    limpo, erros = Sheets::DmProficiencies.sanitize(
      bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : bruto,
      actor_id: @current_user&.id,
      previous: (@sheet.dm_proficiencies || {})
    )
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    @sheet.update!(
      dm_proficiencies: Sheets::DmProficiencies.merge(@sheet.dm_proficiencies, limpo)
    )
    render json: {
      dm_proficiencies: @sheet.dm_proficiencies,
      list: Sheets::DmProficiencies.list(@sheet.dm_proficiencies)
    }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE — retira TODAS as concessões desta ficha.
  def destroy
    @sheet.update!(dm_proficiencies: {})
    render json: { dm_proficiencies: {}, list: [] }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
