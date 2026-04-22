# frozen_string_literal: true

require 'rails_helper'

# Camada A — Loop 1: contrato de shape para TODOS os talentos catalogados.
# Antes de aplicar qualquer fix, este spec serve como "red baseline" — valida que
# `FeatRules.find` devolve `ability_bonuses` (e os outros campos jsonish) como
# Hash, nunca como String. Hoje, por causa do bug de serializacao Ruby-inspect
# em colunas `text` da tabela `feats`, esperamos que ele falhe para os 39 feats
# importados via `rake feats:import`.
#
# Estrategia data-driven: itera sobre `config/feats_improved.yml` (fonte canonica
# usada pelo import) para ter cobertura 1:1 com o catalogo real, sem manter lista
# duplicada no spec.
RSpec.describe FeatRules, 'shape integrity para todos os talentos do catalogo' do
  feats_yaml_path = Rails.root.join('config', 'feats_improved.yml')

  # Helper compartilhado: dado o YAML de um feat, gera choices minimas suficientes
  # para `FeatRules.apply` cobrir todos os caminhos `choose` que o feat declarar.
  # Mantido como modulo aqui (e nao em spec/support) ate o spec se estabilizar.
  def default_choices_for(yaml)
    choices = {}
    ab = yaml['ability_bonuses'] || {}
    pb = yaml['proficiency_bonuses'] || {}
    ca = yaml['cantrips'] || {}
    sp = yaml['spells'] || {}

    if ab.is_a?(Hash) && ab['choose'].is_a?(Hash)
      first = Array(ab['choose']['options']).first
      choices['ability'] = first if first
    end

    # Saving throws (Resiliente declara via special_rules; alguns YAMLs futuros
    # podem declarar via proficiency_bonuses.saving_throws.choose tambem).
    if pb.is_a?(Hash) && pb['saving_throws'].is_a?(Hash) && pb['saving_throws']['choose'].is_a?(Hash)
      first = Array(pb['saving_throws']['choose']['options']).first
      choices['saving_throws'] = first if first
    end

    # Skills genericas (FeatRules.apply le choices['proficiencies'] como skills).
    if pb.is_a?(Hash) && pb['choose'].is_a?(Hash)
      amount = pb['choose']['amount'].to_i.nonzero? || 1
      opts = Array(pb['choose']['options']).first(amount)
      choices['proficiencies'] = opts if opts.any?
    end

    if ca.is_a?(Hash) && ca['choose'].is_a?(Hash)
      amount = ca['choose']['amount'].to_i.nonzero? || 1
      choices['cantrips'] = Array.new(amount) { |i| "cantrip_default_#{i}" }
    end

    if sp.is_a?(Hash) && sp['choose'].is_a?(Hash)
      amount = sp['choose']['amount'].to_i.nonzero? || 1
      choices['spells'] = Array.new(amount) { |i| "spell_default_#{i}" }
    end

    choices
  end

  # Calcula o ability_bonuses esperado APOS .apply resolver o `choose`.
  # Espelha a logica de `FeatRules#apply` (linhas 829-833 atualmente):
  #   - se YAML declarar `ability_bonuses.choose` e a escolha foi feita,
  #     o resultado e `{ chosen_ability => amount }`.
  #   - se nao tem choose, mantem o Hash fixo declarado no YAML.
  #   - se o feat nao declara abilities, fica vazio.
  # Para feats onde o YAML omite ability_bonuses mas RULES estaticas declaram
  # (ex.: `sentinela`), `find()` retorna o valor de RULES — refletimos isso aqui
  # consultando `FeatRules::RULES[feat_id]` como fallback.
  def expected_resolved_ability_bonuses(yaml, choices, feat_id = nil)
    ab = yaml['ability_bonuses'] || {}
    if (!ab.is_a?(Hash) || ab.empty?) && feat_id
      static = FeatRules::RULES.dig(feat_id, :ability_bonuses)
      ab = static.deep_stringify_keys if static.is_a?(Hash) && static.any?
    end
    return {} unless ab.is_a?(Hash) && ab.any?

    if ab['choose'].is_a?(Hash) && choices['ability']
      { choices['ability'] => ab['choose']['amount'] }
    else
      ab
    end
  end

  if File.exist?(feats_yaml_path)
    catalog = YAML.load_file(feats_yaml_path).fetch('feats')

    # Roda o `rake feats:import` em memoria para garantir que estamos lendo do DB
    # da mesma forma que producao (e nao caindo no fallback `RULES` em memoria do
    # FeatRules). Sem isso, o spec ficaria green falsamente porque RULES tem dados
    # ja em formato Hash nativo.
    before(:all) do
      catalog.each do |api_index, data|
        Feat.find_or_create_by!(api_index: api_index) do |f|
          f.name = data['name']
          f.description = data['description']
          # IMPORTANTE: reproduzimos AQUI o mesmo bug do rake task — atribuir Hash
          # diretamente em coluna text. Isso garante que o spec exercite o caminho
          # corrompido. Quando a rake task for corrigida, este bloco do `before`
          # tambem sera atualizado para usar `.to_json` e a ordem natural se mantem.
          f.prerequisites       = data['prerequisites'] || {}
          f.ability_bonuses     = data['ability_bonuses'] || {}
          f.proficiency_bonuses = data['proficiency_bonuses'] || {}
          f.features            = data['features'] || {}
          f.cantrips            = data['cantrips'] || {}
          f.spells              = data['spells'] || {}
          f.special_rules       = data['special_rules'] || {}
        end
      end
    end

    catalog.each do |feat_id, yaml_data|
      describe "feat \"#{feat_id}\"" do
        let(:rule) { described_class.find(feat_id) }
        let(:yaml) { yaml_data }

        it 'esta presente no catalogo via FeatRules.find' do
          expect(rule).to be_a(Hash), "FeatRules.find('#{feat_id}') retornou #{rule.class}"
          expect(rule[:id] || rule['id']).to eq(feat_id)
        end

        # ── Loop 1: shape (Hash, nunca String) ────────────────────────────────
        it 'ability_bonuses e Hash (nao String corrompida)' do
          expect(rule[:ability_bonuses]).to be_a(Hash),
            "ability_bonuses esperado Hash, veio #{rule[:ability_bonuses].class}: #{rule[:ability_bonuses].inspect[0,120]}"
        end

        it 'proficiency_bonuses e Hash (nao String corrompida)' do
          expect(rule[:proficiency_bonuses]).to be_a(Hash),
            "proficiency_bonuses esperado Hash, veio #{rule[:proficiency_bonuses].class}: #{rule[:proficiency_bonuses].inspect[0,120]}"
        end

        it 'prerequisites e Hash (nao String corrompida)' do
          expect(rule[:prerequisites]).to be_a(Hash),
            "prerequisites esperado Hash, veio #{rule[:prerequisites].class}: #{rule[:prerequisites].inspect[0,120]}"
        end

        it 'features e Hash (nao String corrompida)' do
          expect(rule[:features]).to be_a(Hash),
            "features esperado Hash, veio #{rule[:features].class}: #{rule[:features].inspect[0,120]}"
        end

        # ── Loop 2: semantica (valor bate com a fonte da verdade efetiva) ────
        # `FeatRules.find` faz fallback gracioso: prioriza o DB (YAML), mas se o
        # YAML estiver vazio para um campo, cai para `RULES` estatico (codigo).
        # Esses specs validam essa fusao — o que importa e o que o RUNTIME ve,
        # nao apenas o YAML. Detectam corrupcao silenciosa quando o conteudo
        # veio Hash vazio mas a verdade efetiva (YAML ou RULES) e nao-vazia.
        # Eh exatamente o que motivou a investigacao do Observador.
        let(:static_rule) { FeatRules::RULES[feat_id] || {} }

        # Helper compartilhado: replica o `db.presence || static` do find().
        def effective_for(yaml_data, static_data, key)
          y = yaml_data[key.to_s]
          s = static_data[key.to_sym]
          chosen = if y.is_a?(Hash) && y.any?
                     y
                   elsif s.is_a?(Hash) && !s.empty?
                     s
                   else
                     y || s || {}
                   end
          (chosen.is_a?(Hash) ? chosen : {}).deep_stringify_keys
        end

        it 'ability_bonuses reflete fonte efetiva (YAML.presence || RULES)' do
          actual = (rule[:ability_bonuses].is_a?(Hash) ? rule[:ability_bonuses] : {}).deep_stringify_keys
          expected = effective_for(yaml, static_rule, :ability_bonuses)
          expect(actual).to eq(expected), "esperado #{expected.inspect}, veio #{actual.inspect}"
        end

        it 'proficiency_bonuses reflete fonte efetiva' do
          actual = (rule[:proficiency_bonuses].is_a?(Hash) ? rule[:proficiency_bonuses] : {}).deep_stringify_keys
          expected = effective_for(yaml, static_rule, :proficiency_bonuses)
          expect(actual).to eq(expected), "esperado #{expected.inspect}, veio #{actual.inspect}"
        end

        it 'prerequisites reflete fonte efetiva' do
          actual = (rule[:prerequisites].is_a?(Hash) ? rule[:prerequisites] : {}).deep_stringify_keys
          expected = effective_for(yaml, static_rule, :prerequisites)
          expect(actual).to eq(expected), "esperado #{expected.inspect}, veio #{actual.inspect}"
        end

        it 'features reflete fonte efetiva' do
          actual = (rule[:features].is_a?(Hash) ? rule[:features] : {}).deep_stringify_keys
          expected = effective_for(yaml, static_rule, :features)
          expect(actual).to eq(expected), "esperado #{expected.inspect}, veio #{actual.inspect}"
        end

        # ── Loop 3: .apply nao lanca para nenhum feat com choices minimas ─────
        # Reproduz o caminho exato que crasha em runtime hoje (o TypeError do
        # Adimael ao escolher Observador): `FeatRules.apply` faz `feat[:ability_bonuses][:choose]`
        # e quando `feat[:ability_bonuses]` veio como String corrompida, isso
        # vira `String#[]` com Symbol -> TypeError. Garantir que nao lanca e
        # o smoke test mais barato para "feat continua aplicavel".
        it '.apply(feat_id, default_choices) nao lanca exceptions' do
          choices = default_choices_for(yaml)
          begin
            described_class.apply(feat_id, choices)
          rescue StandardError => e
            raise e, "FeatRules.apply('#{feat_id}', #{choices.inspect}) lancou #{e.class}: #{e.message} — provavel String corrompida em ability_bonuses/proficiency_bonuses"
          end
        end

        # ── Loop 4: .apply resolve ability_bonuses corretamente ───────────────
        # Garantia semantica final: o objeto retornado por `.apply` carrega o
        # ability_bonuses APLICADO (nao o template). Cobertura:
        #   - feats fixos como Observador { wis:1, int:1 }
        #   - feats com choose como Atleta { ability:'str' } -> { str:1 }
        #   - feats sem ability como Mobilidade -> {}
        # Esta e a expectativa mais proxima do que o `CharacterSheetSummaryService`
        # vai consumir para somar nos atributos do personagem.
        it '.apply resolve ability_bonuses no shape esperado' do
          choices = default_choices_for(yaml)
          out = described_class.apply(feat_id, choices)
          actual   = (out[:ability_bonuses] || {}).deep_stringify_keys
          expected = expected_resolved_ability_bonuses(yaml, choices, feat_id).deep_stringify_keys
          expect(actual).to eq(expected),
            "esperado #{expected.inspect}, veio #{actual.inspect}"
        end
      end
    end
  else
    it 'config/feats_improved.yml nao encontrado — pula loop 1' do
      skip "Catalogo YAML ausente em #{feats_yaml_path}"
    end
  end
end
