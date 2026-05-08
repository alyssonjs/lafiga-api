# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Audit completo PHB × RaceRules — facetas estáticas das raças e sub-raças.
#
# Escopo: dados FIXOS por raça/sub-raça (não dependem de escolhas):
#   - size
#   - speed (em ft, conforme YAML)
#   - darkvision range
#   - ability increases (apenas as 'fixed'; tipos halfElf/variantHuman ficam
#     fora porque são escolha do jogador e cobertos por specs específicos).
#
# Houserules da campanha Lafiga (registradas em
# `~/.claude/projects/.../memory/lafiga_houserules_racas.md`):
#   - Tieflings: 3 sub-raças extras (não testadas vs PHB).
#   - Aarakocra: 3 sub-raças (falconicos, nocturnos, cypselanos) homebrew.
#   - Centauro: raça extra (Guildmaster's Guide), STR+2 WIS+1.
#   - Minotauro: raça extra, STR+2 CON+1.
# Essas raças entram em `HOUSERULE_RACES` e ficam fora do audit canônico.
#
# Mudanças no `EXPECTED_BY_RACE` exigem cruzar com o livro pt-BR
# (`docs/livro_do_jogador.txt`) — referência de página em cada entrada.
# ----------------------------------------------------------------------------
RSpec.describe 'RaceRules — facetas estáticas × PHB', type: :service do
  # RaceRules cacheia o YAML em memória; recarregar antes garante leitura
  # fresca após edits do dev (e isolamento entre testes que modifiquem o cache).
  before(:all) { RaceRules.reload! }

  EXPECTED_BY_RACE = {
    # Anão (PHB pg 18-20). Subraces: hill (WIS+1), mountain (STR+2).
    'dwarf' => {
      size: 'Médio',
      speed: 25,
      darkvision: 60,
      ability_fixed: { CON: 2 },
      languages: { always: %w[Comum Anão], choice_count: 0 },
      trait_keys_required: %w[dwarven_resilience stonecunning darkvision],
      subraces: {
        'hill'     => { ability_fixed: { WIS: 1 }, trait_keys_required: %w[dwarven_toughness] },
        'mountain' => { ability_fixed: { STR: 2 } }
      }
    },
    # Elfo (PHB pg 22-24). Subraces: high (INT+1), wood (WIS+1, speed 35),
    # drow (CHA+1, superior darkvision 120).
    'elf' => {
      size: 'Médio',
      speed: 30,
      darkvision: 60,
      ability_fixed: { DEX: 2 },
      languages: { always: %w[Comum Élfico], choice_count: 0 },
      trait_keys_required: %w[fey_ancestry trance keen_senses darkvision],
      subraces: {
        'high' => { ability_fixed: { INT: 1 }, trait_keys_required: %w[high_elf_cantrip] },
        'wood' => { ability_fixed: { WIS: 1 }, speed: 35, trait_keys_required: %w[fleet_of_foot mask_of_the_wild] },
        'drow' => { ability_fixed: { CHA: 1 }, darkvision: 120, trait_keys_required: %w[superior_darkvision sunlight_sensitivity drow_magic] }
      }
    },
    # Halfling (PHB pg 26-28). Size SMALL.
    'halfling' => {
      size: 'Pequeno',
      speed: 25,
      darkvision: nil, # Halfling não tem darkvision
      ability_fixed: { DEX: 2 },
      languages: { always: %w[Comum Halfling], choice_count: 0 },
      trait_keys_required: %w[lucky brave halfling_nimbleness],
      subraces: {
        'lightfoot' => { ability_fixed: { CHA: 1 }, trait_keys_required: %w[naturally_stealthy] },
        'stout'     => { ability_fixed: { CON: 1 } }
      }
    },
    # Humano (PHB pg 29-31). Padrão: +1 a TODOS. Variant: choose 2× +1 + skill
    # + feat — variantHuman é coberto por specs próprios (race_creation_*).
    'human' => {
      size: 'Médio',
      speed: 30,
      darkvision: nil,
      ability_fixed: { STR: 1, DEX: 1, CON: 1, INT: 1, WIS: 1, CHA: 1 },
      languages: { always: %w[Comum], choice_count: 1, choice_list_must_include: %w[Anão Élfico Halfling] }
    },
    # Draconato (PHB pg 32-34).
    'dragonborn' => {
      size: 'Médio',
      speed: 30,
      darkvision: nil,
      ability_fixed: { STR: 2, CHA: 1 },
      languages: { always: %w[Comum Dracônico], choice_count: 0 }
    },
    # Gnomo (PHB pg 35-37). SIZE PEQUENO! Subraces: forest (DEX+1), rock (CON+1).
    'gnome' => {
      size: 'Pequeno',
      speed: 25,
      darkvision: 60,
      ability_fixed: { INT: 2 },
      languages: { always: %w[Comum Gnômico], choice_count: 0 },
      trait_keys_required: %w[gnome_cunning darkvision],
      subraces: {
        'forest' => { ability_fixed: { DEX: 1 }, trait_keys_required: %w[minor_illusion_cantrip speak_with_small_beasts] },
        'rock'   => { ability_fixed: { CON: 1 }, trait_keys_required: %w[artificers_lore tinker] }
      }
    },
    # Meio-Elfo (PHB pg 38-39). Tipo halfElf (CHA+2 fixo + escolhe 2× +1) é
    # coberto por specs específicos. Aqui só asserta size/speed/darkvision.
    'half_elf' => {
      size: 'Médio',
      speed: 30,
      darkvision: 60,
      ability_fixed_partial: { CHA: 2 }, # parcial: parte é via choose
      languages: { always: %w[Comum Élfico], choice_count: 1 },
      trait_keys_required: %w[fey_ancestry darkvision skill_versatility]
    },
    # Meio-Orc (PHB pg 40-41).
    'half_orc' => {
      size: 'Médio',
      speed: 30,
      darkvision: 60,
      ability_fixed: { STR: 2, CON: 1 },
      languages: { always: %w[Comum Orc], choice_count: 0 },
      trait_keys_required: %w[relentless_endurance savage_attacks darkvision]
    },
    # Tiefling (PHB pg 42-43). Lafiga adiciona 3 sub-raças (memory
    # lafiga_houserules_racas.md) — só auditamos a raça base aqui.
    'tiefling' => {
      size: 'Médio',
      speed: 30,
      darkvision: 60,
      ability_fixed: { CHA: 2, INT: 1 },
      languages: { always: %w[Comum Infernal], choice_count: 0 }
    }
  }.freeze

  # Raças/sub-raças homebrew. NÃO entram no audit canônico — só registramos
  # para o spec de cobertura completa não falhar.
  HOUSERULE_RACES = %w[aarakocra centaur minotaur tabaxi].freeze

  EXPECTED_BY_RACE.each do |race_id, expected|
    describe "Raça '#{race_id}'" do
      let(:race) { RaceRules.find(race_id) }

      it 'está definida em RaceRules' do
        expect(race).to be_present, "RaceRules.find(#{race_id.inspect}) retornou nil"
      end

      it "size = #{expected[:size].inspect}" do
        size = race[:size] || race['size']
        expect(size.to_s).to eq(expected[:size]),
          "#{race_id}: PHB diz size #{expected[:size].inspect}, código tem #{size.inspect}"
      end

      it "speed = #{expected[:speed]}" do
        speed = race[:speed] || race['speed']
        expect(speed.to_i).to eq(expected[:speed]),
          "#{race_id}: PHB diz speed #{expected[:speed]}, código tem #{speed.inspect}"
      end

      it "darkvision = #{expected[:darkvision].inspect}" do
        dv = race[:darkvision] || race['darkvision']
        if expected[:darkvision].nil?
          # Raças sem darkvision: chave ausente, nil, ou Hash com range nulo/0.
          range = dv.is_a?(Hash) ? (dv[:range] || dv['range']).to_i : dv.to_i
          expect(range).to eq(0),
            "#{race_id}: PHB não dá darkvision, código tem #{dv.inspect}"
        else
          range = dv.is_a?(Hash) ? (dv[:range] || dv['range']).to_i : dv.to_i
          expect(range).to eq(expected[:darkvision]),
            "#{race_id}: PHB diz darkvision #{expected[:darkvision]} ft, código tem #{range.inspect}"
        end
      end

      # ─── Languages ─────────────────────────────────────────────────────────
      if expected[:languages]
        lang_expected = expected[:languages]

        it "languages.always = #{lang_expected[:always].inspect} (PHB)" do
          langs = race[:languages] || race['languages'] || {}
          got = Array(langs[:always] || langs['always']).map(&:to_s).to_set
          want = lang_expected[:always].to_set
          expect(got).to eq(want),
            "#{race_id}: PHB diz idiomas fixos #{want.to_a.sort.inspect}, " \
            "código tem #{got.to_a.sort.inspect}"
        end

        it "languages.choiceCount = #{lang_expected[:choice_count]}" do
          langs = race[:languages] || race['languages'] || {}
          got = (langs[:choiceCount] || langs['choiceCount']).to_i
          expect(got).to eq(lang_expected[:choice_count]),
            "#{race_id}: PHB diz choiceCount=#{lang_expected[:choice_count]}, " \
            "código tem #{got.inspect}"
        end

        if lang_expected[:choice_list_must_include]
          it 'choiceList inclui pelo menos os idiomas comuns do PHB' do
            langs = race[:languages] || race['languages'] || {}
            choice_list = Array(langs[:choiceList] || langs['choiceList']).map(&:to_s)
            missing = lang_expected[:choice_list_must_include] - choice_list
            expect(missing).to be_empty,
              "#{race_id}: choiceList faltando #{missing.inspect}.\n" \
              "  Veio: #{choice_list.inspect}"
          end
        end
      end

      # ─── Traits canônicos ──────────────────────────────────────────────────
      if expected[:trait_keys_required]
        it "traits incluem os canônicos do PHB: #{expected[:trait_keys_required].inspect}" do
          traits = Array(race[:traits] || race['traits'])
          got_keys = traits.map { |t| (t[:key] || t['key']).to_s }.to_set
          missing = expected[:trait_keys_required].reject { |k| got_keys.include?(k) }
          expect(missing).to be_empty,
            "#{race_id}: traits PHB ausentes: #{missing.inspect}.\n" \
            "  Veio (keys): #{got_keys.to_a.sort.inspect}\n" \
            "  Bug clássico: trait some no merge com sub-raça → ficha sem feature racial."
        end
      end

      if expected[:ability_fixed]
        it 'ability increases (fixed) batem com o PHB' do
          ab = race[:ability] || race['ability']
          expect(ab).to be_a(Hash), "#{race_id}: ability ausente"

          got = parse_fixed_increases(ab)
          want = expected[:ability_fixed].transform_keys(&:to_s)

          aggregate_failures do
            want.each do |attr, amount|
              expect(got[attr]).to eq(amount),
                "#{race_id}: PHB diz #{attr}+#{amount}, código tem #{attr}+#{got[attr].inspect}"
            end

            extras = got.reject { |k, v| want.key?(k) && want[k] == v }
            expect(extras).to be_empty,
              "#{race_id}: bonus EXTRAS além do PHB: #{extras.inspect}"
          end
        end
      elsif expected[:ability_fixed_partial]
        it 'ability fixo PARCIAL bate (resto é via choose)' do
          ab = race[:ability] || race['ability']
          got = parse_fixed_increases(ab)
          expected[:ability_fixed_partial].each do |attr, amount|
            expect(got[attr.to_s]).to eq(amount),
              "#{race_id}: parte fixa do PHB diz #{attr}+#{amount}, código tem #{attr}+#{got[attr.to_s].inspect}"
          end
        end
      end

      Array(expected[:subraces]).each do |sub_id, sub_expected|
        describe "subrace '#{sub_id}'" do
          let(:sub) do
            sr = race.dig(:subraces) || race.dig('subraces') || {}
            sr[sub_id.to_sym] || sr[sub_id]
          end

          it 'está definida' do
            expect(sub).to be_present, "subrace #{race_id}/#{sub_id} ausente"
          end

          if sub_expected[:speed]
            it "override de speed = #{sub_expected[:speed]}" do
              sp = sub[:speed] || sub['speed']
              expect(sp.to_i).to eq(sub_expected[:speed]),
                "#{race_id}/#{sub_id}: PHB diz speed #{sub_expected[:speed]}, código tem #{sp.inspect}"
            end
          end

          if sub_expected[:darkvision]
            it "override de darkvision = #{sub_expected[:darkvision]}" do
              dv = sub[:darkvision] || sub['darkvision']
              range = dv.is_a?(Hash) ? (dv[:range] || dv['range']).to_i : dv.to_i
              expect(range).to eq(sub_expected[:darkvision]),
                "#{race_id}/#{sub_id}: PHB diz darkvision #{sub_expected[:darkvision]}, código tem #{range.inspect}"
            end
          end

          if sub_expected[:ability_fixed]
            it 'ability increases (fixed) batem com o PHB' do
              ab = sub[:ability] || sub['ability']
              got = parse_fixed_increases(ab)
              sub_expected[:ability_fixed].each do |attr, amount|
                expect(got[attr.to_s]).to eq(amount),
                  "#{race_id}/#{sub_id}: PHB diz #{attr}+#{amount}, código tem #{attr}+#{got[attr.to_s].inspect}"
              end
            end
          end

          if sub_expected[:trait_keys_required]
            it "traits da sub-raça incluem #{sub_expected[:trait_keys_required].inspect}" do
              traits = Array(sub[:traits] || sub['traits'])
              got_keys = traits.map { |t| (t[:key] || t['key']).to_s }.to_set
              missing = sub_expected[:trait_keys_required].reject { |k| got_keys.include?(k) }
              expect(missing).to be_empty,
                "#{race_id}/#{sub_id}: traits PHB ausentes: #{missing.inspect}.\n" \
                "  Veio: #{got_keys.to_a.sort.inspect}"
            end
          end
        end
      end
    end
  end

  describe 'Audit cobertura completa' do
    it 'EXPECTED_BY_RACE cobre as 9 raças do PHB (anão, elfo, halfling, humano, draconato, gnomo, meio-elfo, meio-orc, tiefling)' do
      expect(EXPECTED_BY_RACE.size).to eq(9)
    end

    it 'RaceRules.RULES contém pelo menos as 9 raças PHB + as houserule registradas' do
      defined_ids = RaceRules.rules.keys.map(&:to_s).to_set
      missing_phb = EXPECTED_BY_RACE.keys.to_set - defined_ids
      expect(missing_phb).to be_empty,
        "Raças PHB ausentes em RaceRules: #{missing_phb.to_a.inspect}"

      missing_hr = HOUSERULE_RACES.to_set - defined_ids
      expect(missing_hr).to be_empty,
        "Houserules registradas mas ausentes do YAML: #{missing_hr.to_a.inspect}"
    end

    it 'raças desconhecidas (nem PHB nem houserule) têm spec próprio explicando' do
      defined_ids = RaceRules.rules.keys.map(&:to_s).to_set
      known = EXPECTED_BY_RACE.keys.to_set | HOUSERULE_RACES.to_set
      unknown = defined_ids - known
      expect(unknown).to be_empty,
        "Raças em RaceRules sem cobertura: #{unknown.to_a.inspect}.\n" \
        "  Adicionar em HOUSERULE_RACES (com nota da fonte) ou em EXPECTED_BY_RACE (PHB)."
    end
  end

  private

  # Extrai map { 'STR' => 1, 'CON' => 2, ... } a partir do `ability` do YAML.
  # Aceita formatos:
  #   { type: 'fixed', increases: [{ ability: 'STR', amount: 1 }, ...] }
  #   { type: 'halfElf', fixed: [{ ability: 'CHA', amount: 2 }], choose: {...} }
  def parse_fixed_increases(ability_hash)
    return {} unless ability_hash.is_a?(Hash)
    incs = ability_hash[:increases] || ability_hash['increases'] ||
           ability_hash[:fixed]     || ability_hash['fixed'] || []
    Array(incs).each_with_object({}) do |row, h|
      next unless row.is_a?(Hash)
      attr = (row[:ability] || row['ability']).to_s.upcase
      amt  = (row[:amount]  || row['amount']).to_i
      h[attr] = amt if attr.present?
    end
  end
end
