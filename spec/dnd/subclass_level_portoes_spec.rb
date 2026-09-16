# frozen_string_literal: true

require 'rails_helper'

# FASE 4 — o nível da sub-classe deixa de viver em quatro sítios.
#
# ⚠️ `klasses.subclass_level` estava VAZIA nas 13 classes, e todos os guardas do
# servidor fazem `k.try(:subclass_level).to_i`: com NULL isso dá 0 e passa
# sempre. Eram SETE guardas inertes — a validação do model, o `LevelUpGuardService`,
# o provisionamento, o gerador aleatório e duas rakes de auditoria. Quem segurava
# a regra era o FRONT, com mapa próprio, que não conhece classe criada pelo editor.
#
# Medido antes de acordar (16/09/2026): 63 fichas com sub-classe, ZERO ilegais
# pela regra, ZERO fichas já no nível de escolher sem sub-classe.
RSpec.describe 'Portões de nível da sub-classe', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:corpo) { JSON.parse(response.body) }

  # `fighter` de propósito: a regra em código diz `choose_level: 3`, então a
  # projeção tem de valer mesmo sem ninguém mandar a coluna no pedido.
  #
  # ⚠️ `find_by ||` e não `create!`: o catálogo de teste costuma estar vazio, mas
  # specs vizinhos que criam classes fora da transação deixam linhas para trás —
  # e aí o `create!` estoura por unicidade, que é uma falha do SPEC a fingir-se
  # de falha do código.
  let(:klass) do
    Klass.find_by(api_index: 'fighter') ||
      Klass.create!(name: 'Guerreiro SO', api_index: 'fighter', hit_die: 10)
  end

  describe 'a coluna é PROJEÇÃO da regra' do
    it 'ao gravar a classe, a coluna passa a valer o `choose_level` da regra' do
      klass.update_columns(subclass_level: nil)

      patch "/api/v1/admin/klasses/#{klass.id}",
            params: { klass: { short_description: 'só o texto' } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(klass.reload.subclass_level).to eq(3)
    end

    it 'e acompanha a regra quando o mestre muda o nível de escolha' do
      patch "/api/v1/admin/klasses/#{klass.id}",
            params: { klass: { rules: { subclass: { choose_level: 5, options: {} } } } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(klass.reload.subclass_level).to eq(5)
    end

    # ⚠️ A coluna guardava "Força" e a regra "FOR" — o mesmo fato em duas
    # grafias, sem tradutor entre elas (13 achados na auditoria da fase 0).
    it 'alinha também a grafia de `saving_throws` à da regra' do
      klass.update_columns(saving_throws: %w[Força Constituição])

      patch "/api/v1/admin/klasses/#{klass.id}",
            params: { klass: { short_description: 'x' } }.to_json, headers: headers

      expect(klass.reload.saving_throws).to eq(ClassRules.find('fighter')[:saving_throws])
    end
  end

  describe 'os guardas acordados' do
    let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }
    let(:sub) do
      SubKlass.create!(name: 'Campeão SO', api_index: "campeao-so-#{SecureRandom.hex(3)}", klass: klass)
    end

    before { klass.update_columns(subclass_level: 3) }

    it 'recusa sub-classe antes do nível dela' do
      sk = SheetKlass.new(sheet: sheet, klass: klass, sub_klass: sub, level: 1)

      expect(sk).not_to be_valid
      expect(sk.errors[:sub_klass].join).to include('a partir do nível 3')
    end

    it 'aceita no nível certo' do
      sk = SheetKlass.new(sheet: sheet, klass: klass, sub_klass: sub, level: 3)

      expect(sk).to be_valid, -> { sk.errors.full_messages.inspect }
    end

    # ⚠️ Com a coluna vazia o guarda dormia e a sub-classe entrava no nível 1
    # para TODA classe. Acordado, ele passa a recusar — e é por isso que a
    # medida de fichas ilegais tinha de ser zero antes de preencher a coluna.
    it 'a coluna vazia é o que fazia o guarda passar sempre' do
      klass.update_columns(subclass_level: nil)
      sk = SheetKlass.new(sheet: sheet, klass: klass, sub_klass: sub, level: 1)

      expect(sk).to be_valid
    end
  end
end
