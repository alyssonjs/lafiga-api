# frozen_string_literal: true

# A oficina da ficha, para LER: receitas conhecidas (com o que há nas bolsas) e
# criações. Dono do personagem ou Mestre — a escrita é só do Mestre
# (`Admin::SheetCraftingController`).
class Api::V1::Player::SheetCraftingController < ApplicationController
  before_action :authorize_request

  # GET /api/v1/player/sheets/:id/crafting
  def show
    sheet = Sheet.find_by(id: params[:id])
    return render(json: { error: 'Not found' }, status: :not_found) unless sheet && current_user_may_access_sheet?(sheet)

    render json: { crafting: Crafting::Presenter.call(sheet) }, status: :ok
  end
end
