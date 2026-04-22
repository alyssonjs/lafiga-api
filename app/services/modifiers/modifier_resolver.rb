# frozen_string_literal: true

module Modifiers
  # ModifierResolver — coleta Modifiers de todos os producers registrados
  # e devolve um índice agregado, pronto para o CharacterSheetSummaryService
  # consumir.
  #
  # Uso:
  #   resolver = Modifiers::ModifierResolver.new(sheet, equipment: equipment_payload)
  #   bag = resolver.call
  #   bag.sum_for("save.con")            # => Integer (com typed stacking)
  #   bag.granted("save")                # => ["str", "con"] (proficiências concedidas)
  #   bag.weapon_attack_for(slot: :main_hand) # => Integer
  #   bag.all_for("speed")               # => Array<Modifier> (raw, pra debug/breakdown)
  #
  # NÃO mexe em ActiveRecord. NÃO persiste nada. É puro.
  class ModifierResolver
    attr_reader :sheet, :context, :producers

    DEFAULT_PRODUCER_KEYS = %i[klass subklass feat equipped_item].freeze

    def initialize(sheet, context: {}, producer_keys: DEFAULT_PRODUCER_KEYS)
      @sheet = sheet
      @context = context || {}
      @producer_keys = Array(producer_keys)
    end

    def call
      mods = []
      @producer_keys.each do |key|
        klass = producer_for(key)
        next unless klass
        begin
          mods.concat(Array(klass.new(sheet, context: context).produce))
        rescue => e
          Rails.logger.warn("ModifierResolver: #{key} producer falhou para sheet ##{sheet.id}: #{e.class}: #{e.message}")
        end
      end
      Bag.new(mods)
    end

    private

    PRODUCER_REGISTRY = {
      klass:          'Modifiers::Producers::KlassProducer',
      subklass:       'Modifiers::Producers::SubklassProducer',
      feat:           'Modifiers::Producers::FeatProducer',
      equipped_item:  'Modifiers::Producers::EquippedItemProducer',
      # placeholders para fases seguintes:
      # race:         'Modifiers::Producers::RaceProducer',
      # background:   'Modifiers::Producers::BackgroundProducer',
      # condition:    'Modifiers::Producers::ConditionProducer',
      # asi:          'Modifiers::Producers::AsiProducer',
    }.freeze

    def producer_for(key)
      const_name = PRODUCER_REGISTRY[key]
      return nil unless const_name
      const_name.safe_constantize
    end

    # Bag — interface ergonômica em cima do array de Modifiers.
    class Bag
      attr_reader :mods

      def initialize(mods)
        @mods = Array(mods).freeze
      end

      def all_for(target)
        mods.select { |m| m.target == target }
      end

      def matching(target_prefix)
        mods.select { |m| m.target.to_s.start_with?(target_prefix.to_s) }
      end

      # Soma TODOS os :add para um target, com typed stacking:
      # - "untyped" soma livremente
      # - tipos nomeados (magico/escudo/armor/circunstancia) pegam o MAIOR por tipo
      def sum_for(target, predicate_match: nil)
        relevant = all_for(target).select do |m|
          m.op == :add && predicate_satisfied?(m, predicate_match)
        end
        return 0 if relevant.empty?

        by_type = relevant.group_by(&:stacking_type)
        total = 0
        by_type.each do |type, ms|
          total += if type == 'untyped'
                     ms.sum { |m| m.value.to_i }
                   else
                     ms.map { |m| m.value.to_i }.max.to_i
                   end
        end
        total
      end

      # Soma todos os :add para um target restringindo por source_kind
      # (`:item`, `:feat`, `:race`, etc.). Aceita Symbol ou Array<Symbol>.
      # Mantem o mesmo typed stacking de `sum_for` (untyped soma livremente,
      # tipos nomeados pegam o maior por tipo).
      #
      # Existe para permitir que a UI separe a origem de um bonus — ex.: a
      # aba "Efeitos de Itens Equipados" deve mostrar so :item, enquanto o
      # bonus total continua via `sum_for`. Bug do Adimael Neverdie: feat
      # Mobilidade vinha aparecendo no bloco de equipamentos.
      def sum_for_kind(target, source_kind:, predicate_match: nil)
        kinds = Array(source_kind).map(&:to_sym)
        relevant = all_for(target).select do |m|
          m.op == :add && kinds.include?(m.source_kind) && predicate_satisfied?(m, predicate_match)
        end
        return 0 if relevant.empty?

        by_type = relevant.group_by(&:stacking_type)
        total = 0
        by_type.each do |type, ms|
          total += if type == 'untyped'
                     ms.sum { |m| m.value.to_i }
                   else
                     ms.map { |m| m.value.to_i }.max.to_i
                   end
        end
        total
      end

      # Para :set, devolve o Modifier de maior priority (o último a "ganhar").
      def set_value(target)
        relevant = all_for(target).select { |m| m.op == :set }
        return nil if relevant.empty?
        relevant.max_by(&:priority).value
      end

      # Para :grant, devolve a lista única de valores concedidos.
      # ex: granted("save") => ["str", "con"]
      def granted(target_prefix)
        matching(target_prefix).select { |m| m.op == :grant }.map(&:value).flatten.compact.uniq.map(&:to_s)
      end

      def weapon_attack_for(slot:)
        sum_for("weapon.attack", predicate_match: { "weapon.slot" => slot.to_s })
      end

      def weapon_damage_for(slot:)
        sum_for("weapon.damage", predicate_match: { "weapon.slot" => slot.to_s })
      end

      def to_breakdown(target)
        all_for(target).map(&:to_h_compact)
      end

      def empty?
        mods.empty?
      end

      def size
        mods.size
      end

      private

      def predicate_satisfied?(mod, query)
        return true if mod.predicate.blank?
        return false if query.blank?
        mod.predicate.all? { |k, v| query[k.to_s] == v.to_s }
      end
    end
  end
end
