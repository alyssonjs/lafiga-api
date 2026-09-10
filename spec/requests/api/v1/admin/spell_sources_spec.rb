require 'rails_helper'

# FASE 2 das magias — gestão das atrelagens com seletor ENCADEADO.
#
# O que este spec prende, por ordem de importância:
#
#   1. ⚠️ `Klass` NÃO é atrelável por aqui. As atrelagens de classe já têm dono
#      — o seletor "Classes" do formulário, que faz replace-all. Medido: atrelar
#      uma classe por aqui e salvar a magia a seguir APAGA a atrelagem, sem
#      aviso. Este é o guarda contra o mecanismo paralelo.
#   2. o seletor devolve `id`, não `api_index` — `spell_sources.source_id` é um id;
#   3. `Feature` tem três níveis, e NENHUMA feature fica inalcançável.
RSpec.describe 'Api::V1::Admin::Spells — atrelagens', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }

  let!(:magia) do
    Spell.create!(api_index: 'f2-teste', name: 'Magia de Teste F2', level: 1, school: 'Evocation',
                  range: '9 metros', components: 'V', duration: 'Instantanea',
                  casting_time: '1 acao', desc: 'teste')
  end
  let!(:raca) { create(:race, name: 'Tiefling F2', api_index: 'tiefling-f2') }
  let!(:sub_raca) { create(:sub_race, name: 'Abissal F2', api_index: 'abissal-f2', race: raca) }
  let(:corpo) { JSON.parse(response.body) }

  # A cadeia classe → subclasse → feature, construída para o teste do seletor.
  let!(:klass_f2) { create(:klass, name: 'Bruxo F2', api_index: 'warlock-f2', hit_die: 8) }
  let!(:sub_klass_f2) { SubKlass.create!(name: 'Patrono F2', api_index: 'patrono-f2', klass: klass_f2) }
  let!(:feature_sub) do
    f = Feature.create!(api_index: 'f2-feature-sub', name: 'Dádiva do Patrono F2', category: :subclass_feature)
    SubKlassLevel.create!(sub_klass: sub_klass_f2, level: 3).features << f
    f
  end
  # Sem `class_levels` nem `sub_klass_levels` — a órfã que não pode sumir.
  let!(:feature_solta) { Feature.create!(api_index: 'f2-feature-solta', name: 'Feature Solta F2', category: :subclass_feature) }

  def atrela(attrs)
    post "/api/v1/admin/spells/#{magia.id}/sources",
         params: { source: attrs }.to_json, headers: headers
  end

  describe 'GET source_options — o vocabulário do seletor' do
    before { get '/api/v1/admin/spells/source_options', headers: headers }

    it 'devolve as fontes encadeadas', :aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(corpo.keys).to include('Race', 'SubKlass', 'Feature', 'Feat', 'Background')
    end

    it '⚠️ NÃO oferece Klass — o formulário da magia é que manda nisso' do
      expect(corpo.keys).not_to include('Klass')
    end

    it '⚠️ a chave é o ID, não o api_index — `source_id` é um id' do
      linha = corpo['Race'].find { |r| r['name'] == 'Tiefling F2' }
      expect(linha['key']).to eq(raca.id)
      expect(linha['children'].first['key']).to eq(sub_raca.id)
    end

    it 'Feature encadeia em TRÊS níveis (classe → subclasse → feature)', :aggregate_failures do
      # ⚠️ A primeira versão deste teste fazia `skip` quando a base não tinha
      # feature nenhuma — passava sem provar nada. Agora constrói a cadeia.
      linha = corpo['Feature'].find { |k| k['name'] == 'Bruxo F2' }
      expect(linha).to be_present

      grupo = linha['children'].find { |g| g['name'] == 'Patrono F2' }
      expect(grupo).to be_present
      expect(grupo['features'].map { |f| f['key'] }).to include(feature_sub.id)
      expect(grupo['features'].first['level']).to eq(3)
    end

    it '⚠️ NENHUMA feature fica inalcançável', :aggregate_failures do
      # 389 das 1301 não estão em `class_levels` nem em `sub_klass_levels`.
      # Agrupá-las por casamento de nome contra `levels_json` agruparia errado —
      # ficam num grupo próprio, honestamente rotulado.
      alcancaveis = corpo['Feature'].flat_map { |k| k['children'].flat_map { |g| g['features'].map { |f| f['key'] } } }
      expect(alcancaveis).to include(feature_solta.id)
      expect(alcancaveis.uniq.size).to eq(Feature.count)
    end
  end

  describe 'POST sources — atrelar' do
    it 'atrela a uma sub-raça e devolve o rótulo de custo', :aggregate_failures do
      atrela(source_type: 'SubRace', source_id: sub_raca.id,
             casting_mode: 'uses_per_rest', uses_per_long_rest: 1, min_character_level: 3)

      expect(response).to have_http_status(:created)
      expect(corpo['source']['source_name']).to eq('Abissal F2')
      expect(corpo['source']['cost_label']).to eq('1/descanso longo')
      expect(corpo['source']['min_character_level']).to eq(3)
    end

    it '⚠️ entra sempre como manual — derived é território do rake' do
      atrela(source_type: 'Race', source_id: raca.id, casting_mode: 'at_will', origin: 'derived')
      expect(corpo['source']['origin']).to eq('manual')
    end

    it '⚠️ RECUSA Klass, dizendo onde se faz', :aggregate_failures do
      klass = Klass.find_by(api_index: 'barbarian') ||
              create(:klass, name: 'Bárbaro', api_index: 'barbarian', hit_die: 12)
      atrela(source_type: 'Klass', source_id: klass.id, casting_mode: 'with_slot')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('Classes')
      expect(SpellSource.where(source_type: 'Klass', spell_id: magia.id)).to be_empty
    end

    it 'recusa fonte que não existe — id sem FK sumiria da UI sem explicação' do
      atrela(source_type: 'SubRace', source_id: 999_999, casting_mode: 'at_will')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('não encontrada')
    end

    it 'recusa tipo fora do vocabulário' do
      atrela(source_type: 'Inventado', source_id: 1)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '⚠️ recusa limite gravado num modo que o ignora' do
      # Senão a ficha mostraria "1/dia" e a regra deixaria conjurar à vontade.
      atrela(source_type: 'Race', source_id: raca.id, casting_mode: 'at_will', uses_per_long_rest: 1)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET show — a magia traz as suas atrelagens' do
    it 'lista o que está atrelado, com origem e custo', :aggregate_failures do
      SpellSource.create!(source_type: 'SubRace', source_id: sub_raca.id, spell: magia,
                          origin: 'derived', casting_mode: 'at_will')
      get "/api/v1/admin/spells/#{magia.id}", headers: headers

      expect(corpo['sources'].size).to eq(1)
      expect(corpo['sources'].first).to include(
        'source_type' => 'SubRace', 'source_name' => 'Abissal F2',
        'origin' => 'derived', 'cost_label' => 'à vontade'
      )
    end
  end

  describe 'DELETE sources — desatrelar' do
    it '⚠️ avisa que a DERIVADA volta no próximo seed', :aggregate_failures do
      src = SpellSource.create!(source_type: 'SubRace', source_id: sub_raca.id, spell: magia,
                                origin: 'derived', casting_mode: 'at_will')
      delete "/api/v1/admin/spells/#{magia.id}/sources/#{src.id}", headers: headers

      expect(corpo['removed']).to be(true)
      expect(corpo['warning']).to eq('derived_will_return')
    end

    it 'a manual sai sem drama' do
      src = SpellSource.create!(source_type: 'Race', source_id: raca.id, spell: magia,
                                origin: 'manual', casting_mode: 'at_will')
      delete "/api/v1/admin/spells/#{magia.id}/sources/#{src.id}", headers: headers
      expect(corpo).not_to have_key('warning')
    end

    it 'não apaga atrelagem de OUTRA magia' do
      outra = Spell.create!(api_index: 'f2-outra', name: 'Outra F2', level: 1, school: 'Evocation',
                            range: '9 m', components: 'V', duration: 'Inst.', casting_time: '1 acao', desc: 'x')
      src = SpellSource.create!(source_type: 'Race', source_id: raca.id, spell: outra,
                                origin: 'manual', casting_mode: 'at_will')
      delete "/api/v1/admin/spells/#{magia.id}/sources/#{src.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(SpellSource.exists?(src.id)).to be(true)
    end
  end

  describe 'autorização' do
    it 'jogador não gere atrelagens' do
      player = create(:user, role: Role.find_or_create_by!(name: 'Player'))
      get '/api/v1/admin/spells/source_options', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
