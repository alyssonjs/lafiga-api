module Combat
  # G14 — Reordena combatentes de um CombatState atomicamente.
  #
  # Por que é não-trivial: a tabela tem índice ÚNICO em
  # (combat_state_id, position). Mover X de pos 5 para pos 2 sem cuidado dispara
  # PG::UniqueViolation porque, durante o shift dos vizinhos, duas linhas
  # tentam ocupar a mesma posição.
  #
  # Estratégia: dentro de UMA transação,
  #   1. mover TODOS os combatentes para posições negativas temporárias
  #      (-1, -2, -3, ...). Como negativos passam pelo `>= 0` validation? — A
  #      validation é `>= 0`, então não. Logo usamos `update_columns` para
  #      pular validação durante o shuffle (o estado final É válido).
  #   2. recalcular a ordem desejada (lista de IDs na nova ordem)
  #   3. atribuir position = 0..N-1 na ordem nova
  #
  # Input: combat_state, ordered_combatant_ids (array com a nova ordem)
  # Saída: combatants reload na nova ordem
  #
  # Validações:
  #   - ordered_combatant_ids precisa cobrir EXATAMENTE os combatentes do
  #     combat_state (sem faltar, sem extra) — evita perder combatente por
  #     bug de UI.
  class ReorderService
    prepend SimpleCommand

    def initialize(combat_state:, ordered_combatant_ids:, current_user: nil)
      @combat_state = combat_state
      @ordered_ids  = Array(ordered_combatant_ids).map(&:to_i)
      @current_user = current_user
    end

    def call
      return errors.add(:combat_state, 'inexistente') && nil if @combat_state.nil?

      existing_ids = @combat_state.combat_combatants.pluck(:id).sort
      requested    = @ordered_ids.dup.sort

      if requested != existing_ids
        errors.add(:ordered_combatant_ids, 'precisa cobrir exatamente os combatentes deste combate')
        return nil
      end

      ActiveRecord::Base.transaction do
        # Fase 1: posições temporárias negativas para liberar o índice único.
        # `update_columns` pula validação (negativo viola `>= 0`), o que é OK
        # porque o estado final será válido e a transação garante consistência.
        @combat_state.combat_combatants.each_with_index do |c, idx|
          c.update_columns(position: -(idx + 1))
        end

        # Fase 2: aplica nova ordem.
        @ordered_ids.each_with_index do |cid, idx|
          @combat_state.combat_combatants.where(id: cid).update_all(position: idx)
        end

        @combat_state.combat_combatants.reload.order(:position)
      end
    end
  end
end
