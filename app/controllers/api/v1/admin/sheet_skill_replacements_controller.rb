# frozen_string_literal: true

# REPOSIÇÃO de perícia sobreposta.
#
# A subclasse concedeu uma perícia que o personagem já tinha escolhido na
# classe. Pela regra de 5e ele escolhe outra; sem isto a escolha ficava
# desperdiçada e nada na tela dizia porquê.
class Api::V1::Admin::SheetSkillReplacementsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:id/skill_replacements
  # body: { skill_replacements: { 'Arcanismo': 'Intuição' } }
  #
  # Valor `null` desfaz a reposição.
  def update
    bruto = params[:skill_replacements]
    if bruto.nil?
      return render(json: { errors: 'Informe `skill_replacements`' }, status: :unprocessable_entity)
    end

    entrada = bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : bruto
    sobreposicoes = Sheets::SkillOverlaps.detect(@sheet)
    erros = []
    meta = (@sheet.metadata || {}).deep_stringify_keys
    meta['class_choices'] ||= {}
    atuais = meta['class_choices']['skill_replacements'].is_a?(Hash) ? meta['class_choices']['skill_replacements'].dup : {}

    entrada.each do |original, nova|
      o = original.to_s
      caso = sobreposicoes.find { |s| s['skill'].to_s == o }
      # ⚠️ Só repõe o que ESTÁ sobreposto. Sem isto o endpoint viraria um jeito
      # de trocar qualquer perícia de classe por qualquer outra, sem regra.
      if caso.nil?
        erros << "#{o} não está sobreposta nesta ficha"
        next
      end

      if nova.nil? || nova.to_s.strip.empty?
        atuais.delete(o)
        next
      end

      n = nova.to_s.strip
      permitidas = Array(caso['options']) + [caso['replacement']].compact
      unless permitidas.any? { |p| Sheets::SkillOverlaps.normalize(p) == Sheets::SkillOverlaps.normalize(n) }
        erros << "#{n} não é uma opção de reposição para #{o}"
        next
      end
      atuais[o] = n
    end

    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    meta['class_choices']['skill_replacements'] = atuais
    @sheet.update!(metadata: meta)
    render json: {
      skill_replacements: atuais,
      skill_overlaps: Sheets::SkillOverlaps.detect(@sheet.reload)
    }, status: :ok
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
