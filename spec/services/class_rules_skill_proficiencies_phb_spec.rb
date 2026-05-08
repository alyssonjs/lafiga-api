# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Audit PHB × projeto: contagem + lista de perícias escolhíveis por classe.
#
# Fonte de verdade: docs/livro_do_jogador.txt (PHB 5e, traduzido). Cada classe
# tem uma seção "PROFICIÊNCIAS → Perícias: Escolha N dentre [lista]".
#
# Esta suite trava regressão se alguém alterar `skill_proficiencies` em
# `app/services/class_rules.rb` saindo do canônico do livro. Adicionar classe
# nova ou houserule = adicionar entrada com nota explicando que é homebrew.
#
# Regra do dev: NÃO mudar o `EXPECTED_BY_CLASS` abaixo sem cruzar com o PHB.
# Se a regra mudar oficialmente (ex.: One D&D), atualizar pelos dois lados E
# documentar a fonte no comentário acima da entrada.
# ----------------------------------------------------------------------------
RSpec.describe 'ClassRules — skill proficiencies × PHB', type: :service do
  # Mapa canônico extraído do PHB pt-BR. Ordem alfabética (case-insensitive)
  # para facilitar comparação visual; o teste compara via Set para tolerar
  # qualquer ordem na implementação.
  #
  # Namespaceado dentro do `describe` para não colidir com o
  # EXPECTED_BY_CLASS do `class_rules_phb_audit_spec.rb` (que cobre outras
  # facetas estáticas).
  SKILLS_EXPECTED_BY_CLASS = {
    # Bárbaro (PHB pg 47)
    'barbarian' => {
      count: 2,
      options: %w[Atletismo Intimidação Lidar\ com\ Animais Natureza Percepção Sobrevivência].map { |s| s.tr('\\', '') }
    },
    # Bardo (PHB pg 50): "três quaisquer"
    'bard' => {
      count: 3,
      options: :any
    },
    # Bruxo (PHB pg 105)
    'warlock' => {
      count: 2,
      options: ['Arcanismo', 'Enganação', 'História', 'Intimidação', 'Investigação', 'Natureza', 'Religião']
    },
    # Clérigo (PHB pg 56)
    'cleric' => {
      count: 2,
      options: ['História', 'Intuição', 'Medicina', 'Persuasão', 'Religião']
    },
    # Druida (PHB pg 65)
    'druid' => {
      count: 2,
      options: ['Arcanismo', 'Lidar com Animais', 'Intuição', 'Medicina', 'Natureza', 'Percepção', 'Religião', 'Sobrevivência']
    },
    # Feiticeiro (PHB pg 99)
    'sorcerer' => {
      count: 2,
      options: ['Arcanismo', 'Enganação', 'Intuição', 'Intimidação', 'Persuasão', 'Religião']
    },
    # Guerreiro (PHB pg 71)
    'fighter' => {
      count: 2,
      options: ['Acrobacia', 'Lidar com Animais', 'Atletismo', 'História', 'Intuição', 'Intimidação', 'Percepção', 'Sobrevivência']
    },
    # Ladino (PHB pg 95)
    'rogue' => {
      count: 4,
      options: ['Acrobacia', 'Atletismo', 'Atuação', 'Enganação', 'Furtividade', 'Intimidação', 'Intuição', 'Investigação', 'Percepção', 'Persuasão', 'Prestidigitação']
    },
    # Mago (PHB pg 113)
    'wizard' => {
      count: 2,
      options: ['Arcanismo', 'História', 'Intuição', 'Investigação', 'Medicina', 'Religião']
    },
    # Monge (PHB pg 77)
    'monk' => {
      count: 2,
      options: ['Acrobacia', 'Atletismo', 'Furtividade', 'História', 'Intuição', 'Religião']
    },
    # Paladino (PHB pg 82)
    'paladin' => {
      count: 2,
      options: ['Atletismo', 'Intuição', 'Intimidação', 'Medicina', 'Persuasão', 'Religião']
    },
    # Patrulheiro (PHB pg 89/116)
    'ranger' => {
      count: 3,
      options: ['Acrobacia', 'Lidar com Animais', 'Atletismo', 'Furtividade', 'Intuição', 'Investigação', 'Natureza', 'Percepção', 'Sobrevivência']
    }
  }.freeze

  # Classes homebrew (não-PHB) que vivem no projeto. NÃO entram no audit
  # canônico — só registramos aqui para documentar que existem e que tiveram
  # decisão deliberada do projeto. Mudanças nelas exigem revisão de design.
  HOMEBREW_CLASSES = %w[cozinheiro].freeze

  SKILLS_EXPECTED_BY_CLASS.each do |klass_id, expected|
    describe "Classe '#{klass_id}'" do
      let(:rule) { ClassRules::CLASS_RULES.fetch(klass_id.to_sym) }
      let(:sp)   { rule[:skill_proficiencies] }

      it 'tem skill_proficiencies declarado' do
        expect(sp).to be_a(Hash),
          "ClassRules.CLASS_RULES[:#{klass_id}] não tem skill_proficiencies. " \
          "Veio: #{rule.keys.inspect}"
      end

      it "permite escolher #{expected[:count]} perícias (PHB)" do
        expect(sp[:choose]).to eq(expected[:count]),
          "Classe #{klass_id}: PHB diz 'Escolha #{expected[:count]}', código " \
          "tem 'choose: #{sp[:choose].inspect}'."
      end

      if expected[:options] == :any
        it 'aceita qualquer perícia (Bardo)' do
          expect(sp[:options]).to eq(:any),
            "Classe #{klass_id} (Bardo): PHB diz 'qualquer'; código deve usar " \
            "options: :any. Veio: #{sp[:options].inspect}"
        end
      else
        it 'lista de opções bate com o PHB (sem itens faltando ou sobrando)' do
          got = Array(sp[:options]).map(&:to_s).to_set
          want = expected[:options].map(&:to_s).to_set

          missing = want - got
          extra   = got - want

          aggregate_failures do
            expect(missing).to be_empty,
              "Classe #{klass_id} está SEM opções do PHB: #{missing.to_a.inspect}.\n" \
              "  Lista no código: #{got.to_a.sort.inspect}\n" \
              "  Lista do PHB:    #{want.to_a.sort.inspect}"
            expect(extra).to be_empty,
              "Classe #{klass_id} tem opções EXTRAS além do PHB: #{extra.to_a.inspect}.\n" \
              "  Se for houserule, adicionar comentário no código + nota no spec."
          end
        end
      end
    end
  end

  describe 'Audit cobrindo TODAS as classes PHB' do
    it 'EXPECTED_BY_CLASS cobre as 12 classes do PHB' do
      expected_count = 12
      expect(SKILLS_EXPECTED_BY_CLASS.size).to eq(expected_count),
        "Esperado #{expected_count} classes PHB, EXPECTED_BY_CLASS tem #{SKILLS_EXPECTED_BY_CLASS.size}."
    end

    it 'CLASS_RULES contém pelo menos as 12 classes PHB + as homebrew declaradas' do
      defined_ids = ClassRules::CLASS_RULES.keys.map(&:to_s).to_set
      missing_phb = SKILLS_EXPECTED_BY_CLASS.keys.to_set - defined_ids
      expect(missing_phb).to be_empty,
        "Classes PHB ausentes em ClassRules.CLASS_RULES: #{missing_phb.to_a.inspect}"

      missing_hb = HOMEBREW_CLASSES.to_set - defined_ids
      expect(missing_hb).to be_empty,
        "Classes homebrew ausentes (esperadas em HOMEBREW_CLASSES): #{missing_hb.to_a.inspect}"
    end

    it 'classes desconhecidas (nem PHB nem homebrew) têm spec próprio explicando' do
      defined_ids = ClassRules::CLASS_RULES.keys.map(&:to_s).to_set
      known = SKILLS_EXPECTED_BY_CLASS.keys.to_set | HOMEBREW_CLASSES.to_set
      unknown = defined_ids - known

      expect(unknown).to be_empty,
        "Classes em CLASS_RULES sem cobertura do audit PHB nem registradas " \
        "como homebrew: #{unknown.to_a.inspect}.\n" \
        "  Se for houserule nova, adicionar em HOMEBREW_CLASSES com comentário " \
        "explicando a origem (PDF, designer, etc.)."
    end
  end
end
