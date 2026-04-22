# frozen_string_literal: true

require 'rails_helper'

# Phase 5 — Roundtrip de edição da ficha
#
# Hipótese: o endpoint POST /provision aceita `character.id` e funciona como
# upsert (criação OU atualização). Edição pelo wizard, troca de classe e
# re-envio idempotente devem todos passar por esse mesmo caminho.
#
# Esta spec cobre 4 cenários típicos que encontramos no produto:
#
#   1. LEVEL UP: provision L1 → re-provision L3 (mesma classe) preserva
#      identidade (character.id, sheet.id), abilities, raça, background,
#      e aplica subclasse no nível certo.
#
#   2. IDEMPOTÊNCIA: re-provisionar L3 com payload IDÊNTICO não duplica
#      sheet_klasses, não duplica feats, não inverte abilities, não muda
#      hp_max nem o id do personagem.
#
#   3. TROCA DE CLASSE: provision L1 bárbaro → re-provision L1 paladino
#      reseta a stack antiga (sheet_klasses) — sem deixar Klass legado
#      órfão na ficha (causa de "duas classes" duplicadas no front).
#
#   4. SUMMARY consistente: o GET /summary após cada provision devolve dados
#      coerentes com o último estado (não cache stale, não mistura runs).
RSpec.describe 'Player::Characters edit roundtrip — Phase 5', type: :request do
  include AuthHelpers

  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  let(:race)  { human_race }
  let(:sub)   { human_standard_subrace(race) }
  let(:bg)    { acolyte_background }
  let(:align) { lawful_good_alignment }

  # HP "fixed average" PHB: ceil(hd/2) + 1 a partir do L2 (igual ao builder Phase 2)
  def per_level_rows(klass, target_lv, skills: nil, subclass_at: nil, sub_id: nil)
    hd  = klass.hit_die.to_i
    avg = (hd / 2) + 1
    rows = (1..target_lv).each_with_object({}) do |lv, h|
      die = lv == 1 ? hd : avg
      h[lv.to_s] = { 'hp' => { 'dieResult' => die, 'total' => die + 2, 'method' => 'fixed' } }
    end
    rows['1']['skills'] = Array(skills) if skills
    if subclass_at && sub_id
      rows[subclass_at.to_s] ||= {}
      rows[subclass_at.to_s]['subclass'] = sub_id
    end
    rows
  end

  def build_payload(klass:, sub_id: nil, level: 1, character_id: nil, name: nil)
    rows = per_level_rows(klass, level, skills: %w[Atletismo Intimidação],
                          subclass_at: klass.subclass_level, sub_id: sub_id)
    char_block = { name: name || "RSpec #{SecureRandom.hex(3)}", background: bg.name }
    char_block[:id] = character_id if character_id
    {
      character: char_block,
      wizard: {
        meta: { name: 'RSpec', alignmentKey: align.api_index },
        race: {
          raceId: race.id, subRaceId: sub.id,
          ruleId: race.api_index, subRuleId: sub.api_index,
          attributes: { str: 16, dex: 12, con: 14, int: 8, wis: 12, cha: 10 },
          raceChoices: { chosenLanguages: [] }
        },
        klass: {
          klassId: klass.id, klassRuleSlug: klass.api_index, level: level,
          classSubclassId: sub_id,
          classSkillPicks: %w[Atletismo Intimidação],
          classPicksByLevel: rows
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  def provision!(payload, expect_status: :created)
    post '/api/v1/player/characters/provision',
         params: payload, headers: headers, as: :json
    expect(response).to have_http_status(expect_status), -> { response.body }
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'Cenário 1 — Level up Paladino L1 → L3 (devotion)' do
    it 'preserva character.id, sheet.id, abilities e aplica subclasse no L3' do
      pal = paladin_klass
      paladin_devotion_subklass(pal)

      # Etapa 1 — provision L1
      payload_l1 = build_payload(klass: pal, level: 1, name: 'Roundtrip Pal')
      r1 = provision!(payload_l1)
      char_id_1   = r1.dig(:character, :id)
      sheet_id_1  = r1.dig(:character, :sheet, :id)
      sheet_l1    = Sheet.find(sheet_id_1)

      expect(char_id_1).to be_present
      expect(sheet_id_1).to be_present
      expect(sheet_l1.current_level).to eq(1)
      expect(sheet_l1.str).to eq(16)
      expect(sheet_l1.con).to eq(14)
      sk_l1 = sheet_l1.sheet_klasses.find_by(klass_id: pal.id)
      expect(sk_l1).to be_present
      expect(sk_l1.level).to eq(1)
      expect(sk_l1.sub_klass_id).to be_nil # paladino só ganha subclasse no L3

      # Etapa 2 — re-provision L3 enviando o mesmo character.id
      payload_l3 = build_payload(klass: pal, level: 3, sub_id: 'devotion',
                                 character_id: char_id_1, name: 'Roundtrip Pal')
      r3 = provision!(payload_l3)
      char_id_3  = r3.dig(:character, :id)
      sheet_l3   = Sheet.find(r3.dig(:character, :sheet, :id))

      # Identidade preservada (não criou personagem novo)
      expect(char_id_3).to eq(char_id_1)
      expect(sheet_l3.id).to eq(sheet_id_1)

      # Stat preservado (point-buy não foi sobrescrito)
      expect(sheet_l3.str).to eq(16)
      expect(sheet_l3.con).to eq(14)
      expect(sheet_l3.cha).to eq(10)

      # Nível subiu para 3 sem duplicar SheetKlass
      expect(sheet_l3.sheet_klasses.where(klass_id: pal.id).count).to eq(1)
      sk_l3 = sheet_l3.sheet_klasses.find_by(klass_id: pal.id)
      expect(sk_l3.level).to eq(3)

      # Subclasse aplicada no L3
      expect(sk_l3.sub_klass&.api_index).to eq('devotion'),
        "Subclasse de paladino L3 não foi aplicada via re-provisioning"

      # HP coerente com PHB fixed avg: L1=10+2 + L2=6+2 + L3=6+2 = 28 (sem feats/race bonus)
      expect(sheet_l3.hp_max).to be >= 25
      expect(sheet_l3.hp_max).to be <= 35
    end
  end

  describe 'Cenário 2 — Idempotência: re-provision L3 com payload idêntico' do
    it 'não duplica sheet_klasses, não muda abilities/hp/level/sub_klass' do
      pal = paladin_klass
      paladin_devotion_subklass(pal)

      payload = build_payload(klass: pal, level: 3, sub_id: 'devotion', name: 'Idempotency')
      r1 = provision!(payload)
      char_id   = r1.dig(:character, :id)
      sheet1    = Sheet.find(r1.dig(:character, :sheet, :id))
      hp_1      = sheet1.hp_max
      str_1     = sheet1.str
      sk_count_1 = sheet1.sheet_klasses.count

      # Re-provisão idêntica enviando character.id
      payload2 = payload.deep_dup
      payload2[:character][:id] = char_id
      r2 = provision!(payload2)

      sheet2 = Sheet.find(r2.dig(:character, :sheet, :id))
      expect(sheet2.id).to eq(sheet1.id)
      expect(sheet2.hp_max).to eq(hp_1), "HP mudou em re-provision idêntico (esperado #{hp_1}, got #{sheet2.hp_max})"
      expect(sheet2.str).to eq(str_1)
      expect(sheet2.current_level).to eq(3)
      expect(sheet2.sheet_klasses.count).to eq(sk_count_1),
        "sheet_klasses duplicado em re-provision idêntico"
      expect(sheet2.sheet_klasses.where(klass_id: pal.id).count).to eq(1)

      sk = sheet2.sheet_klasses.find_by(klass_id: pal.id)
      expect(sk.level).to eq(3)
      expect(sk.sub_klass&.api_index).to eq('devotion')
    end
  end

  describe 'Cenário 3 — Troca de classe: bárbaro L1 → paladino L1' do
    it 'reseta stack antiga sem deixar Klass legado órfão' do
      barb = barbarian_klass
      pal  = paladin_klass

      payload_b = build_payload(klass: barb, level: 1, name: 'ClassSwitch')
      r1 = provision!(payload_b)
      char_id  = r1.dig(:character, :id)
      sheet1   = Sheet.find(r1.dig(:character, :sheet, :id))
      expect(sheet1.sheet_klasses.pluck(:klass_id)).to eq([barb.id])

      # Troca de classe — reset_stale_class_for_sheet! deve agir
      payload_p = build_payload(klass: pal, level: 1, character_id: char_id, name: 'ClassSwitch')
      r2 = provision!(payload_p)
      sheet2 = Sheet.find(r2.dig(:character, :sheet, :id))

      expect(sheet2.id).to eq(sheet1.id)
      expect(sheet2.sheet_klasses.pluck(:klass_id)).to eq([pal.id]),
        "Após trocar bárbaro→paladino, ficha ainda tem klass legado"
      expect(sheet2.current_level).to eq(1)
    end
  end

  describe 'Cenário 4 — GET /summary reflete último estado pós-edição' do
    it 'devolve nivel, subclass e abilities do estado mais recente' do
      pal = paladin_klass
      paladin_devotion_subklass(pal)

      r1 = provision!(build_payload(klass: pal, level: 1, name: 'SummaryRT'))
      char_id  = r1.dig(:character, :id)
      sheet_id = r1.dig(:character, :sheet, :id)

      provision!(build_payload(klass: pal, level: 3, sub_id: 'devotion',
                               character_id: char_id, name: 'SummaryRT'))

      get "/api/v1/player/sheets/#{sheet_id}/summary?sync=true", headers: headers
      expect(response).to have_http_status(:ok)
      sj = JSON.parse(response.body, symbolize_names: true)[:summary]

      expect(sj.dig(:abilities, :scores, :str)).to eq(16)
      expect(sj.dig(:abilities, :scores, :con)).to eq(14)
      classes = Array(sj[:klasses])
      expect(classes.size).to eq(1)
      expect(classes.first[:level]).to eq(3)
      sub_idx = classes.first.dig(:subclass, :api_index) ||
                classes.first.dig(:sub_klass, :api_index) ||
                classes.first[:subclass_index]
      expect(sub_idx.to_s).to eq('devotion'),
        "Summary não reflete subclasse pós-edição: #{classes.first.inspect}"
    end
  end

  describe 'Cenário 5 — Subclasse é IMUTÁVEL após persistida (regra D&D 5e)' do
    # Em D&D 5e a subclasse é permanente após escolhida — não há mecânica de
    # "troca de juramento". O CharacterProvisioningService reflete isso:
    # o backfill em sub_klass_id só atua quando o campo é nil
    # (ver character_provisioning_service.rb ~L384).
    #
    # Esta spec garante que ninguém acidentalmente permita "troca silenciosa"
    # de subclasse via re-provision (causaria perda de features e DC inflados).
    # Se o produto decidir suportar retraining (homerule), este teste deve
    # quebrar e ser explicitamente atualizado.
    it 'NÃO substitui sub_klass_id quando o front re-envia subclasse diferente' do
      pal = paladin_klass
      paladin_devotion_subklass(pal)
      paladin_ancients_subklass(pal)

      r1 = provision!(build_payload(klass: pal, level: 3, sub_id: 'devotion', name: 'SubLock'))
      char_id  = r1.dig(:character, :id)
      sheet1   = Sheet.find(r1.dig(:character, :sheet, :id))
      sk1      = sheet1.sheet_klasses.find_by(klass_id: pal.id)
      expect(sk1.sub_klass&.api_index).to eq('devotion')

      # Tentativa de troca silenciosa — sistema deve preservar a original
      r2 = provision!(build_payload(klass: pal, level: 3, sub_id: 'ancients',
                                     character_id: char_id, name: 'SubLock'))
      sheet2 = Sheet.find(r2.dig(:character, :sheet, :id))
      expect(sheet2.id).to eq(sheet1.id)
      expect(sheet2.sheet_klasses.where(klass_id: pal.id).count).to eq(1)
      sk2 = sheet2.sheet_klasses.find_by(klass_id: pal.id)
      expect(sk2.sub_klass&.api_index).to eq('devotion'),
        "REGRESSÃO: subclasse foi trocada silenciosamente para #{sk2.sub_klass&.api_index}. " \
        "Sub-klass deve ser imutável após persistida (D&D 5e: juramento é permanente)."
    end
  end

  describe 'Cenário 6 — Edição de abilities NÃO duplica racial bonus' do
    # Cenário comum no produto: usuário re-abre o wizard pra ajustar point-buy.
    # `base_str` no payload já é o valor final (point-buy + racial), então
    # re-enviar com o mesmo valor NÃO pode somar +1 racial em cima.
    it 'reaplicar abilities do payload mantém os scores estáveis' do
      pal = paladin_klass
      paladin_devotion_subklass(pal)

      r1 = provision!(build_payload(klass: pal, level: 3, sub_id: 'devotion', name: 'AbilityEdit'))
      char_id  = r1.dig(:character, :id)
      sheet1   = Sheet.find(r1.dig(:character, :sheet, :id))
      str_1, dex_1, con_1, cha_1 = sheet1.str, sheet1.dex, sheet1.con, sheet1.cha

      # Re-provision idêntico múltiplas vezes — abilities não podem driftar
      3.times do
        provision!(build_payload(klass: pal, level: 3, sub_id: 'devotion',
                                 character_id: char_id, name: 'AbilityEdit'))
      end

      sheet_n = Sheet.find(sheet1.id)
      expect(sheet_n.str).to eq(str_1), "STR driftou de #{str_1} para #{sheet_n.str}"
      expect(sheet_n.dex).to eq(dex_1)
      expect(sheet_n.con).to eq(con_1)
      expect(sheet_n.cha).to eq(cha_1)
    end
  end
end
