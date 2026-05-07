# frozen_string_literal: true

require 'rails_helper'

# BDD: Limpeza Fase 3 — homebrews removidos + Heavy Armor Master adicionado.
# ----------------------------------------------------------------------------
# Auditoria identificou:
#   - `atirador_agucado` (homebrew híbrido entre Sharpshooter + Crossbow Expert)
#     redundante com `atirador_eximio` (Sharpshooter completo) e
#     `especialista_em_besta` (Crossbow Expert). 0 uso em DB → REMOVIDO.
#   - `especialista_em_escudo` (homebrew "escudo como arma improvisada 1d4")
#     sem equivalente PHB. 0 uso em DB → REMOVIDO.
#   - `especialista_em_armadura` ↔ `protecao_pesada`: ambos representam PHB
#     Heavily Armored. Mantidos como aliases (campo `deprecated_for: 'protecao_pesada'`).
#   - PHB Heavy Armor Master (feat SEPARADO com -3 dano físico) ausente do
#     Ruby — ADICIONADO como `maestria_em_armadura_pesada`.
RSpec.describe 'FeatRules — Fase 3 (limpeza)', type: :service do
  let(:rules) { FeatRules::RULES }

  describe 'Homebrews removidos' do
    it 'não tem mais `atirador_agucado` (homebrew redundante)' do
      expect(rules.key?('atirador_agucado')).to be(false),
        'atirador_agucado era um híbrido Sharpshooter + Crossbow Expert. ' \
        'Os efeitos canônicos vivem em atirador_eximio e especialista_em_besta.'
    end

    it 'não tem mais `especialista_em_escudo` (homebrew sem PHB)' do
      expect(rules.key?('especialista_em_escudo')).to be(false),
        'especialista_em_escudo (escudo 1d4 improvisado) não tem equivalente ' \
        'PHB. Para escudo como arma use especialista_em_briga (Tavern Brawler).'
    end
  end

  describe 'Especialista em Armadura — alias deprecated' do
    let(:feat) { rules.fetch('especialista_em_armadura') }

    it 'foi mantido para compatibilidade com fichas legadas' do
      expect(feat).to be_present
    end

    it 'declara `deprecated_for: protecao_pesada` (canônico de Heavily Armored)' do
      expect(feat[:deprecated_for] || feat['deprecated_for']).to eq('protecao_pesada')
    end

    it 'tem efeito FUNCIONALMENTE IDÊNTICO a protecao_pesada (PHB Heavily Armored)' do
      pp = rules.fetch('protecao_pesada')

      # Mesmo prereq:
      pp_armors = Array(pp.dig(:prerequisites, :proficiencies, :armors)).map(&:to_s)
      ea_armors = Array(feat.dig(:prerequisites, :proficiencies, :armors)).map(&:to_s)
      expect(ea_armors).to eq(pp_armors), 'prereq de armadura deve ser idêntico'

      # Mesmo +1 STR:
      expect(feat.dig(:ability_bonuses, :str)).to eq(pp.dig(:ability_bonuses, :str))
    end
  end

  describe 'Maestria em Armadura Pesada — Heavy Armor Master (PHB)' do
    let(:feat) { rules.fetch('maestria_em_armadura_pesada') }

    it 'existe em RULES (Fase 3)' do
      expect(feat).to be_present
      expect(feat[:name]).to eq('Maestria em Armadura Pesada')
    end

    it 'exige proficiência em armadura PESADA (não média)' do
      armors = Array(feat.dig(:prerequisites, :proficiencies, :armors)).map(&:to_s)
      expect(armors).to eq(['pesada']),
        'PHB Heavy Armor Master exige profic. em armadura pesada (≠ Heavily Armored ' \
        "que exige média). Atual: #{armors.inspect}"
    end

    it 'concede +1 STR' do
      expect(feat.dig(:ability_bonuses, :str)).to eq(1)
    end

    it 'reduz dano físico não-mágico em 3 (efeito-chave)' do
      params = feat.dig(:special_rules, :defense_modifiers, :damage_resistance, :parameters)
      expect(params[:reduce] || params['reduce']).to eq(3)
      expect(params[:requires_armor_category] || params['requires_armor_category']).to eq('pesada')
    end

    it 'NÃO concede proficiência adicional em armadura (é só redução de dano)' do
      pb = feat[:proficiency_bonuses] || {}
      expect(pb).to be_empty,
        'Heavy Armor Master não dá profic. nova de armadura — quem dá é Heavily Armored.'
    end

    it 'expõe alias EN "Heavy Armor Master" para fichas legadas' do
      aliases = Array(feat[:aliases]).map(&:to_s)
      expect(aliases).to include('Heavy Armor Master')
    end
  end

  describe 'Distinção PHB: Heavily Armored ≠ Heavy Armor Master' do
    it 'protecao_pesada (Heavily Armored) e maestria_em_armadura_pesada (Heavy Armor Master) são DIFERENTES' do
      ha  = rules.fetch('protecao_pesada')
      ham = rules.fetch('maestria_em_armadura_pesada')

      ha_armors  = Array(ha.dig(:prerequisites, :proficiencies, :armors)).map(&:to_s)
      ham_armors = Array(ham.dig(:prerequisites, :proficiencies, :armors)).map(&:to_s)

      expect(ha_armors).to eq(['média']), 'Heavily Armored: prereq média'
      expect(ham_armors).to eq(['pesada']), 'Heavy Armor Master: prereq pesada'

      # Heavily Armored dá profic. nova; Heavy Armor Master não.
      ha_armor_grants = Array(ha.dig(:proficiency_bonuses, :armors)).map(&:to_s)
      expect(ha_armor_grants).to include('pesada')

      # Heavy Armor Master tem damage_resistance; Heavily Armored não.
      ham_dr = ham.dig(:special_rules, :defense_modifiers, :damage_resistance)
      expect(ham_dr).to be_present
      ha_dr = ha.dig(:special_rules, :defense_modifiers, :damage_resistance)
      expect(ha_dr).to be_blank
    end
  end

  describe 'Cobertura final dos 16 feats PHB de combate físico (sanity)' do
    # Lista os feats de combate físico do PHB que devem estar TODOS cobertos
    # após Fase 1+2+3.
    PHB_COMBAT_FEATS = {
      'mestre_de_armas_duplas'      => 'Dual Wielder',
      'mestre_de_armas_grandes'     => 'Great Weapon Master',
      'mestre_arma_de_haste'        => 'Polearm Master',
      'especialista_em_besta'       => 'Crossbow Expert',
      'atirador_eximio'             => 'Sharpshooter',
      'sentinela'                   => 'Sentinel',
      'mobilidade'                  => 'Mobile',
      'duelista_defensivo'          => 'Defensive Duelist',
      'duelista_montado'            => 'Mounted Combatant',
      'mestre_do_escudo'            => 'Shield Master',
      'imobilizador'                => 'Grappler',
      'atacante_selvagem'           => 'Savage Attacker',
      'investida_poderosa'          => 'Charger',
      'protecao_leve'               => 'Lightly Armored',
      'protecao_moderada'           => 'Moderately Armored',
      'protecao_pesada'             => 'Heavily Armored',
      'maestria_em_armadura_media'  => 'Medium Armor Master',
      'maestria_em_armadura_pesada' => 'Heavy Armor Master',
      'especialista_em_briga'       => 'Tavern Brawler'
    }.freeze

    PHB_COMBAT_FEATS.each do |id, phb_name|
      it "cobre #{phb_name} (#{id})" do
        expect(rules).to have_key(id), "feat de combate '#{phb_name}' (#{id}) ausente em RULES"
      end
    end
  end
end
