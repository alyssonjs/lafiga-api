# frozen_string_literal: true

module SessionFeed
  # A ROLAGEM DO SERVIDOR no feed (09/10; L0.6). A partir de uma `Dados::Rolagem`, monta o item de rolagem que o
  # cliente montaria (o total, a conta por extenso, os dados, o losango do d20) e o `selo`, que só o servidor põe.
  # O item ainda passa pelo `RollNormalizer`, como qualquer rolagem; o selo entra DEPOIS, para nenhum cliente forjá-lo.
  module RolagemDoServidor
    module_function

    # `meta`: o que o cliente manda sobre a rolagem (id, timestamp, rótulo, tipo, canal, quem rolou)
    def item(rolagem, meta)
      meta = meta.to_h.stringify_keys
      expr = Dados::Expressao.parse(rolagem.expressao)
      grupos = rolagem.dados
      tipo = meta['type'].to_s
      {
        'kind' => 'roll',
        'id' => meta['id'].to_s,
        'timestamp' => meta['timestamp'],
        'revealAt' => meta['revealAt'],
        'type' => RollNormalizer::ROLL_TYPES.include?(tipo) ? tipo : 'custom',
        'label' => meta['label'].to_s.presence || "!#{rolagem.expressao}",
        'total' => rolagem.total,
        'breakdown' => Dados::Expressao.texto(grupos: grupos, modificador: expr.modificador, total: rolagem.total),
        'dice' => grupos.flat_map { |g| g['rolagens'] },
        'playerName' => meta['playerName'],
        'characterName' => meta['characterName'],
        'rollGroupId' => meta['rollGroupId'],
        'audience' => meta['audience'],
      }.compact.merge(d20(expr, grupos))
    end

    def selo(rolagem)
      { 'rolagem' => rolagem.id, 'fonte' => rolagem.fonte, 'codigo' => rolagem.selo[0, 8] }
    end

    # o losango do d20, com o mesmo critério do chat: um só grupo, 1d20, ou 2d20 mantendo 1 (vantagem/desvantagem)
    def d20(expr, grupos)
      g = expr.grupos.first
      unico = expr.grupos.size == 1 && g.lados == 20 && g.sinal.positive?
      return {} unless unico && (g.quantidade == 1 || (g.quantidade == 2 && g.manter_qtd == 1))

      mantido = grupos.first['mantidos'].first
      out = { 'd20' => mantido, 'isNat20' => mantido == 20, 'isNat1' => mantido == 1 }
      if g.quantidade == 2
        outro = grupos.first['rolagens'].dup
        outro.delete_at(outro.index(mantido))
        out.merge!('d20Alt' => outro.first, 'advantage' => g.manter == 'h' ? 'advantage' : 'disadvantage')
      end
      out
    end
  end
end
