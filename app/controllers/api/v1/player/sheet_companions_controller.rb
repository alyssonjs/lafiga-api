# Companions de uma ficha (familiar, montaria, companheiro animal, invocação).
#
# Antes disto `addCompanion` só fazia `setCharacters` no React — nenhuma
# chamada de API. Medido: 0 fichas tinham companion salvo, ou seja, tudo que o
# jogador adicionava sumia no reload.
#
# Operações GRANULARES com lock da ficha: `sheets.companions` é um array jsonb,
# e um PATCH de blob inteiro faria o Mestre e o jogador se sobrescreverem.
class Api::V1::Player::SheetCompanionsController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet

  # GET /api/v1/player/sheets/:sheet_id/companions
  def index
    render json: { companions: companions_of(@sheet) }, status: :ok
  end

  # POST /api/v1/player/sheets/:sheet_id/companions
  # body: { companion: { id, name, type, ... } }
  def create
    payload = companion_payload
    return render json: { error: 'Companion inválido: `id` e `name` obrigatórios.' }, status: :unprocessable_entity if payload.nil?

    Sheet.transaction do
      sheet = Sheet.lock.find(@sheet.id)
      lista = companions_of(sheet)
      # Mesmo id duas vezes viraria dois cards iguais que o remove não separa.
      lista = lista.reject { |c| c['id'].to_s == payload['id'].to_s }
      sheet.update!(companions: lista + [payload])
      @sheet = sheet
    end

    render json: { companions: companions_of(@sheet.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH /api/v1/player/sheets/:sheet_id/companions/:id
  def update
    achou = false

    Sheet.transaction do
      sheet = Sheet.lock.find(@sheet.id)
      lista = companions_of(sheet).map do |c|
        next c unless c['id'].to_s == params[:id].to_s

        achou = true
        # `id` nunca muda: é a chave que o remove e o update usam.
        c.merge(patch_attributes).merge('id' => c['id'])
      end
      sheet.update!(companions: lista) if achou
      @sheet = sheet
    end

    return render json: { error: 'Companion não encontrado.' }, status: :not_found unless achou

    render json: { companions: companions_of(@sheet.reload) }, status: :ok
  end

  # DELETE /api/v1/player/sheets/:sheet_id/companions/:id
  #
  # Dispensar a montaria DEVOLVE a carga para a bolsa. Mesma garantia que o
  # `release_ammunition_contents` da aljava dá: destruir o recipiente nao pode
  # evaporar o que estava dentro.
  def destroy
    Sheet.transaction do
      sheet = Sheet.lock.find(@sheet.id)
      release_stowed_items!(sheet, params[:id])
      sheet.update!(companions: companions_of(sheet).reject { |c| c['id'].to_s == params[:id].to_s })
      @sheet = sheet
    end

    render json: { companions: companions_of(@sheet.reload) }, status: :ok
  end

  private

  # Solta os itens guardados nesta montaria: apaga so o ponteiro, mantendo a
  # linha do inventario.
  def release_stowed_items!(sheet, companion_id)
    sheet.sheet_items
         .where("props_json ->> '#{SheetItem::MOUNT_CONTAINER_PROP}' = ?", companion_id.to_s)
         .find_each do |si|
      props = (si.props_json || {}).dup
      props.delete(SheetItem::MOUNT_CONTAINER_PROP)
      si.update!(props_json: props)
    end
  end

  def companions_of(sheet)
    Array(sheet.companions).select { |c| c.is_a?(Hash) }
  end

  # O companion é um objeto rico (stats, ataques, ações especiais) montado no
  # front a partir de `companionTemplates`. Guardamos o shape como veio, mas
  # exigimos `id` e `name` — sem eles as operações granulares não têm chave.
  def companion_payload
    raw = params[:companion]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return nil unless raw.is_a?(Hash)

    h = raw.deep_stringify_keys
    return nil if h['id'].to_s.strip.empty? || h['name'].to_s.strip.empty?

    h
  end

  def patch_attributes
    raw = params[:companion]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
  end

  # Mesmo critério de posse do SheetsController: jogador só a própria ficha; o
  # Mestre da mesa alcança a do jogador (corrigir companion na mesa é real).
  def set_sheet
    @sheet = Sheet.find(params[:sheet_id])
    return if @sheet.character&.user_id == @current_user.id
    return if Group.user_is_dm?(@current_user)

    render json: { error: 'Not found' }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
