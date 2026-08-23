# frozen_string_literal: true

require 'rails_helper'

# `recharge` sempre aceitou texto livre. So os tokens canonicos disparam
# recuperacao automatica — o resto segue valendo como flavor, sem recarga.
RSpec.describe MagicItemCatalog, '.recharges_on?' do
  it 'token `long` recupera SO no descanso longo' do
    expect(described_class.recharges_on?('long', :long)).to be(true)
    expect(described_class.recharges_on?('long', :short)).to be(false)
  end

  it 'token `short` recupera no curto E no longo' do
    # Regra D&D: tudo que volta no curto volta no longo.
    expect(described_class.recharges_on?('short', :short)).to be(true)
    expect(described_class.recharges_on?('short', :long)).to be(true)
  end

  it 'REGRESSAO: flavor livre legado NAO recupera sozinho' do
    ['1d4 ao amanhecer', 'ao anoitecer', 'meia-noite'].each do |texto|
      expect(described_class.recharges_on?(texto, :long)).to be(false)
      expect(described_class.recharges_on?(texto, :short)).to be(false)
    end
  end

  it 'vazio/nil nao recupera' do
    [nil, '', '   '].each do |v|
      expect(described_class.recharges_on?(v, :long)).to be(false)
    end
  end

  it 'normaliza caixa e espaco' do
    expect(described_class.normalize_recharge('  LONG ')).to eq('long')
    expect(described_class.normalize_recharge('Short')).to eq('short')
    expect(described_class.normalize_recharge('1d4')).to be_nil
  end
end
