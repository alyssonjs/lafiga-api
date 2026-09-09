# frozen_string_literal: true

# Sobrescritas do MESTRE numa ficha de jogador.
#
# Só existe no namespace admin, de propósito: a MARCA na ficha é para todos (é
# o "fique registrado" — o jogador tem de saber que aquele número foi cravado),
# mas a ESCRITA é do mestre. `authorize_site_wide_dm` é o mesmo gate de
# `WalletsController` e de `SheetsController#summary`.
class Api::V1::Admin::SheetDmOverridesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # PATCH /api/v1/admin/sheets/:sheet_id/dm_overrides
  # body: { dm_overrides: { hp_max: { value: 80, note: "..." }, dex: null } }
  #
  # Patch PARCIAL: chave ausente fica como está, chave com `null` é removida (o
  # gesto de "solta, volta a calcular"). Substituir o hash inteiro obrigaria o
  # front a reenviar tudo e uma corrida entre dois mestres apagaria ajuste alheio.
  def update
    bruto = params[:dm_overrides]
    return render(json: { errors: 'Informe `dm_overrides`' }, status: :unprocessable_entity) if bruto.blank?

    # `computed` sai do summary VIVO, não do que o cliente mandou: é o valor que
    # o motor daria agora, e é o que sustenta o aviso de defasagem depois.
    limpo, erros = Sheets::DmOverrides.sanitize(
      bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : bruto,
      actor_id: @current_user&.id,
      previous: (@sheet.dm_overrides || {}),
      computed: computed_agora
    )
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    @sheet.update!(dm_overrides: Sheets::DmOverrides.merge(@sheet.dm_overrides, limpo))
    espelha_pv_no_combate! if limpo.key?('hp_max')
    render json: { dm_overrides: @sheet.dm_overrides }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/admin/sheets/:sheet_id/dm_overrides — solta TODAS.
  def destroy
    @sheet.update!(dm_overrides: {})
    render json: { dm_overrides: {} }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # ⚠️ HP em combate NÃO vive na ficha: o combatente guarda o próprio `hp_max`,
  # e a reconciliação do front (`reconcileCharactersWithCombatHp`) faz o
  # combatente VENCER a ficha enquanto o combate está ativo. Sem espelhar aqui,
  # o mestre cravaria 80 e a mesa continuaria a ver o teto velho até o combate
  # acabar. É a mesma regra que o descanso longo do mestre já segue: restauração
  # de PV que deva aparecer em combate precisa tocar o COMBATENTE.
  #
  # No servidor, e não no cliente que gravou, porque o ajuste pode vir da ficha
  # fora da sessão — que não tem contexto de combate nenhum.
  def espelha_pv_no_combate!
    novo = @sheet.dm_overrides.dig('hp_max', 'value')&.to_i
    return if novo.nil? || novo <= 0

    CombatCombatant
      .joins(:combat_state)
      .where(combat_states: { active: true })
      .where(combatable_type: 'Character', combatable_id: @sheet.character_id)
      .find_each do |c|
        next if c.hp_max == novo
        # O PV atual acompanha só quando estoura o teto novo — abaixar o teto não
        # pode curar ninguém, nem levantá-lo pode encher a barra de graça.
        c.update!(hp_max: novo, hp_current: [c.hp_current, novo].min)
        ::Combat::Broadcaster.combatant_upserted(c)
      end
  rescue StandardError => e
    Rails.logger.warn("SheetDmOverrides: espelho no combate falhou p/ sheet ##{@sheet.id}: #{e.class}: #{e.message}")
  end

  # O que o motor daria SEM sobrescrita. Vem de `dm_overridable`, que o summary
  # tira antes de aplicar a camada — zerar `dm_overrides` em memória aqui não
  # adiantaria, porque o serviço recarrega a ficha do banco.
  #
  # Best-effort: se o summary explodir, gravamos sem `computed` e a ficha apenas
  # deixa de mostrar o aviso de defasagem — não é motivo para recusar o ajuste.
  def computed_agora
    # ⚠️ `prepend SimpleCommand`: `call` devolve o COMANDO, e o payload vive em
    # `.result` — o mesmo par que `SheetsController#summary` usa.
    (CharacterSheetSummaryService.call(sheet_id: @sheet.id, sync: false).result || {})[:dm_overridable] || {}
  rescue StandardError => e
    Rails.logger.warn("SheetDmOverrides: summary base falhou p/ sheet ##{@sheet.id}: #{e.class}: #{e.message}")
    {}
  end

  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
