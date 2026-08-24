# frozen_string_literal: true

require 'rails_helper'

# Cada tipo de munição tem o seu recipiente.
#
# PHB cap. 5: "sacar a munição de uma aljava, BOLSA, ou outro recipiente faz
# parte do ataque". A Aljava guarda até 20 flechas; o Porta Virotes, até 20
# virotes. O recipiente declara o que ACEITA e QUANTO cabe.
#
# A validação é do SERVIDOR: bloquear só no cliente não bloqueia nada.
RSpec.describe 'Recipientes de munição', type: :model do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, name: 'Recipiente Spec') }
  let!(:sheet) { create(:sheet, character: character) }

  # Catálogo: é dele que vêm tipo e capacidade.
  let!(:cat_aljava) do
    Item.create!(api_index: 'aljava-spec', name: 'Aljava', kind: 'gear',
                 props: { 'equipment_slot' => 'quiver',
                          'ammunition_types' => ['flecha'],
                          'ammunition_capacity' => 20 })
  end
  let!(:cat_bolsa) do
    Item.create!(api_index: 'bolsa-spec', name: 'Bolsa de Munição', kind: 'gear',
                 props: { 'equipment_slot' => 'quiver',
                          'ammunition_types' => %w[pedra-de-funda agulha-de-zarabatana],
                          'ammunition_capacity' => 20 })
  end

  def recipiente(cat)
    SheetItem.create!(sheet: sheet, item: cat, item_name: cat.name,
                      item_index: cat.api_index, category: 'gear', quantity: 1, source: 'test')
  end

  # As munições existem no catálogo como `kind: ammunition` — é de lá que
  # `ammunition?` reconhece pedra de funda e agulha, que a regex por nome não
  # conhecia.
  before do
    [['Flecha', 'flecha'], ['Virote de Besta', 'virote'],
     ['Pedra de Funda', 'pedra-de-funda'],
     ['Agulha de Zarabatana', 'agulha-de-zarabatana']].each do |nome, idx|
      Item.find_or_create_by!(api_index: idx) { |i| i.name = nome; i.kind = 'ammunition' }
    end
  end

  def municao(nome, idx, qtd)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: idx,
                      category: 'Armas', quantity: qtd, source: 'test')
  end

  def guardar(mun, rec, qtd)
    SheetItems::AllocateAmmunitionService.new(ammunition: mun, quiver_id: rec.id, quantity: qtd).call
  end

  describe 'o que o recipiente é' do
    it 'item com `equipment_slot: quiver` no catálogo é recipiente' do
      expect(recipiente(cat_aljava).quiver?).to be(true)
    end

    it 'REGRESSAO: aljava SEM par no catálogo continua sendo recipiente, sem restrição' do
      # Reconhecida pelo NOME. Um item avulso do mestre não pode deixar de
      # guardar munição só porque não tem entrada no catálogo.
      avulsa = SheetItem.create!(sheet: sheet, item_name: 'Aljava surrada do avô',
                                 item_index: 'aljava-surrada-do-avo',
                                 category: 'gear', quantity: 1, source: 'test')

      expect(avulsa.quiver?).to be(true)
      expect(avulsa.accepted_ammunition_indexes).to eq([])
      expect(avulsa.ammunition_capacity).to be_nil
    end

    it 'a aljava de uma ficha ANTIGA herda tipo e capacidade do catálogo' do
      # `SheetItem` liga ao catálogo pelo nome, então a aljava que já estava na
      # bolsa passa a respeitar o limite — sem migração nenhuma.
      antiga = SheetItem.create!(sheet: sheet, item_name: 'Aljava', item_index: 'aljava-velha',
                                 category: 'gear', quantity: 1, source: 'test')

      expect(antiga.item&.api_index).to eq('aljava-spec')
      expect(antiga.ammunition_capacity).to eq(20)
    end
  end

  describe 'tipo aceito' do
    it 'guarda a munição que o recipiente aceita' do
      aljava = recipiente(cat_aljava)
      flechas = municao('Flecha', 'flecha', 10)

      guardar(flechas, aljava, 10)

      expect(flechas.reload.ammunition_container_id).to eq(aljava.id.to_s)
    end

    it 'REGRESSAO: recusa a munição que o recipiente NAO aceita' do
      aljava = recipiente(cat_aljava)
      virotes = municao('Virote de Besta', 'virote', 5)

      expect { guardar(virotes, aljava, 5) }
        .to raise_error(SheetItems::AllocateAmmunitionService::InvalidAllocation, /não guarda/)
      expect(virotes.reload.ammunition_container_id).to be_nil
    end

    it 'a bolsa aceita os DOIS tipos que dividem o mesmo recipiente no PHB' do
      bolsa = recipiente(cat_bolsa)

      guardar(municao('Pedra de Funda', 'pedra-de-funda', 5), bolsa, 5)
      guardar(municao('Agulha de Zarabatana', 'agulha-de-zarabatana', 5), bolsa, 5)

      expect(bolsa.ammunition_stored_count).to eq(10)
    end

    it 'REGRESSAO: lista vazia aceita qualquer munição — é a aljava legada' do
      solto = Item.create!(api_index: 'saco-spec', name: 'Saco', kind: 'gear',
                           props: { 'equipment_slot' => 'quiver' })
      saco = recipiente(solto)

      expect { guardar(municao('Virote de Besta', 'virote', 3), saco, 3) }.not_to raise_error
    end
  end

  describe 'capacidade' do
    it 'REGRESSAO: bloqueia acima do limite e diz quanto ainda cabe' do
      aljava = recipiente(cat_aljava)
      guardar(municao('Flecha', 'flecha', 18), aljava, 18)

      expect { guardar(municao('Flecha', 'flecha', 5), aljava, 5) }
        .to raise_error(SheetItems::AllocateAmmunitionService::InvalidAllocation, /Cabem mais 2/)
    end

    it 'aceita exatamente até o limite' do
      aljava = recipiente(cat_aljava)

      expect { guardar(municao('Flecha', 'flecha', 20), aljava, 20) }.not_to raise_error
      expect(aljava.ammunition_stored_count).to eq(20)
    end

    it 'REGRESSAO: mover DENTRO do mesmo recipiente nao conta duas vezes' do
      # Sem descontar a própria pilha, remanejar 20 flechas numa aljava cheia
      # daria "cabem mais 0" — o jogador ficaria preso.
      aljava = recipiente(cat_aljava)
      flechas = municao('Flecha', 'flecha', 20)
      guardar(flechas, aljava, 20)

      expect { guardar(flechas.reload, aljava, 20) }.not_to raise_error
    end

    it 'sem capacidade declarada nao ha limite' do
      solto = Item.create!(api_index: 'sem-limite-spec', name: 'Saco fundo', kind: 'gear',
                           props: { 'equipment_slot' => 'quiver' })
      saco = recipiente(solto)

      expect { guardar(municao('Flecha', 'flecha', 999), saco, 999) }.not_to raise_error
    end
  end
end
