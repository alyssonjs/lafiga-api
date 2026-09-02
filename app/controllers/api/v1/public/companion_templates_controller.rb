# Leitura do catalogo de companheiros — e o que o JOGADOR ve no "Adicionar
# companheiro". Devolve o shape que o front ja consome (`CompanionTemplate`),
# para o modelo da API entrar no MESMO caminho do estatico.
class Api::V1::Public::CompanionTemplatesController < ApplicationController
  def index
    scope = CompanionTemplate.all
    scope = scope.do_tipo(params[:companion_type] || params[:type])
    scope = scope.busca(params[:q] || params[:search])
    scope = scope.order(:companion_type, :name).limit(500)
    render json: { companion_templates: scope.map(&:as_template_json) }
  end

  def show
    template = CompanionTemplate.find_by(slug: params[:id]) || CompanionTemplate.find(params[:id])
    render json: { companion_template: template.as_template_json }
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end

  # Serve o PNG do token em 1 requisição, com cache imutável (o `?v=` no URL
  # muda quando o blob muda). Cópia de `map_assets#image`: sem o redirect 302 do
  # ActiveStorage, que são dois hits no Rails e nenhum cache.
  #
  # ⚠️ Fica no namespace PÚBLICO de propósito: o token aparece no mapa de toda a
  # mesa, não só do Mestre. Um endpoint atrás do gate de DM deixaria o jogador
  # com o token quadrado cinza.
  def token_image
    template = CompanionTemplate.with_attached_token_image.find_by(id: params[:id])
    return head(:not_found) unless template&.token_image&.attached?

    # O registro do anexo existe, mas o arquivo pode não estar no storage (banco
    # restaurado sem `storage/`). Isso é "não encontrado", não erro de servidor:
    # um 500 aqui vira token invisível no meio do combate, sem pista nenhuma.
    dados = begin
      template.token_image.download
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.warn(
        '[companion_templates#token_image] blob sem arquivo no storage ' \
        "template=#{template.id} blob=#{template.token_image.blob.id}",
      )
      nil
    end
    return head(:not_found) if dados.nil?

    expires_in 1.year, public: true
    response.cache_control[:extras] = ['immutable']
    send_data dados,
              type: template.token_image.blob.content_type || 'application/octet-stream',
              disposition: 'inline'
  end
end
