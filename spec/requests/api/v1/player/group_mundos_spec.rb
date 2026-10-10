# frozen_string_literal: true

require 'rails_helper'

# O relógio da vila na tela (L0.3): o grupo lê a âncora do seu mundo e o agora do servidor; a hora sai de conta no front.
RSpec.describe 'Api::V1::Player::GroupMundosController', type: :request do
  let(:jogador)  { create(:user) }
  let(:estranho) { create(:user) }
  let(:dm)       { create(:user, role: Role.find_by(name: 'DM') || create(:role, name: 'DM')) }
  let(:group)    { create(:group) }
  let!(:pc)      { create(:character, user: jogador, group: group) }

  def le(user)
    get "/api/v1/player/groups/#{group.id}/mundo", headers: bearer_headers_for(user), as: :json
  end

  it 'sem relógio ainda, devolve o mundo nulo e o agora do servidor' do
    le(jogador)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['mundo']).to be_nil
    expect(Time.iso8601(response.parsed_body['agora_servidor'])).to be_within(5.seconds).of(Time.current)
  end

  it 'devolve a âncora com as horas em ISO 8601 e milissegundos' do
    create(:mundo, group: group, epoca_em: Time.utc(2026, 10, 9, 0, 36, Rational(750, 1000)), minuto_na_epoca: 1440, fator: 40)
    le(jogador)

    expect(response.parsed_body['mundo']).to include(
      'group_id' => group.id, 'epoca_em' => '2026-10-09T00:36:00.750Z', 'minuto_na_epoca' => 1440, 'fator' => 40,
      'pausado_desde' => nil,
    )
  end

  it 'ler o mundo alcança o presente: processa a agenda vencida' do
    mundo = create(:mundo, group: group, epoca_em: 1.hour.ago, minuto_na_epoca: 0, fator: 40)
    Mundo::Agenda::Marca.call(mundo, minuto: 60, tipo: 'sino', chave: 'sino:60')
    Mundo::Agenda::Marca.call(mundo, minuto: 100_000, tipo: 'sino', chave: 'sino:100000')
    le(jogador)

    expect(response.parsed_body['agenda']).to eq('processados' => 1, 'em_dia' => true)
    expect(mundo.eventos.find_by(minuto: 60).resultado).to include('hora' => 1)
    expect(mundo.eventos.find_by(minuto: 100_000).processado_em).to be_nil
  end

  it 'o Mestre lê o de qualquer grupo' do
    le(dm)
    expect(response).to have_http_status(:ok)
  end

  it 'quem não é do grupo não vê' do
    le(estranho)
    expect(response).to have_http_status(:not_found)
  end
end
