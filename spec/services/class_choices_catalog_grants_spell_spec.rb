# frozen_string_literal: true

require 'rails_helper'

# Bruxo — Fase 2 do `bruxo-plano.md` (v2): invocações que CONCEDEM magia real.
#
# 19 das 33 invocações dizem "você pode conjurar X". Antes, esse fato existia
# só na prosa da descrição — nenhum código conseguia agir sobre ele. Agora é
# DADO (`grants_spell: { spell, cost }`) no catálogo canônico.
#
# ⚠️ Este spec existe por causa de duas armadilhas que a fase −1 pegou:
#
#  1. **Link morto.** Escrever o slug da magia a partir do TEXTO produz link
#     que não resolve: a invocação aparece na ficha e não conjura nada, sem
#     erro em tela nenhuma. Dois casos reais: "Disfarce" é `disguise-self`
#     (cujo nome no banco é "Disfarçar-Se") e "Levitar" é `levitate`
#     ("Levitação"). O teste amarra cada slug a uma magia que EXISTE.
#
#  2. **Campo morto na normalização.** `normalize_entry` monta uma allowlist
#     de campos; sem uma linha para o campo novo, o YAML teria o dado e
#     NENHUM cliente o veria. É a mesma classe de falha das allowlists de
#     feed, que já mordeu três vezes.
RSpec.describe ClassChoicesCatalog, 'grants_spell (invocações do Bruxo)' do
  let(:entradas) { described_class.load('eldritch_invocations') }
  let(:com_magia) { entradas.select { |e| e[:grants_spell] } }

  it 'o campo SOBREVIVE à normalização (senão o dado existe e ninguém vê)' do
    expect(com_magia).not_to be_empty
    exemplo = com_magia.first[:grants_spell]
    expect(exemplo).to include(:spell, :cost)
  end

  it 'as 19 invocações que concedem magia estão marcadas' do
    expect(com_magia.size).to eq(19)
  end

  it 'toda magia concedida EXISTE no catálogo canônico (sem link morto)' do
    # Confere contra `config/spells.yml` — a FONTE que popula o banco — e não
    # contra o banco de teste (que nasce vazio) nem contra uma fixture minha:
    # fixture provaria só que o lookup compila, não que o slug é real.
    canonicos = YAML.load_file(Rails.root.join('config/spells.yml'))['spells']
                    .map { |e| e['api_index'] }.compact.to_set
    faltando = com_magia.reject { |e| canonicos.include?(e[:grants_spell][:spell]) }
    nomes = faltando.map { |e| "#{e[:slug]} → #{e[:grants_spell][:spell]}" }
    expect(faltando).to be_empty, "magia inexistente em spells.yml: #{nomes.join(', ')}"
  end

  it 'só existem as DUAS famílias de custo, e ambas são usadas' do
    custos = com_magia.map { |e| e[:grants_spell][:cost] }.uniq.sort
    expect(custos).to eq(%w[at_will once_per_lr_with_slot])
  end

  it 'a família bate com o TEXTO da invocação (à vontade × uma vez por descanso)' do
    # O texto é a regra; o dado é a fiação. Divergir aqui é a feature agir
    # diferente do que o jogador lê na própria ficha.
    divergentes = com_magia.filter_map do |e|
      texto = e[:description].downcase
      vontade = texto.include?('à vontade') || texto.include?('a vontade')
      uma_vez = texto.include?('uma vez usando um espaço') || texto.include?('descanso longo antes')
      esperado = vontade ? 'at_will' : (uma_vez ? 'once_per_lr_with_slot' : nil)
      next if esperado.nil? || esperado == e[:grants_spell][:cost]

      "#{e[:slug]}: texto diz #{esperado}, dado diz #{e[:grants_spell][:cost]}"
    end
    expect(divergentes).to be_empty, divergentes.join(' · ')
  end

  it 'só invocações de BRUXO concedem magia por esta via' do
    fora = com_magia.reject { |e| Array(e[:classes]).include?('warlock') }
    expect(fora).to be_empty
  end

  describe 'validação do schema' do
    it 'recusa custo fora das duas famílias' do
      expect(described_class::GRANTS_SPELL_COSTS).to eq(%w[at_will once_per_lr_with_slot])
    end

    it 'recusa chave desconhecida dentro de grants_spell' do
      expect(described_class::ALLOWED_GRANTS_SPELL_KEYS).to eq(%w[spell cost])
    end
  end
end
