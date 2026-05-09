# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Audit cross-source: TODAS as referências a perícias no projeto devem usar
# nomes canônicos do `config/skills.yml` (single source of truth).
#
# Por que existe: bugs como Sage com `"Arcana"` (EN) em vez de `"Arcanismo"`
# (PT-BR canônico) e Patrulheiro com `Acrobacia` faltando aconteceram porque
# várias fontes (class_rules, background YAML, feat_rules.CANONICAL_SKILL_NAMES,
# front catalogs) tinham o conhecimento DUPLICADO sem validação cruzada.
#
# Este spec varre cada fonte e exige:
#   1. Toda skill referenciada existe em `config/skills.yml`.
#   2. `FeatRules::CANONICAL_SKILL_NAMES` == nomes do YAML (sem drift).
#   3. `ClassRules.skill_proficiencies.options` por classe é subconjunto.
#   4. `backgrounds_phb.yml` `starting_proficiencies.skills` é subconjunto.
#
# Falha aqui = você adicionou skill nova em algum lugar mas não em
# `config/skills.yml` (a fonte de verdade), OU divergiu o naming.
#
# Como adicionar skill nova:
#   a) Adicione em `config/skills.yml` PRIMEIRO.
#   b) Reload via `SkillsCatalog.reload!` (em produção; spec usa fresh load).
#   c) Use APENAS o nome canônico em qualquer outro lugar.
# ----------------------------------------------------------------------------
RSpec.describe 'Skills — consistência cross-source × config/skills.yml', type: :service do
  let(:canonical_names) do
    raw = YAML.safe_load(File.read(Rails.root.join('config', 'skills.yml')), aliases: true) || {}
    Array(raw['skills']).map { |s| s['name'].to_s }.to_set
  end

  let(:canonical_ids) do
    raw = YAML.safe_load(File.read(Rails.root.join('config', 'skills.yml')), aliases: true) || {}
    Array(raw['skills']).map { |s| s['id'].to_s }.to_set
  end

  describe 'config/skills.yml (single source of truth)' do
    it 'tem 18 skills (PHB 5e canônicos)' do
      expect(canonical_names.size).to eq(18),
        "PHB 5e tem 18 skills. config/skills.yml tem #{canonical_names.size}: #{canonical_names.to_a.sort.inspect}"
    end

    it 'cada skill tem id, name e ability' do
      raw = YAML.safe_load(File.read(Rails.root.join('config', 'skills.yml')), aliases: true) || {}
      skills = Array(raw['skills'])
      missing = skills.reject { |s| s['id'].present? && s['name'].present? && s['ability'].present? }
      expect(missing).to be_empty, "skills sem id/name/ability: #{missing.inspect}"
    end

    it 'ability é STR/DEX/CON/INT/WIS/CHA' do
      raw = YAML.safe_load(File.read(Rails.root.join('config', 'skills.yml')), aliases: true) || {}
      bad = Array(raw['skills']).reject { |s| %w[STR DEX CON INT WIS CHA].include?(s['ability'].to_s) }
      expect(bad).to be_empty, "skills com ability não-canônico: #{bad.inspect}"
    end
  end

  describe 'FeatRules::CANONICAL_SKILL_NAMES (constante)' do
    it 'contém EXATAMENTE os mesmos nomes de config/skills.yml' do
      const = FeatRules::CANONICAL_SKILL_NAMES.to_set
      missing = canonical_names - const
      extra   = const - canonical_names

      aggregate_failures do
        expect(missing).to be_empty,
          "FeatRules::CANONICAL_SKILL_NAMES está SEM #{missing.to_a.inspect} (que está em skills.yml).\n" \
          "  Adicionar a constante OU remover do YAML."
        expect(extra).to be_empty,
          "FeatRules::CANONICAL_SKILL_NAMES tem nomes EXTRAS além de skills.yml: #{extra.to_a.inspect}.\n" \
          "  Hardcoded fora da fonte canônica — bug de drift potencial."
      end
    end
  end

  describe 'ClassRules.skill_proficiencies.options (12 classes PHB)' do
    %w[barbarian bard cleric druid fighter monk paladin ranger rogue sorcerer warlock wizard].each do |klass_id|
      it "#{klass_id}: todas as opções estão em config/skills.yml" do
        rule = ClassRules::CLASS_RULES.fetch(klass_id.to_sym)
        sp = rule[:skill_proficiencies] || {}
        options = sp[:options]
        # Bardo usa :any (qualquer skill); pulamos a verificação aqui — o
        # próprio fato de ser :any já implica universo == skills.yml.
        next if options == :any

        unknown = Array(options).map(&:to_s).reject { |s| canonical_names.include?(s) }
        expect(unknown).to be_empty,
          "#{klass_id} tem skills divergentes de config/skills.yml: #{unknown.inspect}.\n" \
          "  Padrão histórico: typo (\"Arcana\" vs \"Arcanismo\") ou EN→PT incompleto."
      end
    end
  end

  describe 'backgrounds_phb.yml (13 antecedentes PHB)' do
    let(:bg_yaml) do
      YAML.safe_load(File.read(Rails.root.join('config', 'backgrounds_phb.yml')))['backgrounds']
    end

    it 'cada background usa apenas skills de config/skills.yml' do
      offenders = {}
      bg_yaml.each do |bg_id, bg|
        skills = Array(bg.dig('starting_proficiencies', 'skills')).map(&:to_s)
        unknown = skills.reject { |s| canonical_names.include?(s) }
        offenders[bg_id] = unknown if unknown.any?
      end
      expect(offenders).to be_empty,
        "Backgrounds com skills divergentes:\n#{offenders.map { |k, v| "  #{k}: #{v.inspect}" }.join("\n")}\n" \
        "  Esse foi o bug do Sage (Arcana vs Arcanismo). NÃO usar nomes EN."
    end
  end

  describe 'race_rules.yml — fixed skills' do
    let(:race_yaml) do
      YAML.safe_load(File.read(Rails.root.join('config', 'race_rules.yml')))
    end

    it 'race.proficiencies.skills.fixed usa apenas nomes canônicos' do
      offenders = {}
      race_yaml.each do |race_id, race|
        next unless race.is_a?(Hash)
        fixed = race.dig('proficiencies', 'skills', 'fixed') ||
                race.dig('proficiencies', 'skills') # casos onde 'skills' é Array direto
        next unless fixed.is_a?(Array)
        unknown = fixed.map(&:to_s).reject { |s| canonical_names.include?(s) }
        offenders[race_id] = unknown if unknown.any?

        # Sub-raças
        Array(race['subraces']).each do |sub_id, sub|
          next unless sub.is_a?(Hash)
          sub_fixed = sub.dig('proficiencies', 'skills', 'fixed') ||
                      sub.dig('proficiencies', 'skills')
          next unless sub_fixed.is_a?(Array)
          sub_unknown = sub_fixed.map(&:to_s).reject { |s| canonical_names.include?(s) }
          offenders["#{race_id}/#{sub_id}"] = sub_unknown if sub_unknown.any?
        end
      end
      expect(offenders).to be_empty,
        "Raças/sub-raças com skills divergentes:\n#{offenders.map { |k, v| "  #{k}: #{v.inspect}" }.join("\n")}"
    end

    it 'race.proficiencies.skills.choices (lista de escolha) usa apenas nomes canônicos' do
      offenders = {}
      race_yaml.each do |race_id, race|
        next unless race.is_a?(Hash)
        choices = race.dig('proficiencies', 'skills', 'choices')
        next unless choices.is_a?(Array)
        unknown = choices.map(&:to_s).reject { |s| canonical_names.include?(s) }
        offenders[race_id] = unknown if unknown.any?
      end
      expect(offenders).to be_empty,
        "Raças com choices.skills divergentes:\n#{offenders.map { |k, v| "  #{k}: #{v.inspect}" }.join("\n")}"
    end
  end

  describe 'SkillsCatalog (wrapper) coerência' do
    it 'SkillsCatalog.all carrega os mesmos nomes do YAML' do
      SkillsCatalog.reload!
      catalog_names = SkillsCatalog.all.map { |s| s[:name] }.to_set
      expect(catalog_names).to eq(canonical_names),
        "SkillsCatalog.all desincronizou de skills.yml.\n" \
        "  Catalog: #{catalog_names.to_a.sort.inspect}\n" \
        "  YAML:    #{canonical_names.to_a.sort.inspect}"
    end

    it 'SkillsCatalog.find resolve por id e por nome (lookup bidirecional)' do
      SkillsCatalog.reload!
      sample = SkillsCatalog.all.first
      expect(SkillsCatalog.find(sample[:id])).to be_present
      expect(SkillsCatalog.find(sample[:name])).to be_present
      expect(SkillsCatalog.find(sample[:name].downcase)).to be_present
    end
  end

  describe 'Cross-check: feats que dão skill proficiency' do
    it 'feats com proficiency_bonuses.skills usam apenas nomes canônicos' do
      offenders = {}
      FeatRules::RULES.each do |feat_id, rule|
        skills = Array(rule.dig(:proficiency_bonuses, :skills) || rule.dig(:proficiency_bonuses, 'skills'))
        next if skills.empty?
        unknown = skills.map(&:to_s).reject { |s| canonical_names.include?(s) }
        offenders[feat_id] = unknown if unknown.any?
      end
      expect(offenders).to be_empty,
        "Feats com skills divergentes:\n#{offenders.map { |k, v| "  #{k}: #{v.inspect}" }.join("\n")}\n" \
        "  Ex.: Observador deve usar 'Percepção' (canônico), não 'Perception'."
    end
  end
end
