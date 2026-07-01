module Api::V1::Player::Combat
  # Base compartilhada pelos 4 controllers de combate
  # (CombatStates, CombatCombatants, CombatNpcs, SessionLogs).
  #
  # Centraliza:
  #   - autenticação (JWT via ApplicationController#authorize_request)
  #   - lookup de Schedule via `:schedule_id` no path
  #   - autorização de leitura  (qualquer JWT válido — hub / calendário; espelha
  #     Player::SchedulesController#set_schedule_readable)
  #   - autorização de escrita  (DM da mesa / site-wide; exceções em advance_turn)
  #
  # As rotas dos 4 controllers ficam aninhadas sob `/schedules/:schedule_id/...`,
  # então `:schedule_id` SEMPRE estará disponível em params.
  class BaseController < ApplicationController
    before_action :authorize_request
    before_action :set_schedule
    before_action :authorize_read!

    private

    def set_schedule
      @schedule = Schedule.find_by(id: params[:schedule_id])
      render(json: { error: 'schedule não encontrado' }, status: :not_found) unless @schedule
    end

    # Leitura: qualquer conta autenticada (jogador fora do grupo pode acompanhar
    # a mesa em modo leitura, como na página de sessão / play).
    def authorize_read!
      return if @schedule.nil? # já tratado por set_schedule
    end

  # Escrita:
  # - DM / Admin da plataforma (`Group.user_is_dm?`);
  # - Dono da campanha (`group.dm_user_id`) — mestre da mesa com papel Player;
  # - Em `CombatStatesController#advance_turn` apenas: dono do personagem no
  #   turno atual (Passar Vez na barra lateral do jogador).
  def authorize_write!
    return if site_or_table_dm?
    return if advancing_own_pc_turn?

    render json: { error: 'apenas o DM da mesa ou o mestre da plataforma pode mutar estado da sessão' }, status: :forbidden
  end

  def site_or_table_dm?
    return false if @schedule.nil?

    Group.user_is_dm?(@current_user) ||
      (@schedule.group&.dm_user_id.present? && @schedule.group.dm_user_id == @current_user.id)
  end

  # Liberado só para POST .../combat_state/advance_turn (controller_name path).
  def advancing_own_pc_turn?
    return false unless controller_name == 'combat_states' && action_name == 'advance_turn'
    return false if @schedule.nil?

    cs = @schedule.combat_state
    return false unless cs&.active?

    cc = cs.combat_combatants.find_by(position: cs.current_turn_index, is_dead: false)
    return false unless cc&.combatable_type == Character.name

    cc.combatable&.user_id == @current_user.id
  end

  # PUT .../combat_state/update_movement_ledger — DM ou dono do PC no turno actual.
  def authorize_movement_ledger_update!
    return if site_or_table_dm?
    return if editing_movement_ledger_for_own_pc_turn?

    render json: { error: 'apenas o DM, o dono do avatar no turno, ou o dono da mesa pode actualizar o movimento' },
           status: :forbidden
  end

  def editing_movement_ledger_for_own_pc_turn?
    current_turn_belongs_to_user?
  end

  # O combatente em jogo no TURNO ATUAL (combate ativo): o registro em
  # `position: current_turn_index, is_dead: false`. Retorna nil se não houver
  # combate ativo / combatente nessa posição. Fonte única usada por
  # `current_turn_belongs_to_user?` e pela guarda de teste de morte.
  def current_turn_combatant
    return nil unless @schedule
    cs = @schedule.combat_state
    return nil unless cs&.active?

    cs.combat_combatants.find_by(position: cs.current_turn_index, is_dead: false)
  end

  # O combatente do TURNO ATUAL (combate ativo) é um PC do usuário autenticado.
  # Base para liberar ações do JOGADOR DO TURNO (movimento, efeitos de combate).
  def current_turn_belongs_to_user?
    cc = current_turn_combatant
    return false unless cc&.combatable_type == Character.name

    cc.combatable&.user_id == @current_user.id
  end
  end
end
