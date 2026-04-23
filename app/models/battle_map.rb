# BattleMap = mapa tatico (grid + tokens + fog) usado em sessoes.
#
# Modelo de propriedade hibrido:
# - `user`     : owner / criador. Pode editar e deletar.
# - `group`    : opcional. Quando setado, members do grupo enxergam o mapa.
#
# Authorization rules:
# - read  : DM (site-wide) || owner || (group_id present && group.member?(user))
#           || mapa vinculado a Schedule do mesmo grupo de um personagem do user
#           || mapa vinculado a qualquer Schedule (hub: leitura para conta autenticada)
# - write : DM (site-wide) || owner
#
# Validacoes pesadas:
# - cells e matriz [height][width] de strings. Sem isso o front renderiza
#   index out of bounds e crasha ao paintar.
# - tokens precisa ser array (cada token e validado leniente — front e fonte
#   da verdade do shape porque evolui mais rapido que o backend).
class BattleMap < ApplicationRecord
  TERRAIN_TYPES = %w[empty stone grass water lava wood sand wall].freeze
  # hidden_cells = névoa clássica (mapa + tokens ocultos na célula).
  # hidden_tokens = mapa visível; só tokens com centro na célula ficam ocultos (jogador).
  FOG_MODES = %w[hidden_cells hidden_tokens].freeze
  MIN_DIM = 5
  MAX_DIM = 50

  belongs_to :user
  belongs_to :group, optional: true
  has_many :schedules, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 }
  validates :width,  numericality: { only_integer: true, greater_than_or_equal_to: MIN_DIM, less_than_or_equal_to: MAX_DIM }
  validates :height, numericality: { only_integer: true, greater_than_or_equal_to: MIN_DIM, less_than_or_equal_to: MAX_DIM }
  validates :cell_size_px, numericality: { only_integer: true, greater_than_or_equal_to: 8, less_than_or_equal_to: 128 }
  validates :grid_opacity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :schema_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :distance_display_unit, inclusion: { in: %w[ft m] }
  validates :fog_mode, inclusion: { in: FOG_MODES }
  validates :background_image_pixel_width,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 8192 },
            allow_nil: true
  validates :background_image_pixel_height,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 8192 },
            allow_nil: true
  validate :cell_world_ft_valid

  validate :cells_matrix_well_formed
  validate :tokens_well_formed
  validate :fog_well_formed
  validate :walls_well_formed
  validate :measurements_well_formed
  validate :drawings_well_formed
  validate :aoe_placements_well_formed
  validate :player_permissions_well_formed

  PLAYER_TOOLS = %w[measure pencil aoe].freeze
  DEFAULT_PLAYER_PERMISSIONS = { 'measure' => true, 'pencil' => false, 'aoe' => true }.freeze
  # Multiplos de 5 ft (1,5 m, 3 m, ...) entre 5 e 50 ft por celula.
  ALLOWED_CELL_WORLD_FT = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50].freeze

  # `visible_to` cobre o caso "qualquer mapa que este user pode ver":
  # - DM ve todos (gerenciamento global)
  # - Player ve os proprios + os compartilhados via group_id (membership pelos
  #   personagens daquele grupo) + mapas referenciados por Schedule daqueles grupos
  #   (ex.: mestre vincula mapa pessoal a uma sessao).
  scope :visible_to, ->(user) {
    return none if user.nil?
    if Group.user_is_dm?(user)
      all
    else
      group_ids = user.characters.distinct.pluck(:group_id).compact
      schedule_map_ids =
        if group_ids.any?
          Schedule.where(group_id: group_ids).where.not(battle_map_id: nil).distinct.pluck(:battle_map_id)
        else
          []
        end

      rel = where(user_id: user.id)
      rel = rel.or(where(group_id: group_ids)) if group_ids.any?
      rel = rel.or(where(id: schedule_map_ids)) if schedule_map_ids.any?
      rel
    end
  }

  scope :recent, -> { order(updated_at: :desc) }

  def writable_by?(user)
    return false if user.nil?
    Group.user_is_dm?(user) || user_id == user.id
  end

  # Pergunta canonica: "este player pode usar a ferramenta tool no mapa?"
  # DM sempre pode (para nao bloquear preparacao). Caso contrario consulta
  # o toggle player_permissions (default = DEFAULT_PLAYER_PERMISSIONS).
  def players_can?(tool)
    return false unless PLAYER_TOOLS.include?(tool.to_s)
    perms = player_permissions.is_a?(Hash) ? player_permissions : {}
    val = perms[tool.to_s]
    val.nil? ? DEFAULT_PLAYER_PERMISSIONS[tool.to_s] : !!val
  end

  def readable_by?(user)
    return false if user.nil?
    return true if Group.user_is_dm?(user)
    return true if user_id == user.id
    return true if group_id.present? && group&.member?(user)

    readable_via_linked_schedule?(user) ||
      readable_via_hub_schedule?(user)
  end

  # Deep copy (cells/tokens/fog) para nova posse. Usado ao duplicar mapa na UI
  # e ao continuar mesa entre sessões (`ScheduleContinuity`).
  def self.duplicate_for_user(source, user, name: nil)
    raise ArgumentError, 'user obrigatório' if user.nil?

    copy = source.dup
    copy.user_id = user.id
    copy.name = name.presence || "#{source.name} (Copia)"
    copy.cells = deep_dup_nested_arrays(source.cells)
    copy.tokens = deep_dup_nested_arrays(source.tokens)
    copy.fog = source.fog.nil? ? nil : deep_dup_nested_arrays(source.fog)
    copy.save!
    copy
  end

  def self.deep_dup_nested_arrays(arr)
    return [] if arr.nil?

    arr.map do |row|
      row.is_a?(Array) ? row.dup : (row.respond_to?(:deep_dup) ? row.deep_dup : row.dup)
    end
  end

  private

  # Mapa referenciado por alguma sessão agendada — leitores do hub (não membros).
  def readable_via_hub_schedule?(user)
    return false if user.nil?
    return false unless persisted?

    Schedule.where(battle_map_id: id).exists?
  end

  # Mapa sem `group_id` no BattleMap mas usado numa sessao do grupo do jogador.
  def readable_via_linked_schedule?(user)
    return false unless persisted?

    gids = user.characters.distinct.pluck(:group_id).compact
    return false if gids.empty?

    Schedule.where(battle_map_id: id, group_id: gids).exists?
  end

  def cells_matrix_well_formed
    unless cells.is_a?(Array)
      errors.add(:cells, 'must be an array')
      return
    end

    if cells.size != height
      errors.add(:cells, "row count (#{cells.size}) != height (#{height})")
      return
    end

    cells.each_with_index do |row, idx|
      unless row.is_a?(Array)
        errors.add(:cells, "row #{idx} is not an array")
        return
      end
      if row.size != width
        errors.add(:cells, "row #{idx} length (#{row.size}) != width (#{width})")
        return
      end
    end
  end

  def tokens_well_formed
    return if tokens.is_a?(Array)
    errors.add(:tokens, 'must be an array')
  end

  def fog_well_formed
    return if fog.nil?
    unless fog.is_a?(Array)
      errors.add(:fog, 'must be an array or null')
      return
    end
    return if fog.empty?
    if fog.size != height
      errors.add(:fog, "row count (#{fog.size}) != height (#{height})")
      return
    end
    fog.each_with_index do |row, idx|
      next if row.is_a?(Array) && row.size == width
      errors.add(:fog, "row #{idx} malformed")
      return
    end
  end

  # Cada wall e um hash { 'x' => Int, 'y' => Int, 'side' => 'top'|'left' }
  # com x dentro de [0, width] e y em [0, height] (notar que x ate `width` e
  # valido para arestas left, e y ate `height` para top — convencao de borda).
  def walls_well_formed
    unless walls.is_a?(Array)
      errors.add(:walls, 'must be an array')
      return
    end
    walls.each_with_index do |w, idx|
      unless w.is_a?(Hash)
        errors.add(:walls, "wall #{idx} must be an object")
        return
      end
      x = w['x'] || w[:x]
      y = w['y'] || w[:y]
      side = w['side'] || w[:side]
      unless x.is_a?(Integer) && y.is_a?(Integer) && %w[top left].include?(side.to_s)
        errors.add(:walls, "wall #{idx} malformed (x:#{x.inspect} y:#{y.inspect} side:#{side.inspect})")
        return
      end
      max_x = side.to_s == 'left' ? width : width - 1
      max_y = side.to_s == 'top'  ? height : height - 1
      if x.negative? || x > max_x || y.negative? || y > max_y
        errors.add(:walls, "wall #{idx} out of bounds")
        return
      end
    end
  end

  # Fase E3: regua persistida. Cada item e
  # { id:String, points:[{x:Int,y:Int}+], totalFt:Number, color:String,
  #   label:String?, ownerUserId:Int, createdAt:String }
  def measurements_well_formed
    return if measurements.nil? # column default [] cobre, mas defesa em profundidade
    unless measurements.is_a?(Array)
      errors.add(:measurements, 'must be an array')
      return
    end
    measurements.each_with_index do |m, idx|
      unless m.is_a?(Hash)
        errors.add(:measurements, "item #{idx} must be an object")
        return
      end
      id = m['id'] || m[:id]
      points = m['points'] || m[:points]
      total_ft = m['totalFt'] || m[:totalFt]
      color = m['color'] || m[:color]
      owner = m['ownerUserId'] || m[:ownerUserId]
      unless id.is_a?(String) && color.is_a?(String) && total_ft.is_a?(Numeric) && owner.is_a?(Integer) && points.is_a?(Array) && points.size >= 2
        errors.add(:measurements, "item #{idx} malformed")
        return
      end
      points.each_with_index do |pt, pi|
        unless pt.is_a?(Hash) && (pt['x'] || pt[:x]).is_a?(Integer) && (pt['y'] || pt[:y]).is_a?(Integer)
          errors.add(:measurements, "item #{idx} point #{pi} malformed")
          return
        end
      end
    end
  end

  # Fase E4: lapis persistido. Cada drawing e
  # { id:String, points:[{x:Number,y:Number}+], color:String, widthPx:Number,
  #   ownerUserId:Int, createdAt:String }
  # x/y sao floats (sub-celula) — desenho livre sem snap.
  # Templates de area de efeito confirmados (DM). Mesma convencao camelCase do front.
  def aoe_placements_well_formed
    return if aoe_placements.nil?
    unless aoe_placements.is_a?(Array)
      errors.add(:aoe_placements, 'must be an array')
      return
    end
    shapes = %w[sphere cone cube line cylinder].freeze
    aoe_placements.each_with_index do |p, idx|
      unless p.is_a?(Hash)
        errors.add(:aoe_placements, "item #{idx} must be an object")
        return
      end
      id = p['id'] || p[:id]
      shape = (p['shape'] || p[:shape]).to_s
      size_ft = p['sizeFt'] || p[:sizeFt]
      origin = p['origin'] || p[:origin]
      cells = p['cells'] || p[:cells]
      color = p['color'] || p[:color]
      unless id.is_a?(String) && shapes.include?(shape) && size_ft.is_a?(Numeric) && color.is_a?(String) && origin.is_a?(Hash) && cells.is_a?(Array)
        errors.add(:aoe_placements, "item #{idx} malformed")
        return
      end
      oc = origin['col'] || origin[:col]
      orow = origin['row'] || origin[:row]
      unless oc.is_a?(Integer) && orow.is_a?(Integer)
        errors.add(:aoe_placements, "item #{idx} origin malformed")
        return
      end
      cells.each_with_index do |c, ci|
        unless c.is_a?(Hash) && (c['col'] || c[:col]).is_a?(Integer) && (c['row'] || c[:row]).is_a?(Integer)
          errors.add(:aoe_placements, "item #{idx} cell #{ci} malformed")
          return
        end
      end
    end
  end

  def drawings_well_formed
    return if drawings.nil?
    unless drawings.is_a?(Array)
      errors.add(:drawings, 'must be an array')
      return
    end
    drawings.each_with_index do |d, idx|
      unless d.is_a?(Hash)
        errors.add(:drawings, "item #{idx} must be an object")
        return
      end
      id = d['id'] || d[:id]
      points = d['points'] || d[:points]
      color = d['color'] || d[:color]
      width_px = d['widthPx'] || d[:widthPx]
      owner = d['ownerUserId'] || d[:ownerUserId]
      unless id.is_a?(String) && color.is_a?(String) && width_px.is_a?(Numeric) && owner.is_a?(Integer) && points.is_a?(Array) && points.size >= 2
        errors.add(:drawings, "item #{idx} malformed")
        return
      end
      points.each_with_index do |pt, pi|
        unless pt.is_a?(Hash) && (pt['x'] || pt[:x]).is_a?(Numeric) && (pt['y'] || pt[:y]).is_a?(Numeric)
          errors.add(:drawings, "item #{idx} point #{pi} malformed")
          return
        end
      end
    end
  end

  # Fase E5: { "measure" => bool, "pencil" => bool }. Chaves desconhecidas sao
  # toleradas para forward-compat (se a UI mandar 'spell' algum dia, nao
  # bloqueamos), mas valores precisam ser booleans.
  def player_permissions_well_formed
    return if player_permissions.nil?
    unless player_permissions.is_a?(Hash)
      errors.add(:player_permissions, 'must be an object')
      return
    end
    player_permissions.each do |k, v|
      next if v == true || v == false
      errors.add(:player_permissions, "key #{k} must be boolean")
      return
    end
  end

  def cell_world_ft_valid
    v = cell_world_ft.to_f
    unless ALLOWED_CELL_WORLD_FT.include?(v)
      errors.add(:cell_world_ft, "must be one of #{ALLOWED_CELL_WORLD_FT.join(', ')}")
    end
  end
end
