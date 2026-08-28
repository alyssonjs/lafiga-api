# frozen_string_literal: true

module SessionFeed
  # Quem lê cada canal do feed da sessão.
  #
  # Dois critérios DIFERENTES, de propósito:
  #  - EQUIPE (`players`) é POR MESA: quem tem personagem neste grupo. O papel
  #    global não entra — um Mestre que joga na mesa de outra pessoa continua
  #    na equipe dela.
  #  - MESTRE (`dm`) é pelo PAPEL (`Group.user_is_dm?`), a mesma autoridade que
  #    o resto do app usa para mapa, fichas e combate.
  module Audience
    module_function

    # `true` para quem joga nesta mesa e NÃO é o dono dela.
    #
    # O corte aqui é `dm_user_id` (e não o papel): tirar da equipe todo mundo
    # com papel de DM excluiria do próprio chat o Mestre que naquela mesa é
    # jogador.
    def team_member?(schedule, user)
      return false if user.nil?

      group = schedule&.group
      return false if group.nil?
      return false if group.dm_user_id.present? && group.dm_user_id == user.id

      group.characters.exists?(user_id: user.id)
    end

    # O Mestre desta sessão. Serve para negar a escrita no canal da equipe e
    # para liberar o caderno de rolagens secretas.
    #
    # A autoridade é o PAPEL (`Group.user_is_dm?` — DM/Admin), a mesma regra
    # canónica do resto do app: quem mestra vê o mapa, as fichas e o combate
    # de qualquer mesa por papel, não por ter criado o grupo. O feed era o
    # único ponto que exigia `groups.dm_user_id` e por isso um Mestre que
    # conduzia a sessão de outra pessoa entrava com todas as ferramentas de
    # Mestre e SEM a aba do caderno secreto.
    #
    # `dm_user_id` continua a valer como segundo caminho: o dono da mesa não
    # perde o canal se algum dia o papel dele mudar.
    def table_dm?(schedule, user)
      return false if user.nil?
      return true if Group.user_is_dm?(user)

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
