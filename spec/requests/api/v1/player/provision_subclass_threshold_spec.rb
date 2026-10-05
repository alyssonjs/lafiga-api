# frozen_string_literal: true

require 'rails_helper'

# FASE 4 — o portão do nível da sub-classe no PROVISIONAMENTO, acordado.
#
# ⚠️ Com `klasses.subclass_level` NULL, `eligible_at_l1` era sempre verdadeiro e
# a sub-classe entrava no nível 1 para TODA classe. Preenchida a coluna, o
# provisionamento adia a escolha para o `LevelUpService` quando o limiar é maior
# que 1 — e o risco medido antes do backfill era o portão acordar QUEBRANDO a
# criação (a validação do model estourando o `create!` inteiro). Este spec
# tranca as duas pontas: cria sem erro, e adia/anexa conforme o limiar.
RSpec.describe 'Provisionamento × limiar da sub-classe', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  let(:race)     { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  # ⚠️ O helper do catálogo de teste JÁ projeta `subclass_level = 3` — o mesmo
  # valor que o backfill grava em prod.
  let(:klass)    { barbarian_klass }
  let(:bg)       { acolyte_background }
  let(:align)    { lawful_good_alignment }

  let(:sub_klass) do
    SubKlass.create!(name: 'Caminho SO', api_index: "caminho-so-#{SecureRandom.hex(3)}",
                     klass: klass,
                     levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'Frenesi SO' }] }])
  end

  def provisiona!
    payload = minimal_l1_barbarian_provision_payload(
      race: race, sub_race: sub_race, klass: klass, background: bg, alignment: align
    )
    payload[:wizard][:klass][:classSubclassId] = sub_klass.id
    post '/api/v1/player/characters/provision', params: payload, headers: headers, as: :json
  end

  def sheet_klass_criado
    sheet_id = response.parsed_body.dig('character', 'sheet_id')
    Sheet.find(sheet_id).sheet_klasses.find_by!(klass_id: klass.id)
  end

  it '⚠️ limiar 3: cria SEM erro e ADIA a sub-classe — nada de falso positivo' do
    provisiona!

    expect(response).to have_http_status(:created), -> { response.body }
    sk = sheet_klass_criado
    expect(sk.level).to eq(1)
    expect(sk.sub_klass_id).to be_nil
  end

  it 'limiar 1: anexa a sub-classe já na criação (o caso Bruxo/Clérigo/Feiticeiro)' do
    klass.update_columns(subclass_level: 1)

    provisiona!

    expect(response).to have_http_status(:created), -> { response.body }
    expect(sheet_klass_criado.sub_klass_id).to eq(sub_klass.id)
  end
end
