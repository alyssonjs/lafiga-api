# frozen_string_literal: true

module Combat
  # Valida o JSON de `CombatState#movement_ledger` (undo de movimento / barra de acção).
  # Formato espelha o front: [{ "kind" => "manual", "ft" => 5 }, { "kind" => "map", "ft" => 10, ... }].
  class ValidateMovementLedgerPayload
    MAX_ENTRIES = 200
    MAX_FT = 10_000

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
