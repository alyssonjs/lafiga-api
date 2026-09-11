require 'rails_helper'

# FASE 1 do editor de raças — o mestre grava a MECÂNICA pela API.
#
# ⚠️ O portão desta fase: uma raça criada pelo editor tem de servir para
# provisionar personagem. Antes do overlay, `RaceRules.apply` levantava
# `ArgumentError: race not found` para qualquer raça que só existisse no banco.
RSpec.describe 'Api::V1::Admin::Races — rules_json', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  after { RaceRules.reload! }

  def cria(payload)
    post '/api/v1/admin/races', params: { race: payload }.to_json, headers: headers
  end

  let(:regras_validas) do
    {
      'size' => 'Médio',
      # Formas MEDIDAS no YAML: `speed` inteiro em pés, `darkvision` `{range:}`.
      'speed' => 25,
      'darkvision' => { 'range' => 60 },
      'ability' => { 'type' => 'fixed', 'increases' => [{ 'ability' => 'FOR', 'amount' => 2 }] },
      'languages' => { 'always' => ['Comum'], 'choiceCount' => 1 },
      'traits' => [{ 'key' => 'garra_de_pedra' }],
      'custom_traits' => {
        'garra_de_pedra' => {
          'name' => 'Garra de Pedra',
          'description' => 'Garras naturais que cortam rocha.',
          'grants' => { 'natural_weapon' => { 'name' => 'Garras', 'dice' => '1d6', 'damage_type' => 'cortante', 'ability' => 'STR' } }
        }
      }
    }
  end

  describe 'criar raça com mecânica' do
    it 'grava e devolve o `rules_json`', :aggregate_failures do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })

      expect(response).to have_http_status(:created)
      r = Race.find_by(api_index: 'golem-argila')
      expect(r.rules_json['speed']).to eq(25)
      expect(r.rules_json.dig('ability', 'increases', 0, 'ability')).to eq('FOR')
    end

    it '⚠️ PORTÃO: `RaceRules.apply` responde para a raça nova', :aggregate_failures do
      # Era exatamente isto que levantava ArgumentError antes do overlay.
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      RaceRules.reload!

      resultado = nil
      expect {
        resultado = RaceRules.apply(race_id: 'golem-argila', subrace_id: nil, choices: {})
      }.not_to raise_error
      expect(resultado[:speed]).to eq(25)
    end

    it '⚠️ o traço PRÓPRIO entra no catálogo e o ref RESOLVE', :aggregate_failures do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      RaceRules.reload!

      # A definição sobe PREFIXADA pelo dono — a chave é escolhida dentro de
      # uma raça e o catálogo é global (ver `race_rules_overlay_spec`).
      definicao = RaceRules.trait_definitions[:'golem-argila__garra_de_pedra']
      expect(definicao).to be_present
      expect(definicao.dig(:grants, :natural_weapon, :dice)).to eq('1d6')

      # ⚠️ E o ref DENTRO da raça aponta para essa chave. Se só metade fosse
      # reescrita, o traço existiria no catálogo e a ficha não o veria.
      aplicada = RaceRules.apply(race_id: 'golem-argila', subrace_id: nil, choices: {})
      chaves = Array(aplicada[:traits]).map { |t| t[:key] }
      expect(chaves).to eq(['golem-argila__garra_de_pedra'])
      expect(RaceRules.trait_definitions[chaves.first.to_sym]).to be_present
    end

    it 'a resposta do create vem no envelope `race`, com id', :aggregate_failures do
      # 🐞 antes devolvia o objeto CRU: quem cria raça E sub-raça no mesmo
      # gesto lia `data.race` e recebia `undefined` — ficava sem o `race_id`.
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      expect(corpo['race']).to be_present
      expect(corpo.dig('race', 'id')).to be_present
      expect(corpo.dig('race', 'rules_json', 'speed')).to eq(25)
    end

    it 'a leitura devolve o `rules_json` — senão o editor abre vazio' do
      cria({ name: 'Golem de Argila', api_index: 'golem-argila', rules_json: regras_validas })
      r = Race.find_by(api_index: 'golem-argila')

      get "/api/v1/admin/races/#{r.id}", headers: headers
      expect(corpo.dig('race', 'rules_json', 'speed')).to eq(25)
    end
  end

  # 🐞 `proficiencies` tem TRÊS formas no YAML e a primeira versão do
  # sanitizador só conhecia uma: coagia todo Hash para `{choiceCount, choices}`
  # e atirava fora o `fixed`. O Elfo perderia Percepção no primeiro save que
  # tocasse em proficiências — sem erro, porque o sanitizador "limpava" em vez
  # de recusar. E `fixed` é o que o provisioning lê e reescreve ao resolver a
  # escolha de ferramentas do Anão.
  describe '⚠️ `proficiencies`: as três formas do YAML sobrevivem' do
    def grava(profs)
      cria({ name: 'Golem', api_index: 'golem-prof', rules_json: { 'proficiencies' => profs } })
      Race.find_by(api_index: 'golem-prof')&.rules_json&.dig('proficiencies')
    end

    it 'lista simples (weapons/armor)' do
      expect(grava({ 'weapons' => ['machadinha', ' martelo leve '] }))
        .to eq({ 'weapons' => ['machadinha', 'martelo leve'] })
    end

    it '⚠️ `fixed` (a forma DOMINANTE — 6 de 7 em skills)' do
      expect(grava({ 'skills' => { 'fixed' => ['Percepção'] } }))
        .to eq({ 'skills' => { 'fixed' => ['Percepção'] } })
    end

    it 'escolha (`choiceCount` + `choices`)' do
      expect(grava({ 'tools' => { 'choiceCount' => 1, 'choices' => ['Ferramentas de ferreiro'] } }))
        .to eq({ 'tools' => { 'choiceCount' => 1, 'choices' => ['Ferramentas de ferreiro'] } })
    end

    it 'fixo E escolha convivem', :aggregate_failures do
      out = grava({ 'tools' => { 'fixed' => ['Kit de herbalismo'], 'choiceCount' => 1, 'choices' => ['Ferramentas de ferreiro'] } })
      expect(out.dig('tools', 'fixed')).to eq(['Kit de herbalismo'])
      expect(out.dig('tools', 'choiceCount')).to eq(1)
    end

    it 'categoria desconhecida é RECUSADA, não engolida', :aggregate_failures do
      cria({ name: 'Golem', api_index: 'golem-prof2', rules_json: { 'proficiencies' => { 'pericias' => ['x'] } } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join(' ')).to include('pericias')
    end
  end

  # 🐞 O editor precisa da base CRUA do YAML para saber o que o mestre TOCOU.
  # Duas maneiras de errar, as duas silenciosas:
  #   · não mandar base → `serializar` vê divergência em TODO campo e congela a
  #     raça numa cópia que deixa de acompanhar o catálogo;
  #   · mandar a base JÁ SOBREPOSTA → o que o mestre gravou parece igual à base,
  #     não é reemitido, e DESAPARECE no save seguinte.
  describe '⚠️ `rules_base`: a base crua do YAML viaja com a raça' do
    let(:anao) { Race.find_by(api_index: 'dwarf') || Race.create!(name: 'Anão', api_index: 'dwarf') }

    it 'vem preenchida para uma raça do livro', :aggregate_failures do
      get "/api/v1/admin/races/#{anao.id}", headers: headers

      base = corpo.dig('race', 'rules_base')
      expect(base).to be_present
      expect(base['speed']).to eq(25)
      expect(base.dig('darkvision', 'range')).to eq(60)
    end

    it '⚠️ NÃO traz o overlay — é a base, não o resultado', :aggregate_failures do
      anao.update!(rules_json: { 'speed' => 40 })
      RaceRules.reload!

      get "/api/v1/admin/races/#{anao.id}", headers: headers
      expect(corpo.dig('race', 'rules_base', 'speed')).to eq(25)
      expect(corpo.dig('race', 'rules_json', 'speed')).to eq(40)
    ensure
      anao.update_columns(rules_json: {})
      RaceRules.reload!
    end

    it 'raça sem nó no YAML devolve base vazia, não erro' do
      cria({ name: 'Golem', api_index: 'golem-sem-yaml', rules_json: { 'speed' => 30 } })
      r = Race.find_by(api_index: 'golem-sem-yaml')

      get "/api/v1/admin/races/#{r.id}", headers: headers
      expect(corpo.dig('race', 'rules_base')).to eq({})
    end
  end

  # ⚠️ As formas foram MEDIDAS no YAML: `speed` é inteiro em pés (14/14),
  # `darkvision` é `{range: N}` (8/8), `requires` é lista. Gravar outra forma
  # não levanta erro — faz a ficha ler errado, em silêncio.
  describe '⚠️ as formas do YAML são respeitadas ao gravar' do
    def grava(regras)
      cria({ name: 'Golem', api_index: 'golem-forma', rules_json: regras })
      Race.find_by(api_index: 'golem-forma')&.rules_json
    end

    it '`speed` grava INTEIRO em pés' do
      expect(grava({ 'speed' => '30' })['speed']).to eq(30)
    end

    it '`speed` com unidade é RECUSADO, não convertido à toa', :aggregate_failures do
      cria({ name: 'Golem', api_index: 'golem-forma2', rules_json: { 'speed' => '9m' } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join(' ')).to include('pés')
    end

    it '`darkvision` grava `{range: N}` mesmo recebendo número solto' do
      expect(grava({ 'darkvision' => 60 })['darkvision']).to eq({ 'range' => 60 })
    end

    it '`darkvision` aceita a forma do YAML de volta' do
      expect(grava({ 'darkvision' => { 'range' => 120 } })['darkvision']).to eq({ 'range' => 120 })
    end

    it '`requires` grava LISTA — antes virava a string do array' do
      expect(grava({ 'requires' => ['dwarfTool'] })['requires']).to eq(['dwarfTool'])
    end
  end

  describe '⚠️ o que erraria em silêncio é RECUSADO' do
    it 'chave desconhecida', :aggregate_failures do
      cria({ name: 'X', api_index: 'x1', rules_json: { 'velocidade' => '9m' } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('velocidade')
    end

    it 'canal de grant inventado' do
      # Gravaria e seria IGNORADO: o mestre configurava e não valia, sem nada
      # na tela a dizer porquê.
      cria({ name: 'X', api_index: 'x2', rules_json: {
        'custom_traits' => { 'meu' => { 'name' => 'Meu', 'grants' => { 'superpoder' => {} } } }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('superpoder')
    end

    it 'atributo que não existe' do
      cria({ name: 'X', api_index: 'x3', rules_json: {
        'ability' => { 'type' => 'fixed', 'increases' => [{ 'ability' => 'SORTE', 'amount' => 2 }] }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors'].join).to include('SORTE')
    end

    it 'traço sem nome' do
      cria({ name: 'X', api_index: 'x4', rules_json: {
        'custom_traits' => { 'sem_nome' => { 'description' => 'sem nome' } }
      } })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '⚠️ nada é gravado quando há erro — não fica meio configurada' do
      cria({ name: 'X', api_index: 'x5', rules_json: { 'speed' => '9m', 'inventado' => 1 } })
      expect(Race.find_by(api_index: 'x5')).to be_nil
    end
  end

  describe 'editar' do
    let!(:raca) { Race.create!(name: 'Anão Teste', api_index: 'anao-teste', rules_json: { 'speed' => '7.5m' }) }

    it 'patch parcial: pedido SEM `rules_json` não mexe nas regras' do
      # O toggle de `playable` continua a funcionar sem apagar a mecânica.
      patch "/api/v1/admin/races/#{raca.id}", params: { race: { playable: false } }.to_json, headers: headers
      expect(raca.reload.rules_json['speed']).to eq('7.5m')
    end

    it '`{}` SOLTA as regras — a raça volta a valer o YAML' do
      patch "/api/v1/admin/races/#{raca.id}", params: { race: { rules_json: {} } }.to_json, headers: headers
      expect(raca.reload.rules_json).to eq({})
    end
  end

  describe 'autorização' do
    it 'jogador não grava regra de raça' do
      player = create(:user, role: Role.find_or_create_by!(name: 'Player'))
      post '/api/v1/admin/races',
           params: { race: { name: 'X', api_index: 'x9', rules_json: { 'speed' => '9m' } } }.to_json,
           headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end
end
