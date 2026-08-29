# frozen_string_literal: true

require 'rails_helper'

# Vinculo da ARMA DE PACTO (Pacto da Lamina, Bruxo) — Fase 4 do `bruxo-plano`.
#
# ⚠️ O BLOQUEIO que isto destrava: o modelo sabia QUAL pacto foi escolhido
# (`pactBoon`) mas nao QUAL arma e a de pacto. Sem esse vinculo, marcar toda
# arma corpo a corpo de um Bruxo da Lamina como magica seria ERRADO (so a arma
# de pacto conta, e ela fura resistencia a dano nao-magico).
#
# ⚠️ POR QUE NO SERVIDOR. A regra tem um invariante que so o servidor garante:
# **exatamente uma** arma de pacto por ficha ("a arma deixa de ser a arma de
# pacto se voce realizar o ritual em outra"). Com a exclusividade no cliente,
# dois dispositivos vinculariam duas armas e as DUAS contariam como magicas.
RSpec.describe 'Api::V1::Player::SheetItemsController arma de pacto', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Pact Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def arma!(nome, api_index)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: api_index,
                      category: 'Armas', quantity: 1, source: 'test')
  end

  def vincular(item)
    post "/api/v1/player/sheet_items/#{item.id}/bind_pact_weapon", headers: headers, as: :json
  end

  def desvincular(item)
    post "/api/v1/player/sheet_items/#{item.id}/unbind_pact_weapon", headers: headers, as: :json
  end

  def marcada?(item)
    (item.reload.props_json || {})['pact_weapon'] == true
  end

  describe 'vincular' do
    it 'marca a arma e PERSISTE em props_json' do
      espada = arma!('Espada Longa', 'longsword')

      vincular(espada)

      expect(response).to have_http_status(:ok)
      expect(marcada?(espada)).to be true
      expect(response.parsed_body['sheet_items'].first.dig('props', 'pact_weapon')).to be true
    end

    it 'vincular OUTRA arma desvincula a anterior (exclusividade)' do
      # O coracao da regra: o ritual numa arma nova encerra o vinculo da antiga.
      espada = arma!('Espada Longa', 'longsword')
      machado = arma!('Machado de Batalha', 'battleaxe')
      vincular(espada)

      vincular(machado)

      expect(response).to have_http_status(:ok)
      expect(marcada?(machado)).to be true
      expect(marcada?(espada)).to be(false), 'duas armas de pacto ao mesmo tempo — as DUAS contariam como magicas'
    end

    it 'a resposta devolve TODAS as alteradas (a nova e a que perdeu o vinculo)' do
      # Devolver so a nova deixaria o cliente com a antiga ainda marcada em tela.
      espada = arma!('Espada Longa', 'longsword')
      machado = arma!('Machado de Batalha', 'battleaxe')
      vincular(espada)

      vincular(machado)

      ids = response.parsed_body['sheet_items'].map { |si| si['id'] }
      expect(ids).to contain_exactly(espada.id, machado.id)
    end

    it 'e IDEMPOTENTE (dois cliques nao quebram nada)' do
      espada = arma!('Espada Longa', 'longsword')
      vincular(espada)

      vincular(espada)

      expect(response).to have_http_status(:ok)
      expect(marcada?(espada)).to be true
    end

    it 'recusa arma A DISTANCIA (a arma de pacto e corpo a corpo)' do
      arco = arma!('Arco Longo', 'longbow')

      vincular(arco)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(marcada?(arco)).to be false
    end

    it 'nao vincula item de OUTRO usuario' do
      outro = create(:user)
      outro_char = create(:character, user: outro)
      outra_sheet = create(:sheet, character: outro_char, race: race, sub_race: sub_race)
      alheia = SheetItem.create!(sheet: outra_sheet, item_name: 'Espada Longa',
                                 item_index: 'longsword', category: 'Armas', quantity: 1)

      vincular(alheia)

      expect(response.status).to be >= 400
      expect(marcada?(alheia)).to be false
    end
  end

  describe 'desvincular' do
    it 'sempre permitido (dispensar a arma nao exige acao)' do
      espada = arma!('Espada Longa', 'longsword')
      vincular(espada)

      desvincular(espada)

      expect(response).to have_http_status(:ok)
      expect(marcada?(espada)).to be false
    end
  end

  describe 'empilhamento' do
    it 'a marca impede que duas armas identicas virem uma pilha' do
      # Sem `pact_weapon` em PER_INSTANCE_PROP_KEYS, duas espadas longas
      # iguais empilhariam e o resultado seria "2 espadas, uma de pacto" —
      # sem dizer qual.
      expect(SheetItem::PER_INSTANCE_PROP_KEYS).to include('pact_weapon')
    end
  end
end
