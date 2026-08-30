class SheetItem < ApplicationRecord
  belongs_to :sheet
  belongs_to :item, optional: true

  # ── Slots aceitos ─────────────────────────────────────────────────
  # Slots clássicos (combate / armadura)
  COMBAT_SLOTS    = %w[main_hand off_hand armor shield].freeze
  # Slots de acessório (Fase 2.1) — desbloqueiam itens como anel da
  # vontade, manopla da força, manto de resistência, botas aladas, etc.
  # ring_left/ring_right permitem ATÉ 2 anéis equipados simultaneamente.
  # `face` (rosto: máscara, óculos) entrou em 29/08; `circlet` foi FUNDIDO em
  # `helmet` na mesma data (cabeça inteira: elmo, chapéu, tiara). Medido antes:
  # zero linhas persistidas e zero catálogo usavam `circlet` — a fusão é só de
  # vocabulário, e `canonicalize_legacy_slot` cobre cliente da janela de deploy.
  ACCESSORY_SLOTS = %w[
    ring_left ring_right amulet cloak boots helmet gloves belt
    face earrings bracelet_left bracelet_right
  ].freeze
  # Slots de utilidade — nao existem no PHB, sao HOUSERULE desta mesa.
  # `quiver` guarda municao; `instrument` da lugar ao instrumento musical, que
  # nas regras e FERRAMENTA (PHB cap. 5) e nao tem casa nenhuma. A mesa quis um
  # lugar para ele; para o bardo, e o instrumento que serve de foco de conjuracao.
  # `bag` (29/08): a BOLSA equipada — houserule como os outros dois.
  UTILITY_SLOTS   = %w[quiver instrument bag].freeze
  ALL_SLOTS       = (COMBAT_SLOTS + ACCESSORY_SLOTS + UTILITY_SLOTS).freeze

  # Slot legado → canônico, num lugar SÓ: o `equip` dos dois controllers valida
  # o param ANTES do modelo, então cada porta precisa da mesma tradução — e uma
  # cópia por porta é como a próxima fusão de slot quebra só metade delas.
  def self.canonicalize_slot(value)
    v = value.to_s
    v == 'circlet' ? 'helmet' : v
  end

  validates :sheet_id, presence: true
  validates :item_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slot, inclusion: { in: ALL_SLOTS, allow_nil: true,
                                message: "deve ser um destes: #{ALL_SLOTS.join(', ')}" }
  validate  :validate_equipment_proficiency

  before_validation :canonicalize_legacy_slot
  before_validation :resolve_catalog_item
  before_destroy :release_ammunition_contents, if: :quiver?
  before_destroy :release_bag_contents, if: :bag?
  before_destroy :release_belt_contents, if: :belt?
  before_save :sanitize_slot
  after_save  :enforce_slot_exclusivity_and_conflicts

  # ── Empilhamento de itens idênticos ────────────────────────────────
  # Chaves de `props_json` que representam ESTADO POR-INSTÂNCIA (não atributo do
  # tipo do item): cargas atuais de varinha/cajado, sintonização, usos restantes.
  # Itens que carregam qualquer uma NÃO empilham — duas varinhas 7/7 são duas
  # instâncias com contadores independentes, não uma pilha de 2 com 1 contador.
  # `pact_weapon` entra aqui pelo mesmo motivo de `attuned`: é a MARCA de uma
  # instância. Sem ela na lista, duas espadas longas idênticas empilhariam e a
  # arma de pacto viraria "2 espadas, uma delas de pacto" — sem dizer qual.
  PER_INSTANCE_PROP_KEYS = %w[charges attuned uses uses_remaining uses_left pact_weapon].freeze
  AMMUNITION_CONTAINER_PROP = 'quiver_sheet_item_id'.freeze
  # Item guardado DENTRO de uma bolsa da mesma ficha. Mesmo desenho da aljava,
  # da montaria e da carroça: o item nunca sai da ficha — a localização é um
  # PONTEIRO. Bolsa dentro de bolsa é uma linha de bolsa com este ponteiro
  # (ciclo barrado no `StowInBagService`).
  BAG_CONTAINER_PROP = 'bag_sheet_item_id'.freeze
  BELT_CONTAINER_PROP = 'belt_sheet_item_id'.freeze
  # Item guardado NA MONTARIA. Aponta o `id` do companion (jsonb
  # `sheets.companions`), nao um sheet_item — a montaria nao e um item.
  MOUNT_CONTAINER_PROP = 'mount_companion_id'.freeze

  # Ponto único de criação com empilhamento, ATÔMICO e serializado por ficha.
  # Trava a `sheet` (FOR UPDATE) para evitar corrida read-then-write em
  # double-submit / POSTs paralelos (duas adições virariam 2 linhas ou perderiam
  # a soma). `item.validate` (que dispara `resolve_catalog_item` → ItemResolver,
  # com escrita no catálogo) roda DENTRO da transação para não deixar `Item`
  # órfão em caso de rollback. Retorna `[record, created_bool]`.
  def self.stack_or_create!(item)
    sheet = item.sheet || Sheet.find(item.sheet_id)
    sheet.with_lock do
      item.validate
      raise ActiveRecord::RecordInvalid, item if item.errors.any?

      existing = stackable_match_for(item)
      if existing
        existing.update!(quantity: existing.quantity.to_i + item.quantity.to_i)
        next [existing, false]
      end

      item.position = next_position_for(item.sheet_id) if item.position.blank?
      item.save!
      [item, true]
    end
  end

  # Próxima posição livre (fim da lista) para a bolsa da ficha. Ordenamos sempre
  # por `position, id`, então itens novos vão para o fim.
  def self.next_position_for(sheet_id)
    (where(sheet_id: sheet_id).maximum(:position) || 0) + 1
  end

  # Procura um SheetItem JÁ existente, NÃO-equipado e idêntico ao `item`
  # (recém-construído) para somar `quantity` em vez de criar uma linha nova.
  # "Idêntico" =
  #   • não-equipado e SEM estado por-instância (cargas/sintonia/usos);
  #   • mesma origem `source` E não-`dm_grant` (itens do DM têm fluxo próprio de
  #     auditoria no endpoint `grant`, com scoping por source — não mesclar aqui);
  #   • mesmo catálogo (`item_index`, resolvido por `resolve_catalog_item`),
  #     OU mesmo `item_name` (case-insensitive) + `category` quando custom;
  #   • `props_json` equivalente E `notes` equivalente (nil/'' contam como iguais).
  # Bug: "Poção de Cura" adicionada 2× virava 2 linhas em vez de somar.
  def self.stackable_match_for(item)
    return nil if item.nil? || item.equipped?
    return nil if item.sheet_id.blank?
    return nil if per_instance_state?(item.props_json)
    # Itens do DM (dm_grant) têm fluxo de empilhamento próprio (scoped por source)
    # no endpoint `grant`; o create genérico não deve mesclar com/para essa pilha.
    return nil if item.source.to_s == 'dm_grant'

    scope = where(sheet_id: item.sheet_id, equipped: false)
              .where.not(source: 'dm_grant')
              .where(source: item.source)
    scope = scope.where.not(id: item.id) if item.persisted?

    candidates =
      if item.item_index.present?
        scope.where(item_index: item.item_index)
      else
        name = item.item_name.to_s.strip
        return nil if name.empty?
        rel = scope.where(item_id: nil).where('LOWER(item_name) = ?', name.downcase)
        item.category.present? ? rel.where(category: item.category) : rel.where(category: nil)
      end

    want = normalize_stack_props(item.props_json)
    want_notes = item.notes.to_s.strip
    candidates.order(:id).detect do |c|
      normalize_stack_props(c.props_json) == want && c.notes.to_s.strip == want_notes
    end
  end

  # nil/{} e chaves com valor nil são tratados como hash vazio para comparação.
  def self.normalize_stack_props(props)
    h = props.is_a?(Hash) ? props : {}
    h.reject { |_, v| v.nil? }.stringify_keys
  end

  # true quando `props_json` carrega estado por-instância (cargas/sintonia/usos)
  # que não pode ser compartilhado numa pilha.
  def self.per_instance_state?(props)
    h = props.is_a?(Hash) ? props.stringify_keys : {}
    PER_INSTANCE_PROP_KEYS.any? { |k| !h[k].nil? && h[k] != false }
  end

  # Serialização canônica usada pelo frontend (CharacterBag/HubBag).
  # Mantém o mesmo shape que `EquipmentProfileService#as_json` para que o
  # mapper único `mapApiInventoryItem` funcione tanto vindo do GET character
  # quanto dos endpoints `/sheet_items`.
  def as_inventory_json
    weapon_props = begin
      EquipmentRules.weapon_props(self)
    rescue NameError
      nil
    end
    # Slot declarado no catálogo (vestuário criado pelo mestre). Quando presente,
    # o front usa ELE em vez de inferir o slot pelo nome do item.
    catalog_equip_slot = begin
      EquipmentRules.equip_slot(self)
    rescue NameError
      nil
    end
    # Sela/barda/alforje/freio: o slot da MONTARIA é do catálogo, não da
    # instância. Sem isto o item na mochila não aparece no seletor da montaria.
    catalog_mount_props = begin
      EquipmentRules.mount_props(self)
    rescue NameError
      nil
    end

    {
      id: id,
      index: item_index,
      name: item_name,
      category: category,
      # Verdade do CATÁLOGO, quando o item está ligado a um `Item`.
      #
      # `category` acima é TEXTO copiado no momento da compra, e 74% das linhas
      # reais têm lixo lá (nil, 'background', 'class') — o front caía numa regex
      # de NOME para decidir a gaveta da bolsa. Com estes dois campos ele resolve
      # 36% do inventário pela origem, e a regex vira o fallback que deveria ser.
      catalog_kind: item&.kind,
      catalog_category: item&.category,
      quantity: quantity,
      equipped: equipped,
      slot: slot,
      source: source,
      props: props_json,
      weapon_props: weapon_props,
      equip_slot: catalog_equip_slot,
      mount_props: catalog_mount_props,
      # Recipiente de munição: o que aceita e quanto cabe. Do CATÁLOGO — sem
      # isto o front não sabe desenhar "12 / 20" nem qual munição oferecer.
      ammunition_container_props: ammunition_container_props,
      # PESO da linha, pela MESMA conta que valida a capacidade da bolsa.
      #
      # Faltava, e o front caía em `props_json['weight_lb']` — prop que só
      # existe em quem a gravou na compra. Sete itens de uma mochila apareciam
      # com peso "—" e a barra dizia 10 kg enquanto o servidor somava 15: a
      # tela recusava um movimento que ela própria dizia caber. Uma fonte para
      # os dois lados, na convenção do LIVRO (kg × 2), como o resto da ficha.
      weight_lb: begin
        EquipmentRules.item_weight_lb(self)
      rescue NameError
        nil
      end,
      # Capacidade da BOLSA (kg, canônico do banco). O ponteiro de conteúdo
      # (`bag_sheet_item_id`) já viaja dentro de `props`.
      bag_capacity_kg: (bag_capacity_kg if bag_capacity_kg.positive?),
      # Slots do CINTO (contagem, do catálogo). O ponteiro (`belt_sheet_item_id`)
      # também já viaja dentro de `props`.
      belt_slot_props: belt_slot_props,
      # Usos: quanto cabe (catálogo) e quanto resta (instância).
      uses_props: uses_props,
      uses_remaining: uses_remaining,
      notes: notes,
      position: position,
    }
  end

  # Usos declarados no CATÁLOGO (quantos cabem, e quando voltam).
  # Memoiza com `defined?`, não com `||=`: a resposta normal é NIL (a esmagadora
  # maioria dos itens não tem usos) e `||=` nunca guarda nil — cada chamada
  # refazia o `Item.find_by` do EquipmentRules. `as_inventory_json` chama três
  # vezes por linha, então na bolsa isso era N+1 puro.
  def uses_props
    return @uses_props if defined?(@uses_props)

    @uses_props = begin
      EquipmentRules.uses_props(self)
    rescue NameError
      nil
    end
  end

  def uses_max
    uses_props&.dig('uses_max')
  end

  def uses_recharge
    uses_props&.dig('uses_recharge')
  end

  # Quantos usos restam NESTA instância.
  #
  # Ausente = cheio. Um kit recém-comprado não precisa de gravação nenhuma para
  # estar cheio — só o gasto escreve.
  def uses_remaining
    max = uses_max
    return nil unless max

    bruto = (props_json || {})['uses_remaining']
    bruto.nil? ? max : bruto.to_i.clamp(0, max)
  end

  # Props do recipiente, vindas do CATÁLOGO (a instância não as tem).
  def ammunition_container_props
    @ammunition_container_props ||= begin
      EquipmentRules.ammunition_container_props(self)
    rescue NameError
      nil
    end
  end

  # `true` para recipiente de munição.
  #
  # Leitor TOLERANTE: aceita o recipiente DECLARADO no catálogo e também o
  # nome. A "Aljava" existe em fichas desde antes de recipiente ser um conceito;
  # exigir a declaração faria a munição de todas elas sair do lugar.
  def quiver?
    return true if ammunition_container_props.present?

    identity = normalized_inventory_identity
    identity.include?('aljava') || identity.include?('quiver')
  end

  # Esta linha é uma BOLSA? A declaração canônica é o catálogo
  # (`category: 'bag'` + `props.capacity_kg`); o nome cobre a bolsa avulsa que
  # o mestre criou à mão — o mesmo par de leitores do `quiver?`.
  def bag?
    return true if bag_capacity_kg.positive?

    identity = normalized_inventory_identity
    identity.include?('bolsa') || identity.include?('mochila') ||
      identity.include?('sacola') || identity.include?('backpack')
  end

  # Capacidade em KG, do CATÁLOGO (o banco é canônico em kg). 0 = sem teto
  # declarado — a bolsa manual do mestre guarda sem limite.
  #
  # ⚠️ ÍNDICE primeiro, associação como fallback — e não o contrário. O
  # `resolve_catalog_item` resolve por NOME e o ItemResolver CRIA um registro
  # novo quando o nome não casa: a bolsa renomeada ("Bolsa Pequena" sobre o
  # catálogo `bolsa-viagem`) ganha `item_id` de um CLONE sem capacidade, e a
  # associação-primeiro leria teto 0 (= sem limite) em silêncio. O `item_index`
  # é o identificador canônico que a linha aponta.
  def bag_capacity_kg
    @bag_capacity_kg ||= begin
      registro = (Item.find_by(api_index: item_index) if item_index.present? && defined?(Item))
      registro ||= item
      ((registro&.props || {})['capacity_kg']).to_f
    rescue StandardError
      0.0
    end
  end

  # Bolsa (SheetItem id) onde esta linha está guardada; nil = solta.
  def stored_in_bag_id
    (props_json || {})[BAG_CONTAINER_PROP]
  end

  # CINTO com slots: recipiente de CONTAGEM, não de peso. O criador declara
  # quantos slots LIVRES (arma, ferramenta, aljava — coisas de sacar) e quantos
  # de CONSUMÍVEL o cinto oferece. Mesma leitura índice-primeiro da bolsa: a
  # linha renomeada não pode perder os slots do catálogo.
  def belt_slot_props
    return @belt_slot_props if defined?(@belt_slot_props)

    @belt_slot_props = begin
      registro = (Item.find_by(api_index: item_index) if item_index.present? && defined?(Item))
      registro ||= item
      props = registro&.props || {}
      livres = props['belt_free_slots'].to_i
      consumiveis = props['belt_consumable_slots'].to_i
      (livres.positive? || consumiveis.positive?) ? { 'free' => livres, 'consumable' => consumiveis } : nil
    rescue StandardError
      nil
    end
  end

  def belt?
    belt_slot_props.present?
  end

  # Cinto (SheetItem id) onde esta linha está presa; nil = fora de cinto.
  def stored_on_belt_id
    (props_json || {})[BELT_CONTAINER_PROP]
  end

  # O que este recipiente aceita. Vazio = aceita qualquer munição (é o caso da
  # aljava legada, que não declara nada).
  def accepted_ammunition_indexes
    Array(ammunition_container_props&.dig('ammunition_types'))
  end

  # Quantas peças cabem. `nil` = sem limite declarado.
  def ammunition_capacity
    ammunition_container_props&.dig('ammunition_capacity')
  end

  # Quanto já está guardado aqui — soma das pilhas que apontam para este id.
  def ammunition_stored_count
    sheet.sheet_items
      .where("props_json ->> '#{AMMUNITION_CONTAINER_PROP}' = ?", id.to_s)
      .sum(:quantity)
  end

  # `true` para uma pilha de munição.
  #
  # O CATÁLOGO manda: `kind: ammunition` cobre pedra de funda e agulha de
  # zarabatana, que a regex por nome não conhecia — elas existiam no catálogo
  # como munição e mesmo assim não podiam entrar num recipiente. O nome
  # continua valendo para item solto, sem catálogo por trás.
  def ammunition?
    return true if item&.kind.to_s == 'ammunition'

    identity = normalized_inventory_identity
    identity.match?(/(?:^|[- ])(flecha|flechas|arrow|arrows|virote|virotes|bolt|bolts)(?:$|[- ])/)
  end

  def ammunition_container_id
    value = (props_json || {})[AMMUNITION_CONTAINER_PROP]
    value.present? ? value.to_s : nil
  end

  private

  def normalized_inventory_identity
    [item_index, item_name]
      .compact
      .join(' ')
      .unicode_normalize(:nfd)
      .gsub(/\p{Mn}/, '')
      .downcase
      .gsub(/[^a-z0-9]+/, '-')
  end

  def release_ammunition_contents
    sheet.sheet_items
         .where("props_json ->> 'quiver_sheet_item_id' = ?", id.to_s)
         .find_each do |ammunition|
      props = (ammunition.props_json || {}).deep_dup.stringify_keys
      props.delete(AMMUNITION_CONTAINER_PROP)
      ammunition.update!(props_json: props)
    end
  end

  # Apagar a bolsa não pode APAGAR o que está dentro: o conteúdo volta solto
  # para a mochila (mesma regra da aljava).
  def release_bag_contents
    self.class.where(sheet_id: sheet_id)
        .where("props_json ->> '#{BAG_CONTAINER_PROP}' = ?", id.to_s)
        .find_each do |guardado|
      props = (guardado.props_json || {}).deep_dup.stringify_keys
      props.delete(BAG_CONTAINER_PROP)
      guardado.update!(props_json: props)
    end
  end

  # Apagar o cinto solta o que estava preso nele — mesma regra da bolsa.
  def release_belt_contents
    self.class.where(sheet_id: sheet_id)
        .where("props_json ->> '#{BELT_CONTAINER_PROP}' = ?", id.to_s)
        .find_each do |preso|
      props = (preso.props_json || {}).deep_dup.stringify_keys
      props.delete(BELT_CONTAINER_PROP)
      preso.update!(props_json: props)
    end
  end

  # Garante que todo SheetItem aponte para um Item canonico no catalogo.
  # Se o caller (controller, service, importer) ja passou item_id, respeita.
  # Caso contrario, resolve via ItemResolver — que tenta achar Item existente
  # por nome/slug ou cria um novo a partir das tabelas EquipmentRules. O
  # `item_index` tambem e populado para manter consistencia com o frontend
  # (mapApiInventoryItem usa `index` como chave estavel pra weapons).
  def resolve_catalog_item
    return if item_id.present?
    return if item_name.blank?

    resolver = ItemResolver.new
    item = resolver.resolve(name: item_name, category: category)
    return unless item

    self.item_id = item.id
    self.item_index = item.api_index if item_index.blank?
  rescue StandardError => e
    Rails.logger.warn("SheetItem#resolve_catalog_item failed: #{e.class}: #{e.message}")
  end

  def sanitize_slot
    unless equipped
      self.slot = nil
    end
  end

  # Slot legado → canônico, ANTES da validação (senão o cliente antigo levaria
  # 422 no lugar de funcionar). `circlet` → `helmet` desde 29/08.
  def canonicalize_legacy_slot
    self.slot = self.class.canonicalize_slot(slot) if slot.present?
  end

  def validate_equipment_proficiency
    return unless equipped
    # armor/shield checks
    if slot.to_s == 'shield'
      cats = EquipmentRules.allowed_armor_categories(sheet)
      unless cats.include?('shields')
        errors.add(:base, 'Sem proficiência em escudos')
      end
    end
    if slot.to_s == 'armor' || armor_like?
      res = EquipmentRules.can_wear?(sheet: sheet, armor_item: self)
      errors.add(:base, (res[:reason] || 'Sem proficiência em armadura')) unless res[:ok]
    end

    # off-hand: arma deve ser leve (regra básica de duas armas)
    if slot.to_s == 'off_hand'
      begin
        if EquipmentRules.is_weapon?(self)
          props = EquipmentRules.weapon_props(self) || {}
          is_light = !!props[:light]
          # permitir não-leve se explicitamente habilitado nos props_json (porta de entrada para façanhas/estilos)
          allow_override = !!(props_json || {})['allow_offhand_non_light']
          # ou se o personagem possuir façanha "Dual Wielder"/"Empunhador Duplo"
          allow_override ||= has_dual_wielder_feat?
          unless is_light || allow_override
            errors.add(:base, 'A arma da mão secundária deve ser leve')
          end
        end
      rescue NameError
        # sem EquipmentRules, não valida
      end
    end
  rescue NameError
    # EquipmentRules não disponível: não valida
  end

  def armor_like?
    key = (item_index || item_name || '').to_s.downcase
    idx = key.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    EquipmentRules::ARMOR_TABLE.key?(idx) rescue false
  end

  # Match por:
  #   1) `api_index` canônico (`mestre_de_armas_duplas` no DB; `dual_wielder` em
  #      payloads vindos do front/SRD).
  #   2) substring do nome (PT-BR oficial + variantes históricas).
  # Bug histórico: a checagem só por substring `'duas armas'` não cobria
  # o nome canônico `'Mestre de Armas Duplas'` — usuário com a façanha
  # ficava bloqueado de equipar arma não-leve na mão secundária.
  DUAL_WIELDER_NAME_PATTERNS = [
    'mestre de armas duplas',  # PT-BR oficial (config/feats_improved.yml)
    'dual wielder',            # SRD EN
    'empunhador duplo',        # tradução alternativa
    'duas armas',              # match histórico
    'duelista duplo',          # tradução alternativa
  ].freeze
  DUAL_WIELDER_API_INDEXES = %w[mestre_de_armas_duplas dual_wielder].freeze

  def has_dual_wielder_feat?
    begin
      api_indexes = []
      names = []
      begin
        Array(sheet.feats).each do |f|
          api_indexes << f.api_index.to_s.downcase if f.respond_to?(:api_index) && f.api_index.present?
          names << f.name.to_s.downcase if f.respond_to?(:name) && f.name.present?
        end
      rescue; end
      begin
        feats_meta = Array((sheet.metadata || {})['feats'])
        feats_meta.each do |f|
          api_indexes << (f['api_index'] || f[:api_index]).to_s.downcase
          names << (f['name'] || f[:name]).to_s.downcase
        end
      rescue; end
      api_indexes.compact.any? { |idx| DUAL_WIELDER_API_INDEXES.include?(idx) } ||
        names.compact.any? { |n| DUAL_WIELDER_NAME_PATTERNS.any? { |pat| n.include?(pat) } }
    rescue
      false
    end
  end

  # Garante que apenas um item ocupe cada slot por ficha e resolve conflitos simples
  def enforce_slot_exclusivity_and_conflicts
    return unless equipped && slot.present?
    # Desmarca outros itens no mesmo slot para esta ficha
    SheetItem.where(sheet_id: sheet_id).where.not(id: id).where(slot: slot).update_all(equipped: false, slot: nil)

    # Regras de conflito básicas entre slots
    begin
      # Se equipou escudo, desocupa mão secundária
      if slot.to_s == 'shield'
        SheetItem.where(sheet_id: sheet_id, equipped: true, slot: 'off_hand').update_all(equipped: false, slot: nil)
      end

      # Se equipou em off_hand, remove escudo
      if slot.to_s == 'off_hand'
        SheetItem.where(sheet_id: sheet_id, equipped: true, slot: 'shield').update_all(equipped: false, slot: nil)
      end

      # Se arma de 2 mãos na principal, remove off_hand e escudo
      if slot.to_s == 'main_hand' && EquipmentRules.is_weapon?(self)
        props = EquipmentRules.weapon_props(self) || {}
        using_two = (props_json || {})['using_two_hands'] ? true : false
        is_two_handed = (props[:hands].to_i == 2) || (props[:versatile] && using_two)
        if is_two_handed
          SheetItem.where(sheet_id: sheet_id, equipped: true, slot: ['off_hand','shield']).update_all(equipped: false, slot: nil)
        end
      end
    rescue NameError
      # EquipmentRules não disponível
    end
  end
end
