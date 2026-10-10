# frozen_string_literal: true

require 'rails_helper'

# As ferramentas de dev do relógio (L0.3): criar o relógio de um grupo e avançá-lo de propósito ("avançar 8 h →
# anoitece"). As rotas não existem em produção; aqui, no teste, existem.
RSpec.describe 'Api::V1::Dev::MundosController', type: :request do
  let(:jogador)  { create(:user) }
  let(:estranho) { create(:user) }
  let(:group)    { create(:group) }
  let!(:pc)      { create(:character, user: jogador, group: group) }
  let(:h)        { bearer_headers_for(jogador) }

  def cria(headers = h, **body)
    post '/api/v1/dev/mundos', params: { group_id: group.id, **body }, headers: headers, as: :json
  end

  def avanca(mundo, horas, headers = h)
    post "/api/v1/dev/mundos/#{mundo.id}/avancar", params: { horas: horas }, headers: headers, as: :json
  end

  it 'cria o relógio ao meio-dia do dia 1; de novo, devolve o mesmo' do
    cria
    expect(response).to have_http_status(:created)
    mundo = group.reload.mundo
    expect(mundo.momento_em(Time.current)).to include(dia: 0, hora: 12)

    cria
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['mundo']['id']).to eq(mundo.id)
  end

  it 'avançar 8 h leva o meio-dia ao anoitecer, e a noite começa logo depois' do
    cria
    mundo = group.reload.mundo
    avanca(mundo, 8)

    expect(response).to have_http_status(:ok)
    agora = Time.iso8601(response.parsed_body['agora_servidor'])
    expect(mundo.reload.momento_em(agora)).to include(hora: 20, periodo: 'noite')
  end

  it 'recusa horas fora de 1 a um ano, e um minuto que não é inteiro' do
    cria
    mundo = group.reload.mundo
    avanca(mundo, 0)
    expect(response).to have_http_status(:unprocessable_entity)
    avanca(mundo, 'oito')
    expect(response).to have_http_status(:unprocessable_entity)

    outro = create(:group)
    create(:character, user: jogador, group: outro)
    post '/api/v1/dev/mundos', params: { group_id: outro.id, minuto: 'meio-dia' }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'quem não é do grupo não cria nem avança' do
    cria(bearer_headers_for(estranho))
    expect(response).to have_http_status(:not_found)

    mundo = create(:mundo, group: group)
    avanca(mundo, 8, bearer_headers_for(estranho))
    expect(response).to have_http_status(:not_found)
    expect(mundo.reload.minuto_na_epoca).to eq(0)
  end
end
