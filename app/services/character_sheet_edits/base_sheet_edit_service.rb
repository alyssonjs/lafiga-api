module CharacterSheetEdits
  # Base for per-step services in EDIT mode (status: 'active' characters).
  # Subclasses receive the SAME `data` shape as their CharacterDraftSteps siblings,
  # but instead of mutating draft_data they apply surgical changes to the live
  # Sheet record (and, when required, SheetKlass / SheetItem / SheetFeat).
  #
  # Invariants every subclass MUST preserve unless the step is explicitly about it:
  #   - Sheet.hp_current (live HP), Sheet.temp_hp
  #   - Character usageState, conditions, exhaustion, slots used (front state)
  #   - Inventory ownership / wallet
  #
  # When a step IS about a recompute (abilities -> hp_max delta, race -> speed),
  # subclasses must keep the ratio HP_current/HP_max so the player doesn't drop
  # to 0 silently.
  #
  # Destructive changes (race switch, class switch) raise `requires_confirmation`
  # unless `force: true` is passed.
  class BaseSheetEditService
    Result = Struct.new(:warnings, :cleared_keys, :requires_confirmation, keyword_init: true) do
      def draft_data = nil # parity with DraftStep result for controller.
    end

    DESTRUCTIVE_REASONS = {
      class_changed: 'Trocar de classe nesse personagem ja provisionado apaga niveis 2+, magias conhecidas e escolhas de classe.',
      race_changed:  'Trocar de raca recomputa proficiencias, deslocamento e idiomas; perde escolhas raciais antigas.'
    }.freeze

    attr_reader :character, :sheet, :data, :level, :current_user

    def initialize(character:, data:, level: nil, force: false, current_user: nil)
      @character = character
      @sheet     = character.sheet or raise ArgumentError, 'edit mode requires character.sheet to be present'
      @data      = (data.is_a?(Hash) ? data.deep_stringify_keys : {})
      @level     = level&.to_i
      @force     = !!force
      @current_user = current_user
      @warnings  = []
      @cleared   = []
      @requires_confirmation = nil
    end

    def call
      ActiveRecord::Base.transaction do
        apply!
      end
      Result.new(
        warnings: @warnings.uniq,
        cleared_keys: @cleared.uniq,
        requires_confirmation: @requires_confirmation
      )
    end

    # Default: read fragment from current Sheet/SheetKlass; subclasses may override
    # to read from canonical sources (RaceRules, KlassRules etc.).
    def read
      raise NotImplementedError, "#{self.class.name} must implement #read"
    end

    def step_key
      raise NotImplementedError, "#{self.class.name} must implement #step_key"
    end

    protected

    def apply!
      raise NotImplementedError, "#{self.class.name} must implement #apply!"
    end

    def warn!(msg)
      @warnings << msg.to_s
    end

    def clear!(key, reason: nil, confirm: false)
      @cleared << key.to_s
      if confirm && !@force
        @requires_confirmation = { reason: reason, cleared: @cleared.dup }
        raise ActiveRecord::Rollback # bail out so the destructive change does not commit
      end
    end

    def force?
      @force
    end

    # X2 do relatorio de auditoria de steps: helper compartilhado para
    # resolver referencias polimorficas (id numerico OU api_index/slug em
    # kebab/snake) — antes cada *EditService duplicava esta logica
    # (`resolve_klass_id`, `resolve_race_id`, `resolve_background_id`,
    # `resolve_alignment_*`). Mantemos os helpers locais como wrappers para
    # nao quebrar callers externos / testes que stubam por nome, mas o miolo
    # vive aqui.
    #
    # Uso:
    #   resolve_polymorphic_id(Klass, raw_id)   # => Integer | nil
    #   resolve_polymorphic_id(Race, 'human')   # => 12
    #   resolve_polymorphic_id(Background, 42)  # => 42 (passa-direto)
    def resolve_polymorphic_id(model, raw)
      return nil if raw.blank?
      str = raw.to_s.strip
      return str.to_i if str.match?(/\A\d+\z/)
      slug_kebab = str.downcase.gsub('_', '-')
      model.where('LOWER(api_index) = ?', slug_kebab).pick(:id) ||
        model.where('LOWER(api_index) = ?', slug_kebab.tr('-', '_')).pick(:id)
    end

    # Sync hp_max / hp_current from `metadata.class_choices.per_level` + racial bonus,
    # same formula as provisioning — picks up real HP rolls/averages, not only max+avg heuristic.
    def apply_progression_hp_to_sheet!
      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk&.klass

      per_level = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
      character_level = sheet.sheet_klasses.sum(&:level).to_i
      expected = SheetHpFromProgression.expected_max(sheet, sk.klass, character_level, per_level)
      return if expected <= 0

      prev_max = sheet.hp_max.to_i
      old_cur = sheet.hp_current.to_i
      sheet.hp_max = expected
      sheet.hp_current = if prev_max <= 0
                          expected
                        else
                          ratio = old_cur.to_f / [prev_max, 1].max
                          [(expected * ratio).round, expected].min
                        end
    end

    # Recompute hp_max with new CON modifier, preserving live ratio.
    # Used by abilities_edit and race_edit.
    def recompute_hp_max!(new_con:)
      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk

      hd = sk.klass&.hit_die.to_i.nonzero? || 8
      con_mod = CharacterRules.modifier(new_con)
      total_levels = sheet.sheet_klasses.sum(&:level).to_i
      avg_per_level = (hd / 2.0).ceil
      base = [1, hd + con_mod].max
      extra = (total_levels - 1).clamp(0, 19) * (avg_per_level + con_mod)
      racial_hp = begin
                    RacialHpBonus.per_level_for_sheet(sheet) * total_levels
                  rescue StandardError
                    0
                  end
      new_max = [1, base + extra + racial_hp].max

      old_max = sheet.hp_max.to_i
      old_cur = sheet.hp_current.to_i
      new_cur = if old_max <= 0
                  new_max
                else
                  ratio = old_cur.to_f / old_max
                  [(new_max * ratio).round, new_max].min
                end
      sheet.hp_max = new_max
      sheet.hp_current = new_cur
    end
  end
end
