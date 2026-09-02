# frozen_string_literal: true

require 'rails_helper'

# O ItemResolver é a FÁBRICA de onde saíram os itens-lixo do catálogo
# (medidos em prod, 02/09): "CD de magia" como item em 14 fichas, "Armas" em
# 15, "Roupas" com kind armor sem CA, acessórios de casca vazia. Ele roda em
# TODO SheetItem validado — não só no Excel — então cada guard aqui vale para
# item digitado à mão também.
RSpec.describe ItemResolver, type: :service do
  subject(:resolver) { described_class.new }

  describe 'cabeçalhos de seção NÃO viram item' do
    it 'devolve nil para os cabeçalhos medidos em prod' do
      ['CD de magia', 'CD de habilidade', 'CD do Chi', 'Armas', 'Armaduras',
       'Equipamento', 'Inventário'].each do |cabecalho|
        expect(resolver.resolve(name: cabecalho, category: 'Armaduras & Escudos'))
          .to be_nil, cabecalho
      end
    end

    it 'e não cria registro nenhum no catálogo' do
      expect {
        resolver.resolve(name: 'CD de magia', category: nil)
      }.not_to change(Item, :count)
    end
  end

  describe 'roupa nunca é armadura' do
    it '⚠️ "Roupas" na coluna de armadura vira gear (CA 10+DES, sem item)' do
      item = resolver.resolve(name: 'Roupas de viagem ZZ', category: 'Armaduras & Escudos')
      expect(item.kind).to eq('gear')
    end
  end

  describe 'o item criado nasce DECLARADO (equip_slot carimbado)' do
    it 'arma homebrew: main_hand' do
      item = resolver.resolve(name: 'Lâmina do Vazio ZZ', category: 'Armas')
      expect(item.kind).to eq('weapon')
      expect(item.props['equip_slot']).to eq('main_hand')
    end

    it 'escudo: shield com o +2 do livro' do
      item = resolver.resolve(name: 'Escudo Rúnico ZZ', category: nil)
      expect(item.kind).to eq('shield')
      expect(item.props['equip_slot']).to eq('shield')
      expect(item.props['ac_bonus']).to eq(2)
    end

    it 'acessório do "wearing": peça + slot (a constante que era MORTA)' do
      colar = resolver.resolve(name: 'Colar do Inverno ZZ', category: nil)
      expect(colar.kind).to eq('gear')
      expect(colar.category).to eq('amulet')
      expect(colar.props['equip_slot']).to eq('amulet')
    end

    it '⚠️ "Coldre da perna ZZ" vai para a PERNA — não cai na regex de cinto' do
      coldre = resolver.resolve(name: 'Coldre da perna ZZ', category: nil)
      expect(coldre.category).to eq('belt_leg')
      expect(coldre.props['equip_slot']).to eq('belt_leg_left')
    end

    it 'marca a origem para auditoria' do
      item = resolver.resolve(name: 'Bugiganga Inédita ZZ2', category: nil)
      expect(item.source).to eq('import-auto')
    end
  end

  describe 'o que já existe não é tocado' do
    it 'item existente resolve sem ganhar carimbo novo' do
      existente = Item.create!(api_index: 'peca-antiga-zz', name: 'Peça Antiga ZZ', kind: 'gear')
      resolvido = resolver.resolve(name: 'Peça Antiga ZZ', category: nil)
      expect(resolvido.id).to eq(existente.id)
      expect(resolvido.props['equip_slot']).to be_nil
    end
  end
end
