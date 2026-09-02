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
end
