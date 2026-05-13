# frozen_string_literal: true

require 'rails_helper'

# BDD — Talentos repetíveis (Loop 14C, 2026-05-13).
#
# Cenário: 6 talentos do PHB/houserule Lafiga são cumulativos por pick:
#   - Adepto Elemental (PHB pg 168 — explicitamente repetível)
#   - Mágico Iniciante (PHB pg 168 — explicitamente repetível)
#   - Adepto Marcial   (houserule Lafiga — +1 dado superioridade, +2 manobras)
#   - Poliglota         (houserule Lafiga — +3 idiomas)
#   - Perito            (houserule Lafiga — +3 perícias/ferramentas)
#   - Conjurador de Ritual (houserule Lafiga — rituais de outra lista)
#
# Antes do fix, o FeatAssignmentService rejeitava o segundo pick com
# `errors[:feat] = 'já possui este talento'`. Agora, quando o feat tem
# `repeatable: true`, o check é pulado e a unique constraint do DB
# (relaxada via migration `20260513000000_allow_repeatable_feats_in_sheet_feats`)
# aceita múltiplas linhas em `(sheet_id, feat_id, level_gained)`.
RSpec.describe 'FeatAssignmentService — talentos repetíveis', type: :service do
  let(:role)    { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "rep_#{SecureRandom.hex(4)}@example.com",
                 username: "rep#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1',
                 role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'variant') { |s| s.name = 'Variante' } }
  let(:klass)    { Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 } }
  let(:wizard)   { Klass.find_or_create_by!(api_index: 'wizard')  { |k| k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2 } }

  def build_sheet(klass_to_use: nil)
    k = klass_to_use || klass
    character = Character.create!(user: user, name: "Rep #{SecureRandom.hex(2)}", background: 'Sage')
    # `class_summary.spellcasting` é o que `FeatRules.sheet_has_spellcasting?`
    # detecta para liberar feats que exigem caster (Adepto Elemental etc.).
    # Sem isto, Mago (que no DB tem `sheet_klass.spellcasting=nil`) é
    # rejeitado pelo prereq mesmo sendo mecanicamente conjurador.
    meta = { 'base_ability_scores' => { 'str' => 13, 'dex' => 14, 'con' => 14, 'int' => 14, 'wis' => 14, 'cha' => 14 } }
    meta['class_summary'] = { 'spellcasting' => { 'ability' => 'INT', 'preparation' => 'prepared' } } if k.api_index == 'wizard'
    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 13, dex: 14, con: 14, int: 14, wis: 14, cha: 14,
      hp_max: 12, hp_current: 12, current_level: 8,
      metadata: meta
    )
    SheetKlass.create!(sheet: sheet, klass: k, level: 8)
    sheet
  end

  describe 'Perito (houserule cumulativo)' do
    it 'aceita o 2º pick em level diferente' do
      sheet = build_sheet
      r1 = FeatAssignmentService.call(
        sheet: sheet, feat_id: 'perito', level_gained: 1,
        choices: { 'skillsAndTools' => %w[Arcanismo Investigação Acrobacia] }
      )
      expect(r1.errors).to be_empty
      expect(sheet.reload.sheet_feats.where(level_gained: 1).count).to eq(1)

      r2 = FeatAssignmentService.call(
        sheet: sheet, feat_id: 'perito', level_gained: 4,
        choices: { 'skillsAndTools' => %w[Atletismo Furtividade Religião] }
      )
      expect(r2.errors).to be_empty, "Repetível deveria aceitar 2º pick. Veio: #{r2.errors.full_messages.inspect}"
      expect(sheet.reload.sheet_feats.count).to eq(2)
    end

    it 'metadata.feats acumula entries por level com choices distintos' do
      sheet = build_sheet
      FeatAssignmentService.call(
        sheet: sheet, feat_id: 'perito', level_gained: 1,
        choices: { 'skillsAndTools' => %w[Arcanismo Investigação Acrobacia] }
      )
      FeatAssignmentService.call(
        sheet: sheet, feat_id: 'perito', level_gained: 4,
        choices: { 'skillsAndTools' => %w[Atletismo Furtividade Religião] }
      )
      sheet.reload
      peritos = Array(sheet.metadata['feats']).select { |f| f['feat_id'] == 'perito' }
      expect(peritos.length).to eq(2)
      expect(peritos.map { |f| f['level_gained'] }).to contain_exactly(1, 4)
      expect(peritos.flat_map { |f| Array(f.dig('proficiency_bonuses', 'skills')) }).to include('Arcanismo', 'Atletismo')
    end
  end

  describe 'Adepto Elemental (PHB explicitamente repetível)' do
    it 'aceita 2 picks com damage_type distintos (Mago, tem spellcasting)' do
      sheet = build_sheet(klass_to_use: wizard)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'adepto_elemental', level_gained: 4, choices: {})
      r2 = FeatAssignmentService.call(sheet: sheet, feat_id: 'adepto_elemental', level_gained: 8, choices: {})
      expect(r2.errors).to be_empty,
        "2º pick rejeitado: #{r2.errors.full_messages.inspect}"
      expect(sheet.reload.sheet_feats.where(feat: Feat.find_by(api_index: 'adepto_elemental')).count).to eq(2)
    end
  end

  describe 'Talento NÃO-repetível (Atleta — half-feat PHB) continua bloqueado' do
    it 'rejeita 2º pick com erro' do
      sheet = build_sheet
      r1 = FeatAssignmentService.call(sheet: sheet, feat_id: 'atleta', level_gained: 4, choices: { 'ability' => 'dex' })
      expect(r1.errors).to be_empty if r1.respond_to?(:errors)

      r2 = FeatAssignmentService.call(sheet: sheet, feat_id: 'atleta', level_gained: 8, choices: { 'ability' => 'str' })
      expect(r2.errors.full_messages.join).to include('já possui este talento'),
        'Atleta NÃO é marcado repeatable; o backend deve rejeitar o 2º pick.'
    end
  end

  describe 'Adepto Marcial / Poliglota / Mágico Iniciante / Conjurador de Ritual' do
    {
      'adepto_marcial'       => { needs_caster: false, choices_a: {}, choices_b: {} },
      'poliglota'            => { needs_caster: false, choices_a: {}, choices_b: {} },
      'magico_iniciante'     => { needs_caster: false, choices_a: { 'classe_principal' => 'mago' }, choices_b: { 'classe_principal' => 'bardo' } },
      'conjurador_de_ritual' => { needs_caster: false, choices_a: { 'classe' => 'mago' }, choices_b: { 'classe' => 'clérigo' } },
    }.each do |feat_id, spec|
      it "#{feat_id} aceita 2 picks (repeatable=true em FeatRules)" do
        sheet = build_sheet(klass_to_use: spec[:needs_caster] ? wizard : klass)
        FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 4, choices: spec[:choices_a])
        r2 = FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 8, choices: spec[:choices_b])
        expect(r2.errors).to be_empty, "#{feat_id} deveria aceitar 2º pick — repeatable=true. Veio: #{r2.errors.full_messages.inspect}"
        feat_row = Feat.find_by(api_index: feat_id)
        expect(sheet.reload.sheet_feats.where(feat: feat_row).count).to eq(2)
      end
    end
  end

  describe 'audit: 6 feats marcados repeatable em FeatRules' do
    it 'todos os 6 têm `repeatable: true`' do
      ids = %w[adepto_elemental magico_iniciante adepto_marcial poliglota perito conjurador_de_ritual]
      non_repeatable = ids.reject { |id| FeatRules.find(id)&.dig(:repeatable) || FeatRules.find(id)&.dig('repeatable') }
      expect(non_repeatable).to be_empty,
        "Feats que deveriam ser repeatable mas não estão marcados: #{non_repeatable.inspect}"
    end
  end
end
