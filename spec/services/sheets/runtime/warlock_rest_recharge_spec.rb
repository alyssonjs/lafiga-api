# frozen_string_literal: true

require 'rails_helper'

# Bruxo — Fase 1 do `bruxo-plano.md` (v2): as recargas de descanso nas DUAS
# superfícies.
#
# O deferral registrado era "RSpec do Descanso do Mestre cobrindo o Bruxo". A
# medição da fase −1 mostrou que as duas superfícies JÁ convergem no mesmo
# service (o Descanso do Mestre chama os mesmos endpoints de ficha), então o
# que faltava não era código de recarga — era a PROVA de que os recursos do
# Bruxo passam por ela, incluindo a assimetria que ninguém testava.
#
# ⚠️ A ASSIMETRIA É O PONTO: dos 11 gates persistidos pelo registry do Bruxo,
# dez recarregam em descanso CURTO e `pseudo_titan` recarrega só no LONGO.
# Uma recarga que zerasse tudo em SR devolveria de graça um recurso de
# descanso longo — e isso não aparece em tela nenhuma, só num Bruxo forte
# demais na mesa.
#
# O espaço de PACTO é o outro caso especial: volta no curto, enquanto os
# demais níveis de espaço continuam gastos até o longo.
RSpec.describe 'Bruxo — recargas de descanso', type: :request do
  # Os 11 gates que `warlockHotbarActions.ts` persiste em
  # `class_resources_used`. Mantido explícito: se o registry ganhar um gate
  # novo sem entrada no catálogo, o teste de paridade acusa; se ganhar com a
  # recarga errada, ESTE acusa.
  GATES_CURTO = %w[
    fey_presence dark_delirium vengeance_mark spirit_avatar heroic_safeguard
    titanic_incentive prodigious_form mantle_of_oblivion obliteration_sphere
    death_touch
  ].freeze
  GATES_LONGO = %w[pseudo_titan].freeze
  TODOS_GATES = (GATES_CURTO + GATES_LONGO).freeze

  let(:dono) { create(:user) }
  let(:character) { create(:character, user: dono) }
  let(:sheet) { character.sheet || create(:sheet, character: character) }

  def gastar_tudo!
    runtime = sheet.runtime!
    runtime.update!(
      class_resources_used: TODOS_GATES.index_with { 1 },
      spell_slots_used: { 'pact' => 2, '1' => 1, '3' => 2 },
    )
  end

  def recursos
    sheet.runtime!.reload.class_resources_used
  end

  def espacos
    sheet.runtime!.reload.spell_slots_used
  end

  describe 'catálogo — os gates do Bruxo existem e com a recarga certa' do
    it 'toda chave persistida pelo registry está no catálogo canônico' do
      # Chave fora do catálogo NUNCA recarrega: fica gasta para sempre e o
      # jogador perde o recurso em silêncio.
      ausentes = TODOS_GATES.reject { |k| Sheets::Runtime::ResourceCatalog.all.key?(k) }
      expect(ausentes).to be_empty, "fora do catálogo: #{ausentes.join(', ')}"
    end

    it 'dez recarregam em CURTO e o Pseudo-Titã só no LONGO' do
      GATES_CURTO.each do |k|
        expect(Sheets::Runtime::ResourceCatalog.recharge_for(k)).to eq('short'), "#{k} deveria ser short"
      end
      GATES_LONGO.each do |k|
        expect(Sheets::Runtime::ResourceCatalog.recharge_for(k)).to eq('long'), "#{k} deveria ser long"
      end
    end
  end

  describe 'descanso CURTO' do
    before { gastar_tudo! }

    it 'devolve os dez gates de curto' do
      Sheets::Runtime::ApplyShortRestService.call(sheet)
      GATES_CURTO.each { |k| expect(recursos).not_to have_key(k), "#{k} deveria ter voltado" }
    end

    it 'NÃO devolve o Pseudo-Titã (é de descanso longo)' do
      Sheets::Runtime::ApplyShortRestService.call(sheet)
      expect(recursos['pseudo_titan']).to eq(1)
    end

    it 'devolve o espaço de PACTO e mantém os demais níveis gastos' do
      Sheets::Runtime::ApplyShortRestService.call(sheet)
      expect(espacos).not_to have_key('pact')
      expect(espacos['1']).to eq(1)
      expect(espacos['3']).to eq(2)
    end
  end

  describe 'descanso LONGO' do
    before { gastar_tudo! }

    it 'devolve TODOS os gates, inclusive o de longo' do
      Sheets::Runtime::ApplyLongRestService.call(sheet)
      TODOS_GATES.each { |k| expect(recursos).not_to have_key(k), "#{k} deveria ter voltado" }
    end

    it 'devolve o espaço de pacto junto com os demais' do
      Sheets::Runtime::ApplyLongRestService.call(sheet)
      expect(espacos).to be_blank
    end
  end

  # ─── A SEGUNDA SUPERFÍCIE (o deferral) ────────────────────────────────
  #
  # O Descanso do Mestre (`handlePartyShortRest`/`handlePartyLongRest` no
  # front) não tem endpoint próprio: chama os MESMOS endpoints de ficha, com
  # a autorização de DM (`sheets_scope_for_current_user`). O que este bloco
  # prova é que essa rota — Mestre descansando a ficha de OUTRO jogador —
  # recarrega os recursos do Bruxo de verdade.
  describe 'Descanso do MESTRE (ficha de outro jogador)' do
    let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
    let(:mestre) { create(:user, role: dm_role) }
    let(:dm_headers) { bearer_headers_for(mestre) }

    before { gastar_tudo! }

    it 'descanso CURTO pelo Mestre devolve os gates de curto e o pacto' do
      post "/api/v1/player/sheets/#{sheet.id}/runtime/short_rest", headers: dm_headers
      expect(response).to have_http_status(:ok)
      GATES_CURTO.each { |k| expect(recursos).not_to have_key(k), "#{k} não voltou" }
      expect(espacos).not_to have_key('pact')
      # A assimetria vale nas duas superfícies — não só no service direto.
      expect(recursos['pseudo_titan']).to eq(1)
    end

    it 'descanso LONGO pelo Mestre devolve tudo' do
      post "/api/v1/player/sheets/#{sheet.id}/runtime/long_rest", headers: dm_headers
      expect(response).to have_http_status(:ok)
      TODOS_GATES.each { |k| expect(recursos).not_to have_key(k), "#{k} não voltou" }
    end

    it 'jogador ALHEIO (nem dono, nem Mestre) não descansa a ficha de outro' do
      # A recarga é poderosa: sem esta porta, qualquer um devolveria recursos
      # de qualquer ficha.
      intruso = create(:user)
      post "/api/v1/player/sheets/#{sheet.id}/runtime/short_rest", headers: bearer_headers_for(intruso)
      expect(response).not_to have_http_status(:ok)
      expect(recursos.keys).to include(*GATES_CURTO)
    end
  end
end
