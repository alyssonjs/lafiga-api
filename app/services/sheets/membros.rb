# frozen_string_literal: true

module Sheets
  # MEMBRO PERDIDO (04/10, a mesa: "isso só o mestre vai ter acesso"): o olho, a orelha, o braço, o antebraço, a mão, a
  # perna, a canela e o pé que o personagem perdeu, de cada lado.
  #
  # Mora em `avatar_customization['membros']` — o mesmo hash que a foto do token leva
  # (`BattleMapCharacterCustomization`, `BattleMapSerializer`), então o desenho do mapa muda sem caminho novo. A escrita é
  # do MESTRE (`Admin::SheetMembrosController`); os caminhos de escrita do JOGADOR — o passo de avatar da edição
  # (`AvatarEditService`), o do rascunho (`AvatarStepService`) e o provisionamento — descartam a chave e conservam a
  # gravada: sem isso, salvar a aparência no editor devolveria a mão perdida.
  #
  # ⚠️ Margem para as SUBSTITUIÇÕES (prótese de metal ou madeira, gancho, perna de pau, o membro que vira arma): outro
  # `estado` na mesma chave.
  module Membros
    CHAVE = 'membros'
    PARTES = %w[olho orelha braco antebraco mao perna canela pe].freeze
    LADOS = %w[direito esquerdo].freeze
    KEYS = PARTES.product(LADOS).map { |parte, lado| "#{parte}_#{lado}" }.freeze
    ESTADOS = %w[perdido].freeze

    module_function

    # Normaliza o patch do Mestre. Devolve `[hash_limpo, erros]`; `nil` numa chave é o gesto de DEVOLVER o membro.
    def sanitize(raw, actor_id: nil, previous: {})
      erros = []
      out = {}
      (raw || {}).each do |key, entry|
        k = key.to_s
        unless KEYS.include?(k)
          erros << "Membro não permitido: #{k}"
          next
        end
        if entry.nil?
          out[k] = nil
          next
        end
        h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        h = h.is_a?(Hash) ? h.transform_keys(&:to_s) : { 'estado' => h }
        estado = h['estado'].to_s
        unless ESTADOS.include?(estado)
          erros << "Estado inválido para #{k}: #{h['estado'].inspect}"
          next
        end
        anterior = (previous || {})[k]
        mesmo = anterior.is_a?(Hash) && anterior['estado'] == estado
        out[k] = {
          'estado' => estado,
          'by_user_id' => (mesmo ? anterior['by_user_id'] : nil) || actor_id,
          # a data em que o membro se foi não muda a cada reenvio do mesmo estado
          'at' => (mesmo ? anterior['at'] : nil) || Time.current.iso8601
        }.compact
      end
      [out, erros]
    end

    # Funde o patch no que já existe; chave com `nil` remove.
    def merge(current, patch)
      base = (current || {}).dup
      (patch || {}).each { |k, v| v.nil? ? base.delete(k) : base[k] = v }
      base
    end

    # A aparência que o JOGADOR mandou, sem a chave (a escrita é do Mestre).
    def sem_membros(hash)
      return hash unless hash.is_a?(Hash)

      hash.reject { |k, _| k.to_s == CHAVE }
    end

    # A aparência nova com os membros que JÁ estavam gravados (o provisionamento troca o hash inteiro).
    def preserva(novo, atual)
      base = sem_membros(novo || {})
      gravados = atual.is_a?(Hash) ? (atual[CHAVE] || atual[CHAVE.to_sym]) : nil
      gravados.present? ? base.merge(CHAVE => gravados) : base
    end
  end
end
