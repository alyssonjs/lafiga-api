require 'rails_helper'

# ⚠️ PORTÃO da fase 4: a ficha de um personagem que JÁ existe reflete a edição
# da raça — e reflete-a INTEIRA.
#
# 🐞 Antes, a ficha contradizia-se. A mecânica propagava ao vivo (o
# `RaceProducer` lê `RaceRules.apply` a cada summary), mas a vitrine ficava
# presa no `race_summary` do provisionamento: o personagem passava a resistir a
# contundente e a lista de traços dele não mencionava nenhum traço que
# explicasse porquê. Nada dava erro.
RSpec.describe 'propagação de uma edição de raça para as fichas', type: :service do
  let!(:anao) { Race.find_by(api_index: 'dwarf') || Race.create!(name: 'Anão', api_index: 'dwarf') }

  # ⚠️ A lista branca de traços só FILTRA quando tem alguma coisa dentro
  # (`if allowed.any?`). No banco de teste o Anão não tem linhas `race_traits`,
  # então sem esta fixture o filtro nem chega a correr — e o teste passava pelo
  # motivo errado: apagar a união da lista branca não o derrubava.
  let!(:linha_de_traco) do
    traco = Trait.find_by(api_index: 'dwarven_resilience') ||
            Trait.create!(api_index: 'dwarven_resilience', name: 'Resiliência Anã', description: 'Resistência a veneno.')
    RaceTrait.find_or_create_by!(race_id: anao.id, sub_race_id: nil, trait_id: traco.id)
  end

  let!(:sheet) do
    Sheet.create!(character: create(:character), race_id: anao.id,
                  race_summary: { 'speed_ft' => 25, 'traits' => [{ 'name' => 'Resiliência Anã' }] })
  end

  after do
    anao.update_columns(rules_json: {})
    RaceRules.reload!
  end

  def resumo
    CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result || {}
  end

  def edita_a_raca!
    anao.update!(rules_json: {
                   'speed' => 40,
                   'traits' => [{ 'key' => 'pele_de_pedra' }],
                   'custom_traits' => { 'pele_de_pedra' => {
                     'name' => 'Pele de Pedra',
                     'description' => 'Resistência a dano contundente.',
                     'grants' => { 'defenses' => { 'resistance' => ['contundente'] } }
                   } }
                 })
    RaceRules.reload!
  end

  it 'a MECÂNICA já propagava sozinha — é a metade que funcionava' do
    edita_a_raca!
    expect(Array(resumo.dig(:modifiers, :resistances))).to include('contundente')
  end

  it '⚠️ e agora a VITRINE acompanha: deslocamento e traço', :aggregate_failures do
    edita_a_raca!
    Races::ResyncSummaries.call(race_id: anao.id)

    r = resumo
    expect(r.dig(:movement, :speed_ft)).to eq(40)
    nomes = Array(r[:traits]).map { |t| t[:name] }
    expect(nomes).to include('Pele de Pedra')
  end

  # 🐞 A lista branca de traços saía só das linhas `race_traits`, e o traço
  # PRÓPRIO não tem linha nenhuma: mesmo depois do resync ele era FILTRADO na
  # leitura, e a ficha continuava sem explicar a resistência.
  it '⚠️ a lista branca aceita o que a REGRA concede, não só as linhas do banco' do
    edita_a_raca!
    Races::ResyncSummaries.call(race_id: anao.id)

    expect(Array(resumo[:traits]).map { |t| t[:name] }).to include('Pele de Pedra')
    expect(RaceTrait.joins(:trait).where(race_id: anao.id, traits: { api_index: 'pele_de_pedra' })).to be_empty
  end

  it 'desfazer a edição devolve a ficha ao livro', :aggregate_failures do
    edita_a_raca!
    Races::ResyncSummaries.call(race_id: anao.id)
    anao.update!(rules_json: {})
    RaceRules.reload!
    Races::ResyncSummaries.call(race_id: anao.id)

    r = resumo
    expect(r.dig(:movement, :speed_ft)).to eq(25)
    expect(Array(r[:traits]).map { |t| t[:name] }).not_to include('Pele de Pedra')
  end
end
