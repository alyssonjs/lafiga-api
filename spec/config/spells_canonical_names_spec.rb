require 'rails_helper'
require 'yaml'

# Regressao do bug "Magia Drow → Luzes Dançantes apareciam como 'Globos de Luz'":
#
# O `dancing-lights` (api_index canonico) estava persistido em config/spells.yml
# com `name: 'Globos De Luz'`, divergindo do nome oficial PHB-PT ('Luzes Dançantes').
# Sintoma:
#   - Ficha do jogador exibia 'Globos de Luz' como magia racial do Drow.
#   - Wizard de criação não pré-selecionava a magia 'Luzes Dançantes' (definida em
#     `characterCreationData.ts`) no SpellPicker porque o pool da API retornava
#     'Globos De Luz' e a busca por nome não casava.
#
# Cobertura: este spec garante que mudanças futuras em `spells.yml` mantenham
# o nome PHB-PT sincronizado com `race_rules.yml#drow_magic.description` e com
# `front-lafiga/src/app/data/characterCreationData.ts#drow.spellsGranted`.
RSpec.describe 'config/spells.yml canonical PT-BR names' do
  let(:spells) do
    raw = YAML.load_file(Rails.root.join('config', 'spells.yml'))
    raw.is_a?(Hash) ? (raw['spells'] || raw[:spells] || []) : Array(raw)
  end

  def find_spell(api_index)
    spells.find { |s| s['api_index'] == api_index }
  end

  describe 'magias raciais do Drow (PHB-PT)' do
    it 'usa "Luzes Dançantes" (nao "Globos De Luz") para api_index dancing-lights' do
      spell = find_spell('dancing-lights')

      expect(spell).to be_present, 'spells.yml deve conter dancing-lights'
      expect(spell['name']).to eq('Luzes Dançantes'),
        "esperado 'Luzes Dançantes' (PHB-PT oficial), recebido #{spell['name'].inspect}"
    end

    it 'usa "Fogo das Fadas" para api_index faerie-fire' do
      spell = find_spell('faerie-fire')
      expect(spell).to be_present, 'spells.yml deve conter faerie-fire'
      expect(spell['name']).to eq('Fogo das Fadas')
    end

    it 'usa "Escuridão" para api_index darkness' do
      spell = find_spell('darkness')
      expect(spell).to be_present, 'spells.yml deve conter darkness'
      expect(spell['name']).to eq('Escuridão')
    end
  end

  describe 'config/dnd_translations.yml espelha os nomes canonicos' do
    let(:translations) { YAML.load_file(Rails.root.join('config', 'dnd_translations.yml')).fetch('spells') }

    it 'mapeia dancing-lights → Luzes Dançantes' do
      expect(translations['dancing-lights']).to eq('Luzes Dançantes')
    end
  end

  describe 'config/spell_aliases.yml resolve formas alternativas de Globos de Luz' do
    let(:aliases) { YAML.load_file(Rails.root.join('config', 'spell_aliases.yml')) }

    # "Globos de Luz" e "Luzes Dançantes" sao truques DISTINTOS no nosso sistema:
    #   - dancing-lights → "Luzes Dançantes" (PHB-PT, magia racial do Drow)
    #   - globos-de-luz  → "Globos de Luz"   (variante legacy mantida para
    #     fichas/excels antigos que referenciam o nome velho)
    # Por isso os aliases apontam para `globos-de-luz` (NAO mais para `dancing-lights`).
    it 'aliases "globos de luz" e "globo de luz" apontam para globos-de-luz' do
      expect(aliases['globos de luz']).to eq('globos-de-luz')
      expect(aliases['globo de luz']).to eq('globos-de-luz')
    end
  end

  describe '"Globos de Luz" preservada como truque separado de Luzes Dançantes' do
    # Regressao: "Globos de Luz" e "Luzes Dançantes" sao DOIS truques distintos
    # neste sistema. O fix do bug Drow renomeou o api_index `dancing-lights` para
    # o nome canonico PHB-PT ("Luzes Dançantes"), mas devemos preservar o registro
    # original "Globos de Luz" sob um api_index proprio (`globos-de-luz`) para
    # quem ja referenciava por esse nome.
    it 'spells.yml contem entrada api_index globos-de-luz com name "Globos de Luz"' do
      spell = find_spell('globos-de-luz')

      expect(spell).to be_present, 'spells.yml deve conter o truque globos-de-luz separado'
      expect(spell['name']).to eq('Globos de Luz')
      expect(spell['level']).to eq(0)
    end

    it 'dnd_translations.yml mapeia globos-de-luz → Globos de Luz' do
      translations = YAML.load_file(Rails.root.join('config', 'dnd_translations.yml')).fetch('spells')
      expect(translations['globos-de-luz']).to eq('Globos de Luz')
    end

    it 'os dois truques coexistem em spells.yml com api_indices distintos' do
      dancing = find_spell('dancing-lights')
      globos  = find_spell('globos-de-luz')

      expect(dancing['name']).to eq('Luzes Dançantes')
      expect(globos['name']).to eq('Globos de Luz')
      expect(dancing['api_index']).not_to eq(globos['api_index'])
    end
  end
end
