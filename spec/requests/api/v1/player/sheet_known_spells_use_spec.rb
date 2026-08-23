# frozen_string_literal: true

require 'rails_helper'

# Magia inata (racial/talento) tem orcamento proprio. Sem este endpoint a sessao
# debitava um ESPACO DE MAGIA real do Tiefling — e o Tiefling nao-conjurador
# (Guerreiro/Barbaro, que existem na base) nem conseguia conjurar.
RSpec.describe 'Api::V1::Player::SheetKnownSpellsController use', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Tiefling Request Spec') }
  let!(:sheet) { create(:sheet, character: character, current_level: 5) }
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 5) }

  def known!(per_rest:, remaining: 1, source: 'race')
    sufixo = SecureRandom.hex(3)
    spell = Spell.create!(name: "Repreensão #{sufixo}", api_index: "spec-use-#{sufixo}", level: 1, desc: 'x')
    SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: spell, gained_at_class_level: 3,
                            source: source, uses_per_rest: per_rest, uses_remaining: remaining)
  end

  it 'gasta um uso proprio, sem tocar em espaco de magia' do
    ks = known!(per_rest: 'LR')

    post "/api/v1/player/sheet_known_spells/#{ks.id}/use", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(ks.reload.uses_remaining).to eq(0)
    expect(sheet.runtime!.spell_slots_used).to eq({})
  end

  it 'REGRESSAO: sem usos restantes recusa, e nao fica negativo' do
    ks = known!(per_rest: 'LR', remaining: 0)

    post "/api/v1/player/sheet_known_spells/#{ks.id}/use", headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/sem usos restantes/i)
    expect(ks.reload.uses_remaining).to eq(0)
  end

  it 'magia de classe (sem usos proprios) e recusada — ela gasta espaco' do
    ks = known!(per_rest: nil, source: 'class')

    post "/api/v1/player/sheet_known_spells/#{ks.id}/use", headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/espaço de magia/i)
  end

  it 'restore devolve o uso' do
    ks = known!(per_rest: 'LR', remaining: 0)

    post "/api/v1/player/sheet_known_spells/#{ks.id}/restore", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(ks.reload.uses_remaining).to eq(1)
  end

  it 'nao gasta o uso inato de OUTRO jogador' do
    outro = create(:character, user: create(:user), name: 'Alheio')
    outra = create(:sheet, character: outro, current_level: 5)
    sk = create(:sheet_klass, sheet: outra, level: 5)
    sufixo = SecureRandom.hex(3)
    spell = Spell.create!(name: "Alheia #{sufixo}", api_index: "spec-alheia-#{sufixo}", level: 1, desc: 'x')
    alheia = SheetKnownSpell.create!(sheet_klass: sk, spell: spell, gained_at_class_level: 3,
                                     source: 'race', uses_per_rest: 'LR', uses_remaining: 1)

    post "/api/v1/player/sheet_known_spells/#{alheia.id}/use", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(alheia.reload.uses_remaining).to eq(1)
  end
end
