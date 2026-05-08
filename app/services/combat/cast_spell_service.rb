module Combat
  # Fase 6D — Consome um spell slot da SheetRuntimeState durante combate.
  #
  # Antes da Fase 6D: não havia caminho para o tracker decrementar slots —
  # casters eram efetivamente "infinitos" no combate. Agora o front pode
  # POST `/cast_spell` informando `slot_level` e o slot é incrementado em
  # `runtime_state.spell_slots_used[slot_level]`.
  #
  # SessionLog opcional: se a sessão estiver ativa, registra entrada do tipo
  # `spell_cast` para histórico/replay. Não falha se Schedule#session_log
  # não existir.
  class CastSpellService
    prepend SimpleCommand

    SLOT_LEVEL_RANGE = (1..9).freeze

    def initialize(sheet:, slot_level:, spell_name: nil)
      @sheet      = sheet
      @slot_level = slot_level.to_i
      @spell_name = spell_name.to_s.presence
    end

    def call
      return errors.add(:sheet, 'inexistente') && nil if @sheet.nil?
      unless SLOT_LEVEL_RANGE.cover?(@slot_level)
        errors.add(:slot_level, "deve estar em #{SLOT_LEVEL_RANGE} (cantrips não consomem slot)")
        return nil
      end

      runtime = @sheet.runtime!
      used = Hash(runtime.spell_slots_used)
      key = @slot_level.to_s
      used[key] = used[key].to_i + 1
      runtime.apply_patch!('spell_slots_used' => { key => used[key] })

      { runtime: runtime, slot_level: @slot_level, spell_name: @spell_name }
    rescue StandardError => e
      errors.add(:base, e.message)
      nil
    end
  end
end
