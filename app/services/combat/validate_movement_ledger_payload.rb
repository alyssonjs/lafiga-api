# frozen_string_literal: true

module Combat
  # Valida o JSON de `CombatState#movement_ledger` (undo de movimento / barra de acção).
  # Formato espelha o front: [{ "kind" => "manual", "ft" => 5 }, { "kind" => "map", "ft" => 10, ... }].
  class ValidateMovementLedgerPayload
    MAX_ENTRIES = 200
    MAX_FT = 10_000

    # Fase 6G — Validação por token contra speed do combatente.
    # Recebe um ledger já validado (output de `.call`) + Hash
    # `{ tokenId => { speed_ft: N, multiplier: M } }`. Retorna lista de
    # violações `[{ tokenId, total_ft, cap_ft }]` para que o caller decida
    # rejeitar ou apenas sinalizar via `overBudget: true`.
    #
    # `multiplier` default = 1 (1 turno). Caller pode passar 4 quando o
    # ledger cobre todo o round (Disparada/Investida costuma dobrar speed).
    def self.cap_violations(validated_ledger, combatant_speeds)
      return [] if validated_ledger.blank? || combatant_speeds.blank?

      totals = Hash.new(0.0)
      Array(validated_ledger).each do |entry|
        next unless entry.is_a?(Hash) && entry['kind'] == 'map'
        token = entry['tokenId']
        next unless token.is_a?(String)
        totals[token] += entry['ft'].to_f
      end

      violations = []
      totals.each do |token, total_ft|
        info = combatant_speeds[token] || combatant_speeds[token.to_sym]
        next unless info.is_a?(Hash)
        speed = (info[:speed_ft] || info['speed_ft']).to_i
        next if speed <= 0
        multiplier = (info[:multiplier] || info['multiplier'] || 1).to_i.nonzero? || 1
        cap = speed * multiplier
        next if total_ft <= cap

        violations << { 'tokenId' => token, 'total_ft' => total_ft, 'cap_ft' => cap }
      end
      violations
    end

    def self.call(raw)
      return [] if raw.nil?
      return nil unless raw.is_a?(Array)
      return nil if raw.size > MAX_ENTRIES

      out = []
      raw.each do |row|
        return nil unless row.is_a?(Hash)

        kind = row['kind'] || row[:kind]
        ft = (row['ft'] || row[:ft]).to_f
        return nil unless %w[manual map].include?(kind.to_s)
        return nil unless ft.finite? && ft >= 0 && ft <= MAX_FT

        if kind.to_s == 'manual'
          out << { 'kind' => 'manual', 'ft' => ft }
        else
          token = row['tokenId'] || row[:tokenId]
          pc = row['prevCol'] || row[:prevCol]
          pr = row['prevRow'] || row[:prevRow]
          return nil unless token.is_a?(String) && token.present?
          return nil unless pc.is_a?(Numeric) && pr.is_a?(Numeric)

          entry = { 'kind' => 'map', 'ft' => ft, 'tokenId' => token, 'prevCol' => pc.to_i, 'prevRow' => pr.to_i }
          if row.key?('overBudget') || row.key?(:overBudget)
            ob = row['overBudget'] || row[:overBudget]
            entry['overBudget'] = [true, false].include?(ob) ? ob : [true, 1, '1'].include?(ob)
          end
          out << entry
        end
      end
      out
    end
  end
end
