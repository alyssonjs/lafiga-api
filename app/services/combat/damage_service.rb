module Combat
  # Aplica dano a um combatente e devolve, junto, se um teste de
  # concentração é necessário (G12).
  #
  # Em D&D 5e, sempre que um combatente concentrando em uma magia toma dano,
  # ele faz um teste de Constituição com CD = max(10, dano/2). Se falhar,
  # perde a concentração (a magia termina). O cálculo do dano em si está em
  # `CombatCombatant#apply_damage!`. Este service apenas orquestra:
  #   - aplicar o dano
  #   - calcular a CD se aplicável
  #   - retornar a info estruturada para o front rolar o save
  #
  # O front decide rolar (PC) ou auto-rolar (NPC) e chama o endpoint
  # `record_concentration_save` (a ser adicionado se quisermos resolver o save
  # no servidor; por ora, o front só atualiza is_concentrating=false em caso
  # de falha).
  class DamageService
    prepend SimpleCommand

    def initialize(combatant:, amount:, current_user: nil)
      @combatant = combatant
      @amount = amount.to_i
      @current_user = current_user
    end

    def call
      return errors.add(:combatant, 'inexistente') && nil if @combatant.nil?
      return errors.add(:amount, 'deve ser >= 0') && nil if @amount.negative?

      was_concentrating = @combatant.is_concentrating
      @combatant.apply_damage!(@amount)

      {
        combatant: @combatant,
        damage_applied: @amount,
        concentration_check_required: was_concentrating && @amount.positive? && !@combatant.is_dead,
        concentration_dc: was_concentrating && @amount.positive? ? [10, @amount / 2].max : nil,
      }
    rescue ArgumentError => e
      errors.add(:base, e.message)
      nil
    end
  end
end
