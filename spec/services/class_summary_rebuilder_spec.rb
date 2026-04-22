# frozen_string_literal: true

require 'rails_helper'

# Verifica que ClassSummaryRebuilder reconstroi Sheet#class_summary
# (armaduras/armas/ferramentas) idempotentemente a partir das fontes canônicas:
#   * ClassRules.apply (regras PHB por nível/subclasse)
#   * SubKlass.levels_json (grants extras)
#   * metadata.class_choices.per_level[N].instruments (picks do wizard)
RSpec.describe ClassSummaryRebuilder do
  let!(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "csr_#{SecureRandom.hex(4)}@example.com",
      username: "csr#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end
  let!(:bard) do
    Klass.find_or_create_by!(api_index: 'bard') do |k|
      k.name = 'Bardo'
      k.hit_die = 8
      k.subclass_level = 3
    end
  end
  let!(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  def build_sheet(level: 1, instruments: [], class_summary: {}, extra_meta: {})
    character = Character.create!(user: user, name: 'Spec PC', background: 'Test')
    metadata = {
      'class_choices' => { 'per_level' => { '1' => { 'instruments' => instruments } } }
    }.deep_merge(extra_meta)
    sheet = Sheet.create!(
      character: character,
      race_id: race.id,
      str: 8, dex: 14, con: 12, int: 10, wis: 10, cha: 16,
      hp_max: 10, hp_current: 10,
      class_summary: class_summary,
      metadata: metadata
    )
    SheetKlass.create!(sheet: sheet, klass: bard, level: level)
    sheet
  end

  it 'preenche armor/weapon/tools de Bardo nv1 a partir de ClassRules' do
    sheet = build_sheet(level: 1, instruments: %w[Alaúde Lira Flauta])
    described_class.call(sheet)
    sheet.reload
    cs = sheet.read_attribute(:class_summary) || {}
    expect(Array(cs['armor_proficiencies'])).to be_present
    expect(Array(cs['weapon_proficiencies'])).to be_present
    tools = Array(cs['tools']).map(&:to_s)
    expect(tools).to include('Alaúde', 'Lira', 'Flauta')
  end

  it 'é idempotente: chamadas repetidas mantêm o mesmo resultado' do
    sheet = build_sheet(level: 1, instruments: %w[Alaúde Lira Flauta])
    described_class.call(sheet)
    first = sheet.reload.read_attribute(:class_summary).deep_dup
    described_class.call(sheet)
    second = sheet.reload.read_attribute(:class_summary)
    expect(second).to eq(first)
  end

  it 'lê instrumentos de class_choices.instruments_selected (legado root)' do
    sheet = build_sheet(level: 1, instruments: [], extra_meta: {
      'class_choices' => { 'instruments_selected' => %w[Tambor Gaita Bandolim] }
    })
    described_class.call(sheet)
    tools = Array(sheet.reload.read_attribute(:class_summary)['tools']).map(&:to_s)
    expect(tools).to include('Tambor', 'Gaita', 'Bandolim')
  end

  it 'mescla skills previamente persistidas quando rebuilder roda sem novos picks' do
    sheet = build_sheet(level: 1, instruments: %w[Alaúde Lira Flauta])
    sheet.update_columns(class_summary: { 'skills' => %w[acrobatics performance] })
    described_class.call(sheet)
    cs = sheet.reload.read_attribute(:class_summary)
    expect(Array(cs['skills'])).to include('acrobatics', 'performance')
  end
end
