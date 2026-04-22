require 'net/http'
require 'uri'

class Api::V1::Public::EquipmentCategoriesController < ApplicationController
  # Mantido apenas para compatibilidade – delega para EquipmentController
  def show
    params[:index] = params[:id]
    Api::V1::Public::EquipmentController.action(:categories).call(request.env)
  end
end
