# frozen_string_literal: true

require 'rails_helper'

# BDD: Conformidade dos talentos com o PHB 5e
# --------------------------------------------
# Auditoria identificou 3 bugs de regra dentro de `FeatRules::RULES`:
#
#   Bug 1 — `duravel` (Durável) tem REGRA INCORRETA:
#     Atual: "rerrolar dado de vida se rolar 1"
#     PHB:   "mínimo de cura ao usar Dado de Vida = 2 × mod. CON (mínimo 2)"
#
#   Bug 2 — `duravel` tem PREREQUISITO INCORRETO:
#     Atual: prereq ability_score CON 13
#     PHB:   sem prereq de habilidade
#
#   Bug 3 — `especialista_em_armadura` tem PREREQUISITO INCORRETO:
#     Atual: prereq ability_score STR 15
#     PHB Heavily Armored: prereq = profic. armadura média (sem prereq STR)
#     PHB Heavy Armor Master: prereq = profic. armadura pesada (sem prereq STR)
#
# Estes specs documentam as regras corretas PHB. Devem virar verde após o fix
# em `app/services/feat_rules.rb`.
RSpec.describe 'FeatRules — Conformidade PHB', type: :service do
  describe 'Durável (duravel) — PHB Durable' do
    let(:feat) { FeatRules::RULES.fetch('duravel') }

    it 'NÃO tem prereq de habilidade (PHB Durable não exige CON 13)' do
      prereqs = feat[:prerequisites] || {}
      ability = prereqs[:ability_score] || prereqs['ability_score'] || {}
      expect(ability).to be_empty,
        'PHB Durable: sem prereq de ability_score. Atual = ' \
        "#{ability.inspect}"
    end

    it 'concede +1 CON (PHB: half-feat com +1 CON)' do
      bonuses = feat[:ability_bonuses] || {}
      expect(bonuses[:con] || bonuses['con']).to eq(1)
    end

    it 'description menciona o efeito PHB correto: "mínimo 2x mod.CON" (não rerrolar 1)' do
      desc = feat.dig(:features, :desc) || feat.dig('features', 'desc') || ''
      expect(desc).to match(/2\s*[x×]\s*(mod|modificador).{0,15}CON|2.*Constitui|cura.*m[íi]nim/i),
        "Descrição do Durável deve referenciar o efeito PHB ('mínimo de cura = 2 × mod.CON'). " \
        "Atual: #{desc.inspect}"
    end

    it 'NÃO menciona "rerrolar" (regra incorreta antiga)' do
      desc = feat.dig(:features, :desc) || feat.dig('features', 'desc') || ''
      expect(desc).not_to match(/rerrolar|reroll|rolar.*novamente/i),
        "Descrição do Durável não pode mencionar 'rerrolar' — essa é a regra " \
        "incorreta anterior. Atual: #{desc.inspect}"
    end

    it 'expõe special_rules.dice_modifiers.hit_dice_minimum_heal (engine consume isso)' do
      sr = feat[:special_rules] || feat['special_rules'] || {}
      dm = sr[:dice_modifiers] || sr['dice_modifiers'] || {}
      hdm = dm[:hit_dice_minimum_heal] || dm['hit_dice_minimum_heal']
      expect(hdm).to be_present,
        'Durável precisa de special_rules.dice_modifiers.hit_dice_minimum_heal ' \
        'para o engine de cura aplicar a regra (mínimo = 2×mod.CON, floor 2).'
    end
  end

  describe 'Especialista em Armadura (especialista_em_armadura)' do
    let(:feat) { FeatRules::RULES.fetch('especialista_em_armadura') }

    it 'NÃO tem prereq STR (nenhum dos feats PHB de armadura exige STR fixa)' do
      prereqs = feat[:prerequisites] || {}
      ability = prereqs[:ability_score] || prereqs['ability_score'] || {}
      expect(ability[:str] || ability['str']).to be_nil,
        'Heavily Armored / Heavy Armor Master no PHB exigem proficiência em ' \
        'armadura média/pesada, NÃO um valor mínimo de STR. Atual STR prereq: ' \
        "#{(ability[:str] || ability['str']).inspect}"
    end

    it 'tem prereq de proficiência em armadura média (PHB Heavily Armored)' do
      prereqs = feat[:prerequisites] || {}
      profs = prereqs[:proficiencies] || prereqs['proficiencies'] || {}
      armors = Array(profs[:armors] || profs['armors']).map(&:to_s)
      expect(armors).to include('média').or(include('medium')),
        'PHB Heavily Armored: prereq = profic. armadura média. ' \
        "Atual armors prereq: #{armors.inspect}"
    end

    it 'concede +1 STR e proficiência em armadura pesada (PHB Heavily Armored)' do
      bonuses = feat[:ability_bonuses] || {}
      expect(bonuses[:str] || bonuses['str']).to eq(1)

      pb = feat[:proficiency_bonuses] || {}
      # D5 — vocabulário padronizado para `armors` (plural), que é a chave lida
      # por build_proficiencies. Antes a RULE usava `armor` (singular) e a
      # proficiência de armadura pesada deste feat não materializava na ficha.
      armor = Array(pb[:armors] || pb['armors'] || pb[:armor] || pb['armor']).map(&:to_s)
      expect(armor.any? { |a| a.match?(/pesad|heavy/i) }).to be(true),
        'Heavily Armored deve dar proficiência em armadura pesada. ' \
        "Atual proficiency_bonuses.armors: #{armor.inspect}"
    end
  end

  # Sanity check: outros feats com prereq devem manter as regras já corretas
  describe 'Sanity — feats com prereq correto não devem regredir' do
    {
      'observador'         => { ability: 'wis', value: 13 },   # PHB Observant: prereq alterado para flexible (mas projeto usa wis 13 — manter)
      'sentinela'          => { ability: 'str', value: 13 },   # PHB Sentinel: sem prereq; projeto exige STR/CON — diff conhecido
      'atleta'             => { ability: 'str', value: 13 }    # PHB Athlete: sem prereq; projeto exige STR — diff conhecido
    }.each do |feat_id, expected|
      # Esses já existem e mantêm seus prereqs atuais; o spec apenas
      # documenta que NÃO foram tocados pelo fix do duravel/armadura.
      it "preserva prereq existente do feat '#{feat_id}'" do
        feat = FeatRules::RULES.fetch(feat_id)
        prereqs = feat[:prerequisites] || {}
        ability = prereqs[:ability_score] || {}
        actual = ability[expected[:ability].to_sym] || ability[expected[:ability]]
        expect(actual).to eq(expected[:value])
      end
    end
  end
end
