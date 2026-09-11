require 'rails_helper'
require 'rake'

# FASE 3 — a auditoria do overlay de raças.
#
# ⚠️ O que este spec protege é a própria auditoria: um rake de auditoria que
# quebra em silêncio passa a relatar "0 achados" para sempre, e ninguém repara.
# Por isso cada caso INJETA o defeito e exige que ele apareça.
RSpec.describe 'dnd:audit_race_overrides', type: :model do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('dnd:audit_race_overrides')
  end

  after { RaceRules.reload! }

  def roda
    Rake::Task['dnd:audit_race_overrides'].reenable
    saida = StringIO.new
    original = $stdout
    $stdout = saida
    Rake::Task['dnd:audit_race_overrides'].invoke
    saida.string
  ensure
    $stdout = original
  end

  let!(:raca) do
    Race.find_by(api_index: 'tiefling') || Race.create!(name: 'Tiefling', api_index: 'tiefling')
  end

  it 'corre e relata sem overlay nenhum' do
    expect(roda).to include('overlays no banco: 0 raças')
  end

  # `load_overlay` faz `next if r.api_index.blank?`: o mestre grava, a tela
  # mostra o valor de volta (vem do próprio registo) e a ficha nunca muda.
  it 'apanha overlay que nunca é LIDO (sem `api_index`)' do
    raca.update_columns(rules_json: { 'speed' => 40 }, api_index: nil)
    expect(roda).to include('overlay_sem_chave')
  ensure
    raca.update_columns(rules_json: {}, api_index: 'tiefling')
  end

  # ⚠️ Reusa o sanitizador em vez de reimplementar a validação. Linhas escritas
  # por console ou rake não passaram por ele.
  it 'apanha forma que o sanitizador recusaria' do
    raca.update_columns(rules_json: { 'speed' => '9m' })
    saida = roda
    expect(saida).to include('forma_invalida')
    expect(saida).to include('número em pés')
  ensure
    raca.update_columns(rules_json: {})
  end

  it 'apanha ref de traço sem definição' do
    raca.update!(rules_json: { 'traits' => [{ 'key' => 'traco_que_nao_existe' }] })
    expect(roda).to include('traco_sem_definicao')
  ensure
    raca.update_columns(rules_json: {})
  end

  it 'apanha traço próprio que ninguém referencia' do
    raca.update!(rules_json: { 'custom_traits' => { 'esquecido' => { 'name' => 'Esquecido' } } })
    expect(roda).to include('traco_proprio_sem_ref')
  ensure
    raca.update_columns(rules_json: {})
  end

  # 🐞 `RaceProducer#interpolate` resolve `<damage>` a partir do REF. Sem o
  # campo, o valor vira string vazia e é descartado: a resistência some da
  # ficha e nada diz porquê.
  it 'apanha placeholder sem o campo no ref' do
    raca.update!(rules_json: { 'traits' => [{ 'key' => 'damage_resistance_from_ancestry' }] })
    saida = roda
    expect(saida).to include('placeholder_sem_campo')
    expect(saida).to include('<damage>')
  ensure
    raca.update_columns(rules_json: {})
  end

  it 'apanha prosa que promete o que os grants não concedem' do
    raca.update!(rules_json: {
                   'traits' => [{ 'key' => 'pele_de_brasa' }],
                   'custom_traits' => { 'pele_de_brasa' => {
                     'name' => 'Pele de Brasa',
                     'description' => 'Concede resistência a dano de fogo.',
                     'grants' => { 'defenses' => { 'resistance' => ['frio'] } }
                   } }
                 })
    expect(roda).to include('prosa_x_dado')
  ensure
    raca.update_columns(rules_json: {})
  end

  # ⚠️ Uma definição que ninguém referencia não chega a ficha nenhuma — é
  # arrumação de catálogo, não regra quebrada na mesa. Fica em categoria
  # SEPARADA para o mestre não procurar um problema de jogo onde não há.
  it 'separa a definição órfã da prosa divergente' do
    saida = roda
    expect(saida).to include('definicao_orfa')
    expect(saida).not_to match(/prosa_x_dado[\s\S]*hellish_resistance/)
  end
end
