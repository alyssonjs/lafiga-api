# frozen_string_literal: true

module Sheets
  module Runtime
    # Aplica os efeitos de um Descanso Longo na `SheetRuntimeState`.
    #
    # Fase A (atual):
    #  - death_saves zera
    #  - exhaustion -1 (mínimo 0)
    #  - hit_dice_used recupera floor(level/2) (mínimo 1) — distribuído
    #    proporcionalmente entre dies usados (heurística simples: mantém
    #    proporção atual; refinamento por classe vem em fase posterior)
    #  - last_long_rest_at marcado
    #
    # Fase B: zera spell_slots_used inteiro.
    # Fase C: zera class_resources_used inteiro.
    #
    # HP cheio é responsabilidade do front (PATCH em sheets.hp_current),
    # mantendo coerência com o RestModal atual.
    class ApplyLongRestService
      def self.call(sheet, **kwargs)
        new(sheet, **kwargs).call
      end

      def initialize(sheet, now: Time.current)
        @sheet = sheet
        @now   = now
      end

      def call
        runtime = @sheet.runtime!
        runtime.assign_attributes(
          death_saves: SheetRuntimeState::DEATH_SAVES_DEFAULT.dup,
          exhaustion:  [runtime.exhaustion.to_i - 1, 0].max,
          hit_dice_used: recover_hit_dice(runtime),
          # Fase B: descanso longo zera todos os slots de magia (incluindo pact
          # do Bruxo e arcane_recovery do Mago).
          spell_slots_used: {},
          # Fase C: descanso longo zera todos os recursos de classe conhecidos
          # (regra D&D: tudo que recupera em SR tambem recupera em LR; chaves
          # desconhecidas que o frontend salvou ficam preservadas para nao
          # perder estado).
          class_resources_used: clear_long_rest_resources(runtime),
          last_long_rest_at: @now
        )
        runtime.save!
        runtime
      end

      private

      def clear_long_rest_resources(runtime)
        lr_keys = Sheets::Runtime::ResourceCatalog.long_rest_keys
        Hash(runtime.class_resources_used).reject { |k, _| lr_keys.include?(k.to_s) }
      end

      # Recupera floor(level/2) (min 1) de hit dice usados.
      # Heurística: drena dos dies com mais usos primeiro.
      def recover_hit_dice(runtime)
        used = Hash(runtime.hit_dice_used).transform_values(&:to_i)
        return used if used.values.sum.zero?

        recover = [(character_level / 2.0).floor, 1].max
        # Itera do mais usado para o menos usado, decrementando.
        sorted_keys = used.sort_by { |_die, n| -n }.map(&:first)
        sorted_keys.each do |die|
          break if recover <= 0
          take = [used[die], recover].min
          used[die] -= take
          recover  -= take
        end
        used.reject { |_k, v| v.zero? }
      end

      def character_level
        # Soma níveis de classe da ficha; fallback 1.
        levels = @sheet.sheet_klasses.respond_to?(:sum) ? @sheet.sheet_klasses.sum(:level) : 0
        [levels, 1].max
      end
    end
  end
end
