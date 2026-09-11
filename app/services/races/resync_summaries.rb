# frozen_string_literal: true

module Races
  # FASE 4 do editor de raças — o que o mestre muda chegar às fichas que JÁ
  # existem.
  #
  # ⚠️ Medido numa ficha real: hoje a ficha fica INCOERENTE consigo mesma
  # depois de uma edição. A mecânica propaga ao vivo (o `RaceProducer` lê
  # `RaceRules.apply` a cada summary, então a resistência nova aparece em
  # combate na hora), mas a VITRINE fica presa no `race_summary` materializado
  # no provisionamento — deslocamento, lista de traços e proficiências.
  #
  # O resultado é o pior dos dois: o personagem passa a resistir a contundente
  # e a ficha não lista nenhum traço que explique porquê.
  #
  # ⚠️ E o caminho óbvio de conserto — recompor o snapshot a partir das regras —
  # APAGA AS ESCOLHAS DO JOGADOR. Medido: o Anão guarda a ferramenta escolhida
  # em `proficiencies.tools.fixed`, e o YAML não a tem (lá é
  # `{choiceCount: 1, choices: [...]}`). Recompor sem cuidado tira a escolha
  # dele em silêncio. Por isso cada campo diz explicitamente o que preserva.
  class ResyncSummaries
    Relatorio = Struct.new(:vistas, :mudadas, :detalhes, keyword_init: true)

    def self.call(race_id: nil, dry_run: false)
      new(race_id: race_id, dry_run: dry_run).call
    end

    def initialize(race_id: nil, dry_run: false)
      @race_id = race_id
      @dry_run = dry_run
      @detalhes = []
    end

    def call
      vistas = 0
      mudadas = 0

      escopo.find_each do |sheet|
        vistas += 1
        antes = sheet.race_summary || {}
        depois = recompoe(sheet, antes)
        next if depois.nil? || depois == antes

        mudadas += 1
        @detalhes << { sheet_id: sheet.id, mudou: (depois.keys | antes.keys).select { |k| antes[k] != depois[k] } }
        next if @dry_run

        sheet.update_columns(race_summary: depois)
        # ⚠️ O override em `metadata['race_summary']` VENCE a coluna na leitura
        # (`CharacterSheetSummaryService` tenta o metadata primeiro). Deixá-lo
        # para trás faria o resync não ter efeito nenhum nas fichas que o têm.
        next unless sheet.metadata.is_a?(Hash) && sheet.metadata['race_summary'].present?

        meta = sheet.metadata.dup
        meta['race_summary'] = recompoe(sheet, meta['race_summary']) || meta['race_summary']
        sheet.update_columns(metadata: meta)
      end

      Relatorio.new(vistas: vistas, mudadas: mudadas, detalhes: @detalhes)
    end

    private

    def escopo
      base = Sheet.where.not(race_id: nil)
      @race_id.present? ? base.where(race_id: @race_id) : base
    end

    def recompoe(sheet, antes)
      raca = Race.find_by(id: sheet.race_id)
      return nil if raca.nil? || raca.api_index.blank?

      sub = sheet.sub_race_id.present? ? SubRace.find_by(id: sheet.sub_race_id) : nil
      regra = begin
        RaceRules.apply(race_id: raca.api_index, subrace_id: sub&.api_index, choices: {})
      rescue StandardError
        # Raça sem nó nem overlay: não há regra de onde recompor, e inventar
        # seria pior do que deixar o snapshot como está.
        nil
      end
      return nil if regra.blank?

      novo = antes.deep_dup
      novo['name'] = raca.name
      novo['race_name'] = raca.name
      novo['sub_race_name'] = sub.name if sub

      velocidade = regra[:speed].to_i
      novo['speed_ft'] = velocidade if velocidade.positive?

      visao = RaceRules.normalize_range(regra[:darkvision])
      if visao.positive? then novo['darkvision'] = visao else novo.delete('darkvision') end

      novo['languages'] = idiomas(antes['languages'], regra[:languages])
      novo['proficiencies'] = proficiencias(antes['proficiencies'], regra[:proficiencies])
      tracos = tracos_de(regra)
      novo['traits'] = tracos if tracos.any?
      novo
    end

    # ⚠️ Idioma que o jogador ESCOLHEU (Humano, Meio-elfo) está no snapshot e
    # não na regra. Some se recompormos só pela regra.
    def idiomas(antes, da_regra)
      regra = Array(da_regra).map(&:to_s)
      escolhidos = Array(antes).map(&:to_s) - regra
      regra + escolhidos
    end

    # ⚠️ A escolha do jogador vive no `fixed` do snapshot e NÃO está no `fixed`
    # da regra — o Anão escolhe 1 das 3 ferramentas, e o YAML só lista as 3 em
    # `choices`. Preserva-se o que está nas `choices` da regra; o resto do
    # `fixed` é regra antiga e sai.
    def proficiencias(antes, da_regra)
      regra = (da_regra || {}).deep_stringify_keys
      velho = (antes || {}).deep_stringify_keys

      regra.each_key do |cat|
        bloco = regra[cat]
        next unless bloco.is_a?(Hash)

        opcoes = Array(bloco['choices']).map(&:to_s)
        next if opcoes.empty?

        escolhidos = Array(velho.dig(cat, 'fixed')).map(&:to_s).select { |v| opcoes.include?(v) }
        next if escolhidos.empty?

        bloco['fixed'] = (Array(bloco['fixed']).map(&:to_s) + escolhidos).uniq
      end
      regra
    end

    # ⚠️ A lista vem de `RaceRules.apply` + `trait_definitions`, NÃO das linhas
    # `race_traits`. Um traço PRÓPRIO criado no editor vive só no `rules_json`:
    # não tem linha na tabela e nunca apareceria na ficha por aquele caminho.
    #
    # E a descrição vai JÁ INTERPOLADA a partir do ref. Em runtime a
    # interpolação depende de `RaceTrait.metadata`, que também não existe para
    # o traço próprio — o texto ficaria com `<dano>` à vista, que foi
    # exatamente como 12 descrições se degradaram quando isto foi medido.
    def tracos_de(regra)
      defs = RaceRules.trait_definitions || {}
      Array(regra[:traits]).filter_map do |ref|
        chave = (ref.is_a?(Hash) ? ref[:key] : ref).to_s
        d = defs[chave.to_sym] || defs[chave]
        next if d.nil?

        {
          'name' => (d[:name] || d['name']).to_s,
          'description' => interpola((d[:description] || d['description']).to_s, ref)
        }
      end
    end

    def interpola(texto, ref)
      return texto unless texto.include?('<') && ref.is_a?(Hash)

      texto.gsub(/<([^<>\s]+)>/) do |marca|
        campo = Regexp.last_match(1).to_s
        valor = ref[campo.to_sym] || ref[campo] ||
                ref[TRADUZ_CAMPO[campo]&.to_sym] || ref[TRADUZ_CAMPO[campo]]
        valor.presence ? valor.to_s : marca
      end
    end

    # A prosa do YAML é PT (`<dano>`, `<alcance>`) e o ref é o do livro em
    # inglês (`damage`, `range`) — medido no Draconato.
    TRADUZ_CAMPO = {
      'dano' => 'damage', 'alcance' => 'range', 'area' => 'breath',
      'sopro' => 'breath', 'tipo' => 'damage'
    }.freeze
  end
end
