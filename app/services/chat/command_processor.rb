# frozen_string_literal: true

module Chat
  # Os comandos do chat da campanha: `!help` e as rolagens (`!d20+1`, `!2d6-1`, `!d8`, `!2d20kh1+3`…). A gramática e o
  # sorteio são os dados do servidor (L0.6): `Dados::Expressao` e `Dados::Fonte::Segura`.
  class CommandProcessor
    AJUDA = 'Comandos: !d20+1, !2d6-1, !d8, !2d20kh1 (vantagem), !2d20kl1 (desvantagem), !help'

    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text.to_s.strip
    end

    def call
      return nil unless @text.start_with?('!')
      return { type: 'help', text: AJUDA } if @text.match?(/\A!help\z/i)

      roll(Dados::Expressao.parse(@text.delete_prefix('!')))
    rescue Dados::Expressao::Invalida
      { type: 'unknown', text: 'Comando desconhecido. Use !help' }
    end

    private

    # as chaves de antes (`times`, `sides`, `mod`, `rolls`, `total`, `text`) continuam: a mensagem guarda o resultado
    def roll(expr)
      r = expr.rola(Dados::Fonte::Segura.new)
      primeiro = expr.grupos.first
      texto = Dados::Expressao.texto(grupos: r['grupos'], modificador: r['modificador'], total: r['total'])
      {
        type: 'roll', times: primeiro.quantidade, sides: primeiro.lados, mod: expr.modificador,
        rolls: r['grupos'].flat_map { |g| g['rolagens'] }, total: r['total'], expression: expr.to_s,
        text: "Rolagem: #{texto}",
      }
    end
  end
end
