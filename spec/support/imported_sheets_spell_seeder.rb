# frozen_string_literal: true

# Phase 2.1.B — Seed minimal de Spell + ClassLevel + Spellcasting + SpellSource
# para destravar casters no test DB.
#
# O `LevelUpGuardService` (modo strict, default em RSpec) exige que cada
# `SheetKlass` de classe caster tenha contagem de `SheetKnownSpell` >=
# `Spellcasting#cantrips_known` e `>= spells_known` (quando definidos).
# Esses limites vêm de `ClassLevel` (preenchido normalmente por `dnd:import`).
#
# Aqui criamos:
#   1. Um POOL de Spells genéricas (8 cantrips + 30 leveled de 1..5)
#      compartilhado entre todas as classes casters via `SpellSource`.
#   2. ClassLevel + Spellcasting de level 1..20 para cada caster, usando a
#      tabela canônica PHB de cantrips_known / spells_known.
#
# O `LevelUpService#persist_known_spells!` em strict mode auto-completa do
# pool até atingir os limites, então as fichas de caster sobem sem precisar
# de input explícito de magias por nível.
module ImportedSheetsSpellSeeder
  module_function

  # Tabelas PHB (level 1..20). Usar nil quando a classe é "prepared" e o
  # campo não tem limite (cleric/druid/paladin/wizard tipicamente).
  PHB_SPELLCASTING = {
    'bard' => {
      cantrips:     [2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
      spells_known: [4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 15, 16, 18, 19, 19, 20, 22, 22, 22]
    },
    'cleric' => {
      cantrips:     [3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
      spells_known: nil
    },
    'druid' => {
      cantrips:     [2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
      spells_known: nil
    },
    'paladin' => {
      cantrips:     Array.new(20, 0),
      spells_known: nil
    },
    'ranger' => {
      cantrips:     Array.new(20, 0),
      spells_known: [0, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11]
    },
    'sorcerer' => {
      cantrips:     [4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
      spells_known: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15]
    },
    'warlock' => {
      cantrips:     [2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
      spells_known: [2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15]
    },
    'wizard' => {
      cantrips:     [3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
      # Wizard usa spellbook_progression (auto-completa via persist_known_spells!).
      # Mantemos `spells_known` nil pra não duplicar com o spellbook.
      spells_known: nil
    }
  }.freeze

  CASTER_KLASS_INDEXES = PHB_SPELLCASTING.keys.freeze

  def seed_all!
    # Phase 10 — guard duplo. Esses spells "RSpec Cantrip N" / "RSpec Spell L1
    # #N" sao FAKES de teste e ja vazaram para o dev DB uma vez (Bug 1 do
    # plano), fazendo a UI mostrar "RSpec Cantrip 6" no lugar do nome real.
    # Aqui rejeitamos qualquer execucao fora do test env como bug imediato.
    unless Rails.env.test?
      raise "ImportedSheetsSpellSeeder so pode rodar em Rails.env.test? (atual: #{Rails.env}). " \
            'Para limpar pool RSpec acidental do dev DB, use `bin/rake phase10:purge_rspec_spells`.'
    end

    seed_spell_pool!
    seed_classcasters!
  end

  # 8 cantrips + 30 spells leveled (6 por nível 1..5). API_index estável
  # para idempotência.
  def seed_spell_pool!
    @cantrip_ids = (1..8).map do |i|
      Spell.find_or_create_by!(api_index: "rspec-cantrip-#{i}") do |s|
        s.name  = "RSpec Cantrip #{i}"
        s.level = 0
      end.id
    end

    @leveled_ids = (1..5).flat_map do |lvl|
      (1..6).map do |i|
        Spell.find_or_create_by!(api_index: "rspec-spell-l#{lvl}-#{i}") do |s|
          s.name  = "RSpec Spell L#{lvl} ##{i}"
          s.level = lvl
        end.id
      end
    end
  end

  # Cria ClassLevel(level=1..20) + Spellcasting + SpellSource ligando o pool
  # a cada classe caster.
  def seed_classcasters!
    PHB_SPELLCASTING.each do |class_idx, table|
      klass = Klass.find_by(api_index: class_idx)
      next unless klass

      pool_ids = (Array(@cantrip_ids) + Array(@leveled_ids)).uniq
      pool_ids.each do |sid|
        SpellSource.find_or_create_by!(
          source_type: 'Klass',
          source_id:   klass.id,
          spell_id:    sid
        )
      end

      (1..20).each do |lvl|
        cl = ClassLevel.find_or_create_by!(klass_id: klass.id, level: lvl) do |c|
          c.prof_bonus = ((lvl - 1) / 4) + 2
        end
        # Spellcasting depende de class_level; recriar sob demanda.
        sc = cl.spellcasting || Spellcasting.new(class_level_id: cl.id, level: lvl)
        sc.cantrips_known = table[:cantrips][lvl - 1]
        sc.spells_known   = table[:spells_known] && table[:spells_known][lvl - 1]
        sc.save!
      end
    end
  end
end
