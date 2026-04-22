# Converte proficiências textuais do CLASS_RULES em ids normalizados
# para comparar com weapons_catalog / armors_catalog
module ClassProficiencyAdapter
  module_function

  # ============ Normalizadores ============
  def slugify(str)
    str.to_s.downcase
       .tr("ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç", "AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc")
       .gsub(/[^\w]+/, '_')
       .gsub(/_+/, '_')
       .gsub(/^_|_$/, '')
  end

  ARMOR_GROUPS = {
    'leve' => 'light', 'light' => 'light',
    'média' => 'medium', 'media' => 'medium', 'medium' => 'medium',
    'pesada' => 'heavy', 'heavy' => 'heavy',
    'escudos' => 'shield', 'escudo' => 'shield', 'shield' => 'shield'
  }.freeze

  WEAPON_GROUPS = {
    'armas_simples' => 'simple', 'armas simples' => 'simple',
    'simple' => 'simple', 'simples' => 'simple',
    'armas_marciais' => 'martial', 'armas marciais' => 'martial',
    'martial' => 'martial', 'marciais' => 'martial'
  }.freeze

  ITEM_ALIASES = {
    # Armas
    'espada_longa' => 'longsword', 'espada-longa' => 'longsword', 'espadas_longas' => 'longsword',
    'espada_curta' => 'shortsword', 'espadas_curtas' => 'shortsword',
    'rapieira' => 'rapier',
    'bestas_de_mao' => 'hand_crossbow', 'besta_de_mao' => 'hand_crossbow',
    'besta_leve' => 'light_crossbow', 'besta-pesada' => 'heavy_crossbow',
    'arco_longo' => 'longbow', 'arco_curto' => 'shortbow',
    'clava' => 'club', 'maça' => 'mace', 'adaga' => 'dagger',
    'lança' => 'spear', 'azagaia' => 'javelin', 'machadinha' => 'handaxe',
    'martelo_de_guerra' => 'warhammer', 'picareta_de_guerra' => 'war_pick',
    'chicote' => 'whip', 'escimitarra' => 'scimitar', 'cajado' => 'quarterstaff',
    # Armaduras
    'couro' => 'leather', 'couro_batido' => 'studded_leather',
    'acolchoada' => 'padded',
    'cota_de_malha' => 'chain_mail', 'cota_de_anel' => 'ring_mail',
    'cota_de_talas' => 'splint', 'escudo' => 'shield'
  }.freeze

  def normalize_entry(entry)
    key = slugify(entry)
    ARMOR_GROUPS[key] || WEAPON_GROUPS[key] || ITEM_ALIASES[key] || key
  end

  # ============ Adaptadores ============
  def normalize_weapon_proficiencies(list)
    Array(list).map { |e| normalize_entry(e) }.uniq
  end

  def normalize_armor_proficiencies(list)
    Array(list).map { |e| normalize_entry(e) }.uniq
  end

  def normalize_all(class_rule)
    {
      armor: normalize_armor_proficiencies(class_rule[:armor_proficiencies]),
      weapons: normalize_weapon_proficiencies(class_rule[:weapon_proficiencies]),
      tools: class_rule[:tool_proficiencies] # geralmente já é estruturado
    }
  end
end
