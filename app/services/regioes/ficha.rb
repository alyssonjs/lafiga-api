# frozen_string_literal: true

module Regioes
  # A FICHA DE REGIÃO (09/10; L1.1, plano A14 e B3): o yml de `config/mundo/regioes/`, conferido inteiro ao carregar e
  # congelado. O que cada parte quer dizer, e de onde veio, está no comentário do próprio arquivo (`argoba.yml`).
  #
  # Uma ficha errada falha ao carregar, com o arquivo e o pedaço na mensagem, em vez de virar um setor sem CD ou um
  # bioma que o gerador não conhece mais adiante.
  module Ficha
    module_function

    PASTA = 'config/mundo/regioes'
    PARTES = %w[chave nome reino biomas cd_acampamento campanha].freeze
    PARTES_DO_BIOMA = %w[nome recursos perigos estacoes clima coleta fauna].freeze
    LISTAS_DO_BIOMA = %w[recursos perigos clima coleta fauna].freeze
    PARTES_DA_CAMPANHA = %w[chave nome ameaca etapas setores].freeze
    PARTES_DO_SETOR = %w[chave nome tipo bioma estado territorio pressao_selvagem influencia].freeze
    PRESSOES = %w[pressao_selvagem influencia].freeze
    # o clima simples do MVP (plano I2); as chances por estação são do L1.9
    CLIMAS = %w[chuva tempestade].freeze

    def de(chave)
      todas.fetch(chave.to_s) { raise ArgumentError, "região sem ficha: #{chave}" }
    end

    # chave → ficha, de todos os arquivos da pasta
    def todas
      @todas ||= Dir[Rails.root.join(PASTA, '*.yml')].sort.to_h do |caminho|
        ficha = carrega(caminho)
        [ficha['chave'], ficha]
      end.freeze
    end

    def carrega(caminho)
      ficha = YAML.safe_load(File.read(caminho))
      nome = File.basename(caminho, '.yml')
      unless ficha.is_a?(Hash) && ficha['chave'] == nome
        raise ArgumentError, "#{caminho}: a chave #{ficha.is_a?(Hash) ? ficha['chave'] : '?'} não é o nome do arquivo (#{nome})"
      end

      congela(confere!(ficha, origem: caminho))
    end

    # Confere a ficha inteira; a primeira falha sobe como ArgumentError, com a `origem` na frente.
    def confere!(ficha, origem:)
      falha = ->(mensagem) { raise ArgumentError, "#{origem}: #{mensagem}" }

      falha.call('a ficha não é um mapa') unless ficha.is_a?(Hash)
      PARTES.each { |parte| falha.call("falta #{parte}") if ficha[parte].blank? }
      falha.call('só inteiros na ficha (plano D11)') if quebrado?(ficha)

      confere_biomas(ficha['biomas'], falha)
      cds = confere_cds(ficha['cd_acampamento'], falha)
      confere_campanha(ficha['campanha'], cds, falha)
      ficha
    end

    def confere_biomas(biomas, falha)
      falha.call('biomas não é um mapa') unless biomas.is_a?(Hash)
      biomas.each do |chave, b|
        falha.call("bioma desconhecido: #{chave}") unless Regiao::BIOMAS.include?(chave)
        PARTES_DO_BIOMA.each { |parte| falha.call("falta #{parte} em #{chave}") unless b.is_a?(Hash) && b.key?(parte) }
        LISTAS_DO_BIOMA.each { |parte| falha.call("#{parte} em #{chave} não é uma lista") unless b[parte].is_a?(Array) }
        falha.call("estacoes em #{chave} não é um mapa") unless b['estacoes'].is_a?(Hash)

        (b['estacoes'].keys - Mundo::Relogio::ESTACOES).each { |e| falha.call("estação desconhecida em #{chave}: #{e}") }
        (b['clima'] - CLIMAS).each { |c| falha.call("clima desconhecido em #{chave}: #{c}") }
        (b['coleta'] - Regiao::BIOMAS).each { |t| falha.call("terreno de coleta desconhecido em #{chave}: #{t}") }
        falha.call("fauna em #{chave} tem nome vazio") unless b['fauna'].all? { |m| m.is_a?(String) && m.present? }
        repetida = b['fauna'].detect { |m| b['fauna'].count(m) > 1 }
        falha.call("fauna repetida em #{chave}: #{repetida}") if repetida
      end
    end

    # → as CDs por território (plano A15): uma para cada território do `Setor`
    def confere_cds(cds, falha)
      falha.call('cd_acampamento não é um mapa') unless cds.is_a?(Hash)
      unless cds.keys.sort == Setor::TERRITORIOS.sort
        falha.call("cd_acampamento precisa de #{Setor::TERRITORIOS.join(', ')}")
      end
      cds.each do |territorio, cd|
        falha.call("cd_acampamento #{territorio} fora de 1..30") unless cd.is_a?(Integer) && cd.between?(1, 30)
      end
      cds
    end

    def confere_campanha(campanha, cds, falha)
      falha.call('campanha não é um mapa') unless campanha.is_a?(Hash)
      PARTES_DA_CAMPANHA.each { |parte| falha.call("falta campanha.#{parte}") if campanha[parte].blank? }
      ameaca = campanha['ameaca']
      falha.call('falta a chave da ameaça') unless ameaca.is_a?(Hash) && ameaca['chave'].present?
      falha.call('as tropas da ameaça não são uma lista') unless ameaca['tropas'].is_a?(Array)
      etapas = campanha['etapas']
      falha.call('etapas não é uma lista sem repetição') unless etapas.is_a?(Array) && etapas.uniq.size == etapas.size

      vistos = []
      campanha['setores'].each do |s|
        nome = s['chave']
        PARTES_DO_SETOR.each { |parte| falha.call("setor #{nome || '?'}: falta #{parte}") if s[parte].nil? }
        falha.call("setor repetido: #{nome}") if vistos.include?(nome)
        vistos << nome

        falha.call("#{nome}: tipo desconhecido: #{s['tipo']}") unless Setor::TIPOS.include?(s['tipo'])
        falha.call("#{nome}: bioma desconhecido: #{s['bioma']}") unless Regiao::BIOMAS.include?(s['bioma'])
        falha.call("#{nome}: estado desconhecido: #{s['estado']}") unless Setor::ESTADOS.include?(s['estado'])
        falha.call("#{nome}: territorio desconhecido: #{s['territorio']}") unless cds.key?(s['territorio'])
        PRESSOES.each do |pressao|
          falha.call("#{nome}: #{pressao} fora de 0..100") unless s[pressao].is_a?(Integer) && s[pressao].between?(0, 100)
        end
        confere_mapa(s, nome, falha) if s.key?('mapa')
      end
    end

    # o tamanho do mapa do setor (L1.2), opcional: só o setor que já tem mapa o diz
    def confere_mapa(setor, nome, falha)
      mapa = setor['mapa']
      dims = BattleMap::MIN_DIM..BattleMap::MAX_DIM
      ok = mapa.is_a?(Hash) && %w[colunas linhas].all? { |k| mapa[k].is_a?(Integer) && dims.cover?(mapa[k]) }
      falha.call("#{nome}: mapa fora de #{dims} (colunas e linhas)") unless ok
    end

    # há número quebrado em algum canto? (o `confere!` recusa antes de olhar o resto)
    def quebrado?(valor)
      case valor
      when Float then true
      when Hash then valor.each_value.any? { |v| quebrado?(v) }
      when Array then valor.any? { |v| quebrado?(v) }
      else false
      end
    end

    def congela(valor)
      case valor
      when Hash then valor.each_value { |v| congela(v) }
      when Array then valor.each { |v| congela(v) }
      end
      valor.freeze
    end
  end
end
