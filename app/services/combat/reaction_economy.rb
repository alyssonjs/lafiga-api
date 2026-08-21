# frozen_string_literal: true

module Combat
  # Regra da mesa: a REAÇÃO recarrega na VIRADA DA RODADA.
  #
  # ⚠️ Por que isto é um módulo e não um `if` em cada chamador: a flag crua
  # `actions_used['reaction']` só é limpa no turno DO REATOR. Entre a virada da
  # rodada e a vez dele, ela fica presa em `true` — e quem age ANTES dele na
  # iniciativa enxerga "já reagiu" a rodada inteira. O carimbo `reactionUsedRound`
  # (server-owned) é quem data o uso, e só ele consegue distinguir "usou agora" de
  # "usou na rodada passada".
  #
  # Esta regra já existia no front (`reactionAvailableForRound`) desde o caso do
  # Ainor em 18/08. Ela foi reintroduzida ERRADA no servidor duas vezes — na
  # descoberta de reatores do Acorde e no respond dele — cada uma com um sintoma
  # diferente (a carta não aparecia; a carta aparecia e o botão dava 409). Uma
  # cópia só, para o próximo gate server-side não repetir.
  module ReactionEconomy
    TRUTHY = [true, 1, '1', 'true'].freeze

    module_function

    # `combatant` nil = sem restrição conhecida (mesma tolerância do front).
    def available?(combatant, round)
      return true if combatant.nil?
      return true unless TRUTHY.include?(Hash(combatant.actions_used)['reaction'])

      stamp = Hash(combatant.turn_state)['reactionUsedRound']
      # Sem carimbo não dá para datar o uso: a flag manda, e ela diz "usada".
      stamp.present? && round.to_i > stamp.to_i
    end
  end
end
