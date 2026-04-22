module CharacterDraftSteps
  class AbilitiesStepService < BaseStepService
    def step_key = 'abilities'

    KEYS = %w[str dex con int wis cha].freeze
    POINT_BUY_MIN = 8
    POINT_BUY_MAX = 15
    HARD_MAX = 20

    protected

    # ZX1 do segundo audit: PATCH parcial em creation zerava atributos nao
    # enviados para 8 (default point-buy) — divergente do AbilitiesEditService
    # que faz merge por chave (`v.present?`). Cliente que enviasse so
    # `{ str: 15 }` perdia DEX/CON/INT/WIS/CHA salvos previamente.
    #
    # Estrategia: merge sobre o estado anterior em `merged`. Se o atributo nao
    # vem em `data`, preserva o valor previo; se nao havia nada, cai no default
    # POINT_BUY_MIN. Usamos `key?` em vez de `present?` para aceitar `0` em
    # cenarios homebrew (paridade com o LOW gap apontado no audit do edit).
    def apply!(merged)
      scores_in = (data['abilityScores'].is_a?(Hash) ? data['abilityScores'] : {})
      prev_scores =
        if merged['abilityScores'].is_a?(Hash)
          merged['abilityScores'].deep_stringify_keys
        else
          {}
        end

      out = {}
      KEYS.each do |k|
        v = if scores_in.key?(k) || scores_in.key?(k.to_sym)
              (scores_in[k] || scores_in[k.to_sym]).to_i
            elsif prev_scores.key?(k)
              prev_scores[k].to_i
            else
              POINT_BUY_MIN
            end
        v = HARD_MAX if v > HARD_MAX
        v = POINT_BUY_MIN if v < POINT_BUY_MIN
        out[k] = v
      end
      merged['abilityScores'] = out

      if KEYS.all? { |k| out[k] <= POINT_BUY_MAX }
        cost = KEYS.sum { |k| point_cost(out[k]) }
        warn!("point-buy total != 27 (atual: #{cost})") if cost != 27
      end
    end

    private

    def point_cost(score)
      case score
      when 8..13 then score - 8
      when 14    then 7
      when 15    then 9
      else 0
      end
    end
  end
end
