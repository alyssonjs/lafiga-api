# frozen_string_literal: true

# A PRESENÇA dos personagens (09/10; L0.8, plano B3): um lugar por personagem. Quem chama diz o agora.
#
# - `Presencas.entra(character, schedule:, battle_map:, agora:)`: põe o personagem nesta mesa (e mapa). Se ele estava
#   em outra, sai de lá: nunca fica em dois lugares. A pilha de retorno dos portais (L5.2) zera ao trocar de mesa.
# - `Presencas.batimento(character, agora:)`: o sinal de vida de quem continua no mesmo lugar.
# - `Presencas.sai(character)`: o personagem não está em lugar nenhum.
#
# Quem vai chamar: o canal da vila (L1.8) e os portais (L5.2). A sessão de campanha ainda não registra presença.
module Presencas
  module_function

  def entra(character, schedule:, agora:, battle_map: nil)
    2.times do |tentativa|
      return Presenca.transaction(requires_new: true) do
        presenca = Presenca.lock.find_or_initialize_by(character_id: character.id)
        pilha = presenca.schedule_id == schedule.id ? presenca.pilha : []
        presenca.update!(schedule: schedule, battle_map: battle_map, pilha: pilha, batimento_em: agora)
        presenca
      end
    rescue ActiveRecord::RecordNotUnique
      # outra entrada do mesmo personagem chegou junto e criou a linha: a segunda volta a atualiza
      raise if tentativa.positive?
    end
  end

  def batimento(character, agora:)
    Presenca.where(character_id: character.id).update_all(batimento_em: agora, updated_at: agora) == 1
  end

  def sai(character)
    Presenca.where(character_id: character.id).delete_all.positive?
  end

  def onde(character)
    Presenca.find_by(character_id: character.id)
  end
end
