# frozen_string_literal: true

module BattleMapProjectiles
  class Error < StandardError; end
  class Forbidden < Error; end
  class Invalid < Error; end
  class NotFound < Error; end

  KINDS = %w[thrown_weapon arrow bolt].freeze

  module_function

  def launch!(map:, user:, params:)
    raise Forbidden, 'Sem permissao' unless map.readable_by?(user)

    source = SheetItem.includes(sheet: :character).find_by(id: params[:source_item_id])
    raise NotFound, 'Item de origem nao encontrado' unless source
    character = source.sheet.character
    raise Forbidden, 'Sem permissao para usar este item' unless Group.user_is_dm?(user) || character.user_id == user.id

    kind = params[:kind].to_s
    raise Invalid, 'Tipo de projetil invalido' unless KINDS.include?(kind)
    projectile_id = params[:projectile_id].to_s
    roll_group_id = params[:roll_group_id].to_s
    raise Invalid, 'projectile_id e roll_group_id sao obrigatorios' if projectile_id.blank? || roll_group_id.blank?

    attacker = find_token!(map, params[:attacker_token_id])
    target = find_token!(map, params[:target_token_id])
    unless Group.user_is_dm?(user)
      raise Forbidden, 'Token atacante invalido' unless attacker['characterId'].to_s == character.id.to_s
    end

    projectile = nil
    tokens_changed = false
    BattleMap.transaction do
      map.with_lock do
        raise Invalid, 'Projetil ja registrado' if Array(map.dropped_projectiles).any? { |p| p['id'].to_s == projectile_id }
        begin
          source.lock!
        rescue ActiveRecord::RecordNotFound
          raise Invalid, 'Item sem unidades disponiveis'
        end
        raise Invalid, 'Item sem unidades disponiveis' unless source.quantity.to_i.positive?

        projectile = build_projectile(map, source, attacker, target, params, kind)
        if source.quantity.to_i == 1
          source.destroy!
        else
          source.update!(quantity: source.quantity.to_i - 1, equipped: false, slot: nil)
        end
        next_tokens = Array(map.tokens)
        if kind == 'thrown_weapon'
          next_tokens, tokens_changed = remove_equipped_snapshot(next_tokens, attacker['id'], source)
        end
        map.update!(
          dropped_projectiles: Array(map.dropped_projectiles) + [projectile],
          tokens: next_tokens
        )
      end
    end

    MapRealtime::Broadcaster.tokens_changed(map, map.tokens, actor: user) if tokens_changed
    MapRealtime::Broadcaster.dropped_projectiles_changed(map, map.dropped_projectiles, actor: user)
    projectile
  end

  def resolve!(map:, user:, projectile_id:, outcome:)
    raise Forbidden, 'Sem permissao' unless map.readable_by?(user)
    normalized_outcome = outcome.to_s
    raise Invalid, 'Resultado invalido' unless %w[hit miss].include?(normalized_outcome)
    projectile = Array(map.dropped_projectiles).find { |entry| entry['id'].to_s == projectile_id.to_s }
    raise NotFound, 'Projetil nao encontrado' unless projectile
    unless Group.user_is_dm?(user) ||
           (normalized_outcome == 'hit' && projectile_attacker_owned_by?(map, projectile, user))
      raise Forbidden, 'Apenas o mestre resolve o erro; o atacante resolve o acerto ao rolar dano'
    end

    resolved = nil
    map.with_lock do
      list = Array(map.dropped_projectiles).map(&:deep_dup)
      idx = list.index { |p| p['id'].to_s == projectile_id.to_s }
      raise NotFound, 'Projetil nao encontrado' unless idx
      raise Invalid, 'Projetil ja resolvido' unless list[idx]['state'].to_s == 'pending'
      resolved = list[idx].merge(
        'state' => 'landed',
        'outcome' => normalized_outcome,
        'resolvedAt' => Time.current.iso8601
      )
      list[idx] = resolved
      map.update!(dropped_projectiles: list)
    end

    MapRealtime::Broadcaster.dropped_projectiles_changed(map, map.dropped_projectiles, actor: user)
    MapRealtime::Broadcaster.projectile_resolved(map, resolved, actor: user)
    resolved
  end

  def projectile_attacker_owned_by?(map, projectile, user)
    attacker = Array(map.tokens).find do |token|
      token['id'].to_s == projectile['attackerTokenId'].to_s
    end
    return false unless attacker

    Character.where(id: attacker['characterId'], user_id: user.id).exists?
  end

  def pick_up!(map:, user:, projectile_id:, character_id:, token_id:, equip: false)
    raise Forbidden, 'Sem permissao' unless map.readable_by?(user)
    character = Character.includes(:sheet).find_by(id: character_id)
    raise NotFound, 'Personagem nao encontrado' unless character&.sheet
    raise Forbidden, 'Sem permissao para este personagem' unless Group.user_is_dm?(user) || character.user_id == user.id

    created = nil
    map.with_lock do
      list = Array(map.dropped_projectiles).map(&:deep_dup)
      idx = list.index { |p| p['id'].to_s == projectile_id.to_s }
      raise NotFound, 'Projetil nao encontrado' unless idx
      projectile = list[idx]
      raise Invalid, 'O projetil ainda nao caiu' unless projectile['state'].to_s == 'landed'
      token = Array(map.tokens).find { |t| t['id'].to_s == token_id.to_s }
      raise Invalid, 'Token coletor nao encontrado' unless token
      unless token['characterId'].to_s == character.id.to_s
        raise Invalid, 'Token coletor nao pertence ao personagem'
      end
      unless adjacent_to_landing?(token, projectile['landing'])
        raise Invalid, 'Personagem precisa estar em uma celula adjacente ao item'
      end

      item = projectile.fetch('item')
      should_equip = ActiveModel::Type::Boolean.new.cast(equip) && projectile['kind'] == 'thrown_weapon'
      attrs = {
        sheet: character.sheet,
        item_index: item['itemIndex'],
        item_name: item['itemName'],
        category: item['category'],
        quantity: 1,
        equipped: should_equip,
        slot: should_equip ? 'main_hand' : nil,
        source: item['source'].presence || 'map_pickup',
        notes: item['notes'],
        props_json: item['propsJson'].is_a?(Hash) ? item['propsJson'] : {}
      }
      candidate = SheetItem.new(attrs)
      created = should_equip ? candidate.tap(&:save!) : SheetItem.stack_or_create!(candidate).first
      list.delete_at(idx)
      next_tokens = should_equip ? add_equipped_snapshot(map.tokens, token['id'], created) : map.tokens
      map.update!(dropped_projectiles: list, tokens: next_tokens)
    end

    MapRealtime::Broadcaster.tokens_changed(map, map.tokens, actor: user) if created.equipped?
    MapRealtime::Broadcaster.dropped_projectiles_changed(map, map.dropped_projectiles, actor: user)
    created
  end

  def find_token!(map, id)
    token = Array(map.tokens).find { |t| t['id'].to_s == id.to_s }
    raise NotFound, 'Token nao encontrado' unless token
    token.stringify_keys
  end

  def build_projectile(map, source, attacker, target, params, kind)
    {
      'id' => params[:projectile_id].to_s,
      'rollGroupId' => params[:roll_group_id].to_s,
      'kind' => kind,
      'state' => 'pending',
      'attackerTokenId' => attacker['id'].to_s,
      'targetTokenId' => target['id'].to_s,
      'origin' => token_center(attacker),
      'target' => token_center(target),
      'landing' => random_adjacent_cell(map, target),
      'item' => {
        'itemIndex' => source.item_index,
        'itemName' => source.item_name,
        'category' => source.category,
        'source' => source.source,
        'notes' => source.notes,
        'propsJson' => source.props_json || {}
      },
      'createdAt' => Time.current.iso8601
    }
  end

  def token_center(token)
    size = [token['size'].to_i, 1].max
    { 'col' => token['x'].to_f + size / 2.0, 'row' => token['y'].to_f + size / 2.0 }
  end

  def random_adjacent_cell(map, target)
    x = target['x'].to_i
    y = target['y'].to_i
    size = [target['size'].to_i, 1].max
    candidates = []
    ((x - 1)..(x + size)).each do |col|
      ((y - 1)..(y + size)).each do |row|
        next if col >= x && col < x + size && row >= y && row < y + size
        next if col.negative? || row.negative? || col >= map.width || row >= map.height
        candidates << { 'col' => col, 'row' => row }
      end
    end
    free = candidates.reject { |cell| occupied_cell?(map.tokens, cell) }
    (free.presence || candidates).sample || { 'col' => x.clamp(0, map.width - 1), 'row' => y.clamp(0, map.height - 1) }
  end

  def occupied_cell?(tokens, cell)
    Array(tokens).any? do |token|
      size = [token['size'].to_i, 1].max
      cell['col'] >= token['x'].to_i && cell['col'] < token['x'].to_i + size &&
        cell['row'] >= token['y'].to_i && cell['row'] < token['y'].to_i + size
    end
  end

  # Alcance de coleta: o anel de 1 célula ao redor do token E a(s) célula(s)
  # OCUPADA(S) pelo próprio token — pode pegar estando EM CIMA do item (mesma
  # célula) ou adjacente.
  def adjacent_to_landing?(token, landing)
    return false unless landing.is_a?(Hash)
    x = token['x'].to_i
    y = token['y'].to_i
    size = [token['size'].to_i, 1].max
    col = landing['col'].to_i
    row = landing['row'].to_i
    col >= x - 1 && col <= x + size && row >= y - 1 && row <= y + size
  end

  def remove_equipped_snapshot(tokens, token_id, source)
    changed = false
    next_tokens = Array(tokens).map do |token|
      token = token.deep_dup.stringify_keys
      next token unless token['id'].to_s == token_id.to_s

      equipment = Array(token['chibiEquipment'])
      filtered = equipment.reject do |item|
        item = item.stringify_keys
        same_id = item['id'].to_s == source.id.to_s
        same_catalog = source.item_index.present? && item['refId'].to_s == source.item_index.to_s
        same_name = item['name'].to_s.casecmp(source.item_name.to_s).zero?
        same_id || (same_catalog && same_name)
      end
      changed ||= filtered.length != equipment.length
      token['chibiEquipment'] = filtered.presence
      token.compact
    end
    [next_tokens, changed]
  end

  def add_equipped_snapshot(tokens, token_id, item)
    Array(tokens).map do |token|
      token = token.deep_dup.stringify_keys
      next token unless token['id'].to_s == token_id.to_s

      equipment = Array(token['chibiEquipment']).map(&:deep_dup)
      equipment.reject! { |entry| entry.stringify_keys['slot'].to_s == 'main_hand' }
      weapon_props = EquipmentRules.weapon_props(item) rescue nil
      equipment << {
        'id' => item.id.to_s,
        'refId' => item.item_index,
        'name' => item.item_name,
        'category' => item.category,
        'quantity' => 1,
        'equipped' => true,
        'slot' => 'main_hand',
        'weaponProps' => weapon_props&.deep_stringify_keys
      }.compact
      token['chibiEquipment'] = equipment
      token
    end
  end
end
