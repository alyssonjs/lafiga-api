# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Descrições da bolsa cortadas em 120 caracteres pelo "+ Novo Item". O risco da
# rake não é falhar: é gravar no DRY RUN ou passar por cima de texto escrito à
# mão, que nunca foi cópia do catálogo.
RSpec.describe 'dnd:repair_truncated_item_descriptions' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:sheet) { create(:sheet) }
  let(:texto) do
    'Esta árvore, que pode atingir 12 metros de altura, requer temperaturas suaves e tem uma ' \
      'casca espessa semelhante à da cortiça, e o texto segue além do corte.'
  end
  let!(:erva) do
    Item.find_or_initialize_by(api_index: 'herb-covette').tap do |i|
      i.update!(name: 'Covette', kind: 'material', category: 'herb', description: texto)
    end
  end

  def rodar(aplicar: false)
    Rake::Task['dnd:repair_truncated_item_descriptions'].reenable
    ENV['APPLY'] = '1' if aplicar
    saida = StringIO.new
    $stdout = saida
    Rake::Task['dnd:repair_truncated_item_descriptions'].invoke
    saida.string
  ensure
    $stdout = STDOUT
    ENV.delete('APPLY')
  end

  def linha!(descricao)
    SheetItem.create!(sheet: sheet, item: erva, item_name: 'Covette', item_index: 'herb-covette',
                      category: 'Itens Gerais', quantity: 6, source: 'manual',
                      props_json: { 'description' => descricao, 'weight_lb' => 0 })
  end

  it 'DRY RUN é o padrão — relata e não grava' do
    si = linha!(texto[0, 120])

    expect(rodar).to include('reparadas 1')
    expect(si.reload.props_json['description'].length).to eq(120)
  end

  it 'APPLY=1 repõe o texto inteiro do catálogo, sem mexer no resto da linha' do
    si = linha!(texto[0, 120])

    rodar(aplicar: true)

    si.reload
    expect(si.props_json['description']).to eq(texto)
    expect(si.props_json['weight_lb']).to eq(0)
    expect(si.quantity).to eq(6)
  end

  it '⚠️ texto escrito à mão fica como está — mesmo com 120 caracteres' do
    anotacao = linha!('Anotação do mestre: guardar duas para a poção de cura.')
    outro = linha!('x' * 120)

    rodar(aplicar: true)

    expect(anotacao.reload.props_json['description']).to eq('Anotação do mestre: guardar duas para a poção de cura.')
    expect(outro.reload.props_json['description']).to eq('x' * 120)
  end

  it 'texto que só COMEÇA igual ao do catálogo, mas é mais curto, também fica' do
    # Não foi o corte do "+ Novo Item" (esse tem exatamente 120): foi alguém que
    # escreveu. Trocar pelo texto do catálogo apagaria a edição.
    curto = linha!(texto[0, 50])

    rodar(aplicar: true)

    expect(curto.reload.props_json['description']).to eq(texto[0, 50])
  end

  it 'rodar de novo não acha mais nada' do
    linha!(texto[0, 120])

    rodar(aplicar: true)

    expect(rodar(aplicar: true)).to include('reparadas 0')
  end
end
