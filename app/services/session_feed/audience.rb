# frozen_string_literal: true

module SessionFeed
  # Quem faz parte da EQUIPE de uma sessão — o grupo de jogadores sem o Mestre.
  #
  # O critério é POR MESA, não o papel global `Group.user_is_dm?`: um usuário
  # com papel de DM pode ser jogador na mesa de outra pessoa, e ali o chat da
  # equipe é dele também. Quem manda é `groups.dm_user_id`.
  module Audience
    module_function

    # `true` para quem joga nesta mesa e NÃO é o Mestre dela.
    def team_member?(schedule, user)
      return false if user.nil?

      group = schedule&.group
      return false if group.nil?
      return false if group.dm_user_id.present? && group.dm_user_id == user.id

      group.characters.exists?(user_id: user.id)
    end

    # O Mestre desta mesa. Serve para negar a escrita no canal da equipe e para
    # liberar o caderno de rolagens secretas.
    def table_dm?(schedule, user)
      return false if user.nil?

      group = schedule&.group
      return false if group.nil?

      group.dm_user_id.present? && group.dm_user_id == user.id
    end

    # Canais que este usuário pode LER. `all` é o piso: qualquer um que já podia
    # ver a sessão continua vendo o Geral.
    def readable(schedule, user)
      canais = [SessionFeedItem::AUDIENCE_ALL]
      canais << SessionFeedItem::AUDIENCE_PLAYERS if team_member?(schedule, user)
      canais << SessionFeedItem::AUDIENCE_DM if table_dm?(schedule, user)
      canais
    end

    # Escrever num canal restrito exige poder LÊ-LO. Sem isto, uma aba do Mestre
    # postaria no combinado da equipe — e vice-versa.
    def may_write?(schedule, user, audience)
      readable(schedule, user).include?(audience.to_s)
    end
  end
end
