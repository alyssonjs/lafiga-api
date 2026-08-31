# frozen_string_literal: true

require 'rails_helper'

# FOCO ARCANO como FLAG do item (31/08) e o alargamento do slot livre do cinto.
#
# Antes disto, "ser foco" era inferido pelo NOME, e o nome não escala: nenhuma
# regex adivinha que a espada da campanha virou foco do bruxo. Agora o mestre
# marca `arcane_focus` no editor e qualquer item — arma, armadura, vestuário,
# instrumento, livro — passa a servir.
#
# ⚠️ A flag é CAPACIDADE, não casa: quem decide slot é o front, e lá o foco é a
# última pergunta. A armadura marcada continua vestida no torso.
RSpec.describe 'SheetItems — foco arcano e cinto alargado', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  def catalogo!(slug, nome, kind, props: {}, category: nil, sub_category: nil)
    Item.find_by(api_index: slug) || Item.create!(
      api_index: slug, name: nome, kind: kind, category: category,
      sub_category: sub_category, props: props
    )
  end

  def linha!(nome, index: nil, props: {})
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Itens Gerais',
                      quantity: 1, source: 'test', props_json: props)
  end

  def cinto!(slug, livres:)
    catalogo!(slug, "Cinto #{slug}", 'gear', category: 'belt', props: { 'belt_free_slots' => livres })
    linha!('Cinto de Couro', index: slug)
  end

  def prender(item, cinto)
    post "/api/v1/player/sheet_items/#{item.id}/stow_on_belt",
         params: { belt_id: cinto&.id }, headers: headers, as: :json
  end

  describe 'a flag do catálogo' do
    it 'marca a linha como foco quando o catálogo declara' do
      catalogo!('espada-do-pacto', 'Espada do Pacto', 'weapon', props: { 'arcane_focus' => true })
      linha = linha!('Espada do Pacto', index: 'espada-do-pacto')

      expect(linha.arcane_focus?).to be true
    end

    it 'NÃO marca sem a declaração — a ausência é a resposta "não é foco"' do
      catalogo!('espada-comum', 'Espada Comum', 'weapon')

      expect(linha!('Espada Comum', index: 'espada-comum').arcane_focus?).to be false
    end

    it 'a linha feita à mão pode declarar a sua, sem entrada no catálogo' do
      linha = linha!('Cristal do Mestre', props: { 'arcane_focus' => true })

      expect(linha.arcane_focus?).to be true
    end

    it 'viaja no JSON só quando é true — nada de `false` em toda linha' do
      catalogo!('orbe-marcado', 'Orbe', 'gear', props: { 'arcane_focus' => true })
      marcado = linha!('Orbe', index: 'orbe-marcado')
      comum = linha!('Pedra')

      expect(marcado.as_inventory_json[:arcane_focus]).to be true
      expect(comum.as_inventory_json[:arcane_focus]).to be_nil
    end

    it 'ARMADURA marcada continua armadura — a flag não muda a natureza' do
      catalogo!('peitoral-foco', 'Peitoral Rúnico', 'armor', props: { 'arcane_focus' => true })
      linha = linha!('Peitoral Rúnico', index: 'peitoral-foco')

      # O servidor guarda a capacidade; o slot é decidido no front, onde o foco
      # é a ÚLTIMA pergunta. Se um dia isto virar regra de servidor, é aqui.
      expect(linha.arcane_focus?).to be true
      expect(Item.find_by(api_index: 'peitoral-foco').kind).to eq('armor')
    end
  end

  describe 'slot livre do cinto — o que passou a caber' do
    it 'LIVRO entra no slot livre' do
      cinto = cinto!('cinto-livro', livres: 2)
      catalogo!('livro-de-magias', 'Livro de Magias', 'book')
      livro = linha!('Livro de Magias', index: 'livro-de-magias')

      prender(livro, cinto)

      expect(response).to have_http_status(:ok)
      expect(livro.reload.stored_on_belt_id).to eq(cinto.id)
    end

    it 'INSTRUMENTO entra, mesmo quando o catálogo o guarda como `gear`' do
      # 13 dos 14 instrumentos são `kind: tool` e já passavam por `ferramenta?`;
      # UM é `gear` e ficava de fora sem motivo nenhum.
      cinto = cinto!('cinto-inst', livres: 2)
      catalogo!('alaude-gear', 'Alaúde', 'gear', category: 'instrument')
      alaude = linha!('Alaúde', index: 'alaude-gear')

      prender(alaude, cinto)

      expect(response).to have_http_status(:ok)
      expect(alaude.reload.stored_on_belt_id).to eq(cinto.id)
    end

    it 'VESTUÁRIO mágico entra — a peça vive em `sub_category`' do
      # Medido: 3 peças mundanas contra ~70 mágicas. Ler só `category` deixava
      # quase todo o vestuário de fora.
      cinto = cinto!('cinto-vest', livres: 2)
      catalogo!('mascara-bufao', 'Máscara do Bufão', 'magic_item', sub_category: 'mask')
      mascara = linha!('Máscara do Bufão', index: 'mascara-bufao')

      prender(mascara, cinto)

      expect(response).to have_http_status(:ok)
      expect(mascara.reload.stored_on_belt_id).to eq(cinto.id)
    end

    it 'VESTUÁRIO mundano entra — a peça vive em `category`' do
      cinto = cinto!('cinto-vest2', livres: 2)
      catalogo!('amuleto-simples', 'Amuleto Simples', 'gear', category: 'amulet')
      amuleto = linha!('Amuleto Simples', index: 'amuleto-simples')

      prender(amuleto, cinto)

      expect(response).to have_http_status(:ok)
      expect(amuleto.reload.stored_on_belt_id).to eq(cinto.id)
    end
  end

  describe 'o que continua FORA — a lista não virou "tudo cabe"' do
    it 'GEAR genérico sem peça de vestuário é recusado' do
      # `gear` é o balde do catálogo (300 linhas, a maioria sem categoria).
      # Varrê-lo inteiro para o cinto transformava a vaga num 2º inventário.
      cinto = cinto!('cinto-x', livres: 2)
      catalogo!('corda-de-canhamo', 'Corda de Cânhamo', 'gear', category: 'equipment')
      corda = linha!('Corda de Cânhamo', index: 'corda-de-canhamo')

      prender(corda, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(corda.reload.stored_on_belt_id).to be_nil
    end

    it 'nome que só CITA livro não é livro — o leitor é ancorado' do
      # O falso positivo custa caro noutra ponta (no front rouba a casa do
      # manto); aqui abriria a vaga do cinto a qualquer bugiganga temática.
      cinto = cinto!('cinto-falso', livres: 2)
      catalogo!('broche-do-livro', 'Broche do Livro do Vazio', 'gear', category: 'equipment')
      broche = linha!('Broche do Livro do Vazio', index: 'broche-do-livro')

      prender(broche, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'CINTO não entra noutro cinto' do
      # Cinto veste-se na cintura. Deixá-lo entrar abria a pergunta do
      # cinto-dentro-do-cinto, que nenhum guard de ciclo responde hoje.
      cinto = cinto!('cinto-a', livres: 2)
      catalogo!('cinto-magico', 'Cinto da Força', 'magic_item', sub_category: 'belt')
      outro = linha!('Cinto da Força', index: 'cinto-magico')

      prender(outro, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'CONSUMÍVEL mantém a vaga própria, e não rouba a livre' do
      cinto = cinto!('cinto-c', livres: 1)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocao = linha!('Poção de Cura', index: 'pocao-cura')

      prender(pocao, cinto)

      # Cinto sem slot de consumível: a poção não cabe, mesmo com a vaga livre
      # aberta ao lado.
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
