# frozen_string_literal: true

# Triagem de bug reports pelo DM/Admin site-wide. Vê TODOS os relatos, filtra por
# status/severidade e atualiza o status + `metadata` (costura da futura IA de
# triagem). `authorize_site_wide_dm` aceita DM e Admin (não só Admin).
class Api::V1::Admin::BugReportsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_report, only: %i[show update]

  def index
    reports = BugReport.all
    reports = reports.where(kind: params[:kind]) if params[:kind].present?
    reports = reports.where(status: params[:status]) if params[:status].present?
    reports = reports.where(severity: params[:severity]) if params[:severity].present?
    reports = reports.recent_first.limit(500)
    render json: {
      bug_reports: BugReportSerializer.serialize_collection(reports),
      meta: { count: reports.size },
    }, status: 200
  end

  def show
    render json: { bug_report: BugReportSerializer.serialize(@report) }, status: 200
  end

  def update
    if @report.update(admin_bug_report_params)
      render json: { bug_report: BugReportSerializer.serialize(@report) }, status: 200
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_report
    @report = BugReport.find_by(id: params[:id])
    render json: { error: 'Relatório não encontrado' }, status: :not_found unless @report
  end

  # DM edita conteúdo (título/descrição/passos/tipo/severidade), o status de
  # triagem e o jsonb `metadata` (resumo/notas da IA).
  def admin_bug_report_params
    params.require(:bug_report).permit(
      :kind, :title, :description, :steps_to_reproduce, :severity, :status, metadata: {}
    )
  end
end
