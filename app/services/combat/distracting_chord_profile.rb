# frozen_string_literal: true

module Combat
  # Deriva a identidade e a economia canônicas do Acorde Distrativo a partir da
  # ficha persistida. O payload da interação é apenas transporte/UI: CD, dado,
  # nível, subclasse e quantidade de usos nunca são confiados ao cliente.
  class DistractingChordProfile
    prepend SimpleCommand

    MIN_LEVEL = 6

    def initialize(combatant:)
      @combatant = combatant
    end

    def call
      character = @combatant&.combatable if @combatant&.combatable_type == Character.name
      return fail_with('o reator precisa ter uma ficha de personagem') unless character

      sheet = character.sheet
      return fail_with('ficha do reator inexistente') unless sheet

      bard = sheet.sheet_klasses.includes(:klass, :sub_klass).find do |entry|
        bard_class?(entry.klass)
      end
      return fail_with('o reator não é Bardo') unless bard
      return fail_with('Acorde Distrativo exige nível 6 de Bardo') if bard.level.to_i < MIN_LEVEL
      return fail_with('o reator não pertence ao Colégio do Virtuosismo') unless virtuoso?(bard.sub_klass)

      summary_command = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      return fail_with(summary_command.errors.full_messages.to_sentence) unless summary_command.success?

      summary = summary_command.result || {}
      resource = summary.dig(:resources, :bardic_inspiration) || {}
      die = resource[:die].to_s
      total = resource[:total].to_i
      used = resource[:used].to_i
      dc = summary.dig(:conjuration, :spell_save_dc).to_i
      return fail_with('recurso de Inspiração Bárdica indisponível') unless total.positive? && die.match?(/\Ad(?:6|8|10|12)\z/)
      return fail_with('CD de magia do Bardo indisponível') unless dc.positive?

      {
        character: character,
        sheet: sheet,
        die: die,
        total: total,
        used: used,
        dc: dc,
      }
    end

    private

    def bard_class?(klass)
      key = [klass&.api_index, klass&.name].compact.join(' ').downcase
      key.include?('bard') || key.include?('bardo')
    end

    def virtuoso?(subklass)
      key = [subklass&.api_index, subklass&.name].compact.join(' ')
      ActiveSupport::Inflector.transliterate(key).downcase.include?('virtuos')
    end

    def fail_with(message)
      errors.add(:base, message.presence || 'Acorde Distrativo indisponível')
      nil
    end
  end
end
