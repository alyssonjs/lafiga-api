# frozen_string_literal: true

# Serializa BugReport no shape camelCase consumido direto pelo front
# (espelha `BugReportRecord` em bugReportsApi.ts). URLs de anexo são paths
# relativos do blob ActiveStorage (`/rails/active_storage/...`); o front prefixa
# com a baseURL da API — mesma estratégia de MapAssetSerializer/GroupSerializer.
class BugReportSerializer
  def self.serialize(report)
    return nil unless report

    {
      id: report.id,
      kind: report.kind,           # "bug" | "improvement"
      title: report.title,
      description: report.description,
      stepsToReproduce: report.steps_to_reproduce,
      severity: report.severity,   # string do enum (ex.: "critical")
      status: report.status,       # string do enum (ex.: "novo")
      context: report.context || {},
      metadata: report.metadata || {},
      userId: report.user_id,
      author: author_for(report),
      attachments: attachments_for(report),
      createdAt: report.created_at&.iso8601,
      updatedAt: report.updated_at&.iso8601,
    }
  end

  def self.serialize_collection(list)
    list.map { |r| serialize(r) }
  end

  def self.author_for(report)
    u = report.user
    return nil unless u

    { id: u.id, username: u.try(:username) }
  end

  # Path relativo (sem host) — não depende de default_url_options[:host].
  def self.attachments_for(report)
    return [] unless report.respond_to?(:attachments) && report.attachments.attached?

    report.attachments.map do |att|
      blob = att.blob
      {
        id: att.id,
        filename: blob&.filename.to_s,
        contentType: blob&.content_type,
        byteSize: blob&.byte_size,
        url: blob_path(att),
      }
    end
  rescue StandardError
    []
  end

  def self.blob_path(att)
    Rails.application.routes.url_helpers.rails_blob_path(att, only_path: true)
  rescue StandardError
    nil
  end
end
