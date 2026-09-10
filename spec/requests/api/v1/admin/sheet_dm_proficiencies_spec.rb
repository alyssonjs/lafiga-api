require 'rails_helper'

# Proficiência CONCEDIDA pelo Mestre, avulsa.
#
# ⚠️ Existe porque não havia caminho nenhum, e o que mais se parecia com um era
# ERRADO: o passo de Perícias do wizard grava em
# `class_choices.per_level['1'].skills`, então a perícia passaria a constar como
# vinda da CLASSE. O servidor só avisava (`warn!`), não bloqueava — o dado
# entraria com a proveniência errada em silêncio.
RSpec.describe 'Api::V1::Admin::SheetDmProficiencies', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }
  let(:corpo) { JSON.parse(response.body) }

  let!(:pericia) do
    Proficiency.find_by(api_index: 'skill-furtividade') ||
      Proficiency.create!(api_index: 'skill-furtividade', name: 'Furtividade', category: 'skill')
  end
  let!(:idioma) do
    Proficiency.find_by(api_index: 'lang-anao') ||
      Proficiency.create!(api_index: 'lang-anao', name: 'Anão', category: 'language',
                          sub_category: 'standard')
  end

  def concede(payload)
    patch "/api/v1/admin/sheets/#{sheet.id}/dm_proficiencies",
          params: { dm_proficiencies: payload }.to_json, headers: headers
  end

  describe 'PATCH — conceder' do
    it 'concede e devolve a lista com nome e categoria', :aggregate_failures do
      concede({ pericia.api_index => { note: 'aprendeu com o mestre ladrão' } })

      expect(response).to have_http_status(:ok)
      expect(corpo['list'].first).to include(
        'api_index' => 'skill-furtividade', 'name' => 'Furtividade',
        'category' => 'skill', 'note' => 'aprendeu com o mestre ladrão'
      )
    end

    it 'guarda quem concedeu e quando', :aggregate_failures do
      concede({ pericia.api_index => {} })
      linha = sheet.reload.dm_proficiencies[pericia.api_index]
      expect(linha['by_user_id']).to eq(dm.id)
      expect(linha['at']).to be_present
    end

    it '⚠️ recusa proficiência fora do catálogo' do
      # Sem isto, um erro de digitação concederia algo que não aparece em lado
      # nenhum — invisível para sempre.
      concede({ 'inventada' => {} })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('não catalogada')
    end

    it 'patch PARCIAL: chave ausente não mexe no que já estava' do
      concede({ pericia.api_index => { note: 'primeiro' } })
      concede({ idioma.api_index => {} })
      expect(sheet.reload.dm_proficiencies.keys).to contain_exactly(pericia.api_index, idioma.api_index)
      expect(sheet.dm_proficiencies[pericia.api_index]['note']).to eq('primeiro')
    end

    it '`null` retira a concessão' do
      concede({ pericia.api_index => {} })
      concede({ pericia.api_index => nil })
      expect(sheet.reload.dm_proficiencies).to eq({})
    end

    it '⚠️ a data da concessão NÃO é reescrita ao editar o motivo' do
      concede({ pericia.api_index => { note: 'antes' } })
      antes = sheet.reload.dm_proficiencies[pericia.api_index]['at']
      concede({ pericia.api_index => { note: 'depois' } })
      expect(sheet.reload.dm_proficiencies[pericia.api_index]['at']).to eq(antes)
    end
  end

  describe 'a ficha passa a listar, na FONTE certa' do
    it '⚠️ perícia entra como `dm`, não como se viesse da classe', :aggregate_failures do
      concede({ pericia.api_index => {} })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result

      expect(sum.dig(:proficiencies, :skills, :dm)).to eq(['Furtividade'])
      expect(Array(sum.dig(:proficiencies, :skills, :class))).not_to include('Furtividade')
    end

    it 'idioma entra na lista de idiomas' do
      concede({ idioma.api_index => {} })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(Array(sum.dig(:proficiencies, :languages))).to include('Anão')
    end

    it 'e sai da ficha quando o Mestre retira' do
      concede({ pericia.api_index => {} })
      concede({ pericia.api_index => nil })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(sum.dig(:proficiencies, :skills, :dm)).to be_nil
    end
  end

  describe '⚠️ concedida NÃO é o mesmo que treinada' do
    it 'a concessão não aparece no aprendizado', :aggregate_failures do
      concede({ pericia.api_index => {} })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result

      # São coisas diferentes e a ficha tem de as distinguir: uma diz "o Mestre
      # deu", a outra "o personagem treinou e concluiu".
      expect(Array(sum[:learning])).to be_empty
      expect(Array(sum[:dm_proficiencies]).map { |l| l['name'] }).to eq(['Furtividade'])
    end

    it 'e cada uma tem a sua fonte na lista' do
      concede({ pericia.api_index => {} })
      sheet.update_column(:training, {
        idioma.api_index => { 'learning' => true, 'hours_required' => 10, 'hours_trained' => 10 }
      })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result

      expect(sum.dig(:proficiencies, :skills, :dm)).to eq(['Furtividade'])
      expect(Array(sum.dig(:proficiencies, :languages))).to include('Anão')
    end
  end

  describe '⚠️ RETIRAR — o mestre passa por cima da regra' do
    let(:sheet) do
      s = create(:sheet, character: create(:character, user: create(:user)))
      # Perícia vinda da CLASSE, como o pipeline a grava.
      s.update_column(:class_summary, { 'name' => 'Ladino', 'skills' => ['Furtividade', 'Acrobacia'] })
      s
    end

    it 'a perícia da CLASSE sai da ficha', :aggregate_failures do
      antes = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(Array(antes.dig(:proficiencies, :skills, :class))).to include('Furtividade')

      concede({ pericia.api_index => { revoked: true, note: 'perdeu o braço em Vorthek' } })

      depois = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(Array(depois.dig(:proficiencies, :skills, :class))).not_to include('Furtividade')
      # E o que NÃO foi retirado continua.
      expect(Array(depois.dig(:proficiencies, :skills, :class))).to include('Acrobacia')
    end

    it 'a retirada aparece na lista, marcada' do
      concede({ pericia.api_index => { revoked: true } })
      linha = corpo['list'].find { |l| l['api_index'] == pericia.api_index }
      expect(linha['revoked']).to be(true)
    end

    it '⚠️ retirada NÃO entra na fonte `dm` — ela tira, não dá' do
      concede({ pericia.api_index => { revoked: true } })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(sum.dig(:proficiencies, :skills, :dm)).to be_nil
    end

    it 'desmarcar `revoked` devolve a perícia' do
      concede({ pericia.api_index => { revoked: true } })
      concede({ pericia.api_index => { revoked: false } })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(Array(sum.dig(:proficiencies, :skills, :class))).to include('Furtividade')
    end

    it '⚠️ tira mesmo com a grafia diferente' do
      # As listas são STRINGS e a mesma proficiência já apareceu em quatro
      # grafias nesta base — comparar cru deixaria a retirada não fazer nada.
      sheet.update_column(:class_summary, { 'skills' => ['furtividade'] })
      concede({ pericia.api_index => { revoked: true } })
      sum = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(Array(sum.dig(:proficiencies, :skills, :class))).to be_empty
    end

    it 'em curso e retiradas convivem na mesma lista' do
      concede({ pericia.api_index => { revoked: true }, idioma.api_index => {} })
      nomes = corpo['list'].map { |l| [l['name'], l['revoked']] }
      expect(nomes).to contain_exactly(['Anão', false], ['Furtividade', true])
    end
  end

  describe 'DELETE — retira tudo' do
    it 'esvazia as concessões' do
      concede({ pericia.api_index => {}, idioma.api_index => {} })
      delete "/api/v1/admin/sheets/#{sheet.id}/dm_proficiencies", headers: headers
      expect(sheet.reload.dm_proficiencies).to eq({})
    end
  end

  describe 'autorização' do
    it 'jogador não concede proficiência' do
      player = create(:user, role: Role.find_or_create_by!(name: 'Player'))
      patch "/api/v1/admin/sheets/#{sheet.id}/dm_proficiencies",
            params: { dm_proficiencies: { pericia.api_index => {} } }.to_json,
            headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end
end
