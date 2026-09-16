# frozen_string_literal: true

require 'rails_helper'
require 'json'
require 'fileutils'

# GOLDEN das fontes de regra de classe — a rede das fases 3–5.
#
# ⚠️ A paridade das fases 0–2 foi feita FORA da árvore (guardar a saída de HEAD e
# diffar à mão) e por isso não é repetível: o registo dela vive só na mensagem do
# commit. Isto traz a técnica para dentro — fixture commitado, regravado SÓ com
# `GOLDEN_REBUILD=1`, para o rebaseline ser um diff revisável no PR.
#
# ⚠️ O golden não pode depender do banco — e "o catálogo de teste está vazio" NÃO
# basta como garantia. A primeira gravação deste fixture saiu poluída: a suíte
# inteira tinha acabado de rodar e deixara `klasses` para trás; com `klass_record`
# presente, `available_subclasses` troca de ramo (marca `custom: true` e deriva
# `spellcasting` do banco, `class_rules.rb:319-326`) e o fixture congelou ESSE
# ramo. O `rails db:migrate` seguinte recriou o banco de teste a partir do schema,
# os restos sumiram e o golden acusou 13/13 chaves — ele funcionou, só que contra
# o próprio fixture.
#
# Por isso as portas de banco desta composição são fechadas explicitamente abaixo.
# O que se congela é a COMPOSIÇÃO DE ARQUIVO (constante + YAML) — exatamente a
# camada que as fases 3–5 mexem. Overlay gravado por mestre, que é o ramo do
# banco, é coberto pelos request specs.
#
# Regenerar:
#   docker exec -e RAILS_ENV=test -e GOLDEN_REBUILD=1 lafiga_api \
#     bundle exec rspec spec/dnd/golden_class_sources_spec.rb
RSpec.describe 'Golden das fontes de regra de classe' do
  # As três portas para o banco nesta composição: o overlay da classe, o catálogo
  # de sub-classes e a tradução de slug→nome de magia no fallback do YAML
  # (`class_rules.rb:386`). Fechadas, o golden dá o mesmo resultado rodando
  # sozinho ou no fim da suíte — que é a única forma de ele valer como rede.
  before do
    allow(KlassClassRulesProvider).to receive(:call).and_return(nil)
    allow(Klass).to receive(:find_by).and_return(nil)
    allow(Spell).to receive(:find_by).and_return(nil)
  end

  def secoes
    %w[class_rules available_subclasses yaml_levels]
  end

  def golden_path
    Rails.root.join('spec', 'fixtures', 'golden', 'class_sources.json')
  end

  # Ordena chaves e normaliza símbolos — o mesmo conteúdo produz sempre o mesmo
  # texto. A ordem dos ARRAYS é preservada: nas regras ela é significativa.
  def canonico(valor)
    case valor
    when Hash   then valor.map { |k, v| [k.to_s, canonico(v)] }.sort_by(&:first).to_h
    when Array  then valor.map { |v| canonico(v) }
    when Symbol then valor.to_s
    else valor
    end
  end

  def classes
    ClassRules::CLASS_RULES.keys.map(&:to_s).sort
  end

  # O que o YAML COMPÕE por sub-classe, com o mesmo discriminador e os mesmos
  # aliases do import (`apply_subclass_overrides!`): `boons`/`invocations`/`rules`
  # do bruxo são estrutura, não sub-classe.
  #
  # ⚠️ Aqui guarda-se DIGEST, não conteúdo: em corpo inteiro esta seção era 75%
  # do fixture (257 KB) e é eco do `config/*.yml`, que já é versionado — o diff
  # revisável de uma mudança de regra é o do próprio YAML, no mesmo commit. O
  # número de linhas vai junto porque transforma "mudou" em "tinha 13 níveis,
  # agora tem 12" sem custo nenhum.
  def yaml_levels
    DndImportHelpers.merged_overrides.each_with_object({}) do |(klass_idx, subs), acc|
      next unless subs.is_a?(Hash)

      subs.each do |sub_idx, raw|
        next if %w[boons invocations rules].include?(sub_idx.to_s)
        next unless raw.is_a?(Hash)

        destino = DndImportHelpers::SUBCLASS_ALIASES.dig(klass_idx.to_s, sub_idx.to_s) || sub_idx.to_s
        linhas = Array(raw['levels'] || raw[:levels]).compact.select { |r| r.is_a?(Hash) }
        digest = Digest::SHA256.hexdigest(JSON.generate(canonico(linhas)))
        acc["#{klass_idx}/#{destino}"] = "#{linhas.size} linhas · #{digest[0, 32]}"
      end
    end.sort_by(&:first).to_h
  end

  def instantaneo
    {
      'class_rules' => classes.index_with { |id| canonico(ClassRules.find(id)) },
      'available_subclasses' => classes.index_with { |id| canonico(ClassRules.available_subclasses(id)) },
      'yaml_levels' => yaml_levels
    }
  end

  it 'as fontes compostas continuam idênticas ao fixture' do
    atual = instantaneo

    if ENV['GOLDEN_REBUILD'] == '1'
      FileUtils.mkdir_p(File.dirname(golden_path))
      File.write(golden_path, "#{JSON.pretty_generate(atual)}\n")
      skip "fixture regravado (#{File.size(golden_path)} bytes) — revise o diff e commite à parte"
    end

    unless File.exist?(golden_path)
      raise "fixture ausente (#{golden_path}) — regravar com GOLDEN_REBUILD=1"
    end

    esperado = JSON.parse(File.read(golden_path))

    # Falha por SEÇÃO e por CHAVE: "mudou" sem dizer ONDE custa uma hora de busca.
    secoes.each do |secao|
      atuais = atual.fetch(secao)
      antigos = esperado.fetch(secao, {})
      mudadas = (antigos.keys | atuais.keys).reject { |k| antigos[k] == atuais[k] }

      expect(mudadas).to eq([]),
                         "seção #{secao}: divergem #{mudadas.size} chave(s) → #{mudadas.first(8).inspect}" \
                         "#{' …' if mudadas.size > 8} (rebaseline deliberado: GOLDEN_REBUILD=1)"
    end
  end
end
