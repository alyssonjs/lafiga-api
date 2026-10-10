# frozen_string_literal: true

require 'rails_helper'

# O SERVIDOR rola no feed (L0.6): a expressão vira uma rolagem selada, e o item do feed sai com o selo. O selo só o
# servidor põe: o que o cliente manda no `create` é descartado.
RSpec.describe 'Feed da sessão — rolar no servidor', type: :request do
  let(:mestre)   { create(:user) }
  let(:jogadora) { create(:user) }
  let(:group)    { create(:group, name: 'Mesa dos Dados', dm_user_id: mestre.id) }
  let!(:pc)      { create(:character, user: jogadora, group: group, name: 'Ana') }
  let(:schedule) { create(:schedule, group: group) }
  let(:agora_ms) { (Time.current.to_r * 1000).to_i }

  def rola(expressao, id: 'r-1', user: jogadora, **extra)
    post "/api/v1/player/schedules/#{schedule.id}/session_feed_items/rolar",
         params: { rolagem: { id: id, expressao: expressao, timestamp: agora_ms, label: "!#{expressao}", **extra } },
         headers: bearer_headers_for(user), as: :json
  end

  it 'rola no servidor e o item sai com o selo da rolagem gravada' do
    rola('d20+5')

    expect(response).to have_http_status(:ok)
    item = response.parsed_body['item']
    rolagem = Dados::Rolagem.find_by!(chave: "feed:#{schedule.id}:r-1")
    expect(item).to include('kind' => 'roll', 'id' => 'r-1', 'total' => rolagem.total, 'label' => '!d20+5')
    expect(item['selo']).to eq('rolagem' => rolagem.id, 'fonte' => 'segura', 'codigo' => rolagem.selo[0, 8])
    expect(item['d20']).to eq(rolagem.dados.first['rolagens'].first)
    expect(item['breakdown']).to eq("1d20 (#{item['d20']}) + 5 = #{rolagem.total}")
    expect(rolagem.contexto).to include('schedule_id' => schedule.id, 'user_id' => jogadora.id)
    expect(SessionFeedItem.find_by!(schedule: schedule, client_id: 'r-1').payload['selo']).to eq(item['selo'])
  end

  it 'a vantagem sai com os dois d20 no losango' do
    rola('2d20kh1+3')

    item = response.parsed_body['item']
    rolagens = Dados::Rolagem.last.dados.first['rolagens']
    expect(item).to include('advantage' => 'advantage', 'd20' => rolagens.max, 'd20Alt' => rolagens.min)
  end

  it 'o retry devolve a mesma rolagem, sem rolar de novo' do
    rola('4d6', id: 'r-2')
    primeira = response.parsed_body['item']
    rola('4d6', id: 'r-2')

    expect(response.parsed_body['item']['total']).to eq(primeira['total'])
    expect(Dados::Rolagem.where(chave: "feed:#{schedule.id}:r-2").count).to eq(1)
    expect(SessionFeedItem.where(schedule: schedule, client_id: 'r-2').count).to eq(1)
  end

  it 'recusa a expressão que não é de dados' do
    rola('d20*2')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Dados::Rolagem.count).to eq(0)
  end

  it 'a jogadora não rola no caderno do Mestre, e nada é rolado' do
    rola('d20', audience: 'dm')

    expect(response).to have_http_status(:forbidden)
    expect(Dados::Rolagem.count).to eq(0)
  end

  it 'REGRESSAO: o selo que o cliente manda no create é descartado' do
    post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
         params: { item: { kind: 'roll', id: 'falso-1', type: 'custom', label: '!d20', total: 20, timestamp: agora_ms,
                           selo: { rolagem: 1, fonte: 'segura', codigo: 'deadbeef' } } },
         headers: bearer_headers_for(jogadora), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['item']).not_to have_key('selo')
    expect(SessionFeedItem.find_by!(client_id: 'falso-1').payload).not_to have_key('selo')
  end
end
