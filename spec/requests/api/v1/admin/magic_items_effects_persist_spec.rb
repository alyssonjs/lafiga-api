# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::MagicItemsController effects JSON persistence', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm_user).merge('Content-Type' => 'application/json') }

  it 'persiste effects no POST (ex.: speed_bonus)' do
    slug = "spec-mi-effects-#{SecureRandom.hex(4)}"
    payload = {
      magic_item: {
        name: 'Spec Botas de Teste',
        slug: slug,
        rarity: 'uncommon',
        category: 'wondrous item',
        requires_attunement: false,
        effects: [{ kind: 'speed_bonus', value: 12 }],
      },
    }
    post '/api/v1/admin/magic_items', params: payload.to_json, headers: headers

    expect(response).to have_http_status(:created)
    body = response.parsed_body['magic_item']
    expect(body['effects']).to eq([{ 'kind' => 'speed_bonus', 'value' => 12 }])
    expect(body['category']).to eq('gear')
    expect(body['is_wondrous']).to be true

    mi = MagicItem.find_by(slug: slug)
    expect(mi).to be_present
    expect(mi.effects).to eq([{ 'kind' => 'speed_bonus', 'value' => 12 }])
  end

  it 'persiste effects com arrays aninhados no PUT (ex.: resistance)' do
    slug = "spec-mi-res-#{SecureRandom.hex(4)}"
    mi = MagicItem.create!(
      name: 'Spec Anel',
      slug: slug,
      rarity: 'rare',
      category: 'ring',
      requires_attunement: false,
      effects: [],
    )

    payload = {
      magic_item: {
        effects: [
          { kind: 'resistance', damage_types: %w[fogo frio] },
        ],
      },
    }
    put "/api/v1/admin/magic_items/#{mi.slug}", params: payload.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    mi.reload
    expect(mi.effects.size).to eq(1)
    expect(mi.effects.first['kind']).to eq('resistance')
    expect(mi.effects.first['damage_types']).to match_array(%w[fogo frio])
  end

  it 'persiste passive_feature (nome + desc) no PUT' do
    slug = "spec-mi-pf-#{SecureRandom.hex(4)}"
    mi = MagicItem.create!(
      name: 'Spec Item PF',
      slug: slug,
      rarity: 'common',
      category: 'wondrous item',
      requires_attunement: false,
      effects: [],
    )

    payload = {
      magic_item: {
        effects: [
          {
            kind: 'passive_feature',
            name: 'Aura de Teste',
            desc: 'Texto longo do efeito.',
          },
        ],
      },
    }
    put "/api/v1/admin/magic_items/#{mi.slug}", params: payload.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    mi.reload
    expect(mi.effects).to eq(
      [
        {
          'kind' => 'passive_feature',
          'name' => 'Aura de Teste',
          'desc' => 'Texto longo do efeito.',
        },
      ],
    )
  end

  # O proprio controller avisa: chave fora do MAGIC_ITEM_EFFECTS_PERMIT some em
  # SILENCIO (strong params descarta, nao levanta). Sem estes exemplos, o DM
  # preencheria custo em cargas / magia do item e o jsonb chegaria vazio.
  it 'persiste `charge_cost` (custo em cargas do efeito)' do
    slug = "spec-mi-charge-#{SecureRandom.hex(4)}"
    payload = {
      magic_item: {
        name: 'Spec Varinha', slug: slug, rarity: 'rare', category: 'wand',
        charges: 7, recharge: 'long',
        effects: [{ kind: 'damage_bonus_dice', dice: '3d6', damage_type: 'fogo', charge_cost: 2 }],
      },
    }
    post '/api/v1/admin/magic_items', params: payload.to_json, headers: headers

    expect(response).to have_http_status(:created)
    mi = MagicItem.find_by(slug: slug)
    expect(mi.effects.first['charge_cost']).to eq(2)
    expect(mi.recharge).to eq('long')
  end

  it 'persiste `item_spell` completo (magia + nivel + CD + custo)' do
    slug = "spec-mi-itemspell-#{SecureRandom.hex(4)}"
    payload = {
      magic_item: {
        name: 'Spec Varinha de Misseis', slug: slug, rarity: 'uncommon', category: 'wand',
        charges: 7, recharge: 'long',
        effects: [{
          kind: 'item_spell',
          spell_name: 'Mísseis Mágicos',
          spell_api_index: 'magic-missile',
          spell_level: 1,
          save_dc: 15,
          charge_cost: 1,
        }],
      },
    }
    post '/api/v1/admin/magic_items', params: payload.to_json, headers: headers

    expect(response).to have_http_status(:created)
    eff = MagicItem.find_by(slug: slug).effects.first
    expect(eff).to eq(
      'kind' => 'item_spell',
      'spell_name' => 'Mísseis Mágicos',
      'spell_api_index' => 'magic-missile',
      'spell_level' => 1,
      'save_dc' => 15,
      'charge_cost' => 1,
    )
  end

  it 'efeito passivo nao ganha charge_cost fantasma' do
    slug = "spec-mi-passive-#{SecureRandom.hex(4)}"
    payload = {
      magic_item: {
        name: 'Spec Manto', slug: slug, rarity: 'rare', category: 'wondrous item',
        effects: [{ kind: 'ac_bonus', value: 1, type: 'magico' }],
      },
    }
    post '/api/v1/admin/magic_items', params: payload.to_json, headers: headers

    expect(response).to have_http_status(:created)
    expect(MagicItem.find_by(slug: slug).effects.first).not_to have_key('charge_cost')
  end

end
