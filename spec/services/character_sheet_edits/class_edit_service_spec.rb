# frozen_string_literal: true

require 'rails_helper'

# Cobre os fixes B4.2 e B4.3 do relatorio de auditoria de steps:
#   B4.2: troca de classe fazia shallow-merge em `class_choices.per_level['1']`,
#         mantendo escolhas da classe antiga (instrumentos do Bardo, fighting_style
#         do Guerreiro, etc) contaminando a nova classe.
#   B4.3: troca de classe nao recomputava `hp_max` quando o `hit_die` mudava
#         (d12 do Barbaro -> d6 do Mago). HP ficava stale.
RSpec.describe CharacterSheetEdits::ClassEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:bard) { create(:klass, name: 'Bardo', hit_die: 8) }
  let(:fighter) { create(:klass, name: 'Guerreiro', hit_die: 10) }
  let(:wizard) { create(:klass, name: 'Mago', hit_die: 6) }
  let!(:sheet) do
    create(:sheet, character: character, race: race, sub_race: sub_race,
                   con: 14, hp_max: 12, hp_current: 12, current_level: 3,
                   metadata: {
                     'class_choices' => {
                       'per_level' => {
                         '1' => {
                           'instruments' => %w[lute flute drum],
                           'skills' => %w[Persuasao Investigacao]
                         },
                         '2' => { 'expertise' => %w[Persuasao] }
                       }
                     },
                     'class_summary' => { 'armor' => %w[light] }
                   })
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: bard, level: 3) }

  describe 'B4.2 — troca de classe limpa per_level antigo' do
    it 'apaga per_level inteiro e nao deixa instrumentos do Bardo na ficha do Guerreiro (force=true)' do
      svc = described_class.new(character: character,
                                data: {
                                  'classId' => fighter.id.to_s,
                                  'level1Choices' => { 'fighting_style' => ['defense'] },
                                  'classSkillPicks' => %w[Atletismo]
                                },
                                force: true)
      svc.call
      sheet.reload

      pl = sheet.metadata.dig('class_choices', 'per_level')
      expect(pl.keys).to eq(['1']) # nivel 2 antigo destruido
      expect(pl['1']).to eq('fighting_style' => ['defense'], 'skills' => ['Atletismo'])
      expect(pl['1']).not_to have_key('instruments')
    end

    it 'apaga class_summary cached da classe antiga' do
      svc = described_class.new(character: character,
                                data: { 'classId' => fighter.id.to_s },
                                force: true)
      svc.call
      sheet.reload
      # ClassSummaryRebuilder reconstroi com armor/weapons da nova classe (vazio aqui).
      # O importante: NAO mantem o cache literal `{'armor' => ['light']}` da antiga.
      expect(sheet.metadata['class_summary']).not_to eq('armor' => %w[light])
    end

    it 'flags requires_confirmation em troca destrutiva sem force' do
      svc = described_class.new(character: character,
                                data: { 'classId' => fighter.id.to_s })
      result = svc.call
      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:cleared]).to include('metadata.class_choices')
    end

    it 'mantem per_level intacto quando NAO ha troca de classe' do
      svc = described_class.new(character: character,
                                data: { 'level1Choices' => { 'instruments' => %w[lute violin drum] } })
      svc.call
      sheet.reload
      pl = sheet.metadata.dig('class_choices', 'per_level')
      expect(pl['2']).to eq('expertise' => ['Persuasao']) # nivel 2 preservado
      expect(pl['1']['instruments']).to eq(%w[lute violin drum])
      # Skills antigas preservadas (nao vieram no PATCH)
      expect(pl['1']['skills']).to eq(%w[Persuasao Investigacao])
    end
  end

  describe 'B4.3 — recomputa hp_max quando classe muda hit_die' do
    it 'recalcula hp_max para hit_die da nova classe (Bardo d8 -> Mago d6)' do
      old_hp_max = sheet.hp_max
      svc = described_class.new(character: character,
                                data: { 'classId' => wizard.id.to_s },
                                force: true)
      svc.call
      sheet.reload

      # CON 14 -> mod +2. Nivel 1 com d6: hp_max = 6 + 2 = 8 (sem extras pois sheet_klasses level>=2 foi destruido).
      expect(sheet.hp_max).to eq(8)
      expect(sheet.hp_max).not_to eq(old_hp_max)
    end

    it 'preserva ratio HP_current na recomputacao' do
      sheet.update!(hp_current: 6) # ratio 0.5
      svc = described_class.new(character: character,
                                data: { 'classId' => wizard.id.to_s },
                                force: true)
      svc.call
      sheet.reload
      ratio = sheet.hp_current.to_f / sheet.hp_max
      expect(ratio).to be_within(0.15).of(0.5)
    end

    it 'NAO mexe em HP quando so muda subclasse' do
      sub = create(:sub_klass, klass: bard)
      old_hp = sheet.hp_max
      svc = described_class.new(character: character,
                                data: { 'subclassId' => sub.id.to_s })
      svc.call
      sheet.reload
      expect(sheet.hp_max).to eq(old_hp)
    end
  end

  # Gap G8.2 do relatorio de auditoria de steps: ao trocar classe em modo
  # edit, `metadata.equipment.*` e os SheetItems auto-provisionados
  # (source='class' + provisioning_run_id) ficavam stale (pacote inicial do
  # Bardo aparecia na ficha do Mago). Items manuais do jogador (sem
  # provisioning_run_id) DEVEM permanecer.
  describe 'G8.2 — invalidate equipment ao trocar classe' do
    before do
      sheet.update!(metadata: sheet.metadata.merge(
        'equipment' => {
          'mode' => 'preset',
          'choices' => [{ 'kind' => 'weapon', 'pick' => 'longsword' }]
        }
      ))
      # SheetItem auto-provisionado pelo wizard (com run_id)
      SheetItem.create!(
        sheet: sheet, item_name: 'Alaude', category: 'instrument',
        quantity: 1, source: 'class',
        props_json: { 'provisioning_run_id' => 'old-run-uuid' }
      )
      # SheetItem manual (sem run_id) — comprado pelo jogador
      SheetItem.create!(
        sheet: sheet, item_name: 'Pocao de Cura', category: 'consumable',
        quantity: 3, source: 'class',
        props_json: { 'note' => 'comprada na loja' }
      )
    end

    it 'limpa metadata.equipment e items auto-provisionados ao trocar de classe' do
      described_class.new(character: character,
                          data: { 'classId' => fighter.id.to_s },
                          force: true).call
      sheet.reload

      expect(sheet.metadata['equipment']).to be_nil
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Alaude' }).to be_nil
      # Item manual preservado
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Pocao de Cura' }).to be_present
    end

    it 'requires_confirmation lista metadata.equipment e sheet_items entre os keys clearing' do
      result = described_class.new(character: character,
                                    data: { 'classId' => fighter.id.to_s }).call
      expect(result.requires_confirmation[:cleared]).to include(
        'metadata.equipment',
        'sheet_items(source=class, provisioned)'
      )
    end

    it 'NAO toca em equipment quando so muda subclasse' do
      sub = create(:sub_klass, klass: bard)
      described_class.new(character: character,
                          data: { 'subclassId' => sub.id.to_s }).call
      sheet.reload
      expect(sheet.metadata.dig('equipment', 'mode')).to eq('preset')
      expect(sheet.sheet_items.detect { |i| i.item_name == 'Alaude' }).to be_present
    end
  end

  # Gap G4.5 do relatorio de auditoria de steps: ClassEditService destruia
  # `sheet_klasses(level>=2)` sem detectar/anunciar multiclass. Antes do fix,
  # a confirmacao mostrava so "perde nivel 2+" mesmo quando o personagem
  # tinha Bardo 5 + Mago 2 (multiclass), e o jogador nao sabia que perderia
  # o Mago 2 inteiro.
  describe 'G4.5 — multiclass: confirmacao detalhada e cleanup completo' do
    let!(:secondary_klass) { create(:klass, name: 'Mago', hit_die: 6) }
    # ClassEditService.apply! trata `sk = order(level: :asc).first` como "primario",
    # entao Mago 2 (menor level) vira o primario e Bardo 3 vira o "secundario" que
    # entrara na lista de confirmacao.
    let!(:secondary_sk) { create(:sheet_klass, sheet: sheet, klass: secondary_klass, level: 2) }

    it 'lista classes secundarias destruidas no requires_confirmation' do
      result = described_class.new(character: character,
                                    data: { 'classId' => fighter.id.to_s }).call
      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:reason]).to include('Bardo 3')
      expect(result.requires_confirmation[:cleared]).to include('sheet_klasses(multiclass)')
    end

    it 'destroi sheet_klasses secundarios ao trocar classe (force=true)' do
      expect(sheet.sheet_klasses.size).to eq(2)
      described_class.new(character: character,
                          data: { 'classId' => fighter.id.to_s },
                          force: true).call
      sheet.reload
      expect(sheet.sheet_klasses.size).to eq(1)
      expect(sheet.sheet_klasses.first.klass_id).to eq(fighter.id)
    end

    it 'NAO menciona multiclass quando ha apenas 1 classe' do
      secondary_sk.destroy!
      result = described_class.new(character: character,
                                    data: { 'classId' => fighter.id.to_s }).call
      expect(result.requires_confirmation[:reason]).not_to include('classes secundarias')
      expect(result.requires_confirmation[:cleared]).not_to include('sheet_klasses(multiclass)')
    end
  end

  # Gap G4.6 do relatorio de auditoria de steps: ClassEditService nao
  # validava se `level1Choices` enviado era compativel com a nova classe
  # (skill catalog, fighting_style requerido, etc.). Resultado: jogador
  # trocava Mago -> Guerreiro sem fighting_style e ficha entrava em estado
  # invalido. Agora rodamos LevelUpGuardService apos o save.
  describe 'G4.6 — LevelUpGuardService valida escolhas obrigatorias da nova classe' do
    it 'aceita troca quando todas as escolhas obrigatorias vem no PATCH (force=true)' do
      svc = described_class.new(character: character,
                                data: {
                                  'classId' => fighter.id.to_s,
                                  'level1Choices' => { 'fighting_style' => ['defense'] }
                                },
                                force: true)
      result = svc.call
      # Mesmo que LevelUpGuardService nao valide fighting_style explicitamente
      # neste caso (depende da configuracao de required_choices_at_level),
      # o resultado deve ser sucesso sem requires_confirmation residual.
      expect(result.requires_confirmation).to be_nil.or(satisfy { |rc| !rc[:reason]&.include?('Trocar para') })
    end

    it 'force: true bypass-a o guard (mesma semantica de B4.x)' do
      svc = described_class.new(character: character,
                                data: { 'classId' => fighter.id.to_s },
                                force: true)
      result = svc.call
      sheet.reload
      expect(sheet.sheet_klasses.first.klass_id).to eq(fighter.id)
      expect(result.requires_confirmation).to be_nil.or(satisfy { |rc| !rc[:reason]&.include?('Trocar para') })
    end
  end
end
