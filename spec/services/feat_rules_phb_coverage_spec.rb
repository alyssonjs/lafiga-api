# frozen_string_literal: true

require 'rails_helper'

# BDD: Cobertura completa de feats PHB no Ruby (`FeatRules::RULES`).
# -------------------------------------------------------------------
# Auditoria identificou 9 feats PHB que não estavam no Ruby:
#   - 2 ausentes em ambos (Ruby + YAML): Alerta, Mente Aguçada
#   - 7 só no YAML (`config/feats_improved.yml`), exigindo seed do DB
#     para funcionar: Ator, Investida Poderosa, Adepto Elemental,
#     Matador de Conjuradores, Adepto Marcial, Maestria em Armadura
#     Média, Especialista em Briga.
#
# Após a Fase 2, todos os 9 estão em `RULES` (Ruby) — fonte canônica
# imediatamente disponível, sem depender de rake `import_feats`.
RSpec.describe 'FeatRules — cobertura completa PHB (Fase 2)', type: :service do
  let(:rules) { FeatRules::RULES }

  describe 'Alerta (Alert) — feat sem prereq, +5 iniciativa' do
    let(:feat) { rules.fetch('alerta') }

    it 'existe em RULES e não tem prereq' do
      expect(feat[:prerequisites] || feat['prerequisites']).to eq({})
      expect(feat[:ability_bonuses] || feat['ability_bonuses']).to eq({})
    end

    it 'concede +5 em iniciativa via special_rules' do
      ini = feat.dig(:special_rules, :combat_modifiers, :initiative_bonus) ||
            feat.dig('special_rules', 'combat_modifiers', 'initiative_bonus')
      expect(ini).to be_present
      expect(ini.dig(:parameters, :bonus) || ini.dig('parameters', 'bonus')).to eq(5)
    end

    it 'declara imunidade a surpresa e ignore-hidden-advantage' do
      sr = feat.dig(:special_rules, :combat_modifiers) ||
           feat.dig('special_rules', 'combat_modifiers') || {}
      expect(sr.keys.map(&:to_s)).to include('surprise_immunity', 'ignore_hidden_attacker_advantage')
    end
  end

  describe 'Mente Aguçada (Keen Mind) — half-feat +1 INT com perfect recall' do
    let(:feat) { rules.fetch('mente_agucada') }

    it 'concede +1 INT (half-feat)' do
      bonuses = feat[:ability_bonuses] || feat['ability_bonuses']
      expect(bonuses[:int] || bonuses['int']).to eq(1)
    end

    it 'declara perfect_recall com janela de 30 dias e knows_north/solar_time' do
      sr = feat.dig(:special_rules, :social_modifiers) ||
           feat.dig('special_rules', 'social_modifiers') || {}
      keys = sr.keys.map(&:to_s)
      expect(keys).to include('perfect_recall_30_days', 'knows_north', 'knows_solar_time')

      window = sr.dig(:perfect_recall_30_days, :parameters, :window_days) ||
               sr.dig('perfect_recall_30_days', 'parameters', 'window_days')
      expect(window).to eq(30)
    end
  end

  describe 'Ator (Actor) — half-feat +1 CHA' do
    let(:feat) { rules.fetch('ator') }

    it 'concede +1 CHA' do
      bonuses = feat[:ability_bonuses] || feat['ability_bonuses']
      expect(bonuses[:cha] || bonuses['cha']).to eq(1)
    end

    it 'concede vantagem em Atuação e Enganação para personificar' do
      adv = feat.dig(:special_rules, :skill_modifiers, :skill_advantage, :parameters) ||
            feat.dig('special_rules', 'skill_modifiers', 'skill_advantage', 'parameters')
      expect(Array(adv)).to include('Atuação', 'Enganação')
    end
  end

  describe 'Investida Poderosa (Charger) — sem prereq, ataque/empurrão após Disparada' do
    let(:feat) { rules.fetch('investida_poderosa') }

    it 'expõe special_rules.combat_modifiers.bonus_action_attack_or_shove_after_dash' do
      key = feat.dig(:special_rules, :combat_modifiers, :bonus_action_attack_or_shove_after_dash) ||
            feat.dig('special_rules', 'combat_modifiers', 'bonus_action_attack_or_shove_after_dash')
      expect(key).to be_present
      expect(key.dig(:parameters, :damage_bonus) || key.dig('parameters', 'damage_bonus')).to eq(5)
    end
  end

  describe 'Adepto Elemental (Elemental Adept) — prereq spellcasting' do
    let(:feat) { rules.fetch('adepto_elemental') }

    it 'exige spellcasting' do
      sc = (feat[:prerequisites] || feat['prerequisites'] || {})
      expect(sc[:spellcasting] || sc['spellcasting']).to be(true)
    end

    it 'oferece os 5 tipos de dano elementais do PHB e regra "1s contam como 2"' do
      ef = feat.dig(:special_rules, :magic_modifiers, :elemental_focus, :parameters) ||
           feat.dig('special_rules', 'magic_modifiers', 'elemental_focus', 'parameters')
      types = Array(ef[:damage_type_choice] || ef['damage_type_choice']).map(&:to_s)
      expect(types).to include('ácido', 'frio', 'fogo', 'relâmpago', 'trovão')
      expect(ef[:ones_count_as] || ef['ones_count_as']).to eq(2)
    end
  end

  describe 'Matador de Conjuradores (Mage Slayer) — 3 efeitos PHB' do
    let(:feat) { rules.fetch('matador_de_conjuradores') }

    it 'expõe os 3 special_rules: reação, desvantagem em concentração, vantagem em saves vs magia adjacente' do
      cm = feat.dig(:special_rules, :combat_modifiers) ||
           feat.dig('special_rules', 'combat_modifiers') || {}
      keys = cm.keys.map(&:to_s)
      expect(keys).to include(
        'reaction_attack_on_cast',
        'impose_concentration_disadvantage',
        'advantage_on_saves_vs_adjacent_spells'
      )
    end
  end

  describe 'Adepto Marcial (Martial Adept) — 2 manobras + 1d6 superioridade' do
    let(:feat) { rules.fetch('adepto_marcial') }

    it 'declara escolha de 2 manobras' do
      mn = feat.dig(:special_rules, :maneuvers) || feat.dig('special_rules', 'maneuvers')
      expect(mn[:choose] || mn['choose']).to eq(2)
      options = Array(mn[:options] || mn['options'])
      expect(options.size).to be >= 10  # PHB Battle Master tem 16; nosso subset cobre 10+
    end

    it 'concede 1 dado de superioridade (d6)' do
      sd = feat.dig(:special_rules, :superiority_die, :parameters) ||
           feat.dig('special_rules', 'superiority_die', 'parameters')
      expect(sd[:count] || sd['count']).to eq(1)
      expect(sd[:die] || sd['die']).to eq('d6')
    end
  end

  describe 'Maestria em Armadura Média (Medium Armor Master) — prereq armor média' do
    let(:feat) { rules.fetch('maestria_em_armadura_media') }

    it 'exige proficiência em armadura média' do
      armors = Array(feat.dig(:prerequisites, :proficiencies, :armors) ||
                     feat.dig('prerequisites', 'proficiencies', 'armors')).map(&:to_s)
      expect(armors).to include('média')
    end

    it 'concede DEX cap +3 com prereq DEX 16+' do
      cap = feat.dig(:special_rules, :defense_modifiers, :dex_cap_plus_three, :parameters) ||
            feat.dig('special_rules', 'defense_modifiers', 'dex_cap_plus_three', 'parameters')
      expect(cap[:dex_cap] || cap['dex_cap']).to eq(3)
      expect(cap[:requires_dex] || cap['requires_dex']).to eq(16)
    end
  end

  describe 'Especialista em Briga (Tavern Brawler) — half-feat STR ou CON' do
    let(:feat) { rules.fetch('especialista_em_briga') }

    it 'concede +1 STR ou CON à escolha' do
      choose = feat.dig(:ability_bonuses, :choose) || feat.dig('ability_bonuses', 'choose')
      expect(choose[:amount] || choose['amount']).to eq(1)
      options = Array(choose[:options] || choose['options']).map(&:to_s)
      expect(options).to contain_exactly('str', 'con')
    end

    it 'concede proficiência em armas improvisadas' do
      weapons = Array(feat.dig(:proficiency_bonuses, :weapons) ||
                      feat.dig('proficiency_bonuses', 'weapons')).map(&:to_s)
      expect(weapons).to include('armas improvisadas')
    end

    it 'declara dado de dano desarmado d4 e bonus_action_grapple_on_hit' do
      ud = feat.dig(:special_rules, :unarmed_modifiers, :unarmed_damage_die, :parameters) ||
           feat.dig('special_rules', 'unarmed_modifiers', 'unarmed_damage_die', 'parameters')
      expect(ud[:die] || ud['die']).to eq('d4')

      grapple = feat.dig(:special_rules, :combat_modifiers, :bonus_action_grapple_on_hit) ||
                feat.dig('special_rules', 'combat_modifiers', 'bonus_action_grapple_on_hit')
      expect(grapple).to be_present
    end
  end

  # =====================================================================
  #  Sanity check — total de feats e ausência de regressão Fase 1
  # =====================================================================
  describe 'Total de feats em RULES' do
    # Fase 1: 35 feats. Fase 2: +9 (44). Fase 3: -2 (atirador_agucado +
    # especialista_em_escudo) +1 (maestria_em_armadura_pesada) = 43.
    it 'tem 43 feats (35 originais + 9 Fase 2 - 2 homebrews + 1 Heavy Armor Master)' do
      expect(rules.keys.size).to eq(43),
        "Total esperado pós-Fase 3 = 43 (35 + 9 + 1 - 2). Atual: #{rules.keys.size}"
    end

    it 'inclui os 9 feats novos pelo api_index' do
      novos = %w[
        alerta mente_agucada ator investida_poderosa adepto_elemental
        matador_de_conjuradores adepto_marcial maestria_em_armadura_media
        especialista_em_briga
      ]
      novos.each do |id|
        expect(rules).to have_key(id), "feat '#{id}' não encontrado em RULES"
      end
    end

    it 'preserva os fixes da Fase 1 (duravel sem prereq, especialista_em_armadura sem STR fixa)' do
      duravel = rules.fetch('duravel')
      expect(duravel.dig(:prerequisites, :ability_score) ||
             duravel.dig('prerequisites', 'ability_score')).to be_nil

      esp_arm = rules.fetch('especialista_em_armadura')
      expect(esp_arm.dig(:prerequisites, :ability_score, :str) ||
             esp_arm.dig('prerequisites', 'ability_score', 'str')).to be_nil
    end
  end
end
