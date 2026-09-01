require 'rails_helper'

# `damage_bonus_dice` com `applies_to: 'spells'` (a Lâmina Trovejante: +2d8
# trovão em MAGIAS de trovão) NÃO pode virar nota de dano da ARMA — quem rola o
# rider é o front, no cast. Sem o filtro, a espada somava 2d8 em todo golpe.
RSpec.describe MagicItemRules, type: :service do
  def make_magic_item!(slug:, name:, effects:)
    MagicItem.find_or_create_by!(slug: slug) do |mi|
      mi.name = name
      mi.category = 'weapon'
      mi.rarity = 'rare'
      mi.requires_attunement = true
      mi.effects = effects
    end.tap { |mi| mi.update!(effects: effects) if mi.effects != effects }
  end

  let(:sheet_stub) { Object.new }

  # `weapon_bonus_for` é onde a nota nasce (o merge de weapon_mods hoje descarta
  # notes — caminho latente; a fonte viva do front é a estruturada). Testamos a
  # origem: é ela que qualquer consumidor futuro de notes vai herdar.
  def weapon_mods_for(slug, name)
    svc = described_class.new(sheet_stub, equipment: { equipped: {} })
    svc.send(:weapon_bonus_for, { name: name, index: slug, props: { 'magic_item_slug' => slug } })
  end

  it "rider 'spells' fica FORA das notas da arma, mas a arma segue mágica" do
    make_magic_item!(
      slug: 'lamina-trovejante-spec', name: 'Lâmina Trovejante',
      effects: [{ 'kind' => 'damage_bonus_dice', 'dice' => '2d8',
                  'damage_type' => 'trovão', 'applies_to' => 'spells' }],
    )
    mods = weapon_mods_for('lamina-trovejante-spec', 'Lâmina Trovejante')
    expect(mods[:notes]).to eq([])
    expect(mods[:is_magical]).to be true
  end

  it "rider 'both' e SEM applies_to (default weapon) continuam nas notas" do
    make_magic_item!(
      slug: 'cetro-ambivalente-spec', name: 'Cetro Ambivalente',
      effects: [
        { 'kind' => 'damage_bonus_dice', 'dice' => '1d4', 'damage_type' => 'frio', 'applies_to' => 'both' },
        { 'kind' => 'damage_bonus_dice', 'dice' => '1d6', 'damage_type' => 'fogo' },
      ],
    )
    mods = weapon_mods_for('cetro-ambivalente-spec', 'Cetro Ambivalente')
    expect(mods[:notes]).to match_array(['+1d4 frio', '+1d6 fogo'])
  end
end
