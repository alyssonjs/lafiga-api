# frozen_string_literal: true

# Merges per-user custom XP thresholds (JSONB) with D&D 5e defaults (total XP to reach each level).
module DmProgressionSettingsMerge
  DEFAULT_XP_THRESHOLDS = {
    1 => 0,
    2 => 300,
    3 => 900,
    4 => 2700,
    5 => 6500,
    6 => 14_000,
    7 => 23_000,
    8 => 34_000,
    9 => 48_000,
    10 => 64_000,
    11 => 85_000,
    12 => 100_000,
    13 => 120_000,
    14 => 140_000,
    15 => 165_000,
    16 => 195_000,
    17 => 225_000,
    18 => 265_000,
    19 => 305_000,
    20 => 355_000
  }.freeze

  module_function

  # @param raw [Hash, nil] from user.progression_settings["xp_thresholds"] (string or int keys)
  # @return [Hash<String, Integer>] keys "1".."20"
  def merged_xp_thresholds(raw)
    base = DEFAULT_XP_THRESHOLDS.transform_keys(&:to_s)
    return base if raw.blank?

    h = raw.is_a?(Hash) ? raw : {}
    out = base.dup
    h.each do |k, v|
      lk = k.to_s
      next unless lk.match?(/\A\d+\z/)

      lv = lk.to_i
      next if lv < 1 || lv > 20

      n = v.to_i
      out[lk] = n if n >= 0
    end
    out
  end

  # @param user [User]
  # @return [Hash]
  def read_merged(user)
    raw = (user.progression_settings || {}).deep_stringify_keys
    xp_raw = raw['xp_thresholds']
    { 'xp_thresholds' => merged_xp_thresholds(xp_raw) }
  end
end
