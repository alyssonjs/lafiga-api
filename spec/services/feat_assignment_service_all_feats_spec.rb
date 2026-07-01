# frozen_string_literal: true

require 'rails_helper'

# Camada A — Spec 2 (FeatAssignmentService): garante que TODOS os 41 talentos
# do catalogo conseguem ser atribuidos a uma Sheet sem corromper metadata.
#
# Diferenca chave vs feat_rules_all_feats_shape_spec.rb:
#   - Aquele bate em FeatRules.find/.apply (camada de regras pura, in-memory).
#   - Este aqui exercita o caminho COMPLETO de runtime: persiste Feat no DB,
#     cria SheetFeat, atualiza Sheet#metadata['feats'] — que e o ponto onde
#     hoje o `rescue StandardError` do FeatAssignmentService engole o TypeError
#     e zera silenciosamente `ability_bonuses`/`proficiency_bonuses`.
#
# Loop 1: smoke. `call` retorna resultado truthy (nao nil) para todos os feats,
#         dada uma sheet "uber" que satisfaz qualquer prerequisite (atributos
#         maximos, spellcasting flag em metadata, classe valida).
#
# Loop 2+ adicionarao expectativas semanticas (entry em metadata, valores).
RSpec.describe FeatAssignmentService, 'todos os 41 talentos do catalogo' do
  feats_yaml_path = Rails.root.join('config', 'feats_improved.yml')

  if File.exist?(feats_yaml_path)
    catalog = YAML.load_file(feats_yaml_path).fetch('feats')

    # Mesma estrategia do spec 1: alimentar a tabela `feats` reproduzindo o bug
    # da rake task (atribuir Hash em coluna text), para o spec exercitar o
    # caminho corrompido. Quando a rake for corrigida, este `before(:all)` deve
    # ser atualizado em uma operacao identica.
    before(:all) do
      catalog.each do |api_index, data|
        Feat.find_or_create_by!(api_index: api_index) do |f|
          f.name = data['name']
          f.description = data['description']
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

    # Helper compartilhado com feat_rules_all_feats_shape_spec.rb. Mantido
    # local por ora (extrair para spec/support/feat_choices_helper.rb se um
    # terceiro spec precisar).
    # Espelha o comportamento simplista de FeatRules.apply para proficiency_bonuses:
    #   - Se houver `choose` no topo, substitui por { 'skills' => choices['proficiencies'] }.
    #   - Caso contrario, devolve o hash cru do YAML (incluindo subhashes com `choose`).
    # Stringifica chaves para comparacao com metadata (que sai como JSON).
    def expected_resolved_proficiency_bonuses(yaml, choices)
      pb = yaml['proficiency_bonuses']
      return {} unless pb.is_a?(Hash)

      if pb['choose'].is_a?(Hash) && choices['proficiencies']
        return { 'skills' => Array(choices['proficiencies']) }
      end

      # D4 — `choose` ANINHADO por categoria (weapons/armors/tools/languages) é
      # resolvido por FeatRules.resolve_nested_proficiency_choice para um Array
      # plano lido de `choices[<categoria>]` (contrato flat do front). Espelhamos
      # essa resolução aqui (antes o spec esperava o sub-hash {choose:{...}} cru,
      # que era justamente o lixo que vazava na ficha).
      out = pb.deep_stringify_keys
      %w[weapons armor armors tools languages].each do |cat|
        block = out[cat]
        next unless block.is_a?(Hash) && block['choose'].is_a?(Hash)
        amount = block['choose']['amount'].to_i.nonzero? || 1
        picks = Array(choices[cat]).map(&:to_s).first(amount)
        out[cat] = picks
      end
      out
    end

    # Espelha expected_resolved_ability_bonuses do feat_rules_all_feats_shape_spec.
    # Resolve `choose` -> escolha simulada, mantendo bonuses fixos.
    # Normaliza chaves PT-BR ('for','des','sab','car') para EN porque
    # `CharacterSheetSummaryService#build_abilities` usa esse mapeamento ao somar
    # `metadata['feats'][n]['ability_bonuses']` em `abilities[:scores]` (str/dex/wis/cha).
    PT_TO_EN_ABILITY = { 'for' => 'str', 'des' => 'dex', 'con' => 'con',
                         'int' => 'int', 'sab' => 'wis', 'car' => 'cha' }.freeze

    def normalize_ability_key(k)
      key = k.to_s.downcase
      PT_TO_EN_ABILITY[key] || key
    end

    def expected_resolved_ability_bonuses(yaml, choices)
      ab = yaml['ability_bonuses']
      return {} unless ab.is_a?(Hash)

      resolved = {}
      ab.each do |k, v|
        next if k == 'choose'
        resolved[k] = v if v.is_a?(Numeric)
      end
      if ab['choose'].is_a?(Hash) && choices['ability']
        amount = ab['choose']['amount'].to_i.nonzero? || 1
        resolved[choices['ability']] = (resolved[choices['ability']] || 0) + amount
      end
      resolved
    end

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
      if pb.is_a?(Hash) && pb['saving_throws'].is_a?(Hash) && pb['saving_throws']['choose'].is_a?(Hash)
        first = Array(pb['saving_throws']['choose']['options']).first
        choices['saving_throws'] = first if first
      end
      if pb.is_a?(Hash) && pb['choose'].is_a?(Hash)
        amount = pb['choose']['amount'].to_i.nonzero? || 1
        opts = Array(pb['choose']['options']).first(amount)
        choices['proficiencies'] = opts if opts.any?
      end
      # D4 — picks por categoria flat (Especialista em Armas → choices['weapons']),
      # simulando o que o front envia para `choose` aninhado.
      if pb.is_a?(Hash)
        %w[weapons armor armors tools languages].each do |cat|
          block = pb[cat]
          next unless block.is_a?(Hash) && block['choose'].is_a?(Hash)
          amount = block['choose']['amount'].to_i.nonzero? || 1
          opts = Array(block['choose']['options']).first(amount)
          choices[cat] = opts if opts.any?
        end
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

    # Sheet "uber": atributos no maximo (passa qualquer ability_score >= N),
    # com class_summary marcando spellcasting (passa prereq de spellcaster),
    # e proficiencias amplas (passa qualquer requires armor/weapon/skill).
    # Cada example pega uma sheet fresca para nao acumular sheet_feats entre feats.
    def build_uber_sheet
      role = Role.find_or_create_by!(name: 'player')
      user = User.create!(
        email: "fas_#{SecureRandom.hex(4)}@example.com",
        username: "fas#{SecureRandom.hex(4)}",
        password: 'password1',
        password_confirmation: 'password1',
        role_id: role.id
      )
      character = Character.create!(user: user, name: 'Spec Uber', background: 'Test')
      race = Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
      sub_race = SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
      sheet = Sheet.create!(
        character: character,
        race: race, sub_race: sub_race,
        # Base 15 (não 20): satisfaz qualquer prereq de atributo (máx. 13) e ainda
        # deixa o +1 dos half-feats VISÍVEL sem esbarrar no teto 20 (F6). Antes,
        # com base 20, o teste esperava 21 — comportamento que o cap agora proíbe.
        str: 15, dex: 15, con: 15, int: 15, wis: 15, cha: 15,
        hp_max: 100, hp_current: 100,
        metadata: {
          'class_summary' => {
            # Hash ao inves de string p/ nao quebrar ClassProfileService#dig (caminho legado).
            # A presence do hash satisfaz check_prerequisites(:spellcasting) tambem.
            'spellcasting' => { 'ability' => 'INT', 'preparation' => 'prepared' },
            'armor_proficiencies' => ['leve', 'média', 'pesada'],
            'weapon_proficiencies' => ['arma_simples', 'arma_marcial'],
            'skills' => ['Atletismo', 'Investigação', 'Percepção'],
            'tools' => []
          }
        }
      )
      klass = Klass.find_or_create_by!(api_index: 'wizard') do |k|
        k.name = 'Mago'
        k.hit_die = 6
        k.subclass_level = 2
      end
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      sheet
    end

    catalog.each do |feat_id, yaml_data|
      describe "feat \"#{feat_id}\"" do
        let(:sheet)   { build_uber_sheet }
        let(:choices) { default_choices_for(yaml_data) }

        it '.call retorna resultado truthy (assignment bem-sucedido)' do
          result = described_class.call(
            sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices
          )
          # SimpleCommand devolve o `result` direto (nil em failure); errors fica no .errors do command.
          expect(result).to be_present,
            "FeatAssignmentService.call('#{feat_id}', choices=#{choices.inspect}) devolveu nil"
        end

        it 'persiste entrada em metadata["feats"] com ability_bonuses resolvidos' do
          described_class.call(
            sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices
          )

          feats_md = sheet.reload.metadata['feats']
          expect(feats_md).to be_a(Array),
            "metadata['feats'] deveria ser Array, veio #{feats_md.inspect}"

          entry = feats_md.find { |f| f['feat_id'] == feat_id }
          expect(entry).to be_present,
            "metadata['feats'] nao contem entry para '#{feat_id}': #{feats_md.inspect}"

          expected_ab = expected_resolved_ability_bonuses(yaml_data, choices)

          # So checa quando o YAML realmente define bonuses (skip vazio == vazio).
          if expected_ab.any?
            actual_ab = entry['ability_bonuses'] || {}
            expect(actual_ab).to eq(expected_ab),
              "ability_bonuses persistido em metadata diverge.\n" \
              "  feat_id=#{feat_id}\n" \
              "  esperado (do YAML resolvido)=#{expected_ab.inspect}\n" \
              "  persistido em metadata['feats']=#{actual_ab.inspect}\n" \
              "  (suspeita: rescue silencioso engoliu TypeError de Hash#inspect string)"
          end
        end

        it 'CharacterSheetSummaryService nao quebra com este feat aplicado' do
          described_class.call(
            sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices
          )

          cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
          summary = cmd.respond_to?(:result) ? cmd.result : cmd

          expect(summary).to be_present,
            "CharacterSheetSummaryService retornou nil para feat '#{feat_id}'.\n" \
            "  errors=#{cmd.try(:errors)&.full_messages.inspect}\n" \
            "  (impacto: ficha do personagem com este feat retorna 500/vazio)"
        end

        it 'CharacterSheetSummaryService reflete ability_bonuses do feat em abilities[:scores]' do
          # Feats sem ability_bonuses no YAML nao tem nada a checar aqui.
          expected_ab = expected_resolved_ability_bonuses(yaml_data, choices)
          skip "feat '#{feat_id}' nao define ability_bonuses no YAML" if expected_ab.empty?

          base_scores = { str: sheet.str, dex: sheet.dex, con: sheet.con,
                          int: sheet.int, wis: sheet.wis, cha: sheet.cha }

          described_class.call(
            sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices
          )

          cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
          summary = cmd.respond_to?(:result) ? cmd.result : cmd
          expect(summary).to be_present,
            "CharacterSheetSummaryService retornou nil. errors=#{cmd.try(:errors)&.full_messages.inspect} (impacto: ficha 500/vazia)"

          actual_scores = summary[:abilities][:scores]
          expected_ab.each do |ab_key, bonus|
            sym = normalize_ability_key(ab_key).to_sym
            expected_total = base_scores[sym].to_i + bonus.to_i
            actual_total = actual_scores[sym].to_i
            expect(actual_total).to eq(expected_total),
              "abilities[:scores][:#{sym}] nao reflete bonus do feat.\n" \
              "  feat_id=#{feat_id}\n" \
              "  YAML key=#{ab_key} -> normalizada=#{sym}\n" \
              "  base=#{base_scores[sym]} + bonus=#{bonus} esperado=#{expected_total}\n" \
              "  obtido=#{actual_total}\n" \
              "  (impacto: ficha mostra atributo errado por causa de metadata['feats'] zerado)"
          end
        end

        it 'persiste entrada em metadata["feats"] com proficiency_bonuses resolvidos' do
          described_class.call(
            sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices
          )

          feats_md = sheet.reload.metadata['feats']
          entry = (feats_md || []).find { |f| f['feat_id'] == feat_id }
          expect(entry).to be_present,
            "metadata['feats'] sem entry para '#{feat_id}'"

          expected_pb = expected_resolved_proficiency_bonuses(yaml_data, choices)

          if expected_pb.any?
            actual_pb = entry['proficiency_bonuses'] || {}
            expect(actual_pb).to eq(expected_pb),
              "proficiency_bonuses persistido em metadata diverge.\n" \
              "  feat_id=#{feat_id}\n" \
              "  esperado (do YAML resolvido)=#{expected_pb.inspect}\n" \
              "  persistido em metadata['feats']=#{actual_pb.inspect}\n" \
              "  (suspeita: rescue silencioso engoliu TypeError de Hash#inspect string)"
          end
        end
      end
    end
  else
    it 'config/feats_improved.yml nao encontrado — pula' do
      skip "Catalogo YAML ausente em #{feats_yaml_path}"
    end
  end
end
