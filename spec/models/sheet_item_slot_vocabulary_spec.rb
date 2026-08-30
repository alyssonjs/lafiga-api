# frozen_string_literal: true

require 'rails_helper'

# Reforma dos slots (29/08): `face` (rosto: máscara, óculos) entrou;
# `circlet` foi FUNDIDO em `helmet` (cabeça inteira: elmo, chapéu, tiara).
#
# Medido antes da mudança: ZERO SheetItems e zero catálogo usavam `circlet` —
# a fusão é só de vocabulário. A canonicalização existe para o CLIENTE da
# janela de deploy (front antigo ainda manda `circlet`), não para dados.
RSpec.describe 'SheetItem — vocabulário de slots', type: :model do
  let(:sheet) { create(:sheet) }

  def item!(nome, slot: nil, equipped: false)
    SheetItem.create!(sheet: sheet, item_name: nome, category: 'Vestuário',
                      quantity: 1, slot: slot, equipped: equipped)
  end

  it '`face` é slot válido (máscara/óculos deixam de ser inequipáveis)' do
    linha = item!('Máscara do Corvo', slot: 'face', equipped: true)
    expect(linha.reload.slot).to eq('face')
  end

  it 'cliente antigo mandando `circlet` NÃO leva 422 — canonicaliza para helmet' do
    # A canonicalização roda ANTES da validação de propósito: depois dela, o
    # front da janela de deploy quebraria ao equipar tiara.
    linha = item!('Tiara Prateada', slot: 'circlet', equipped: true)
    expect(linha.reload.slot).to eq('helmet')
  end

  it '`circlet` não está mais na lista canônica' do
    expect(SheetItem::ACCESSORY_SLOTS).not_to include('circlet')
    expect(SheetItem::ACCESSORY_SLOTS).to include('face')
  end

  it 'o scanner de efeitos varre o slot novo (a lista é a MESMA constante)' do
    # `EquipmentProfileService` monta o mapa de acessórios a partir de
    # ACCESSORY_SLOTS — um slot fora dela teria item equipado cujo efeito
    # mágico nunca aplica.
    item!('Óculos da Noite', slot: 'face', equipped: true)
    perfil = EquipmentProfileService.new(sheet.reload).call
    acessorios = perfil.dig(:equipped, :accessories) || {}
    expect(acessorios.keys.map(&:to_s)).to include('face')
  end
end
