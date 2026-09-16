# frozen_string_literal: true

module Subclasses
  # Aplica um PATCH GRANULAR ao `sub_klasses.levels_json`.
  #
  # ⚠️ Irmão de `Klasses::RulesOverlay`, mesma fronteira e mesmo motivo: o admin
  # grava `levels_json` cru, em replace-all — então um PATCH com um nível apagava
  # os outros dezenove. É o mesmo buraco que a fase 1 fechou em `klasses.rules` e
  # que aqui seguia aberto, agora com a agravante de a página do compêndio passar
  # a editar nível a nível.
  #
  # O patch fala em NÍVEIS, não no documento inteiro: `set` mescla linha a linha
  # (raso, chave a chave), `remove` tira níveis, `rules` cuida do bloco de topo.
  # `nil` numa chave é o gesto de SOLTAR — a chave volta a valer a base do livro,
  # que é diferente de gravar vazio ("a sub-classe não tem isso").
  #
  # ⚠️ Linha não tocada sai como o MESMO objeto. É isso que deixa o request spec
  # provar granularidade: se um patch no nível 3 devolvesse cópias das outras,
  # "não mexeu" ficaria indistinguível de "reescreveu igual".
  module LevelsPatch
    CHAVES_DO_PATCH = %w[set remove rules].freeze

    module_function

    # Devolve `[linhas, erros]`. Com qualquer erro devolve as linhas ATUAIS
    # intactas: nada fica gravado pela metade, nem a parte válida do patch.
    def aplicar(atual, patch)
      linhas = Array(atual).select { |l| l.is_a?(Hash) }
      bruto = normaliza(patch)
      return [linhas, ['patch tem de ser um objeto']] unless bruto.is_a?(Hash)

      fora = bruto.keys - CHAVES_DO_PATCH
      return [linhas, ["chaves desconhecidas no patch: #{fora.sort.join(', ')}"]] if fora.any?

      erros = []
      saida = linhas.dup

      Array(bruto['set']).each do |linha|
        nova, e = linha_saneada(linha)
        erros.concat(e)
        next if nova.nil?

        i = saida.index { |l| nivel_de(l) == nivel_de(nova) }
        i ? saida[i] = mescla(saida[i], nova) : saida << nova
      end

      remover, e = niveis_a_remover(bruto['remove'])
      erros.concat(e)
      saida = saida.reject { |l| remover.include?(nivel_de(l)) } if remover.any?

      if bruto.key?('rules')
        saida, e = aplica_rules(saida, bruto['rules'])
        erros.concat(e)
      end

      return [linhas, erros] if erros.any?

      [saida.sort_by { |l| nivel_de(l) }, []]
    end

    # Mescla RASA: o patch manda na chave que trouxe, o resto da linha fica.
    def mescla(velha, nova)
      out = velha.merge(nova)
      nova.each_key { |k| out.delete(k) if nova[k].nil? }
      out
    end

    def linha_saneada(linha)
      return [nil, ['cada item de `set` tem de ser um objeto']] unless linha.is_a?(Hash)

      nivel = inteiro(linha['level'])
      unless nivel && nivel.between?(0, SubKlass::NIVEL_MAXIMO)
        return [nil, ["`level` inválido em `set`: #{linha['level'].inspect}"]]
      end

      erros = erros_de_features(linha['features'], nivel)
      return [nil, erros] if erros.any?

      # Escritor canônico: `level` grava SEMPRE inteiro, venha "3" de um form ou
      # 3 de um JSON — é por ele que toda leitura casa nível com nível.
      [linha['level'].is_a?(Integer) ? linha : linha.merge('level' => nivel), []]
    end

    def erros_de_features(feats, nivel)
      return [] if feats.nil?
      return ["nível #{nivel}: `features` tem de ser uma lista"] unless feats.is_a?(Array)

      feats.each_with_index.filter_map do |f, i|
        next if f.is_a?(Hash) && f['name'].to_s.strip.present?

        "nível #{nivel}, feature #{i + 1}: `name` é obrigatório"
      end
    end

    def niveis_a_remover(valor)
      return [[], []] if valor.nil?
      return [[], ['`remove` tem de ser uma lista de níveis']] unless valor.is_a?(Array)

      erros = []
      niveis = valor.filter_map do |v|
        n = inteiro(v)
        erros << "`remove`: nível inválido #{v.inspect}" if n.nil?
        n
      end
      [niveis, erros]
    end

    # ⚠️ As `rules` de topo moram na LINHA DE NÍVEL 0 — foi assim que o import as
    # guardou (`apply_subclass_grants!`) e é de lá que todo leitor as tira. As 13
    # linhas de nível 0 medidas em prod têm exatamente as chaves `level`+`rules`.
    def aplica_rules(saida, valor)
      i = saida.index { |l| nivel_de(l).zero? }
      return [solta_rules(saida, i), []] if valor.nil?
      return [saida, ['`rules` tem de ser um objeto']] unless valor.is_a?(Hash)

      novo = saida.dup
      if i
        novo[i] = novo[i].merge('rules' => valor)
      else
        novo << { 'level' => 0, 'rules' => valor }
      end
      [novo, []]
    end

    def solta_rules(saida, i)
      return saida if i.nil?

      resto = saida[i].except('rules')
      novo = saida.dup
      if (resto.keys - ['level']).empty?
        novo.delete_at(i)
      else
        novo[i] = resto
      end
      novo
    end

    def nivel_de(linha)
      (linha['level'] || linha[:level]).to_i
    end

    def inteiro(valor)
      return valor if valor.is_a?(Integer)
      return valor.to_i if valor.is_a?(String) && valor.strip.match?(/\A\d+\z/)

      nil
    end

    def normaliza(raw)
      return raw.to_unsafe_h.deep_stringify_keys if raw.respond_to?(:to_unsafe_h)
      return raw.deep_stringify_keys if raw.is_a?(Hash)

      raw
    end
  end
end
