class Api::V1::Public::TraitsController < ApplicationController
  def index
    traits = Trait.all
    render json: { traits: traits }, status: :ok
  end
end

