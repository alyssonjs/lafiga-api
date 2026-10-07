# frozen_string_literal: true

require 'rails_helper'

# O TEXTO da wiki no banco + o papel EDITOR (07/10/2026).
#
# Duas coisas se provam aqui, e a segunda é a que importa:
#   1. O ciclo do lápis — ler sem token, criar, reescrever e apagar.
#   2. O CERCO do Editor. Ele escreve texto e NADA mais: o mesmo token que
#      reescreve um deus leva 403 em combate, usuários e catálogo. Era o risco
#      real do pedido — pôr o papel novo dentro de `Group.user_is_dm?` seria uma
#      linha só e entregaria a mesa inteira a quem foi convidado para corrigir
#      um texto.
RSpec.describe 'Wiki Articles API', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM')     || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:editor_role) { Role.find_by(name: 'Editor') || create(:role, name: 'Editor') }

  let(:dm)     { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }
  let(:editor) { create(:user, role: editor_role) }

  let!(:solarius) do
    WikiArticle.create!(section: 'gods', slug: 'god-01', position: 0,
                        data: { 'name' => 'Solarius', 'title' => 'O Senhor da Aurora' })
  end
  let!(:lunara) do
    WikiArticle.create!(section: 'gods', slug: 'god-02', position: 1,
                        data: { 'name' => 'Lunara', 'title' => 'A Tecelã da Noite' })
  end
  let!(:material) do
    WikiArticle.create!(section: 'planes', slug: 'plane-01', position: 0,
                        data: { 'name' => 'Plano Material' })
  end

  describe 'GET /api/v1/public/wiki_articles' do
    it 'o visitante DESLOGADO lê o lore — era o que via quando vinha do código' do
      get '/api/v1/public/wiki_articles'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['wiki_articles'].size).to eq(3)
    end

    it 'filtra por seção e devolve em ordem' do
      get '/api/v1/public/wiki_articles', params: { section: 'gods' }

      corpo = response.parsed_body['wiki_articles']
      expect(corpo.map { |a| a['id'] }).to eq(%w[god-01 god-02])
      expect(corpo.first['data']['name']).to eq('Solarius')
    end

    it '⚠️ `id` do payload é o SLUG, não a chave do banco — o front navega por ele' do
      get '/api/v1/public/wiki_articles', params: { section: 'planes' }

      artigo = response.parsed_body['wiki_articles'].first
      expect(artigo['id']).to eq('plane-01')
      # O `data.id` também, senão a página perdia a referência ao abrir o card.
      expect(artigo['data']['id']).to eq('plane-01')
    end
  end

  describe 'PATCH /api/v1/admin/wiki_articles/:id — o lápis' do
    let(:reescrita) do
      { section: 'gods', wiki_article: { data: { 'name' => 'Solarius', 'lore' => 'Texto novo da mesa.' } } }
    end

    it 'o EDITOR reescreve — é a feature' do
      patch '/api/v1/admin/wiki_articles/god-01', params: reescrita, as: :json,
            headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:ok)
      expect(solarius.reload.data['lore']).to eq('Texto novo da mesa.')
    end

    it 'o Mestre também reescreve — quem manda na mesa escreve' do
      patch '/api/v1/admin/wiki_articles/god-01', params: reescrita, as: :json,
            headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
    end

    it 'jogador comum recebe 403 e o texto fica intacto' do
      patch '/api/v1/admin/wiki_articles/god-01', params: reescrita, as: :json,
            headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
      expect(solarius.reload.data['lore']).to be_nil
    end

    it 'sem token responde 401' do
      patch '/api/v1/admin/wiki_articles/god-01', params: reescrita, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'o slug é IMUTÁVEL — renomear quebraria link guardado por um jogador' do
      patch '/api/v1/admin/wiki_articles/god-01',
            params: { section: 'gods', wiki_article: { slug: 'outro', data: { 'name' => 'X' } } },
            as: :json, headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:ok)
      expect(solarius.reload.slug).to eq('god-01')
    end

    it 'artigo de outra seção não é alcançável pelo slug sozinho' do
      patch '/api/v1/admin/wiki_articles/plane-01', params: reescrita, as: :json,
            headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/admin/wiki_articles' do
    it 'o Editor cria artigo novo, ao fim da seção' do
      post '/api/v1/admin/wiki_articles',
           params: { wiki_article: { section: 'gods', slug: 'god-99', data: { 'name' => 'Novo' } } },
           as: :json, headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['wiki_article']['position']).to eq(2)
    end

    it 'sem slug, deriva do nome que o redator escreveu' do
      post '/api/v1/admin/wiki_articles',
           params: { wiki_article: { section: 'gods', data: { 'name' => 'Deus Sem Slug' } } },
           as: :json, headers: bearer_headers_for(editor)

      expect(response.parsed_body['wiki_article']['id']).to eq('deus-sem-slug')
    end

    it 'recusa slug repetido na MESMA seção, aceita na outra' do
      post '/api/v1/admin/wiki_articles',
           params: { wiki_article: { section: 'gods', slug: 'god-01', data: { 'name' => 'X' } } },
           as: :json, headers: bearer_headers_for(editor)
      expect(response).to have_http_status(:unprocessable_entity)

      post '/api/v1/admin/wiki_articles',
           params: { wiki_article: { section: 'planes', slug: 'god-01', data: { 'name' => 'X' } } },
           as: :json, headers: bearer_headers_for(editor)
      expect(response).to have_http_status(:created)
    end

    it 'jogador comum recebe 403' do
      post '/api/v1/admin/wiki_articles',
           params: { wiki_article: { section: 'gods', slug: 'god-98', data: { 'name' => 'X' } } },
           as: :json, headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v1/admin/wiki_articles/:id' do
    it 'o Editor apaga — decisão da mesa em 07/10' do
      delete '/api/v1/admin/wiki_articles/god-02', params: { section: 'gods' },
             headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:no_content)
      expect(WikiArticle.in_section('gods').pluck(:slug)).to eq(['god-01'])
    end

    it 'jogador comum recebe 403 e o artigo continua lá' do
      delete '/api/v1/admin/wiki_articles/god-02', params: { section: 'gods' },
             headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
      expect(WikiArticle.exists?(lunara.id)).to be(true)
    end
  end

  # ⚠️ O CERCO. Esta é a razão de o portão do Editor ser separado: o mesmo
  # token que acabou de reescrever um deus não pode abrir mais nada.
  describe 'o Editor NÃO é Mestre' do
    it 'fica de fora de `Group.user_is_dm?` — o portão dos outros 38 controllers' do
      expect(Group.user_is_dm?(editor)).to be(false)
      expect(Group.user_is_dm?(dm)).to be(true)
    end

    it 'passa no portão do conteúdo e só nele' do
      expect(editor.may_edit_content?).to be(true)
      expect(player.may_edit_content?).to be(false)
    end

    it 'leva 403 no CATÁLOGO, que é poder de Mestre' do
      post '/api/v1/admin/magic_items', params: { magic_item: { name: 'Lâmina do Editor' } },
           as: :json, headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
    end

    it 'leva 403 nas SEÇÕES da wiki — a estrutura do site segue do Mestre' do
      post '/api/v1/admin/wiki_sections',
           params: { wiki_section: { slug: 'secao-do-editor', label: 'X', icon_name: 'Globe' } },
           as: :json, headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
