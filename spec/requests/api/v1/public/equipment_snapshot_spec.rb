# frozen_string_literal: true

require 'rails_helper'

# O snapshot alimenta a busca do "+ Novo Item" da bolsa. É pedido SEM
# parâmetros: quem decide o que existe é o controller.
#
# ⚠️ Balde ausente NÃO dá erro — o item só não aparece, em silêncio. Foi assim
# que 425 matérias-primas e 48 obras de arte ficaram invisíveis: o front já as
# listava (`snapshotBucketKeys`), mas elas nunca chegavam.
RSpec.describe 'Api::V1::Public::Equipment snapshot do catálogo', type: :request do
  # Espelho de `snapshotBucketKeys()` no front
  # (`front-lafiga/src/app/data/compendiumTabRegistry.ts`). Se uma aba nova
  # entrar lá e não aqui, este teste avisa antes do jogador.
  BALDES_DO_FRONT = %w[
    simple-weapons martial-weapons light-armor medium-armor heavy-armor shields
    gear consumables potions instruments ammunition books tools packs
    materials treasure vehicles
  ].freeze

  it '⚠️ serve TODO balde que o front pede' do
    get '/api/v1/public/equipment_catalog_snapshot'
    expect(response).to have_http_status(:ok)

    servidos = response.parsed_body['by_category'].keys
    # O controller pula balde VAZIO, então só exigimos os que têm item.
    faltando = BALDES_DO_FRONT.reject do |b|
      servidos.include?(b) || Api::V1::Public::EquipmentController::CATEGORIES_DO_SNAPSHOT.include?(b)
    end
    expect(faltando).to be_empty, "baldes que o front pede e o snapshot não conhece: #{faltando}"
  end

  it 'matéria-prima e tesouro chegam ao snapshot (o bug de 27/08)' do
    Item.create!(api_index: 'snap-erva', name: 'Erva de Teste', kind: 'material',
                 category: 'herb', value_gp: 5)
    Item.create!(api_index: 'snap-jarro', name: 'Jarro de Teste', kind: 'treasure',
                 category: 'art', value_gp: 25)

    get '/api/v1/public/equipment_catalog_snapshot'
    body = response.parsed_body['by_category']

    expect(body['materials']&.map { |e| e['index'] }).to include('snap-erva')
    expect(body['treasure']&.map { |e| e['index'] }).to include('snap-jarro')
  end
end
