# app/services/class_rules_helper.rb
module ClassRulesHelper
  module_function

  # ============ Normalização / Aliases ============
  # slugify simples pra comparar ids/nome PT/EN sem acento
  def slugify(str)
    str.to_s.downcase
       .tr("ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç", "AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc")
       .gsub(/[^\w]+/, '_')
       .gsub(/_+/, '_')
       .gsub(/^_|_$/, '')
  end

  # Aliases de grupos de armadura
  ARMOR_GROUP_ALIASES = {
    'leve'   => 'light',
    'light'  => 'light',
    'média'  => 'medium',
    'media'  => 'medium',
    'medium' => 'medium',
    'pesada' => 'heavy',
    'heavy'  => 'heavy',
    'escudos'=> 'shield',
    'escudo' => 'shield',
    'shield' => 'shield'
  }.freeze

  # Aliases de grupos de arma
  WEAPON_GROUP_ALIASES = {
    'armas_simples'  => 'simple',
    'armas simples'  => 'simple',
    'simple'         => 'simple',
    'simples'        => 'simple',
    'armas_marciais' => 'martial',
    'armas marciais' => 'martial',
    'martial'        => 'martial',
    'marciais'       => 'martial'
  }.freeze

  # Alguns aliases comuns de itens (expanda conforme seu catálogo)
  WEAPON_ITEM_ALIASES = {
    'espada_longa'     => 'longsword',
    'espada-longa'     => 'longsword',
    'espadas_longas'   => 'longsword',
    'espada_longa_pt'  => 'longsword',
    'espada_curta'     => 'shortsword',
    'espada-curta'     => 'shortsword',
    'espadas_curtas'   => 'shortsword',
    'rapieira'         => 'rapier',
    'bestas_de_mao'    => 'hand_crossbow',
    'besta_de_mao'     => 'hand_crossbow',
    'besta-leve'       => 'light_crossbow',
    'besta_pesada'     => 'heavy_crossbow',
    'arco_longo'       => 'longbow',
    'arco-longo'       => 'longbow',
    'arco_curto'       => 'shortbow',
    'arco-curto'       => 'shortbow',
    'maça'             => 'mace',
    'clava'            => 'club',
    'adaga'            => 'dagger',
    'lança'            => 'spear',
    'lanca'            => 'spear',
    'azagaia'          => 'javelin',
    'machadinha'       => 'handaxe',
    'picareta_de_guerra'=> 'war_pick',
    'martelo_de_guerra'=> 'warhammer',
    'chicote'          => 'whip',
    'escimitarra'      => 'scimitar',
    'cajado'           => 'quarterstaff'
  }.freeze

  ARMOR_ITEM_ALIASES = {
    'armadura_acolchoada' => 'padded',
    'couro_batido'        => 'studded_leather',
    'couro'               => 'leather',
    'cota_de_anel'        => 'ring_mail',
    'cota_de_malha'       => 'chain_mail',
    'cota_de_talas'       => 'splint',
    'escudo'              => 'shield',
    'escudos'             => 'shield'
  }.freeze

  def normalize_weapon_id(name_or_id)
    key = slugify(name_or_id)
    WEAPON_ITEM_ALIASES[key] || key
  end

  def normalize_armor_id(name_or_id)
    key = slugify(name_or_id)
    ARMOR_ITEM_ALIASES[key] || key
  end

  def normalize_armor_group(str)
    ARMOR_GROUP_ALIASES[slugify(str)] || slugify(str)
  end

  def normalize_weapon_group(str)
    WEAPON_GROUP_ALIASES[slugify(str)] || slugify(str)
  end

  # Extrai grupos e itens explícitos a partir das proficiências declaradas
  # weapon_profs pode ser: ['armas simples','armas marciais','rapieira','espadas longas', ...]
  def split_weapon_proficiencies(weapon_profs)
    groups = []
    items  = []
    Array(weapon_profs).each do |entry|
      s = entry.is_a?(Hash) ? entry[:id] || entry['id'] || entry[:name] || entry['name'] : entry
      next if s.nil?
      g = normalize_weapon_group(s)
      if %w[simple martial].include?(g)
        groups << g
      else
        items << normalize_weapon_id(s)
      end
    end
    [groups.uniq, items.uniq]
  end

  # armor_profs pode ser: %w[leve média escudos] ou equivalentes
  def split_armor_proficiencies(armor_profs)
    groups = []
    Array(armor_profs).each do |entry|
      s = entry.is_a?(Hash) ? entry[:id] || entry['id'] || entry[:name] || entry['name'] : entry
      next if s.nil?
      groups << normalize_armor_group(s)
    end
    groups.uniq
  end

  # ============ Checagens de proficiência ============
  # weapon: hash do catálogo (ou id/nome se preferir fazer o lookup fora)
  def proficient_with_weapon?(weapon, weapon_profs, weapons_catalog:)
    w = weapon.is_a?(Hash) ? weapon : weapons_catalog[normalize_weapon_id(weapon)]
    return false unless w

    groups, items = split_weapon_proficiencies(weapon_profs)

    # 1) Se o item está explicitamente listado
    return true if items.include?(normalize_weapon_id(w[:id] || w['id'] || w[:name] || w['name']))

    # 2) Se o grupo bate
    grp = (w[:group] || w['group']).to_s # 'simple'|'martial'
    return true if grp && groups.include?(grp)

    false
  end

  # armor: hash do catálogo (ou id/nome)
  def proficient_with_armor?(armor, armor_profs, armors_catalog:)
    a = armor.is_a?(Hash) ? armor : armors_catalog[normalize_armor_id(armor)]
    return false unless a

    groups = split_armor_proficiencies(armor_profs)

    cat = (a[:category] || a['category']).to_s # 'light'|'medium'|'heavy'|'shield'
    return groups.include?(cat)
  end

  def proficient_with_shield?(armor_profs)
    groups = split_armor_proficiencies(armor_profs)
    groups.include?('shield')
  end

  # ============ Avisos de equipamento para o FE ============
  # summary: resultado do apply_with_derived (ou algo equivalente)
  # Espera: summary[:armor_proficiencies], summary[:weapon_proficiencies], summary[:derived_rules], picks/equipment
  def equipment_warnings(summary, weapons_catalog:, armors_catalog:)
    warnings = []

    armor_profs   = summary[:armor_proficiencies]   || []
    weapon_profs  = summary[:weapon_proficiencies]  || []
    derived       = summary[:derived_rules]         || {}
    equipment     = summary.dig(:picks, :equipment) || {}

    # ARMADURA
    armor_id = equipment[:armor_id] || equipment['armor_id']
    if armor_id
      armor_obj = armors_catalog[normalize_armor_id(armor_id)]
      unless proficient_with_armor?(armor_obj, armor_profs, armors_catalog: armors_catalog)
        warnings << "Armadura equipada sem proficiência"
      end
    end

    # ESCUDO
    if truthy?(equipment[:shield_equipped] || equipment['shield_equipped'])
      unless proficient_with_shield?(armor_profs)
        warnings << "Escudo equipado sem proficiência"
      end
    end

    # ARMA PRINCIPAL
    weapon_main_id = equipment[:weapon_main_id] || equipment['weapon_main_id']
    if weapon_main_id
      w1 = weapons_catalog[normalize_weapon_id(weapon_main_id)]
      unless proficient_with_weapon?(w1, weapon_profs, weapons_catalog: weapons_catalog)
        warnings << "Arma principal sem proficiência"
      end
    end

    # ARMA SECUNDÁRIA (dual wield)
    weapon_off_id = equipment[:weapon_off_id] || equipment['weapon_off_id']
    if weapon_off_id
      w2 = weapons_catalog[normalize_weapon_id(weapon_off_id)]
      unless proficient_with_weapon?(w2, weapon_profs, weapons_catalog: weapons_catalog)
        warnings << "Arma secundária sem proficiência"
      end
    end

    # Regras de AC alternativa (ex.: Unarmored Defense) bloqueadas por armadura?
    if derived.dig(:ac, :formula).present?
      if armor_id
        warnings << "Defesa sem Armadura não se aplica enquanto estiver usando armadura"
      end
      if truthy?(equipment[:shield_equipped] || equipment['shield_equipped']) && !derived.dig(:ac, :allows_shield)
        warnings << "A fórmula de AC ativa não permite escudo"
      end
    end

    warnings
  end

  # ============ Utils ============
  def truthy?(val)
    [true, 'true', 1, '1', 'yes', 'on'].include?(val)
  end
end
