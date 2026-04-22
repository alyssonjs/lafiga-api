# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DmProgressionSettingsMerge do
  describe '.merged_xp_thresholds' do
    it 'returns defaults when raw is blank' do
      out = described_class.merged_xp_thresholds(nil)
      expect(out['2']).to eq(300)
      expect(out['20']).to eq(355_000)
    end

    it 'overrides single levels from custom hash' do
      out = described_class.merged_xp_thresholds({ '5' => 9999 })
      expect(out['5']).to eq(9999)
      expect(out['4']).to eq(2700)
    end
  end
end
