module CharacterDraftSteps
  # Base for per-step services in CREATION mode. Each subclass:
  #   - implements `step_key` (returns String matching CharacterDraftSchema::STEP_KEYS)
  #   - implements `apply!(merged)` that mutates `merged` (a Hash deep_stringified)
  #     placing/normalizing the step's fields.
  #   - optionally overrides `read(data)` to expose a custom fragment.
  #   - optionally overrides `invalidate!(prev, merged)` to scrub dependent fields
  #     when a destructive change is detected (returns Array<String> of cleared keys).
  #
  # Contract:
  #   service = CharacterDraftSteps::ClassStepService.new(character: c, data: payload, level: nil)
  #   result  = service.call
  #   result.draft_data        # frozen Hash with new draft_data after merge+migrate
  #   result.warnings          # Array<String> soft-validation messages
  #   result.cleared_keys      # Array<String> destructive cleanup hits
  #
  # `invalidate!` is the canonical place for the cleanup logic that historically
  # lived in front-lafiga/src/app/pages/character-creation/draftStorage.ts
  # (`mergeDraftPartialWithCleanup`). Frontend keeps it as offline fallback.
  #
  # X3 do relatorio de auditoria de steps: INVARIANT contratual de invalidate!
  # ------------------------------------------------------------------------
  # Toda implementacao de `invalidate!` DEVE seguir as 3 regras abaixo, sob
  # pena de bugs de "PATCH atomico apaga dados que vieram juntos" (ver B4.1
  # do ClassStep, G3.3 do BackgroundStep, G2.4 do RaceStep — todos foram
  # corrigidos para o pattern):
  #
  #   1. ATOMICIDADE: nao zerar uma chave dependente se ela veio no MESMO
  #      data hash. Cliente que envia `{classId: X, level1Choices: {...}}`
  #      atomicamente claramente quer manter as escolhas — apply! ja
  #      colocou em merged, invalidate! NAO deve apagar.
  #      `unless data.key?('level1Choices') ... end`
  #
  #   2. PROVENANCE: so reportar `clear!` para chave que TINHA conteudo em
  #      `prev` (estado anterior). Reportar perda de campo que era nil
  #      gera `requires_confirmation` ruidoso (ver G2.4 — "voce vai perder
  #      selectedFeat" para quem nunca teve feat).
  #      `clear!('selectedFeat', confirm: destructive) if had_feat`
  #
  #   3. DESTRUCTIVE FLAG: `confirm: true` so quando AMBOS prev_id e new_id
  #      estao presentes (= troca consciente de uma escolha previa). Setar
  #      por primeira vez (prev_id nil) NAO e destrutivo, nao deve disparar
  #      requires_confirmation.
  #      `destructive = prev_id.present? && new_id.present?`
  #
  # Specs de referencia que cobrem o invariant (use como template):
  #   spec/services/character_draft_steps/class_step_service_spec.rb (B4.1)
  #   spec/services/character_draft_steps/background_step_service_spec.rb (G3.3)
  #   spec/services/character_draft_steps/race_step_service_spec.rb (G2.4)
  class BaseStepService
    Result = Struct.new(:draft_data, :warnings, :cleared_keys, :requires_confirmation, keyword_init: true)

    # Mensagens exibidas ao jogador quando uma escolha apaga dependentes.
    # Centralizadas aqui (não literais espalhados) para facilitar revisão de
    # tom de voz. Caso o projeto adote i18n full, mover para
    # `config/locales/pt-BR.yml` sob `character_draft.destructive_reasons.*`
    # e trocar acessos por `I18n.t(...)`. Hoje o backend não usa I18n nos
    # services, então mantemos a constante simples.
    DESTRUCTIVE_REASONS = {
      class_changed: 'Trocar de classe apaga progressão, escolhas de nível 1 e magias.',
      race_changed:  'Trocar de raça apaga escolhas raciais, sub-raça e feat racial.'
    }.freeze

    attr_reader :character, :data, :level

    def initialize(character:, data:, level: nil, force: false)
      @character = character
      @data      = (data.is_a?(Hash) ? data.deep_stringify_keys : {})
      @level     = level&.to_i
      @force     = !!force
      @warnings  = []
      @cleared   = []
      @requires_confirmation = nil
    end

    def call
      raw    = character.draft_data || {}
      prev   = CharacterDraftSchema.migrate(raw)
      merged = prev.deep_dup

      apply!(merged)
      invalidate!(prev, merged)

      merged = CharacterDraftSchema.migrate(merged)
      Result.new(
        draft_data: merged,
        warnings: @warnings.uniq,
        cleared_keys: @cleared.uniq,
        requires_confirmation: @requires_confirmation
      )
    end

    # Expose just the step's fragment (used by controller `show`).
    def read
      data = CharacterDraftSchema.migrate(character.draft_data || {})
      CharacterDraftSchema.read_step(data, step_key)
    end

    def step_key
      raise NotImplementedError, "#{self.class.name} must implement #step_key"
    end

    protected

    def apply!(_merged)
      raise NotImplementedError, "#{self.class.name} must implement #apply!"
    end

    def invalidate!(_prev, _merged)
      # default no-op; class/race overrides below.
    end

    def warn!(msg)
      @warnings << msg.to_s
    end

    def clear!(key, reason: nil, confirm: false)
      @cleared << key.to_s
      if confirm && !@force
        @requires_confirmation = { reason: reason || DESTRUCTIVE_REASONS[:class_changed], cleared: @cleared.dup }
      end
    end

    def force?
      @force
    end
  end
end
