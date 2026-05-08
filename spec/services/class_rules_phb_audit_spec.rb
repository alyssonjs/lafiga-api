# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Audit completo PHB × ClassRules — facetas estáticas das 12 classes do PHB.
#
# Escopo: dados FIXOS por classe (não dependem de escolhas do jogador):
#   - hit_die
#   - saving_throws
#   - primary_abilities (para multiclass + design)
#   - armor_proficiencies
#   - weapon_proficiencies
#   - tool_proficiencies (apenas quando FIXO; tools com `choose:` ficam fora)
#
# Skill proficiencies (que envolvem `choose: N, options: [...]`) já têm spec
# dedicado em class_rules_skill_proficiencies_phb_spec.rb.
#
# Este audit existe porque o cruzamento PHB×projeto descobriu (2026-05-08):
#   - Patrulheiro sem `Acrobacia` na lista de perícias (corrigido).
#   - Bruxo com `weapon_proficiencies: ['armas','simples']` (split bugado).
#
# Mudanças no `EXPECTED_BY_CLASS` exigem cruzamento com o livro pt-BR
# (`docs/livro_do_jogador.txt`) — referência de página em cada entrada.
# ----------------------------------------------------------------------------
RSpec.describe 'ClassRules — facetas estáticas × PHB', type: :service do
  # ASI levels: PHB pg 36 (geral). Todas as classes ganham ASI nos níveis
  # 4, 8, 12, 16, 19. Guerreiro ganha extras em 6 e 14 (PHB pg 71).
  # Ladino ganha extra em 10 (PHB pg 95).
  STANDARD_ASI_LEVELS = [4, 8, 12, 16, 19].freeze
  FIGHTER_ASI_LEVELS  = [4, 6, 8, 12, 14, 16, 19].freeze
  ROGUE_ASI_LEVELS    = [4, 8, 10, 12, 16, 19].freeze

  EXPECTED_BY_CLASS = {
    # Bárbaro (PHB pg 47). Subclasse no nv 3 (Caminho Primal). Sem magias.
    'barbarian' => {
      hit_die: 'd12',
      saving_throws: %w[STR CON],
      primary_abilities: %w[STR CON],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples', 'armas marciais'],
      tool_proficiencies: [],
      spellcasting: nil,
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Bardo (PHB pg 50). full caster CHA known. Subclasse nv 3.
    'bard' => {
      hit_die: 'd8', saving_throws: %w[DEX CHA], primary_abilities: %w[CHA],
      armor_proficiencies: %w[leve],
      weapon_proficiencies: ['armas simples', 'bestas de mão', 'espadas longas', 'rapieiras', 'espadas curtas'],
      tool_proficiencies: :choose,
      spellcasting: { type: 'full', ability: 'CHA', preparation: 'known', cantrips_known_at_1: 2, spells_known_at_1: 4, list: 'bard' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Bruxo (PHB pg 105). pact caster CHA known. Subclasse nv 1 (Patrono).
    'warlock' => {
      hit_die: 'd8', saving_throws: %w[WIS CHA], primary_abilities: %w[CHA],
      armor_proficiencies: %w[leve], weapon_proficiencies: ['armas simples'], tool_proficiencies: [],
      spellcasting: { type: 'pact', ability: 'CHA', preparation: 'known', cantrips_known_at_1: 2, spells_known_at_1: 2, list: 'warlock' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 1
    },
    # Clérigo (PHB pg 56). full caster WIS prepared. Subclasse nv 1 (Domínio).
    'cleric' => {
      hit_die: 'd8', saving_throws: %w[WIS CHA], primary_abilities: %w[WIS],
      armor_proficiencies: %w[leve média escudos], weapon_proficiencies: ['armas simples'], tool_proficiencies: [],
      spellcasting: { type: 'full', ability: 'WIS', preparation: 'prepared', cantrips_known_at_1: 3, spells_known_at_1: nil, list: 'cleric' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 1
    },
    # Druida (PHB pg 65). full caster WIS prepared. Subclasse nv 2 (Círculo).
    'druid' => {
      hit_die: 'd8', saving_throws: %w[INT WIS], primary_abilities: %w[WIS],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['clavas', 'adagas', 'dardos', 'azagaias', 'maças', 'bordões', 'cimitarra', 'foices', 'fundas', 'lanças'],
      tool_proficiencies: ['Kit de Herbalismo'],
      spellcasting: { type: 'full', ability: 'WIS', preparation: 'prepared', cantrips_known_at_1: 2, spells_known_at_1: nil, list: 'druid' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 2
    },
    # Feiticeiro (PHB pg 99). full caster CHA known. Subclasse nv 1 (Origem).
    'sorcerer' => {
      hit_die: 'd6', saving_throws: %w[CON CHA], primary_abilities: %w[CHA],
      armor_proficiencies: [], weapon_proficiencies: ['adagas', 'dardos', 'fundas', 'bordões', 'bestas leves'], tool_proficiencies: [],
      spellcasting: { type: 'full', ability: 'CHA', preparation: 'known', cantrips_known_at_1: 4, spells_known_at_1: 2, list: 'sorcerer' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 1
    },
    # Guerreiro (PHB pg 71). Sem spellcasting nativo. ASI extras em 6 e 14. Arquétipo nv 3.
    'fighter' => {
      hit_die: 'd10', saving_throws: %w[STR CON], primary_abilities: %w[STR DEX CON],
      armor_proficiencies: %w[leve média pesada escudos],
      weapon_proficiencies: ['armas simples', 'armas marciais'], tool_proficiencies: [],
      spellcasting: nil,
      asi_levels: FIGHTER_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Ladino (PHB pg 95). Sem spellcasting nativo. ASI extra em 10. Arquétipo nv 3.
    'rogue' => {
      hit_die: 'd8', saving_throws: %w[DEX INT], primary_abilities: %w[DEX],
      armor_proficiencies: %w[leve],
      weapon_proficiencies: ['armas simples', 'bestas de mão', 'espadas longas', 'rapieiras', 'espadas curtas'],
      tool_proficiencies: ['Ferramentas de Ladrão'],
      spellcasting: nil,
      asi_levels: ROGUE_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Mago (PHB pg 113). full caster INT prepared (spellbook). Subclasse nv 2 (Escola).
    'wizard' => {
      hit_die: 'd6', saving_throws: %w[INT WIS], primary_abilities: %w[INT],
      armor_proficiencies: [], weapon_proficiencies: ['adagas', 'dardos', 'fundas', 'bordões', 'bestas leves'], tool_proficiencies: [],
      spellcasting: { type: 'full', ability: 'INT', preparation: 'prepared', cantrips_known_at_1: 3, spells_known_at_1: 6, list: 'wizard' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 2
    },
    # Monge (PHB pg 77). Sem spellcasting nativo. Tradição nv 3.
    'monk' => {
      hit_die: 'd8', saving_throws: %w[STR DEX], primary_abilities: %w[DEX WIS],
      armor_proficiencies: [], weapon_proficiencies: ['armas simples', 'espadas curtas'],
      tool_proficiencies: :choose,
      spellcasting: nil,
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Paladino (PHB pg 82). half caster CHA prepared. Sem cantrips. Juramento nv 3.
    'paladin' => {
      hit_die: 'd10', saving_throws: %w[WIS CHA], primary_abilities: %w[STR CHA],
      armor_proficiencies: %w[leve média pesada escudos], weapon_proficiencies: ['armas simples', 'armas marciais'], tool_proficiencies: [],
      spellcasting: { type: 'half', ability: 'CHA', preparation: 'prepared', cantrips_known_at_1: 0, spells_known_at_1: nil, list: 'paladin' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 3
    },
    # Patrulheiro (PHB pg 89). half caster WIS known. Arquétipo nv 3.
    'ranger' => {
      hit_die: 'd10', saving_throws: %w[STR DEX], primary_abilities: %w[DEX WIS],
      armor_proficiencies: %w[leve média escudos], weapon_proficiencies: ['armas simples', 'armas marciais'], tool_proficiencies: [],
      spellcasting: { type: 'half', ability: 'WIS', preparation: 'known', cantrips_known_at_1: 0, spells_known_at_1: 0, list: 'ranger' },
      asi_levels: STANDARD_ASI_LEVELS,
      subclass_choose_level: 3
    }
  }.freeze

  EXPECTED_BY_CLASS.each do |klass_id, expected|
    describe "Classe '#{klass_id}'" do
      let(:rule) { ClassRules::CLASS_RULES.fetch(klass_id.to_sym) }

      it "hit_die = #{expected[:hit_die]}" do
        expect(rule[:hit_die]).to eq(expected[:hit_die]),
          "#{klass_id}: PHB diz #{expected[:hit_die].inspect}, código tem #{rule[:hit_die].inspect}"
      end

      it "saving_throws = #{expected[:saving_throws].inspect}" do
        got = Array(rule[:saving_throws]).map(&:to_s).to_set
        want = expected[:saving_throws].to_set
        expect(got).to eq(want),
          "#{klass_id}: PHB diz #{want.to_a.sort.inspect}, código tem #{got.to_a.sort.inspect}"
      end

      it "primary_abilities = #{expected[:primary_abilities].inspect}" do
        got = Array(rule[:primary_abilities]).map(&:to_s).to_set
        want = expected[:primary_abilities].to_set
        expect(got).to eq(want),
          "#{klass_id}: PHB diz #{want.to_a.sort.inspect}, código tem #{got.to_a.sort.inspect}"
      end

      it "armor_proficiencies = #{expected[:armor_proficiencies].inspect}" do
        got = Array(rule[:armor_proficiencies]).map(&:to_s).to_set
        want = expected[:armor_proficiencies].to_set
        expect(got).to eq(want),
          "#{klass_id}: armaduras divergem do PHB.\n" \
          "  PHB:    #{want.to_a.sort.inspect}\n" \
          "  Código: #{got.to_a.sort.inspect}"
      end

      it "weapon_proficiencies cobre o PHB" do
        got = Array(rule[:weapon_proficiencies]).map(&:to_s).to_set
        want = expected[:weapon_proficiencies].to_set
        missing = want - got
        extra = got - want
        aggregate_failures do
          expect(missing).to be_empty,
            "#{klass_id}: armas FALTANDO vs PHB: #{missing.to_a.inspect}\n" \
            "  PHB:    #{want.to_a.sort.inspect}\n" \
            "  Código: #{got.to_a.sort.inspect}"
          expect(extra).to be_empty,
            "#{klass_id}: armas EXTRAS além do PHB: #{extra.to_a.inspect}\n" \
            "  Se for houserule, comentar no código + nota no audit."
        end
      end

      if expected[:tool_proficiencies] == :choose
        it 'tool_proficiencies tem `choose` declarado (Bardo/Monge: escolha)' do
          tp = rule[:tool_proficiencies]
          # Aceita Hash com :choose, ou estruturas { instruments: { choose: N } }.
          chooseable = tp.is_a?(Hash) && (tp[:choose].present? || tp.values.any? { |v| v.is_a?(Hash) && v[:choose].present? })
          expect(chooseable).to be(true),
            "#{klass_id}: PHB declara escolha de ferramentas; código não tem `choose:`. " \
            "Veio: #{tp.inspect}"
        end
      else
        it "tool_proficiencies = #{expected[:tool_proficiencies].inspect} (fixo)" do
          got = Array(rule[:tool_proficiencies]).map(&:to_s).to_set
          want = expected[:tool_proficiencies].map(&:to_s).to_set
          expect(got).to eq(want),
            "#{klass_id}: ferramentas divergem do PHB.\n" \
            "  PHB:    #{want.to_a.sort.inspect}\n" \
            "  Código: #{got.to_a.sort.inspect}"
        end
      end

      # ─── Spellcasting ──────────────────────────────────────────────────────
      if expected[:spellcasting].nil?
        it 'NÃO tem spellcasting nativo (Bárbaro/Guerreiro/Ladino/Monge)' do
          sc = rule[:spellcasting]
          expect(sc.blank? || sc[:casting_ability].blank?).to be(true),
            "#{klass_id}: PHB não tem spellcasting nativo (subclasses como " \
            "Eldritch Knight/Arcane Trickster ganham via `subclass.grants`). " \
            "Código tem: #{sc.inspect}"
        end
      else
        sc_expected = expected[:spellcasting]

        it "spellcasting.type = #{sc_expected[:type].inspect}" do
          got = rule.dig(:spellcasting, :type)
          expect(got.to_s).to eq(sc_expected[:type]),
            "#{klass_id}: PHB diz type #{sc_expected[:type].inspect}, código tem #{got.inspect}"
        end

        it "spellcasting.casting_ability = #{sc_expected[:ability].inspect} (PHB)" do
          got = rule.dig(:spellcasting, :casting_ability)
          expect(got.to_s.upcase).to eq(sc_expected[:ability]),
            "#{klass_id}: PHB diz #{sc_expected[:ability]}, código tem #{got.inspect}.\n" \
            "  Bug clássico: cast ability errada → CD de magia errada → ficha sem dano correto."
        end

        it "spellcasting.preparation = #{sc_expected[:preparation].inspect}" do
          got = rule.dig(:spellcasting, :preparation)
          expect(got.to_s).to eq(sc_expected[:preparation]),
            "#{klass_id}: PHB diz preparation #{sc_expected[:preparation].inspect}, " \
            "código tem #{got.inspect}"
        end

        it "spellcasting.cantrips_known_at_1 = #{sc_expected[:cantrips_known_at_1].inspect}" do
          got = rule.dig(:spellcasting, :cantrips_known_at_1)
          expect(got.to_i).to eq(sc_expected[:cantrips_known_at_1].to_i),
            "#{klass_id}: PHB diz #{sc_expected[:cantrips_known_at_1]} truques no nv 1, " \
            "código tem #{got.inspect}"
        end

        it "spellcasting.spells_known_at_1 = #{sc_expected[:spells_known_at_1].inspect}" do
          got = rule.dig(:spellcasting, :spells_known_at_1)
          # nil tolerado quando o valor canônico for nil (prepared casters).
          if sc_expected[:spells_known_at_1].nil?
            expect(got).to be_nil,
              "#{klass_id}: PHB diz spells_known_at_1=nil (prepared caster), código tem #{got.inspect}"
          else
            expect(got.to_i).to eq(sc_expected[:spells_known_at_1]),
              "#{klass_id}: PHB diz #{sc_expected[:spells_known_at_1]} magias conhecidas no nv 1, " \
              "código tem #{got.inspect}"
          end
        end

        it "spellcasting.list = #{sc_expected[:list].inspect}" do
          got = rule.dig(:spellcasting, :list)
          expect(got.to_s).to eq(sc_expected[:list]),
            "#{klass_id}: PHB diz list #{sc_expected[:list].inspect}, código tem #{got.inspect}"
        end
      end

      # ─── ASI levels ────────────────────────────────────────────────────────
      it "ASI levels = #{expected[:asi_levels].inspect}" do
        got = rule.dig(:feature_rules, :ability_score_improvement, :levels) ||
              rule.dig('feature_rules', 'ability_score_improvement', 'levels')
        expect(Array(got)).to eq(expected[:asi_levels]),
          "#{klass_id}: PHB diz ASI nos níveis #{expected[:asi_levels].inspect}, " \
          "código tem #{got.inspect}.\n" \
          "  Bug clássico: jogador chega no nv 6 (Guerreiro) e não recebe ASI extra."
      end

      # ─── Subclass choose level ─────────────────────────────────────────────
      # PHB: subclasse no nv 1 (Clérigo, Feiticeiro, Bruxo), nv 2 (Druida, Mago)
      # ou nv 3 (todos os outros). Bug clássico: trocar errado faz a UI pedir
      # subclasse no nível errado.
      it "subclass.choose_level = #{expected[:subclass_choose_level]}" do
        got = rule.dig(:subclass, :choose_level)
        expect(got).to eq(expected[:subclass_choose_level]),
          "#{klass_id}: PHB diz subclasse no nv #{expected[:subclass_choose_level]}, " \
          "código tem #{got.inspect}"
      end
    end
  end

  describe 'Audit cobertura completa' do
    it 'EXPECTED_BY_CLASS cobre as 12 classes do PHB' do
      expect(EXPECTED_BY_CLASS.size).to eq(12)
    end

    it 'CLASS_RULES contém pelo menos as 12 classes do PHB' do
      defined_ids = ClassRules::CLASS_RULES.keys.map(&:to_s).to_set
      missing = EXPECTED_BY_CLASS.keys.to_set - defined_ids
      expect(missing).to be_empty,
        "Classes PHB ausentes em ClassRules.CLASS_RULES: #{missing.to_a.inspect}"
    end
  end
end
