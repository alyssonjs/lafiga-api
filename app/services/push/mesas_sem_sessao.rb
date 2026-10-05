# frozen_string_literal: true

module Push
  # A MESA SEM SESSÃO MARCADA (05/10, a mesa: "quando um grupo não tiver nenhuma sessão marcada nas próximas duas
  # semanas, mande uma notificação com dias disponíveis… se o user apertar no botão já redirecione para a página de
  # criação de sessão no dia específico").
  #
  # Quem chama é a rake `push:mesas_sem_sessao`, uma vez por dia pelo cron do servidor (deploy/crontab) — o mesmo
  # caminho dos lembretes (`Push::SessionReminders`).
  #
  # - QUEM RECEBE: os JOGADORES da mesa (a escolha da mesa, 05/10) — o Mestre fica de fora. Como em todo push, só quem
  #   tem o opt-in `notify_session_reminders` e ao menos uma assinatura.
  # - QUANDO: o grupo não tem nenhuma sessão marcada daqui para a frente. Repete a cada 3 dias enquanto durar, pela
  #   marca `groups.no_session_notified_at`.
  # - DOIS AVISOS, porque o grupo só aceita UMA sessão em aberto por vez:
  #   · sem sessão nenhuma → "marquem a próxima", com as datas nos botões;
  #   · com uma sessão ATRASADA em aberto (a de 21/09 que ninguém encerrou) → "encerrem aquela para marcar a próxima",
  #     com o botão abrindo a sessão. Sem este segundo caso o aviso nasceria mudo: em prod, 05/10, era a única mesa
  #     sem sessão à frente — e marcar ali daria erro de validação.
  # - AS DATAS: o DIA DA SEMANA da mesa, tirado do histórico (Batutinhas joga segunda, Gold quinta); sem padrão, os
  #   próximos dias. Sempre pulando o que o Mestre vetou no calendário (`date_dimensions.available = false`).
  #   Vão como BOTÕES da notificação (`actions`) e levam à criação da sessão naquele dia; o navegador que não desenha
  #   botão (o iPhone) abre a mesma tela pelo corpo, na primeira data.
  class MesasSemSessao
    # "as próximas duas semanas" da mesa
    JANELA = 14
    # de quanto em quanto tempo o aviso se repete enquanto a mesa continuar sem sessão
    INTERVALO = 3.days
    # quantas datas a notificação oferece (o Chrome desenha 2 botões; ver `Notification.maxActions`)
    SUGESTOES = 2
    # quantas sessões passadas dizem qual é o dia da mesa
    HISTORICO = 12
    # o dia da semana só é "o da mesa" com esta fatia do histórico (4 de 10 já é um padrão claro)
    FATIA_DO_PADRAO = 0.4
    # até onde procurar data (dias à frente): 8 semanas cobrem o dia da mesa mesmo com feriados vetados
    HORIZONTE = 56
    DIAS_DA_SEMANA = %w[domingo segunda terça quarta quinta sexta sábado].freeze

    Result = Struct.new(:avisadas, :lines, :grupos, keyword_init: true)

    # `apply: false` é o DRY RUN: não envia push nem marca o grupo — só relata, mesa a mesa, o que faria.
    def self.call(now: Time.zone.now, apply: true)
      new(now: now, apply: apply).call
    end

    def initialize(now: Time.zone.now, apply: true)
      @now = now
      @hoje = now.to_date
      @apply = apply
    end

    # @return [Result] mesas avisadas, linhas de log (uma por mesa) e quantas mesas foram olhadas
    def call
      lines = []
      avisadas = 0
      grupos = Group.includes(:schedules, characters: :user).to_a
      if @apply && !Push::Sender.vapid_configured?
        return Result.new(avisadas: 0, lines: ['[mesas_sem_sessao] VAPID não configurado'], grupos: grupos.size)
      end

      grupos.each do |group|
        etiqueta = "grupo ##{group.id} '#{group.name}'"
        motivo = motivo_para_pular(group)
        if motivo
          lines << "[pulou] #{etiqueta}: #{motivo}"
          next
        end

        # a sessão que ficou em aberto lá atrás impede marcar a próxima: o aviso é outro
        atrasada = em_aberto(group).min_by { |s| s.date_dimension&.date || @hoje }
        datas = atrasada ? [] : datas_sugeridas(group)
        if !atrasada && datas.empty?
          lines << "[pulou] #{etiqueta}: sem data livre à frente"
          next
        end

        users = destinatarios(group)
        if users.empty?
          lines << "[pulou] #{etiqueta}: nenhum jogador com push"
          next
        end

        oferta = atrasada ? "encerrar a sessão ##{atrasada.id} de #{atrasada.date_dimension&.date&.strftime('%d/%m')}" : datas.map { |d| rotulo(d) }.join(', ')
        unless @apply
          padrao = dia_da_mesa(group) ? DIAS_DA_SEMANA[dia_da_mesa(group)] : 'sem padrão'
          lines << "[avisaria] #{etiqueta} → #{users.size} jogador(es), #{oferta}#{atrasada ? '' : " (dia da mesa: #{padrao})"}"
          avisadas += 1
          next
        end

        entregues = atrasada ? avisa_atrasada(group, users, atrasada) : avisa(group, users, datas)
        avisadas += 1
        lines << "[avisou] #{etiqueta} → #{users.size} jogador(es), #{entregues} aparelho(s), #{oferta}"
        group.update_column(:no_session_notified_at, @now)
      end

      Result.new(avisadas: avisadas, lines: lines, grupos: grupos.size)
    end

    # O dia da semana da mesa (0 = domingo), pelo histórico; nil quando não há padrão claro.
    def dia_da_mesa(group)
      datas = datas_do_historico(group)
      return nil if datas.empty?

      wday, vezes = datas.group_by(&:wday).transform_values(&:size).max_by { |_, n| n }
      vezes >= [2, (datas.size * FATIA_DO_PADRAO).ceil].max ? wday : nil
    end

    # As datas que a notificação oferece: as próximas no dia da mesa; sem padrão, os próximos dias.
    def datas_sugeridas(group)
      wday = dia_da_mesa(group)
      vetadas = DateDimension.where(available: false).where(date: (@hoje + 1)..(@hoje + HORIZONTE)).pluck(:date).to_set
      livres = ((@hoje + 1)..(@hoje + HORIZONTE)).reject { |d| vetadas.include?(d) }
      livres = livres.select { |d| d.wday == wday } if wday
      livres.first(SUGESTOES)
    end

    # O horário de sempre da mesa ("21:00"); nil quando ela nunca marcou hora.
    def horario_da_mesa(group)
      horas = group.schedules.reject { |s| s.scheduled_time.blank? }.map { |s| s.scheduled_time.to_s[0, 5] }
      return nil if horas.empty?

      horas.tally.max_by { |_, n| n }.first
    end

    private

    # nil = a mesa precisa do aviso; uma string diz por que ela ficou de fora.
    def motivo_para_pular(group)
      if group.no_session_notified_at && group.no_session_notified_at > @now - INTERVALO
        return "avisada em #{group.no_session_notified_at.strftime('%d/%m %H:%M')}"
      end
      # sessão em aberto daqui para a frente = a mesa já tem o próximo encontro marcado
      return 'já tem sessão marcada' if em_aberto(group).any? { |s| (s.date_dimension&.date || @hoje) >= @hoje }
      return 'sem jogador' if group.characters.none? { |c| c.user_id && c.user_id != group.dm_user_id }

      nil
    end

    def em_aberto(group)
      group.schedules.select do |s|
        Schedule::SCHEDULING_BLOCKING_STATUSES.include?(s.status.to_s) && !(s.respond_to?(:sandbox?) && s.sandbox?)
      end
    end

    def datas_do_historico(group)
      ids = group.schedules.reject { |s| s.status.to_s == 'cancelled' }.map(&:date_dimension_id).compact
      return [] if ids.empty?

      DateDimension.where(id: ids).order(date: :desc).limit(HISTORICO).pluck(:date)
    end

    # Os JOGADORES da mesa com push (o Mestre fica de fora — a escolha da mesa).
    def destinatarios(group)
      ids = group.characters.map(&:user_id).compact.uniq - [group.dm_user_id]
      return [] if ids.empty?

      User.where(id: ids, notify_session_reminders: true).where(id: PushSubscription.select(:user_id)).to_a
    end

    def avisa(group, users, datas)
      hora = horario_da_mesa(group)
      entregues = 0
      users.each do |user|
        entregues += Push::Sender.call(
          user: user,
          title: "#{group.name} está sem sessão marcada",
          body: corpo(group, datas, hora),
          url: url_da_data(datas.first, hora),
          tag: "sem-sessao-#{group.id}",
          actions: datas.map { |d| { action: url_da_data(d, hora), title: rotulo(d) } },
        )
      end
      entregues
    end

    # A sessão que ficou em aberto lá atrás (05/10): sem encerrá-la a mesa não marca outra — o botão abre essa sessão.
    def avisa_atrasada(group, users, schedule)
      quando = schedule.date_dimension&.date&.strftime('%d/%m')
      url = "/sessions/api-#{schedule.id}"
      entregues = 0
      users.each do |user|
        entregues += Push::Sender.call(
          user: user,
          title: "#{group.name} está sem a próxima sessão marcada",
          body: "A sessão de #{quando} (#{schedule.title}) ficou em aberto. Encerrem ela para marcar a próxima.",
          url: url,
          tag: "sem-sessao-#{group.id}",
          actions: [{ action: url, title: 'Abrir a sessão' }],
        )
      end
      entregues
    end

    def corpo(group, datas, hora)
      quando = datas.map { |d| rotulo(d) }.join(' ou ')
      dia = dia_da_mesa(group)
      abertura = dia ? "Vocês costumam jogar #{DIAS_DA_SEMANA[dia]}" : 'Marque a próxima'
      [abertura, "#{quando}#{hora ? " às #{hora}" : ''}?"].join(': ')
    end

    # "qui, 09/10"
    def rotulo(date)
      "#{DIAS_DA_SEMANA[date.wday][0, 3]}, #{date.strftime('%d/%m')}"
    end

    # A tela de sessões abre a criação já nesta data (o front acha a próxima livre se ela tiver sido tomada).
    def url_da_data(date, hora)
      "/sessions?nova=#{date.iso8601}#{hora ? "&hora=#{hora}" : ''}"
    end
  end
end
