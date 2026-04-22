# frozen_string_literal: true

module Sheets
  module Runtime
    # Aplica os efeitos de um Descanso Curto na `SheetRuntimeState`.
    #
    # Fase A (atual): zera death_saves (PJ acordou estável) e marca timestamp.
    # Fase B: zerará chave 'pact' de spell_slots_used (Bruxo) e (opcional)
    #         arcane_recovery (Mago) se opção for passada.
    # Fase C: zerará todas chaves de class_resources_used cujo recharge
    #         (em config/class_resource_recharges.yml) seja "SR".
    #
    # Não toca em HP — Descanso Curto vanilla 5e cura via dados de vida que o
    # jogador opta no modal (frontend); HP fica em sheets.hp_current via
    # endpoint próprio do PATCH de sheets.
    class ApplyShortRestService
      def self.call(sheet, **kwargs)
        new(sheet, **kwargs).call
      end

      def initialize(sheet, now: Time.current)
        @sheet = sheet
        @now   = now
      end

      def call
        runtime = @sheet.runtime!
        # Fase B: pact slots (Bruxo) recarregam em descanso curto. Removemos
        # apenas a chave 'pact'; demais niveis continuam consumidos ate o longo.
        next_slots = Hash(runtime.spell_slots_used).dup
        next_slots.delete('pact')
        next_slots.delete(:pact)

        # Fase C: zera class_resources_used cuja recarga eh SR (catalogo
        # canonico em config/class_resources.yml).
        # P2.14: passa o nivel atual do personagem para que o catalogo aplique
        # `recharge_at_level` (ex: bardic_inspiration vira SR a partir do nv 5).
        sr_keys = Sheets::Runtime::ResourceCatalog.short_rest_keys(level: character_level)
        next_resources = Hash(runtime.class_resources_used).reject { |k, _| sr_keys.include?(k.to_s) }

        runtime.assign_attributes(
          death_saves: SheetRuntimeState::DEATH_SAVES_DEFAULT.dup,
          spell_slots_used: next_slots,
          class_resources_used: next_resources,
          last_short_rest_at: @now
        )
        runtime.save!
        runtime
      end

      private

      def character_level
        # Usa total_level do CharacterRules quando disponivel; fallback no
        # current_level da sheet ou na soma dos sheet_klasses.
        if defined?(CharacterRules) && CharacterRules.respond_to?(:total_level)
          CharacterRules.total_level(@sheet)
        else
          @sheet.current_level.to_i.nonzero? || @sheet.sheet_klasses.sum(:level)
        end
      rescue StandardError
        @sheet.current_level.to_i
      end
    end
  end
end
