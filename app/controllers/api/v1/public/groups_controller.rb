# Leitura pública: roster/capa para calendário e visualização de campanha
# (não requer `Character` no grupo — espelha o payload canónico de `GroupSerializer` no player).
class Api::V1::Public::GroupsController < ApplicationController
  before_action :set_group, only: [:show]

  # Só id/nome — roster completo em `#show` (evita fuga de dados e payload gigante em listas).
  def index
    groups = Group.order(:name).pluck(:id, :name)
    render json: { groups: groups.map { |id, name| { id: id, name: name } } }, status: :ok
  end

  def show
    render json: { group: GroupSerializer.serialize(@group) }, status: :ok
  end

  private

  def set_group
    @group = Group
      .includes(characters: { sheet: [:race, { sheet_klasses: %i[klass sub_klass] }] })
      .find_by(id: params[:id])
    return render json: { error: 'Grupo não encontrado' }, status: :not_found unless @group
  end
end
