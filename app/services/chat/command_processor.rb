module Chat
  class CommandProcessor
    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text.to_s.strip
    end

    def call
      return nil unless @text.start_with?('!')
      # Supported: !d20+1, !2d6-1, !d8, !help
      if @text =~ /^!help$/i
        return { type: 'help', text: 'Comandos: !d20+1, !2d6-1, !d8, !help' }
      end
      if @text =~ /^!(\d*)d(\d+)([+-]\d+)?$/i
        times = ($1.blank? ? 1 : $1.to_i)
        sides = $2.to_i
        mod   = ($3 || '+0').to_i
        return roll(times, sides, mod)
      end
      { type: 'unknown', text: 'Comando desconhecido. Use !help' }
    end

    private
    def roll(times, sides, mod)
      times = [[times, 1].max, 20].min
      sides = [[sides, 2].max, 1000].min
      rolls = Array.new(times) { 1 + rand(sides) }
      total = rolls.sum + mod
      txt = "Rolagem: #{rolls.join(' + ')} #{mod >= 0 ? '+ ' : '- '}#{mod.abs} = #{total}"
      { type: 'roll', times: times, sides: sides, mod: mod, rolls: rolls, total: total, text: txt }
    end
  end
end

