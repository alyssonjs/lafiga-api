# frozen_string_literal: true

require 'rails_helper'

# Specs de baseline para LevelUpGuardService — captura o comportamento atual
# antes da implementação dos Kits 1-4. Qualquer mudança aqui requer revisão
# explícita.
#
# Cenários cobertos:
#   1. Early returns (sem klass / level 0)
#   2. Subclasse obrigatória no threshold
#   3. required_choices_at_level: presença e quantidade
#   4. Skill proficiencies (nv 1)
#   5. Instrument proficiencies (nv 1)
#   6. Warlock invocations: limite por nível e pré-requisitos
RSpec.describe LevelUpGuardService do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "guard_#{SecureRandom.hex(4)}@example.com",
      username: "guard#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end
  let(:race) { Race.create!(name: "Race#{SecureRandom.hex(4)}", api_index: "race_#{SecureRandom.hex(4)}") }
  let(:sub_race) { SubRace.create!(race: race, name: 'Padrão', api_index: "sub_#{SecureRandom.hex(4)}") }
  let(:character) { Character.create!(user: user, name: "PC#{SecureRandom.hex(4)}", background: 'spec') }

  def make_sheet(metadata: {}, level: 1)
    sheet = Sheet.create!(
      character: character,
      race: race,
      sub_race: sub_race,
      str: 14, dex: 14, con: 14, int: 12, wis: 12, cha: 14,
      hp_max: 10, hp_current: 10, temp_hp: 0,
      metadata: metadata,
      race_summary: {},
      class_summary: {},
      background_summary: {}
    )
    sheet
  end

  # ---------------------------------------------------------
  describe 'early returns' do
    it 'returns true when sheet has no SheetKlass for the given klass' do
      sheet = make_sheet
      klass = Klass.find_or_create_by!(api_index: 'sorcerer') { |k| k.name = 'Feiticeiro'; k.hit_die = 6; k.subclass_level = 1 }
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.success?).to be(true)
    end

    # SheetKlass valida level >= 1, então o early-return de level<=0 do guard
    # nunca é exercido em prática — mantemos o teste comentado como contrato.
    #
    # it 'returns true when SheetKlass level is 0' — ver SheetKlass validation
  end

  # ---------------------------------------------------------
  describe 'required subclass at threshold' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'wizard') { |k| k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2 } }

    it 'fails when level >= subclass_level and no sub_klass and no metadata subclass_id' do
      sheet = make_sheet(metadata: {})
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.success?).to be(false)
      expect(result.errors.full_messages.join).to match(/Subclasse obrigat/)
    end

    it 'passes when subclass_id is set in metadata' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'subclass_id' => 99 } })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      # nota: pode falhar por outras coisas (skills, etc) mas NÃO pela subclasse
      expect(result.errors.full_messages.join).not_to match(/Subclasse obrigat/)
    end
  end

  # ---------------------------------------------------------
  describe 'required_choices_at_level — fighting_style' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 } }

    it 'Kit 1.fix-autochoice (strict default em test): fighting_style ausente FALHA o guard' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Atletismo Intimidação] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.success?).to be(false)
      expect(result.errors.full_messages.join).to match(/Estilo de Luta/i)
    end

    it 'Kit 1.fix-autochoice: emite Rails.logger.warn[autochoice-guard] quando preencheria' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Atletismo Intimidação] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      warn_msgs = []
      allow(Rails.logger).to receive(:warn) { |m| warn_msgs << m.to_s }
      LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(warn_msgs.any? { |m| m =~ /\[autochoice-guard\].*key=fighting_style.*klass=fighter.*level=1/ }).to be(true)
    end

    it 'Kit 1.fix-autochoice: non-strict toggle (ENV=false) preserva auto-fill legado' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Atletismo Intimidação] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      original = ENV['LAFIGA_STRICT_REQUIRED_CHOICES']
      ENV['LAFIGA_STRICT_REQUIRED_CHOICES'] = 'false'
      begin
        result = LevelUpGuardService.call(sheet: sheet, klass: klass)
        expect(result.errors.full_messages.join).not_to match(/Estilo de Luta/i)
      ensure
        ENV['LAFIGA_STRICT_REQUIRED_CHOICES'] = original
      end
    end

    it 'passes the fighting_style check when populated' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '1' => { 'skills' => %w[Atletismo Intimidação], 'fighting_style' => 'Defesa' }
          },
          'fighting_style' => 'Defesa'
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).not_to match(/Estilo de Luta/i)
    end
  end

  # ---------------------------------------------------------
  describe 'required_choices_at_level — metamagic (count)' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'sorcerer') { |k| k.name = 'Feiticeiro'; k.hit_die = 6; k.subclass_level = 1 } }

    it 'reporta quantidade quando less than choose count' do
      # nv 3 exige 2 metamágicas
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '3' => { 'metamagic' => ['Acelerar Magia'] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 3)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.any? { |m| m =~ /Metam/i && m =~ /1.*de.*2|Faltam 1/i }).to be(true)
    end

    it 'passes the metamagic check when 2 são fornecidas' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '3' => { 'metamagic' => ['Acelerar Magia', 'Estender Magia'] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 3)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).not_to match(/Metam/i)
    end

    it 'NOTA Kit 3 baseline: NÃO valida que escolha está no subset do catálogo' do
      # Mesmo "Magia Cuidadosa" (nome do front, ∉ canon backend) passa hoje
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '3' => { 'metamagic' => ['Magia Cuidadosa', 'Magia Distante'] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 3)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      # baseline: NÃO há erro de subset → será adicionado em Kit 3
      expect(result.errors.full_messages.join).not_to match(/Metam/i)
    end
  end

  # ---------------------------------------------------------
  describe 'skill_proficiencies (nv 1)' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'rogue') { |k| k.name = 'Ladino'; k.hit_die = 8; k.subclass_level = 3 } }

    it 'fails when escolheu menos perícias que o exigido' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Furtividade] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).to match(/per[ií]cias/i)
    end
  end

  # ---------------------------------------------------------
  describe 'instrument_proficiencies (Bardo nv 1)' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'bard') { |k| k.name = 'Bardo'; k.hit_die = 8; k.subclass_level = 3 } }

    it 'fails when bardo nv 1 sem instrumentos' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Atuação Persuasão História] } }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).to match(/instrumento/i)
    end

    it 'passes the instrument check when fornecidos' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => { '1' => { 'skills' => %w[Atuação Persuasão História] } },
          'instruments_selected' => %w[Alaúde Flauta Tambor]
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).not_to match(/instrumento/i)
    end
  end

  # ---------------------------------------------------------
  # Kit 3 — Subset Validator
  #
  # Novos specs cobrindo `validate_options_subset!` opt-in:
  #   - sem flag → comportamento legado preservado (não valida subset)
  #   - flag + Array<String> + escolha válida → pass
  #   - flag + Array<String> + escolha inválida → fail
  #   - flag + Array<Hash> + escolha válida (matched by slug) → pass
  #   - flag + Symbol resolvido via dictionaries → pass/fail correto
  describe 'subset validation (Kit 3 opt-in)' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'sorcerer') { |k| k.name = 'Feiticeiro'; k.hit_die = 6; k.subclass_level = 1 } }

    let(:rule_with_subset_array_string) do
      {
        skill_proficiencies: { choose: 0 },
        required_choices_at_level: {
          3 => {
            metamagic: {
              choose: 1,
              options: ['Acelerar Magia', 'Estender Magia'],
              validate_subset: true
            }
          }
        }
      }
    end

    let(:rule_with_subset_array_hash) do
      {
        skill_proficiencies: { choose: 0 },
        required_choices_at_level: {
          3 => {
            metamagic: {
              choose: 1,
              options: [
                { 'slug' => 'mm-careful',  'name' => 'Magia Cuidadosa' },
                { 'slug' => 'mm-distant',  'name' => 'Magia Distante' }
              ],
              validate_subset: true
            }
          }
        }
      }
    end

    let(:rule_with_subset_symbol) do
      {
        skill_proficiencies: { choose: 0 },
        required_choices_at_level: {
          2 => {
            invocations: {
              choose: 1,
              options: :invocations_core, # resolved via dictionaries (Array<String> EN)
              validate_subset: true
            }
          }
        }
      }
    end

    let(:rule_without_subset) do
      {
        skill_proficiencies: { choose: 0 },
        required_choices_at_level: {
          3 => {
            metamagic: {
              choose: 1,
              options: ['Acelerar Magia', 'Estender Magia']
              # validate_subset não setado → legado, não valida
            }
          }
        }
      }
    end

    def call_guard_with_rule(sheet, level:, rule:)
      SheetKlass.create!(sheet: sheet, klass: klass, level: level)
      allow(ClassRules).to receive(:find).with('sorcerer').and_return(rule)
      LevelUpGuardService.call(sheet: sheet, klass: klass)
    end

    it 'sem flag: aceita qualquer string mesmo fora do options (legado preservado)' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => ['Magia Cuidadosa'] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_without_subset)
      expect(result.errors.full_messages.join).not_to match(/inv[áa]lida/i)
    end

    it 'com flag + Array<String>: aceita escolha que está em options' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => ['Acelerar Magia'] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_with_subset_array_string)
      expect(result.errors.full_messages.join).not_to match(/inv[áa]lida/i)
    end

    it 'com flag + Array<String>: rejeita escolha fora de options' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => ['Magia Cuidadosa'] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_with_subset_array_string)
      expect(result.errors.full_messages.join).to match(/inv[áa]lida.*Magia Cuidadosa/i)
      expect(result.errors.full_messages.join).to match(/Permitidas:.*Acelerar Magia/i)
    end

    it 'com flag + Array<Hash>: aceita escolha que matche slug' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => ['mm-careful'] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_with_subset_array_hash)
      expect(result.errors.full_messages.join).not_to match(/inv[áa]lida/i)
    end

    it 'com flag + Array<Hash>: rejeita slug fora do catálogo' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => ['mm-empowered'] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_with_subset_array_hash)
      expect(result.errors.full_messages.join).to match(/inv[áa]lida.*mm-empowered/i)
    end

    it 'com flag + Array<Hash>: aceita choice em formato Hash com slug' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '3' => { 'metamagic' => [{ 'slug' => 'mm-distant', 'name' => 'Magia Distante' }] } } } })
      result = call_guard_with_rule(sheet, level: 3, rule: rule_with_subset_array_hash)
      expect(result.errors.full_messages.join).not_to match(/inv[áa]lida/i)
    end

    it 'com flag + Symbol :invocations_core: aceita Devil\'s Sight (em dictionaries EN)' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '2' => { 'invocations' => ["Devil's Sight"] } } } })
      result = call_guard_with_rule(sheet, level: 2, rule: rule_with_subset_symbol)
      expect(result.errors.full_messages.join).not_to match(/inv[áa]lida/i)
    end

    it 'com flag + Symbol :invocations_core: rejeita PT (Visão do Demônio ∉ dict EN)' do
      sheet = make_sheet(metadata: { 'class_choices' => { 'per_level' => { '2' => { 'invocations' => ['Visão do Demônio'] } } } })
      result = call_guard_with_rule(sheet, level: 2, rule: rule_with_subset_symbol)
      expect(result.errors.full_messages.join).to match(/inv[áa]lida.*Vis[ãa]o do Dem[ôo]nio/i)
    end
  end

  # ---------------------------------------------------------
  describe 'warlock invocations — limite e pré-requisitos' do
    let(:klass) { Klass.find_or_create_by!(api_index: 'warlock') { |k| k.name = 'Bruxo'; k.hit_die = 8; k.subclass_level = 1 } }

    it 'fails when invocações excedem o limite por nível' do
      # nv 2 → 2 invocações; passar 5 deve falhar
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => {
              'invocations' => [
                "Devil's Sight", 'Eldritch Sight', 'Mask of Many Faces',
                'Beast Speech', 'Fiendish Vigor'
              ]
            }
          }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).to match(/Invoca|m[áa]ximo/i)
    end

    it 'fails when Agonizing Blast (EN) escolhida sem Eldritch Blast cantrip' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => { 'invocations' => ['Agonizing Blast', "Devil's Sight"] }
          }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      # Kit 1.invocations: erro usa name_pt do catálogo
      expect(result.errors.full_messages.join).to match(/Explos[ãa]o Ag[oô]nica.*Eldritch Blast/i)
    end

    # Kit 1.invocations: invocações enviadas em PT (front) ou via slug (`ei-*`)
    # AGORA são validadas via catálogo canônico (eldritch_invocations.yml).
    it 'fails when Explosão Agônica (PT) escolhida sem Eldritch Blast cantrip — Kit 1.invocations' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => { 'invocations' => ['Explosão Agônica', 'Visão do Demônio'] }
          }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).to match(/Explos[ãa]o Ag[oô]nica.*Eldritch Blast/i)
    end

    it 'fails when ei-agonizing-blast (slug) escolhida sem Eldritch Blast — Kit 1.invocations' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => { 'invocations' => ['ei-agonizing-blast', 'ei-devils-sight'] }
          }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      expect(result.errors.full_messages.join).to match(/Explos[ãa]o Ag[oô]nica.*Eldritch Blast/i)
    end

    # ---------------------------------------------------------
    # Kit 1.maneuvers — Battle Master maneuvers via catálogo canônico
    describe 'fighter Battle Master maneuvers — Kit 1.maneuvers' do
      let(:fighter) do
        Klass.find_or_create_by!(api_index: 'fighter') do |k|
          k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
        end
      end
      let(:battlemaster) do
        SubKlass.find_or_create_by!(klass: fighter, api_index: 'battlemaster') do |sk|
          sk.name = 'Mestre de Batalha'
        end
      end

      it 'fails when more maneuvers chosen than allowed at level 3 (max 3)' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'maneuvers' => %w[mn-parry mn-riposte mn-trip-attack mn-precision-attack] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: fighter, sub_klass: battlemaster, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: fighter)
        expect(result.errors.full_messages.join).to match(/Manobras.*m[áa]ximo 3/i)
      end

      it 'fails when an unknown maneuver slug is chosen (not in catalog)' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'maneuvers' => %w[mn-parry mn-riposte mn-fake-one] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: fighter, sub_klass: battlemaster, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: fighter)
        expect(result.errors.full_messages.join).to match(/Manobra desconhecida.*mn-fake-one/i)
      end

      it 'accepts maneuver chosen by name_pt (alias resolution)' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'maneuvers' => ['Aparar', 'Riposte', 'Ataque Preciso'] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: fighter, sub_klass: battlemaster, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: fighter)
        # Pode falhar por outras razões (cantrips, etc.) mas NÃO deve haver erro de manobras.
        expect(result.errors.full_messages.join).not_to match(/Manobra/)
      end

      it 'does not validate maneuvers for non-Battle-Master fighter (Champion)' do
        champion = SubKlass.find_or_create_by!(klass: fighter, api_index: 'champion') do |sk|
          sk.name = 'Campeão'
        end
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'maneuvers' => %w[mn-parry mn-riposte mn-trip-attack mn-precision-attack] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: fighter, sub_klass: champion, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: fighter)
        expect(result.errors.full_messages.join).not_to match(/Manobra/)
      end
    end

    # ---------------------------------------------------------
    # Kit 1.disciplines — Monk Way of the Four Elements via catálogo canônico
    describe 'monk Way of the Four Elements disciplines — Kit 1.disciplines' do
      let(:monk) do
        Klass.find_or_create_by!(api_index: 'monk') do |k|
          k.name = 'Monge'; k.hit_die = 8; k.subclass_level = 3
        end
      end
      let(:four_elements) do
        SubKlass.find_or_create_by!(klass: monk, api_index: 'four_elements') do |sk|
          sk.name = 'Caminho dos Quatro Elementos'
        end
      end

      it 'fails when more than 1 discipline chosen at level 3' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'disciplines' => %w[ed-water-whip ed-fangs-of-fire-snake] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: monk, sub_klass: four_elements, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: monk)
        expect(result.errors.full_messages.join).to match(/Disciplinas.*m[áa]ximo 1/i)
      end

      it 'fails when level-6 discipline chosen at level 3' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'disciplines' => %w[ed-flames-of-phoenix] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: monk, sub_klass: four_elements, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: monk)
        expect(result.errors.full_messages.join).to match(/Chamas.*F[êe]nix.*n[íi]vel 6/i)
      end

      it 'fails when an unknown discipline slug is chosen' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'disciplines' => %w[ed-fake-one] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: monk, sub_klass: four_elements, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: monk)
        expect(result.errors.full_messages.join).to match(/Disciplina desconhecida.*ed-fake-one/i)
      end

      it 'accepts discipline by name_pt (alias resolution)' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'disciplines' => ['Chicote de Água'] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: monk, sub_klass: four_elements, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: monk)
        expect(result.errors.full_messages.join).not_to match(/Disciplina/)
      end

      it 'does not validate disciplines for non-Four-Elements monk (Open Hand)' do
        open_hand = SubKlass.find_or_create_by!(klass: monk, api_index: 'open_hand') do |sk|
          sk.name = 'Caminho da Mão Aberta'
        end
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'disciplines' => %w[ed-water-whip ed-fangs-of-fire-snake ed-flames-of-phoenix] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: monk, sub_klass: open_hand, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: monk)
        expect(result.errors.full_messages.join).not_to match(/Disciplina/)
      end
    end

    # ---------------------------------------------------------
    # Kit 1.snacks — Cozinheiro (Cook): catálogo + count + subclass gating
    describe 'cozinheiro snacks — Kit 1.snacks' do
      let(:cook) do
        Klass.find_or_create_by!(api_index: 'cozinheiro') do |k|
          k.name = 'Cozinheiro'; k.hit_die = 8; k.subclass_level = 3
        end
      end
      let(:sous_chef) do
        SubKlass.find_or_create_by!(klass: cook, api_index: 'mestre-da-fritura') do |sk|
          sk.name = 'Mestre da Fritura'
        end
      end
      let(:doceiro) do
        SubKlass.find_or_create_by!(klass: cook, api_index: 'doceiro-encantado') do |sk|
          sk.name = 'Doceiro Encantado'
        end
      end

      it 'fails when more than 3 snacks chosen at level 1' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '1' => { 'snacks' => %w[
                cook-snack-corte-fresco cook-snack-cha-verde
                cook-snack-pao-duro cook-snack-cristais-de-acucar
              ] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, level: 1)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).to match(/Petiscos.*m[áa]ximo 3/i)
      end

      it 'fails when level-7 snack chosen at level 3' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'snacks' => %w[cook-snack-faisao-assado] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, sub_klass: sous_chef, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).to match(/Faisão Assado.*n[íi]vel 7/i)
      end

      it 'fails when subclass-locked snack is chosen with the wrong subclass' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'snacks' => %w[cook-snack-uvas-cristalizadas] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, sub_klass: doceiro, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).to match(/Uvas Cristalizadas.*requer subclasse mestre-da-fritura/i)
      end

      it 'accepts subclass-locked snack with the correct subclass' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '3' => { 'snacks' => %w[cook-snack-uvas-cristalizadas] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, sub_klass: sous_chef, level: 3)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).not_to match(/Petisco|Petiscos/)
      end

      it 'fails when an unknown snack slug is chosen' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '1' => { 'snacks' => %w[cook-snack-fake-one] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, level: 1)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).to match(/Petisco desconhecido.*cook-snack-fake-one/i)
      end

      it 'accepts snack chosen by name_pt (alias resolution)' do
        sheet = make_sheet(metadata: {
          'class_choices' => {
            'per_level' => {
              '1' => { 'snacks' => ['Corte Fresco'] }
            }
          }
        })
        SheetKlass.create!(sheet: sheet, klass: cook, level: 1)
        result = LevelUpGuardService.call(sheet: sheet, klass: cook)
        expect(result.errors.full_messages.join).not_to match(/Petisco|Petiscos/)
      end
    end

    it 'fails when Thirsting Blade chosen at level 2 — requires level 5 + blade pact' do
      sheet = make_sheet(metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => { 'invocations' => ['ei-thirsting-blade', 'ei-devils-sight'] }
          }
        }
      })
      SheetKlass.create!(sheet: sheet, klass: klass, level: 2)
      result = LevelUpGuardService.call(sheet: sheet, klass: klass)
      msg = result.errors.full_messages.join
      expect(msg).to match(/Sede da L[âa]mina.*n[íi]vel 5/i).or match(/Sede da L[âa]mina.*Pacto/i)
    end
  end
end
