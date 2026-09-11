require 'rails_helper'
require 'rake'

# FASE 0 do editor de classes — o spec protege a AUDITORIA.
#
# ⚠️ Um rake de auditoria que quebra em silêncio passa a relatar "0 achados"
# para sempre, e ninguém repara. Cada caso injeta o defeito e exige que ele
# apareça.
RSpec.describe 'dnd:audit_class_sources', type: :model do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('dnd:audit_class_sources')
  end

  let!(:klass) do
    Klass.find_by(api_index: 'fighter') ||
      Klass.create!(name: 'Guerreiro', api_index: 'fighter', hit_die: 10)
  end
  let(:original) { { subclass_level: klass.subclass_level, rules: klass.read_attribute(:rules), saving_throws: klass.saving_throws } }

  after { Klass.where(id: klass.id).update_all(original) }

  def roda
    Rake::Task['dnd:audit_class_sources'].reenable
    saida = StringIO.new
    original_stdout = $stdout
    $stdout = saida
    Rake::Task['dnd:audit_class_sources'].invoke
    saida.string
  ensure
    $stdout = original_stdout
  end

  it 'corre e relata as fontes' do
    expect(roda).to include('fontes medidas')
  end

  # ⚠️ `SheetKlass#subclass_only_after_threshold` faz `return if
  # threshold.blank?`, e o provisionamento faz `k.try(:subclass_level).to_i` →
  # 0 → `eligible_at_l1` sempre verdadeiro. Com a coluna vazia os guardas do
  # servidor ficam inertes e quem segura a regra é o front.
  it 'apanha o portão inerte (coluna vazia)' do
    Klass.where(id: klass.id).update_all(subclass_level: nil)
    expect(roda).to include('portao_inerte')
  end

  it 'apanha a coluna que discorda da regra' do
    Klass.where(id: klass.id).update_all(subclass_level: 7)
    saida = roda
    expect(saida).to include('coluna_x_regra')
    expect(saida).to include('7')
  end

  # ⚠️ O achado mais perigoso: `ClassRules.find` devolve o DB INTEIRO quando
  # `rules` está presente, e o controller admite `rules: {}` sem sanitizador.
  # Meia classe gravada apaga a outra metade.
  it 'apanha `rules` incompleto — o replace-all que apaga a classe' do
    Klass.where(id: klass.id).update_all(rules: { 'name' => 'X' })
    saida = roda
    expect(saida).to include('rules_incompleto')
    expect(saida).to include('replace-all')
  end

  # ⚠️ `SavingThrowsCatalog.translate_array` só mapeia sigla EN→PT
  # (`str`→`FOR`); não atravessa `FOR` ↔ `Força`. Medido.
  it 'separa grafia diferente de valor diferente', :aggregate_failures do
    Klass.where(id: klass.id).update_all(saving_throws: ['Força', 'Constituição'])
    expect(roda).to include('saving_throws_grafia')

    Klass.where(id: klass.id).update_all(saving_throws: %w[FOR CON])
    saida = roda
    expect(saida).not_to match(/saving_throws_grafia[\s\S]{0,400}\bfighter\b/)
  end

  # ⚠️ Casar por NOME é o que distingue "a sub-classe não existe" de "existe
  # com o slug do SRD". Sem isso a auditoria acusa 11 órfãos que não são.
  it 'chama de DUPLICADO o que existe no banco com outro slug', :aggregate_failures do
    saida = roda
    expect(saida).to include('duplicado_por_slug')
    expect(saida).to include('berserker')
  end

  # `warlock` tem `rules`, `boons` e `invocations` sob a classe, que são
  # estrutura e não sub-classe. A sub-classe de verdade traz `levels`.
  it 'não confunde chave estrutural do YAML com sub-classe' do
    saida = roda
    expect(saida).not_to include('warlock/boons')
    expect(saida).not_to include('warlock/invocations')
  end
end
