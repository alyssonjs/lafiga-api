# frozen_string_literal: true

# Relatar bug (botão no header). Qualquer usuário autenticado cria e vê os
# próprios relatos; o DM/Admin vê todos via Api::V1::Admin::BugReportsController.
# Upload multipart de screenshots (has_many_attached) espelha o padrão do
# GroupsController/MapAssetsController.
class Api::V1::Player::BugReportsController < ApplicationController
  before_action :authorize_request

  def index
    reports = BugReport.where(user_id: @current_user.id).recent_first.limit(100)
    render json: { bug_reports: BugReportSerializer.serialize_collection(reports) }, status: 200
  end

  def create
    report = BugReport.new(bug_report_params.merge(user_id: @current_user.id))
    report.context = parsed_context
    # `kind` (bug/improvement) vem do payload; qualquer usuário pode relatar bug
    # OU solicitar melhoria. Valor inválido faz o enum levantar → 422 (rescue).

    Array(params.dig(:bug_report, :attachments)).reject(&:blank?).each do |file|
      report.attachments.attach(file)
    end

    if report.save
      render json: { bug_report: BugReportSerializer.serialize(report) }, status: :created
    else
      render json: { errors: report.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # `context` chega como string JSON no multipart (o front faz JSON.stringify);
  # em JSON puro pode chegar como Hash/ActionController::Parameters.
  def parsed_context
    raw = params.dig(:bug_report, :context)
    return {} if raw.blank?

    case raw
    when String then (JSON.parse(raw) rescue {})
    when ActionController::Parameters then raw.to_unsafe_h
    when Hash then raw
    else {}
    end
  end

  # `status`/`metadata` NÃO entram aqui: o relato nasce `novo` (default) e só o
  # DM/IA escreve `metadata`/`status` via controller admin. `context` é atribuído
  # à parte (parsed_context) porque vem como string no multipart.
  def bug_report_params
    params.require(:bug_report).permit(:title, :description, :steps_to_reproduce, :severity, :kind)
  end
end
