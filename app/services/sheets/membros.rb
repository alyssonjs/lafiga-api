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
  # AS SUBSTITUIÇÕES (05/10, a mesa: "a substituição de membros vai poder dar atributos diferenciados ao personagem, ou
  # transformar o membro em uma arma"): `{ estado: 'substituido', substituto: { tipo, material, cor, efeitos, arma } }`.
  #  - o TIPO, os EFEITOS (os mesmos dos itens mágicos, `MagicItemRules`) e a ARMA natural são do Mestre;
  #  - o MATERIAL e a COR (o visual) também do jogador (`Player::SheetMembrosController`).
  # O membro PERDIDO tem as penalidades do Guia do Mestre (Ferimentos Persistentes); a substituição que RESTAURA (a
  # prótese, a perna de pau no andar) as tira. O espelho do front é `lpcProteses.ts` + `membrosRuntime.ts`.
  module Membros
    CHAVE = 'membros'
    PARTES = %w[olho orelha braco antebraco mao perna canela pe].freeze
    LADOS = %w[direito esquerdo].freeze
    KEYS = PARTES.product(LADOS).map { |parte, lado| "#{parte}_#{lado}" }.freeze
    ESTADOS = %w[perdido substituido].freeze

    NOMES_DAS_PARTES = {
      'olho' => 'olho', 'orelha' => 'orelha', 'braco' => 'braço', 'antebraco' => 'antebraço', 'mao' => 'mão',
      'perna' => 'perna', 'canela' => 'canela', 'pe' => 'pé',
    }.freeze
    # O maior leva os menores (sem o antebraço, a mão também; com o braço de metal, a mão é de metal).
    CONTEM = { 'braco' => %w[antebraco mao], 'antebraco' => %w[mao], 'perna' => %w[canela pe], 'canela' => %w[pe] }.freeze
    DO_MAIOR = %w[braco antebraco mao perna canela pe olho orelha].freeze
    DO_BRACO = %w[braco antebraco mao].freeze
    DA_PERNA = %w[perna canela pe].freeze

    # As rampas do LPC de cada material (o que o jogador escolhe).
    MATERIAIS = {
      'metal' => %w[steel iron silver gold bronze brass copper ceramic],
      'madeira' => %w[maple oak walnut mahogany],
      'tecido' => %w[black charcoal brown leather maroon red navy forest white],
    }.freeze
    # Os tipos, para quem servem e o PADRÃO (o Mestre ajusta os efeitos e a arma). `restaura`: devolve a função do
    # membro — `true` (tudo), `false` (nada) ou a lista do que devolve (a perna de pau devolve o ANDAR, não o equilíbrio).
    TIPOS = {
      'protese' => { 'nome' => 'Prótese', 'membros' => PARTES, 'material' => 'metal', 'cor' => 'steel', 'restaura' => true },
      'gancho' => {
        'nome' => 'Gancho', 'membros' => DO_BRACO, 'material' => 'metal', 'cor' => 'steel', 'restaura' => false,
        'arma' => { 'nome' => 'Gancho', 'dano' => '1d4', 'tipoDeDano' => 'piercing', 'propriedades' => %w[light finesse] },
      },
      'lamina' => {
        'nome' => 'Lâmina', 'membros' => DO_BRACO, 'material' => 'metal', 'cor' => 'steel', 'restaura' => false,
        'arma' => { 'nome' => 'Lâmina', 'dano' => '1d6', 'tipoDeDano' => 'slashing', 'propriedades' => %w[light finesse] },
      },
      'perna_de_pau' => {
        'nome' => 'Perna de pau', 'membros' => DA_PERNA, 'material' => 'madeira', 'cor' => 'maple', 'restaura' => %w[andar],
      },
      'tapa_olho' => { 'nome' => 'Tapa-olho', 'membros' => %w[olho], 'material' => 'tecido', 'cor' => 'black', 'restaura' => false },
    }.freeze

    # Os efeitos que um membro aceita: os PERMANENTES dos itens mágicos (o que se consome — cura, magia, pergaminho — não).
    KINDS_DE_EFEITO = %w[
      ac_bonus set_ac_base attack_bonus damage_bonus_flat damage_bonus_dice damage_type_override weapon_is_magical
      resistance damage_immunity damage_vulnerability condition_immunity save_advantage skill_advantage
      ability_bonus ability_set speed_bonus passive_feature ignore_difficult_terrain apply_condition target_vulnerability
    ].freeze
    MAX_EFEITOS = 20
    TIPOS_DE_DANO_DA_ARMA = %w[piercing slashing bludgeoning].freeze
    # (sem `thrown`: o membro não se arremessa — e o arremesso no mapa procura o item na bolsa)
    PROPRIEDADES_DA_ARMA = %w[light finesse reach].freeze
    DADO = /\A[1-9]\d?d(4|6|8|10|12)\z/

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
        h = plain(entry)
        h = h.is_a?(Hash) ? h : { 'estado' => h }
        estado = h['estado'].to_s
        unless ESTADOS.include?(estado)
          erros << "Estado inválido para #{k}: #{h['estado'].inspect}"
          next
        end
        limpo = { 'estado' => estado }
        if estado == 'substituido'
          substituto, erro = substituto_limpo(k, h['substituto'])
          if erro
            erros << erro
            next
          end
          limpo['substituto'] = substituto
        end
        anterior = (previous || {})[k]
        mesmo = anterior.is_a?(Hash) && anterior['estado'] == estado
        out[k] = limpo.merge(
          'by_user_id' => (mesmo ? anterior['by_user_id'] : nil) || actor_id,
          # a data em que o membro se foi não muda a cada reenvio do mesmo estado
          'at' => (mesmo ? anterior['at'] : nil) || Time.current.iso8601,
        ).compact
      end
      [out, erros]
    end

    # O substituto do Mestre: o tipo que serve àquele membro, o material e a cor do LPC (fora da lista, o padrão), os
    # efeitos dos itens mágicos (só os permanentes) e a arma natural (`nil` = sem arma; ausente = a do tipo).
    def substituto_limpo(chave, raw)
      h = plain(raw)
      return [nil, "Substituto inválido para #{chave}"] unless h.is_a?(Hash)

      tipo = h['tipo'].to_s
      padrao = TIPOS[tipo]
      return [nil, "Tipo de substituto inválido para #{chave}: #{h['tipo'].inspect}"] unless padrao

      parte = chave.split('_').first
      return [nil, "#{padrao['nome']} não serve para #{NOMES_DAS_PARTES[parte]}"] unless padrao['membros'].include?(parte)

      material, cor = visual_limpo(tipo, h['material'], h['cor'])
      out = { 'tipo' => tipo, 'material' => material, 'cor' => cor }
      efeitos = efeitos_limpos(h['efeitos'])
      out['efeitos'] = efeitos if efeitos.any?
      if h.key?('arma')
        arma = arma_limpa(h['arma'])
        out['arma'] = arma
      end
      [out, nil]
    end

    # O material e a cor: a prótese escolhe metal ou madeira; os outros tipos têm o material deles.
    def visual_limpo(tipo, material, cor)
      padrao = TIPOS.fetch(tipo)
      m = material.to_s
      m = padrao['material'] unless tipo == 'protese' ? %w[metal madeira].include?(m) : m == padrao['material']
      c = cor.to_s
      c = (m == padrao['material'] ? padrao['cor'] : MATERIAIS[m].first) unless MATERIAIS[m].include?(c)
      [m, c]
    end

    def efeitos_limpos(raw)
      Array(plain(raw)).first(MAX_EFEITOS).filter_map do |e|
        next unless e.is_a?(Hash) && KINDS_DE_EFEITO.include?(e['kind'].to_s)

        e.each_with_object({}) do |(k, v), acc|
          valor = valor_simples(v)
          acc[k.to_s] = valor unless valor.nil?
        end
      end
    end

    # Só número, texto, booleano e listas deles (o efeito vai para o jsonb e volta para o front como veio).
    def valor_simples(v)
      case v
      when Integer, Float, TrueClass, FalseClass then v
      when String then v[0, 300]
      when Array then v.first(20).map { |x| valor_simples(x) }.compact
      when Hash then v.first(10).to_h { |k, x| [k.to_s, valor_simples(x)] }.compact
      end
    end

    def arma_limpa(raw)
      h = plain(raw)
      return nil unless h.is_a?(Hash)

      dano = h['dano'].to_s.strip.downcase
      return nil unless DADO.match?(dano)

      tipo = h['tipoDeDano'].to_s
      tipo = 'bludgeoning' unless TIPOS_DE_DANO_DA_ARMA.include?(tipo)
      nome = h['nome'].to_s.strip[0, 40].presence || 'Arma natural'
      {
        'nome' => nome, 'dano' => dano, 'tipoDeDano' => tipo,
        'propriedades' => Array(h['propriedades']).map(&:to_s).select { |p| PROPRIEDADES_DA_ARMA.include?(p) }.uniq,
      }
    end

    # O patch do JOGADOR: só o VISUAL (material e cor) de membro que JÁ está substituído — o tipo, os efeitos e a arma
    # ficam como o Mestre gravou. Devolve `[hash_dos_membros_mexidos, erros]`.
    def sanitize_visual(raw, atual)
      erros = []
      out = {}
      (raw || {}).each do |key, entry|
        k = key.to_s
        gravado = (atual || {})[k]
        unless KEYS.include?(k) && gravado.is_a?(Hash) && gravado['estado'] == 'substituido' && gravado['substituto'].is_a?(Hash)
          erros << "Só o visual de um membro substituído pode mudar: #{k}"
          next
        end
        h = plain(entry)
        h = {} unless h.is_a?(Hash)
        sub = gravado['substituto']
        material, cor = visual_limpo(sub['tipo'].to_s, h.fetch('material', sub['material']), h.fetch('cor', sub['cor']))
        out[k] = gravado.merge('substituto' => sub.merge('material' => material, 'cor' => cor))
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

    # ========================================================================== o ESTADO de cada membro (a cascata)
    # Os membros gravados de uma ficha (o hash de `avatar_customization`).
    def da_ficha(sheet)
      aparencia = sheet.respond_to?(:avatar_customization) ? sheet.avatar_customization : nil
      m = aparencia.is_a?(Hash) ? (aparencia[CHAVE] || aparencia[CHAVE.to_sym]) : nil
      m.is_a?(Hash) ? m.transform_keys(&:to_s) : {}
    end

    # O estado gravado de UMA chave, sem cascata: nil, `{ 'estado' => 'perdido' }` ou o substituído (com o tipo válido).
    def gravado(membros, chave)
      e = membros[chave]
      return nil unless e.is_a?(Hash)

      e = e.transform_keys(&:to_s)
      return e if e['estado'] == 'perdido'
      return nil unless e['estado'] == 'substituido'

      sub = e['substituto']
      tipo = sub.is_a?(Hash) ? (sub['tipo'] || sub[:tipo]).to_s : ''
      padrao = TIPOS[tipo]
      padrao && padrao['membros'].include?(chave.split('_').first) ? e : nil
    end

    # O membro como o jogo o vê, pelo MAIOR marcado que o contém: `[estado_gravado, parte_que_marcou]` ou nil (inteiro).
    def estado_efetivo(membros, parte, lado)
      DO_MAIOR.each do |maior|
        next unless maior == parte || CONTEM.fetch(maior, []).include?(parte)

        g = gravado(membros, "#{maior}_#{lado}")
        return [g, maior] if g
      end
      nil
    end

    # O membro FUNCIONA? Inteiro, sim; perdido, não; substituído, pelo `restaura` do tipo (`aspecto`: o que se pergunta
    # — 'andar' ou 'equilibrio' na perna).
    def funciona?(membros, parte, lado, aspecto: nil)
      e, = estado_efetivo(membros, parte, lado)
      return true unless e
      return false if e['estado'] == 'perdido'

      restaura = TIPOS.dig(e.dig('substituto', 'tipo').to_s, 'restaura')
      restaura == true || (restaura.is_a?(Array) && aspecto && restaura.include?(aspecto))
    end

    # As PENALIDADES (Guia do Mestre, Ferimentos Persistentes):
    #  - olho: desvantagem em Percepção pela visão e em ataque à distância; sem os dois, cego;
    #  - orelha (da mesa): desvantagem em Percepção pela audição;
    #  - mão/braço: nada com duas mãos, um objeto por vez; sem as duas, nada;
    #  - perna/pé: deslocamento a pé pela metade, cai ao fim da Disparada, desvantagem em teste de DES para se equilibrar.
    def penalidades(membros)
      contar = ->(parte, aspecto = nil) { LADOS.count { |l| !funciona?(membros, parte, l, aspecto: aspecto) } }
      {
        olhos: contar.call('olho'),
        orelhas: contar.call('orelha'),
        maos: contar.call('mao'),
        pernas_sem_andar: contar.call('pe', 'andar'),
        pernas_sem_equilibrio: contar.call('pe', 'equilibrio'),
      }
    end

    # Quantas mãos seguram alguma coisa (0, 1 ou 2).
    def maos_livres(membros)
      2 - penalidades(membros)[:maos]
    end

    # Os membros SUBSTITUÍDOS que valem (o maior de cada família, de cada lado): `[[chave, substituto], …]`.
    def substituicoes(membros)
      out = []
      LADOS.each do |lado|
        vistos = []
        DO_MAIOR.each do |parte|
          next if vistos.include?(parte)

          g = gravado(membros, "#{parte}_#{lado}")
          next unless g

          vistos << parte
          vistos.concat(CONTEM.fetch(parte, []))
          out << ["#{parte}_#{lado}", g['substituto'].transform_keys(&:to_s)] if g['estado'] == 'substituido'
        end
      end
      out
    end

    # "Prótese (braço direito)" — o rótulo de uma fonte de efeito.
    def rotulo(chave, substituto)
      parte, lado = chave.split('_')
      "#{TIPOS.dig(substituto['tipo'].to_s, 'nome') || 'Substituto'} (#{NOMES_DAS_PARTES[parte]} #{lado})"
    end

    def plain(v)
      v = v.to_unsafe_h if v.respond_to?(:to_unsafe_h)
      v.is_a?(Hash) ? v.deep_stringify_keys : v
    end
  end
end
