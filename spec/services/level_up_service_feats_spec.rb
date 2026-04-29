# frozen_string_literal: true

require 'rails_helper'

# Camada A.2 — ASI feats no LevelUpService e ProgressionEditService.
#
# Reproduz o cenario real "Adimael Neverdie escolhe Observador ao subir para
# nivel 4 de Mago". O fluxo do front grava `metadata.class_choices.per_level['4'].asi`
# com `mode='feat'`, `featId='observador'`, `featAbility='wis'`. Esperamos que:
#
#   1. Seja criado um `SheetFeat` no DB.
#   2. `metadata['feats']` tenha entrada com `ability_bonuses` resolvidos.
#   3. `CharacterSheetSummaryService` reflita `+1 SAB` em `abilities[:scores][:wis]`.
#
# Hoje (red baseline) NENHUM desses tres invariantes e satisfeito por nenhum dos
# dois caminhos: o feat e gravado SOMENTE como string em `per_level[N].asi.featId`,
# ninguem chama `FeatAssignmentService`, e `build_abilities` so trata
# `mode in ['attributes','plus2','plus1x2']` — `mode == 'feat'` e silenciosamente
# ignorado.
#
# Quando os fixes da Camada A virem GREEN, este spec garante regressao zero.
RSpec.describe 'ASI feat no level-up e edit (Camada A.2)' do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "asi_feat_#{SecureRandom.hex(4)}@example.com",
      username: "asifeat#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) do
    SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
  end
  let(:klass) do
    # api_index 'wizard' faz com que LevelUpService respeite branches de Wizard.
    # Importante: nao acrescentar sufixo aleatorio no api_index — alguns
    # fallbacks (p.ex. ClassProfileService) batem por string igual a 'wizard'.
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'
      k.hit_die = 6
      k.subclass_level = 2
    end
  end

  # Mago precisa de sub_klass a partir do nivel 2 (LevelUpGuardService valida).
  # Usamos 'evocacao' como subclass canonica do Mago.
  let(:sub_klass) do
    SubKlass.find_or_create_by!(klass_id: klass.id, api_index: 'evocacao') do |s|
      s.name = 'Escola de Evocação'
    end
  end

  # Garantia de que o Feat 'observador' esteja persistido em formato JSON valido.
  # Apos os fixes da Camada A1, parse_jsonish tambem aceita a string corrompida
  # — mas aqui usamos o caminho feliz para isolar bugs do level-up/edit dos bugs
  # de serializacao ja cobertos pelo feat_rules_all_feats_shape_spec.
  before(:all) do
    yaml = YAML.load_file(Rails.root.join('config', 'feats_improved.yml')).fetch('feats')
    obs = yaml.fetch('observador')
    Feat.find_or_create_by!(api_index: 'observador') do |f|
      f.name                = obs['name']
      f.description         = obs['description']
      f.prerequisites       = (obs['prerequisites']       || {}).to_json
      f.ability_bonuses     = (obs['ability_bonuses']     || {}).to_json
      f.proficiency_bonuses = (obs['proficiency_bonuses'] || {}).to_json
      f.features            = (obs['features']            || {}).to_json
      f.cantrips            = (obs['cantrips']            || {}).to_json
      f.spells              = (obs['spells']              || {}).to_json
      f.special_rules       = (obs['special_rules']       || {}).to_json
    end
  end

  # Cria uma sheet de Mago nivel 3 com base scores 14 em SAB (para somar +1 do
  # Observador e bater 15) e per_level vazio nos niveis 2 e 3 (sem ASI antes).
  def build_mago_lvl3
    character = Character.create!(user: user, name: "Adimael Spec #{SecureRandom.hex(2)}", background: 'Sage')
    sheet = Sheet.create!(
      character: character,
      race: race,
      sub_race: sub_race,
      str: 10, dex: 12, con: 14, int: 16, wis: 14, cha: 10,
      hp_max: 20, hp_current: 20,
      current_level: 3,
      metadata: {
        # Contrato do CharacterProvisioningService: toda sheet criada via wizard
        # carrega base_ability_scores (point-buy + racial). Sem isso,
        # sync_ability_columns_from_metadata! degrada para ler `sheet.wis` como
        # base, somando incrementos por cima de totais ja persistidos a cada
        # re-edit (bug ortogonal). Como o spec foca no fix do ASI feat, fixamos
        # a base aqui para garantir idempotencia das edicoes.
        'base_ability_scores' => {
          'str' => 10, 'dex' => 12, 'con' => 14, 'int' => 16, 'wis' => 14, 'cha' => 10
        },
        'class_choices' => {
          'per_level' => {
            '2' => {},
            '3' => {}
          },
          'skills_selected' => %w[Arcanismo História]
        },
        # class_summary minimo para CharacterSheetSummaryService nao crashar.
        # `spellcasting` HASH (nao string) por causa do bug ortogonal em
        # ClassProfileService#dig — ver
        # spec/services/feat_assignment_service_all_feats_spec.rb.
        'class_summary' => {
          'spellcasting' => { 'ability' => 'INT', 'preparation' => 'prepared' },
          'armor_proficiencies' => []
        }
      }
    )
    SheetKlass.create!(sheet: sheet, klass: klass, sub_klass: sub_klass, level: 3)
    sheet
  end

  # Per_level row no shape canonico que `LevelChoiceNormalizer.normalize_row`
  # produz a partir do `asiChoice` que o front envia. Ja normalizado para focar
  # o spec no que importa: o consumo desse `asi` por LevelUp / ProgressionEdit.
  def asi_observador_row
    {
      'asi' => {
        'mode' => 'feat',
        'featId' => 'observador',
        'featAbility' => 'wis',
        'choices' => { 'ability' => 'wis' }
      }
    }
  end

  def summary_for(sheet)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    raise "summary nil: #{cmd.try(:errors)&.full_messages.inspect}" if cmd.nil?

    cmd.respond_to?(:result) ? cmd.result : cmd
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Caminho 1: LevelUpService chamado direto pelo controller de SheetKlasses.
  # O front pode gravar per_level[N] em outro endpoint antes; aqui simulamos
  # esse pre-set no metadata e verificamos se LevelUpService honra o asi.feat.
  # ──────────────────────────────────────────────────────────────────────────
  describe 'LevelUpService.call(levels: 1) com per_level[N].asi.featId' do
    it 'cria SheetFeat para o feat escolhido como ASI', :aggregate_failures do
      sheet = build_mago_lvl3
      meta = sheet.metadata.deep_dup
      meta['class_choices']['per_level']['4'] = asi_observador_row
      sheet.update!(metadata: meta)

      result = LevelUpService.call(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
      expect(result).to be_success,
        "LevelUpService falhou: #{result.errors.full_messages.inspect}"

      sheet.reload
      sheet_feat = sheet.sheet_feats.joins(:feat).where(feats: { api_index: 'observador' }).first
      expect(sheet_feat).to be_present,
        "esperado SheetFeat(api_index='observador') apos level-up.\n" \
        "  sheet_feats=#{sheet.sheet_feats.includes(:feat).map { |sf| { feat: sf.feat&.api_index, lvl: sf.level_gained } }.inspect}\n" \
        "  (impacto: feat selecionada no wizard de level-up some — bug do Adimael)"
      expect(sheet_feat.level_gained).to eq(4),
        "level_gained deveria ser 4, veio #{sheet_feat.level_gained}"
    end

    it 'persiste entrada em metadata["feats"] com ability_bonuses do Observador', :aggregate_failures do
      sheet = build_mago_lvl3
      meta = sheet.metadata.deep_dup
      meta['class_choices']['per_level']['4'] = asi_observador_row
      sheet.update!(metadata: meta)

      LevelUpService.call(sheet_id: sheet.id, klass_id: klass.id, levels: 1)

      sheet.reload
      feats_meta = Array(sheet.metadata['feats'])
      observador_entry = feats_meta.find { |e| (e['feat_id'] || e[:feat_id]).to_s == 'observador' }
      expect(observador_entry).to be_present,
        "metadata['feats'] nao contem o Observador.\n" \
        "  feats=#{feats_meta.inspect}\n" \
        "  (impacto: build_abilities ignora bonus de feat e ficha mostra +0 SAB)"
      expect(observador_entry['ability_bonuses']).to be_present
      ab = observador_entry['ability_bonuses']
      # Observador da +1 SAB e +1 INT (ver config/feats_improved.yml).
      expect(ab['wis'].to_i).to eq(1)
      expect(ab['int'].to_i).to eq(1)
    end

    it 'CharacterSheetSummaryService reflete +1 SAB do Observador em abilities[:scores]' do
      sheet = build_mago_lvl3
      meta = sheet.metadata.deep_dup
      meta['class_choices']['per_level']['4'] = asi_observador_row
      sheet.update!(metadata: meta)

      LevelUpService.call(sheet_id: sheet.id, klass_id: klass.id, levels: 1)

      summary = summary_for(sheet.reload)
      expect(summary[:abilities][:scores][:wis]).to eq(15),
        "esperado wis=15 (base 14 + 1 do Observador), veio #{summary[:abilities][:scores][:wis]}\n" \
        "  abilities=#{summary[:abilities].inspect}\n" \
        "  (impacto: jogador escolhe Observador mas ficha mostra SAB inalterada — exato bug do Adimael)"
      expect(summary[:abilities][:scores][:int]).to eq(17),
        "esperado int=17 (base 16 + 1 do Observador), veio #{summary[:abilities][:scores][:int]}"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Caminho 2: ProgressionEditService chamado pelo edit de ficha ativa.
  # Mesmo invariante: ao gravar `levelChoice` com asiChoice mode='feat', o feat
  # tem que sair pela porta da frente — DB + metadata['feats'] + summary.
  # ──────────────────────────────────────────────────────────────────────────
  describe 'CharacterSheetEdits::ProgressionEditService#apply!' do
    def build_mago_lvl4_aguardando_feat
      sheet = build_mago_lvl3
      sheet.sheet_klasses.first.update!(level: 4)
      sheet.update!(current_level: 4)
      sheet
    end

    let(:edit_data) do
      {
        'levelChoice' => {
          'level' => 4,
          'asiChoice' => {
            'mode' => 'feat',
            'featId' => 'observador',
            'featAbility' => 'wis',
            'featGrantChoices' => {}
          }
        }
      }
    end

    it 'cria SheetFeat para o feat escolhido na edicao do nivel 4', :aggregate_failures do
      sheet = build_mago_lvl4_aguardando_feat
      svc = CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character, data: edit_data, level: 4
      )
      result = svc.call
      expect(result).to be_a(CharacterSheetEdits::BaseSheetEditService::Result)

      sheet.reload
      sheet_feat = sheet.sheet_feats.joins(:feat).where(feats: { api_index: 'observador' }).first
      expect(sheet_feat).to be_present,
        "ProgressionEditService nao criou SheetFeat para 'observador'.\n" \
        "  per_level[4]=#{sheet.metadata.dig('class_choices','per_level','4').inspect}\n" \
        "  (impacto: edicao de ficha aceita o feat mas nao registra em sheet_feats)"
      expect(sheet_feat.level_gained).to eq(4)
    end

    it 'persiste entrada em metadata["feats"] com ability_bonuses do Observador' do
      sheet = build_mago_lvl4_aguardando_feat
      CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character, data: edit_data, level: 4
      ).call

      sheet.reload
      feats_meta = Array(sheet.metadata['feats'])
      observador_entry = feats_meta.find { |e| (e['feat_id'] || e[:feat_id]).to_s == 'observador' }
      expect(observador_entry).to be_present,
        "metadata['feats'] nao contem o Observador apos edit.\n" \
        "  feats=#{feats_meta.inspect}"
      ab = observador_entry['ability_bonuses']
      expect(ab['wis'].to_i).to eq(1)
      expect(ab['int'].to_i).to eq(1)
    end

    it 'CharacterSheetSummaryService reflete +1 SAB apos edicao' do
      sheet = build_mago_lvl4_aguardando_feat
      CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character, data: edit_data, level: 4
      ).call

      summary = summary_for(sheet.reload)
      expect(summary[:abilities][:scores][:wis]).to eq(15),
        "esperado wis=15 (base 14 + 1 do Observador), veio #{summary[:abilities][:scores][:wis]}"
    end

    it 'Perito no nivel 4 aplica skillsAndTools na ficha' do
      sheet = build_mago_lvl4_aguardando_feat
      CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character,
        level: 4,
        data: {
          'levelChoice' => {
            'level' => 4,
            'asiChoice' => {
              'mode' => 'feat',
              'featId' => 'perito',
              'featGrantChoices' => {
                'skillsAndTools' => ['Investigação', 'Natureza', 'Utensílios de Cozinheiro']
              }
            }
          }
        }
      ).call

      sheet.reload
      perito = Array(sheet.metadata['feats']).find { |f| f['feat_id'].to_s == 'perito' }
      expect(perito).to be_present
      expect(Array(perito.dig('proficiency_bonuses', 'skills'))).to include('Investigação', 'Natureza')
      expect(Array(perito.dig('proficiency_bonuses', 'tools'))).to include('Utensílios de Cozinheiro')

      summary = summary_for(sheet)
      expect(Array(summary.dig(:proficiencies, :skills, :feat))).to include('Investigação', 'Natureza')
      expect(Array(summary.dig(:proficiencies, :tools))).to include('Utensílios de Cozinheiro')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Idempotencia / re-edit: editar o mesmo nivel 4 trocando Observador para
  # Resiliente nao deve duplicar SheetFeat nem somar bonus duas vezes.
  # ──────────────────────────────────────────────────────────────────────────
  describe 'idempotencia ao re-editar o ASI do mesmo nivel' do
    let(:resiliente_yaml) do
      YAML.load_file(Rails.root.join('config', 'feats_improved.yml')).fetch('feats').fetch('resiliente')
    end

    before do
      Feat.find_or_create_by!(api_index: 'resiliente') do |f|
        f.name                = resiliente_yaml['name']
        f.description         = resiliente_yaml['description']
        f.prerequisites       = (resiliente_yaml['prerequisites']       || {}).to_json
        f.ability_bonuses     = (resiliente_yaml['ability_bonuses']     || {}).to_json
        f.proficiency_bonuses = (resiliente_yaml['proficiency_bonuses'] || {}).to_json
        f.features            = (resiliente_yaml['features']            || {}).to_json
        f.cantrips            = (resiliente_yaml['cantrips']            || {}).to_json
        f.spells              = (resiliente_yaml['spells']              || {}).to_json
        f.special_rules       = (resiliente_yaml['special_rules']       || {}).to_json
      end
    end

    it 'troca Observador por Resiliente sem deixar SheetFeat orfao nem somar bonus duplicado' do
      sheet = build_mago_lvl3
      sheet.sheet_klasses.first.update!(level: 4)
      sheet.update!(current_level: 4)

      # Edit 1: escolhe Observador.
      CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character,
        data: {
          'levelChoice' => {
            'level' => 4,
            'asiChoice' => { 'mode' => 'feat', 'featId' => 'observador', 'featAbility' => 'wis' }
          }
        },
        level: 4
      ).call

      # Edit 2: troca para Resiliente (CON).
      CharacterSheetEdits::ProgressionEditService.new(
        character: sheet.character,
        data: {
          'levelChoice' => {
            'level' => 4,
            'asiChoice' => { 'mode' => 'feat', 'featId' => 'resiliente', 'featAbility' => 'con' }
          }
        },
        level: 4
      ).call

      sheet.reload
      lvl4_feats = sheet.sheet_feats.where(level_gained: 4)
      expect(lvl4_feats.count).to eq(1),
        "esperado 1 SheetFeat no nivel 4 apos re-edit, veio #{lvl4_feats.count}: " \
        "#{lvl4_feats.includes(:feat).map { |sf| sf.feat&.api_index }.inspect}"
      expect(lvl4_feats.first.feat.api_index).to eq('resiliente')

      summary = summary_for(sheet)
      meta_feats = Array(sheet.metadata['feats']).map { |f| { id: f['feat_id'], lvl: f['level_gained'], ab: f['ability_bonuses'] } }
      expect(summary[:abilities][:scores][:wis]).to eq(14),
        "esperado wis=14 (Observador removido), veio #{summary[:abilities][:scores][:wis]}\n" \
        "  metadata['feats']=#{meta_feats.inspect}\n" \
        "  sources[:wis]=#{summary[:abilities][:sources][:wis].inspect}"
      expect(summary[:abilities][:scores][:con]).to eq(15),
        "esperado con=15 (base 14 + 1 do Resiliente), veio #{summary[:abilities][:scores][:con]}"
    end
  end
end
