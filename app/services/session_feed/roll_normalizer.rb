# frozen_string_literal: true

module SessionFeed
  # Contrato único de entrada para rolagens, compartilhado pelo ActionCable
  # legado e pelo endpoint HTTP durável. O cliente calcula o dado, mas não pode
  # publicar campos arbitrários no feed ou esconder o resultado indefinidamente.
  class RollNormalizer
    MAX_ID_LENGTH = 128
    ROLL_TYPES = %w[attack damage skill save ability initiative heal spell custom].freeze
    CHAT_ROLES = %w[dm player visitor].freeze
    ATTACK_HIT_OUTCOMES = %w[pending hit miss].freeze
    MAX_DAMAGE_LINES = 16
    DAMAGE_LINE_MULTS = [0, 0.5, 1, 2].freeze

    class << self
      def call(schedule_id:, item:)
        return nil unless item.is_a?(Hash)

        h = item.stringify_keys
        return nil unless h['kind'].to_s == 'roll'

        type = h['type'].to_s
        return nil unless ROLL_TYPES.include?(type)

        id = h['id'].to_s
        return nil if id.empty? || id.length > MAX_ID_LENGTH

        timestamp = integer(h['timestamp'])
        return nil unless timestamp

        label = h['label'].to_s
        return nil if label.empty? || label.length > 500

        total = integer(h['total'])
        return nil unless total

        out = {
          'kind' => 'roll',
          'id' => id,
          'timestamp' => timestamp,
          'sessionId' => schedule_id.to_s,
          'playerName' => h['playerName'].to_s.truncate(120),
          'characterName' => h['characterName'].to_s.truncate(120),
          'type' => type,
          'label' => label.truncate(500),
          'total' => total,
          'breakdown' => h['breakdown'].to_s.truncate(2_000),
        }

        reveal_at = integer(h['revealAt'])
        if reveal_at && reveal_at >= timestamp
          out['revealAt'] = [reveal_at, timestamp + 5_000].min
        end

        copy_identifier(h, out, 'rollGroupId')
        copy_identifier(h, out, 'interactionId')
        # Identidade de QUEM rolou. Sem ela, ofertas avaliadas em OUTRO cliente
        # (Palavras de Interrupcao: o dono do Bardo decide sobre a rolagem alheia)
        # nao conseguem medir distancia nem faccao — o ataque escapava pelo
        # `attackerTokenId` (so copiado p/ type=attack) e o DANO chegava sem nada
        # (bug de 16/08: janela nunca abria no cliente do Mestre).
        copy_identifier(h, out, 'actorCombatantId')
        resolution_text = h['resolutionText'].to_s
        out['resolutionText'] = resolution_text.truncate(500) if resolution_text.present?

        %w[d20 d20Alt advantage isNat20 isNat1 isCrit damageType].each do |key|
          out[key] = h[key] if h.key?(key)
        end

        if h['dice'].is_a?(Array)
          out['dice'] = h['dice'].filter_map { |value| integer(value) }.first(40)
        end

        if type == 'damage'
          lines = sanitize_damage_lines(h['damageLines'])
          out['damageLines'] = lines if lines.present?
          # Alvo do dano: a reversao das Palavras de Interrupcao (F3.21) e o
          # top-up da Bravura precisam saber em quem o dano aterrissou.
          copy_identifier(h, out, 'targetTokenId')
        end

        sender_role = h['senderRole'].to_s
        out['senderRole'] = sender_role if CHAT_ROLES.include?(sender_role)
        accent = sanitize_hex_color(h['cardAccentColor'])
        out['cardAccentColor'] = accent if accent

        normalize_attack_fields(h, out) if type == 'attack'
        normalize_save_prompt(h, out) if type == 'save'
        out
      end

      def sanitize_hex_color(raw)
        value = raw.to_s.strip
        return nil if value.blank?
        return value if value.match?(/\A#[0-9a-f]{3}\z/i) || value.match?(/\A#[0-9a-f]{6}\z/i)

        nil
      end

      def sanitize_damage_lines(raw)
        return nil unless raw.is_a?(Array)

        lines = raw.first(MAX_DAMAGE_LINES).filter_map do |line|
          next unless line.is_a?(Hash)

          item = line.stringify_keys
          damage_type = item['type'].to_s.slice(0, 24)
          next if damage_type.empty?

          raw_amount = integer(item['raw'])
          final_amount = integer(item['final'])
          next if raw_amount.nil? || final_amount.nil? || raw_amount.negative? || final_amount.negative?

          multiplier = float(item['mult'])
          multiplier = 1.0 unless DAMAGE_LINE_MULTS.include?(multiplier)
          {
            'type' => damage_type,
            'raw' => raw_amount,
            'final' => final_amount,
            'mult' => multiplier,
          }
        end

        lines.presence
      end

      private

      def normalize_attack_fields(h, out)
        outcome = h['attackHitOutcome'].to_s
        out['attackHitOutcome'] = outcome if ATTACK_HIT_OUTCOMES.include?(outcome)

        target_ac = integer(h['targetAC'])
        out['targetAC'] = target_ac if target_ac&.between?(0, 1_000)
        copy_identifier(h, out, 'targetTokenId')
        copy_identifier(h, out, 'attackerTokenId')

        return unless h['projectile'].is_a?(Hash)

        projectile = h['projectile'].stringify_keys
        projectile_id = projectile['id'].to_s
        projectile_kind = projectile['kind'].to_s
        return if projectile_id.empty? || projectile_id.length > MAX_ID_LENGTH
        return unless BattleMapProjectiles::KINDS.include?(projectile_kind)

        out['projectile'] = {
          'id' => projectile_id,
          'kind' => projectile_kind,
          'itemName' => projectile['itemName'].to_s.truncate(120),
        }
      end

      def normalize_save_prompt(h, out)
        return unless h['savePrompt'].is_a?(Hash)

        source = h['savePrompt'].stringify_keys
        dc = integer(source['dc'])
        return unless dc

        prompt = {
          'dc' => dc,
          'ability' => source['ability'].to_s.slice(0, 8),
          'targetName' => source['targetName'].to_s.truncate(120),
        }
        prompt['sourceName'] = source['sourceName'].to_s.truncate(120) if source['sourceName'].present?
        prompt['mode'] = source['mode'] if %w[apply-on-fail remove-on-success].include?(source['mode'].to_s)
        prompt['resolved'] = true if source['resolved'] == true
        match_key = source['matchKey'].to_s
        prompt['matchKey'] = match_key.truncate(MAX_ID_LENGTH) if match_key.present?
        out['savePrompt'] = prompt
      end

      def copy_identifier(source, target, key)
        value = source[key].to_s
        target[key] = value if value.present? && value.length <= MAX_ID_LENGTH
      end

      def integer(value)
        value.is_a?(Numeric) ? value.to_i : Integer(value, exception: false)
      rescue FloatDomainError, TypeError, ArgumentError
        nil
      end

      def float(value)
        value.is_a?(Numeric) ? value.to_f : Float(value, exception: false)
      rescue FloatDomainError, TypeError, ArgumentError
        nil
      end
    end
  end
end
