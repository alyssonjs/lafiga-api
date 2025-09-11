class Api::V1::Public::AlignmentsController < ApplicationController
  # GET /api/v1/public/alignments
  def index
    list = Alignment.order(:id).map { |a| { index: a.api_index || a.id.to_s, id: a.api_index || a.id.to_s, name: a.name } }
    render json: { alignments: list }, status: :ok
  end

  # GET /api/v1/public/alignments/:id
  def show
    a = Alignment.find_by(api_index: params[:id]) || Alignment.find_by(id: params[:id])
    return render json: { error: 'not found' }, status: :not_found unless a
    render json: { alignment: { index: a.api_index || a.id.to_s, id: a.api_index || a.id.to_s, name: a.name, abbreviation: a.abbreviation, desc: a.desc } }, status: :ok
  end
end

