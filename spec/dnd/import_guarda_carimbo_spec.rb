# frozen_string_literal: true

require 'rails_helper'

# A GUARDA DE CARIMBO do import.
#
# ⚠️ `apply_subclass_overrides!` faz REPLACE-ALL do `levels_json`: sem a guarda,
# re-rodar a rake apagava em silêncio tudo o que o mestre tivesse gravado pela
# página do compêndio. `edited_at` NULL significa "é o livro" — sub nunca tocada
# continua atualizando, e `FORCE=1` volta ao comportamento antigo por pedido.
RSpec.describe 'guarda de carimbo do import de sub-classes' do
  let(:klass) do
    Klass.find_by(api_index: 'fighter') ||
      Klass.create!(name: 'Guerreiro SO', api_index: 'fighter', hit_die: 10)
  end

  # ⚠️ A guarda lê ENV['FORCE']; isolar o exemplo do ambiente do processo.
  around do |exemplo|
    forca_antes = ENV.delete('FORCE')
    exemplo.run
  ensure
    forca_antes.nil? ? ENV.delete('FORCE') : ENV['FORCE'] = forca_antes
  end

  def importa!
    DndImportHelpers.apply_subclass_overrides!(klass)
  end

  def campeao
    klass.sub_klasses.find_by!(api_index: 'campeao')
  end

  it 'sub-classe SEM carimbo continua sendo atualizada pelo import' do
    importa!
    campeao.update_columns(levels_json: [], edited_at: nil)

    importa!

    expect(campeao.reload.linhas_de_nivel).not_to be_empty
  end

  it '⚠️ sub-classe CARIMBADA é pulada — a edição do mestre sobrevive à rake' do
    importa!
    do_mestre = [{ 'level' => 3, 'features' => [{ 'name' => 'Regra do Mestre' }] }]
    campeao.update!(levels_json: do_mestre, edited_at: Time.current)

    importa!

    expect(campeao.reload.linhas_de_nivel).to eq(do_mestre)
  end

  it 'e o carimbo não bloqueia as OUTRAS subs da mesma classe' do
    importa!
    campeao.update!(levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'Regra do Mestre' }] }],
                    edited_at: Time.current)
    outra = klass.sub_klasses.find_by!(api_index: 'mestre-de-batalha')
    outra.update_columns(levels_json: [], edited_at: nil)

    importa!

    expect(outra.reload.linhas_de_nivel).not_to be_empty
  end

  it 'FORCE=1 volta ao replace-all, de propósito e por pedido' do
    importa!
    campeao.update!(levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'Regra do Mestre' }] }],
                    edited_at: Time.current)

    ENV['FORCE'] = '1'
    importa!

    linhas = campeao.reload.linhas_de_nivel
    nomes = linhas.flat_map { |l| Array(l['features']).map { |f| f['name'] } }
    expect(nomes).not_to include('Regra do Mestre')
    # Os níveis do livro, medidos: o Campeão tem features em 3/7/10/15/18.
    expect(linhas.map { |l| l['level'] }).to include(3, 7, 10, 15, 18)
  end
end
