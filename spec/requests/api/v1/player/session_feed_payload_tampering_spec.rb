# frozen_string_literal: true

require 'rails_helper'

# Auditoria de adulteração de payload no feed da sessão.
#
# A pergunta destes specs é sempre a mesma: **mexer no corpo do pedido dá
# acesso a informação de Mestre?** O cliente calcula o dado e escreve o texto,
# mas quem decide CANAL e VISIBILIDADE é o servidor.
RSpec.describe 'Feed da sessão — adulteração de payload', type: :request do
  let(:papel_dm) { Role.find_or_create_by!(name: 'DM') }
  let(:mestre)   { create(:user, role: papel_dm) }
  let(:jogadora) { create(:user) }
  let(:forasteiro) { create(:user) }

  let(:group) { create(:group, name: 'Mesa Tampering', dm_user_id: mestre.id) }
  let!(:pc) { create(:character, user: jogadora, group: group, name: 'Ana') }
  let(:schedule) { create(:schedule, group: group) }

  def post_roll(user, extra = {})
    item = {
      kind: 'roll', id: "r-#{SecureRandom.hex(4)}", timestamp: (Time.current.to_f * 1000).to_i,
      type: 'custom', label: 'rolagem', total: 7, breakdown: 'd20',
    }.merge(extra)

    post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
         params: { item: item }, headers: bearer_headers_for(user), as: :json
    item[:id]
  end

  def ler(user)
    get "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
        headers: bearer_headers_for(user), as: :json
    response.parsed_body
  end

  describe 'ESCALAÇÃO DE ESCRITA — o jogador declara `audience: dm` no corpo' do
    it 'é RECUSADO com 403 e nada é gravado' do
      id = post_roll(jogadora, audience: 'dm')

      expect(response).to have_http_status(:forbidden)
      expect(SessionFeedItem.find_by(client_id: id)).to be_nil
    end

    it 'forasteiro nao escreve no combinado da equipe pelo corpo' do
      id = post_roll(forasteiro, audience: 'players')

      expect(response).to have_http_status(:forbidden)
      expect(SessionFeedItem.find_by(client_id: id)).to be_nil
    end

    it 'sem declarar canal, a rolagem do jogador cai no Geral' do
      id = post_roll(jogadora)

      expect(response).to have_http_status(:ok)
      expect(SessionFeedItem.find_by(client_id: id).audience).to eq('all')
    end
  end

  describe 'IDENTIDADE — o jogador declara `senderRole: dm` no corpo' do
    it 'NAO ganha o cracha de MESTRE (o servidor deriva o papel)' do
      # O front pinta o cracha "MESTRE" a partir de `senderRole` (ROLE_LABELS em
      # DiceRollBubble). Se o campo vier do cliente sem conferencia, qualquer
      # jogador publica uma mensagem que parece do Mestre.
      id = post_roll(jogadora, senderRole: 'dm')

      expect(response).to have_http_status(:ok)
      gravado = SessionFeedItem.find_by(client_id: id)
      expect(gravado.payload['senderRole']).not_to eq('dm')
    end

    it 'o Mestre recebe o papel `dm` mesmo sem o declarar' do
      id = post_roll(mestre)

      gravado = SessionFeedItem.find_by(client_id: id)
      expect(gravado.payload['senderRole']).to eq('dm')
    end
  end

  describe 'ESCALAÇÃO DE LEITURA — o jogador pede o canal do Mestre' do
    before do
      SessionFeedItem.create!(
        schedule: schedule, kind: 'chat', client_id: 'segredo-1', audience: 'dm',
        posted_at: Time.current,
        payload: { 'kind' => 'chat', 'id' => 'segredo-1', 'text' => 'segredo do mestre' },
      )
    end

    it 'parametro `audience` na query NAO abre o caderno secreto' do
      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items" \
          "?audience=dm&audiences[]=dm",
          headers: bearer_headers_for(jogadora), as: :json

      expect(response).to have_http_status(:ok)
      textos = response.parsed_body['items'].map { |i| i['text'] }
      expect(textos).not_to include('segredo do mestre')
      expect(response.parsed_body['meta']['audiences']).not_to include('dm')
    end
  end

  describe 'CONFIDENCIALIDADE — a rolagem secreta do Mestre pelo caminho durável' do
    it 'permanece no canal do Mestre e NAO chega ao jogador' do
      id = post_roll(mestre, audience: 'dm', label: 'rolagem secreta do mestre')
      expect(response).to have_http_status(:ok)

      gravado = SessionFeedItem.find_by(client_id: id)
      expect(gravado.audience).to eq('dm')

      rotulos = ler(jogadora)['items'].map { |i| i['label'] }
      expect(rotulos).not_to include('rolagem secreta do mestre')
    end
  end

  describe 'MESA ALHEIA — trocar o `schedule_id` na URL' do
    let(:outra_mesa) { create(:group, name: 'Mesa Alheia', dm_user_id: create(:user).id) }
    let(:outra) { create(:schedule, group: outra_mesa) }

    before do
      %w[all players dm].each do |canal|
        SessionFeedItem.create!(
          schedule: outra, kind: 'chat', client_id: "alheio-#{canal}", audience: canal,
          posted_at: Time.current,
          payload: { 'kind' => 'chat', 'id' => "alheio-#{canal}", 'text' => "#{canal} da outra mesa" },
        )
      end
    end

    it 'NAO entrega o caderno do Mestre nem o combinado da equipe alheia' do
      get "/api/v1/player/schedules/#{outra.id}/session_feed_items",
          headers: bearer_headers_for(forasteiro), as: :json

      textos = Array(response.parsed_body['items']).map { |i| i['text'] }
      expect(textos).not_to include('dm da outra mesa')
      expect(textos).not_to include('players da outra mesa')
      expect(response.parsed_body['meta']['audiences']).to eq(['all'])
    end

    it 'DECISAO DE PRODUTO: o Geral e legivel por qualquer utilizador autenticado' do
      # Espelha `SessionFeedChannel#can_read?` e o hub (`SessionRealtimeChannel`),
      # ambos com spec propria. Documentado aqui para que uma futura restricao
      # seja uma escolha explicita, e nao um efeito colateral.
      get "/api/v1/player/schedules/#{outra.id}/session_feed_items",
          headers: bearer_headers_for(forasteiro), as: :json

      textos = Array(response.parsed_body['items']).map { |i| i['text'] }
      expect(textos).to include('all da outra mesa')
    end
  end
end
