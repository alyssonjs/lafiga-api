# frozen_string_literal: true

require 'rails_helper'

# Sobrescritas do Mestre: o valor que ele crava tem de PERSISTIR (esta é a razão
# de a camada existir), passar o teto da regra, e não aceitar chave inventada.
RSpec.describe Sheets::DmOverrides do
  describe '.sanitize' do
    it 'recusa chave fora da lista branca' do
      limpo, erros = described_class.sanitize({ 'ac' => { 'value' => 30 } })
      expect(limpo).to eq({})
      expect(erros).to include(a_string_matching(/ac/))
    end

    it 'grava valor, nota, autor e o calculado do momento' do
      limpo, erros = described_class.sanitize(
        { 'hp_max' => { 'value' => '80', 'note' => 'bênção do templo' } },
        actor_id: 7, computed: { 'hp_max' => 73 }
      )
      expect(erros).to be_empty
      expect(limpo['hp_max']).to include('value' => 80, 'computed' => 73,
                                         'note' => 'bênção do templo', 'by_user_id' => 7)
    end

    it '`nil` é o gesto de SOLTAR — a ficha volta a calcular' do
      limpo, = described_class.sanitize({ 'str' => nil })
      expect(limpo).to eq('str' => nil)
      expect(described_class.merge({ 'str' => { 'value' => 20 } }, limpo)).to eq({})
    end

    it '⚠️ passa dos 20 da regra (é para isso que existe), mas para em 30' do
      # ABILITY_SCORE_CAP = 20 é o limite da PROGRESSÃO (ASI/half-feat). A
      # sobrescrita cobre justamente o que a regra não cobre.
      limpo, = described_class.sanitize({ 'str' => { 'value' => 24 } })
      expect(limpo.dig('str', 'value')).to eq(24)
      # 30 é o teto do motor do front — passar disso daria um número que a
      # ficha não mostraria.
      limpo30, = described_class.sanitize({ 'str' => { 'value' => 99 } })
      expect(limpo30.dig('str', 'value')).to eq(30)
    end

    it 'valor não-numérico vira erro, não zero silencioso' do
      limpo, erros = described_class.sanitize({ 'hp_max' => { 'value' => 'muito' } })
      expect(limpo).to eq({})
      expect(erros).to be_present
    end
  end

  describe '.apply!' do
    it 'substitui atributo (com o modificador), deslocamento e PV máximo' do
      abilities = { scores: { str: 11 }, mods: { str: 0 }, sources: { str: [{ label: 'Dado/Base', val: 11 }] } }
      movement  = { speed_ft: 30, speed_m: 9.1 }

      hp = described_class.apply!(
        { 'str' => { 'value' => 24 }, 'speed_ft' => { 'value' => 45 }, 'hp_max' => { 'value' => 80 } },
        abilities: abilities, movement: movement, hp_max: 73
      )

      expect(abilities[:scores][:str]).to eq(24)
      expect(abilities[:mods][:str]).to eq(7)
      expect(abilities[:sources][:str].last).to eq(label: 'Mestre', val: 24)
      expect(movement[:speed_ft]).to eq(45)
      expect(movement[:speed_m]).to eq(13.7)
      expect(hp).to eq(80)
    end

    it 'sem sobrescrita não toca em nada' do
      abilities = { scores: { str: 11 }, mods: { str: 0 } }
      expect(described_class.apply!({}, abilities: abilities, movement: {}, hp_max: 73)).to eq(73)
      expect(abilities[:scores][:str]).to eq(11)
    end
  end
end

RSpec.describe 'sobrescrita do Mestre no summary', type: :model do
  let(:sheet) { create(:sheet, str: 11, hp_max: 73) }

  it 'chega no payload, com o calculado de AGORA em `dm_overridable`' do
    sheet.update!(dm_overrides: { 'str' => { 'value' => 24 }, 'hp_max' => { 'value' => 80 } })
    r = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result

    expect(r[:abilities][:scores][:str]).to eq(24)
    expect(r.dig(:sheet, :hp_max)).to eq(80)
    # o que o motor daria hoje, para CADA chave — alimenta o "calculado" do editor
    expect(r[:dm_overridable]['str']).to eq(11)
    expect(r[:dm_overridable]['hp_max']).to eq(73)
  end

  # ⚠️ O aviso de defasagem depende disto. Se o payload devolvesse o calculado de
  # AGORA no lugar do gravado, a comparação viraria "cravado ≠ calculado", que é
  # verdade sempre — e um aviso que nunca apaga não avisa nada.
  it 'preserva o `computed` do MOMENTO do ajuste, mesmo com a ficha já mudada' do
    sheet.update!(dm_overrides: { 'hp_max' => { 'value' => 80, 'computed' => 73 } })
    sheet.update!(hp_max: 92)   # subiu de nível depois do ajuste

    r = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
    expect(r[:dm_overrides]['hp_max']['computed']).to eq(73)
    expect(r[:dm_overridable]['hp_max']).to eq(92)
  end

  # ⚠️ O TESTE QUE JUSTIFICA A CAMADA. `sync_ability_columns_from_metadata!`
  # reescreve `str..cha` a partir do metadata e roda no level-up, no talento e
  # na edição de raça. Sobrescrita gravada NA COLUNA sumiria em silêncio.
  it 'SOBREVIVE ao sync que reescreve as colunas de atributo' do
    sheet.update!(dm_overrides: { 'str' => { 'value' => 24 } })

    CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)
    sheet.reload

    expect(sheet.dm_overrides['str']['value']).to eq(24)
    expect(CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result[:abilities][:scores][:str]).to eq(24)
  end

  it 'soltar devolve o valor calculado' do
    sheet.update!(dm_overrides: { 'str' => { 'value' => 24 } })
    sheet.update!(dm_overrides: {})
    expect(CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result[:abilities][:scores][:str]).to eq(11)
  end
end
