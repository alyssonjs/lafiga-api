class BackgroundRules
  # PT-BR background catalog with proficiencies/choices based on D&D 5e PHB
  # Keys are slugs; values include required skills, tools and optional choices
  RULES = {
    acolyte: {
      id: 'acolyte', name: 'Acólito',
      skills: ['Intuição','Religião'],
      tools: [],
      languages: { choose: 2, choices: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal','Anão das Profundezas','Silvestre'] },
      equipment: ['Um símbolo sagrado', 'Um livro de orações', 'Um incensário com incenso', 'Vestes comuns', 'Uma algibeira contendo 15 po'],
      feature: {
        name: 'ABRIGO DOS FIÉIS',
        desc: 'Como um acólito, você detém o respeito daqueles que compartilham de sua fé, e você pode realizar cerimônias de sua divindade. Você e seus companheiros de aventura podem até receber cura e caridade de um templo, santuário ou outro posto de sua fé, embora devam fornecer quaisquer componentes materiais necessários para as magias.'
      }
    },
    criminal: {
      id: 'criminal', name: 'Criminoso',
      skills: ['Enganação','Furtividade'],
      tools: ['Ferramentas de Ladrão', { gaming_set: { choose: 1, choices: ['Dados','Cartas'] } }],
      languages: { choose: 0 },
      equipment: ['Uma alavanca de ferro', 'Um punhal escuro com capuz', 'Um conjunto de roupas escuras comuns', 'Uma algibeira contendo 15 po'],
      feature: {
        name: 'CONTATO CRIMINOSO',
        desc: 'Você tem um contato confiável e confiável que atua como sua ligação com uma rede de outros criminosos. Você sabe como enviar mensagens para e receber mensagens de e através de sua rede de contatos criminosos, mesmo através de grandes distâncias.'
      }
    },
    soldier: {
      id: 'soldier', name: 'Soldado',
      skills: ['Atletismo','Intimidação'],
      tools: ['Veículos Terrestres', { gaming_set: { choose: 1, choices: ['Dados','Cartas'] } }],
      languages: { choose: 0 },
      equipment: ['Um insígnia de posto', 'Um troféu tomado de um inimigo caído', 'Um conjunto de dados de osso', 'Um conjunto de roupas comuns', 'Uma algibeira contendo 10 po'],
      feature: {
        name: 'POSIÇÃO MILITAR',
        desc: 'Você tem uma posição militar, permitindo que você comande soldados de baixo escalão que o reconhecem como tendo autoridade sobre eles. Você pode invocar sua posição militar para influenciar soldados de baixo escalão, requisitar equipamentos militares simples ou obter acesso livre a acampamentos e fortalezas militares onde sua posição é reconhecida.'
      }
    },
    charlatan: {
      id: 'charlatan', name: 'Charlatão',
      skills: ['Enganação','Prestidigitação'],
      tools: ['Kit de disfarce', 'Ferramentas de falsificação'],
      languages: { choose: 0 },
      equipment: ['Um kit de disfarce', 'Ferramentas de falsificação', 'Um conjunto de roupas finas', 'Uma algibeira contendo 15 po'],
      feature: {
        name: 'IDENTIDADE FALSA',
        desc: 'Você criou uma segunda identidade que inclui documentação, conhecidos estabelecidos e disfarces que permitem que você se passe por essa pessoa. Enquanto você está usando sua identidade falsa, outros acreditam que você é essa pessoa até que você se revele.'
      }
    },
    entertainer: {
      id: 'entertainer', name: 'Artista',
      skills: ['Acrobacia','Atuação'],
      tools: ['Kit de disfarce', { instrument: { choose: 1, choices: ['Alaúde', 'Violino', 'Flauta', 'Harpa'] } }],
      languages: { choose: 0 },
      equipment: ['Um instrumento musical', 'Um presente de um admirador', 'Um traje', 'Uma algibeira contendo 15 po'],
      feature: {
        name: 'PELA DEMANDA POPULAR',
        desc: 'Você sempre encontra um lugar para atuar, geralmente em tavernas ou estalagens mas, possivelmente em circos, teatros ou até em cortes nobres. Em tais lugares, você recebe alojamento e comida modesta ou de patrões confortáveis, de graça.'
      }
    },
    :'folk-hero' => {
      id: 'folk-hero',
      name: 'Herói do Povo',
      skills: ['Lidar com Animais', 'Sobrevivência'],
      tools: [
        { artisan_tools: { choose: 1, choices: ClassRules::ARTISAN_TOOLS } },
        'Veículos Terrestres'
      ],
      languages: { choose: 0 },
      equipment: [
        'Ferramentas de artesão (à escolha)',
        'Uma pá',
        'Uma panela de ferro',
        'Um conjunto de roupas comuns',
        'Uma algibeira contendo 10 po'
      ],
      feature: {
        name: 'HOSPITALIDADE RÚSTICA',
        desc: 'Camponeses oferecem abrigo e ajuda, contanto que não se coloquem em risco direto. Você se mistura facilmente entre o povo.'
      }
    },
    :'guild-artisan' => {
      id: 'guild-artisan',
      name: 'Artesão da Guilda',
      skills: ['Intuição', 'Persuasão'],
      tools: [{ artisan_tools: { choose: 1, choices: ClassRules::ARTISAN_TOOLS } }],
      languages: { choose: 1, choices: ['Anão', 'Élfico', 'Halfling', 'Dracônico', 'Gnômico', 'Orc', 'Infernal', 'Anão das Profundezas', 'Silvestre'] },
      equipment: [
        'Ferramentas de artesão (à escolha)',
        'Uma carta de apresentação da guilda',
        'Um conjunto de roupas de viajante',
        'Uma algibeira contendo 15 po'
      ],
      feature: {
        name: 'ASSOCIADOS DA GUILDA',
        desc: 'A guilda fornece contatos, oportunidades e, em necessidade, comida e hospedagem. Você deve pagar 5 po/mês em cotas para manter os benefícios.'
      }
    },
    hermit: {
      id: 'hermit', name: 'Eremita',
      skills: ['Medicina','Religião'],
      tools: ['Kit de herbalismo'],
      languages: { choose: 1, choices: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal','Anão das Profundezas','Silvestre'] },
      equipment: ['Um kit de herbalismo', 'Um pergaminho com uma profecia', 'Um conjunto de roupas comuns', 'Uma algibeira contendo 5 po'],
      feature: {
        name: 'DESCOBERTA',
        desc: 'O isolamento de sua vida eremítica lhe deu acesso a uma descoberta única e poderosa. A natureza dessa descoberta depende da natureza de sua vida eremítica. Pode ser uma grande verdade sobre o cosmos, os deuses, os poderosos do mundo, a natureza da magia, ou um segredo que há muito tempo foi perdido.'
      }
    },
    noble: {
      id: 'noble', name: 'Nobre',
      skills: ['História','Persuasão'],
      tools: [
        {
          gaming_set: {
            choose: 1,
            choices: ['Conjunto de dados', 'Xadrez de dragão', 'Baralho de cartas', 'Conjunto de Três-Dragões Ante']
          }
        }
      ],
      languages: { choose: 1, choices: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal','Anão das Profundezas','Silvestre'] },
      equipment: ['Um insígnia de posto', 'Uma carta de apresentação de um nobre', 'Um conjunto de roupas finas', 'Uma algibeira contendo 25 po'],
      feature: {
        name: 'POSIÇÃO DE PRIVILÉGIO',
        desc: 'Graças à sua origem nobre, as pessoas estão inclinadas a pensar o melhor de você. Você é bem-vindo na alta sociedade, e as pessoas assumem que você tem o direito de estar onde quer que esteja. Os plebeus fazem o melhor para acomodá-lo e evitar sua desaprovação, e outros nobres o tratam como um membro da mesma esfera social.'
      }
    },
    outlander: {
      id: 'outlander', name: 'Forasteiro',
      skills: ['Atletismo','Sobrevivência'],
      tools: [
        {
          instrument: {
            choose: 1,
            choices: ['Alaúde', 'Charamela', 'Cítara', 'Cornamusa', 'Flauta', 'Flauta de Pã', 'Gaita de foles', 'Lira', 'Tambor', 'Viola']
          }
        }
      ],
      languages: { choose: 1, choices: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal','Anão das Profundezas','Silvestre'] },
      equipment: ['Um bastão', 'Uma armadilha de caça', 'Um troféu de animal', 'Um conjunto de roupas de viagem', 'Uma algibeira contendo 10 po'],
      feature: {
        name: 'ORIGEM',
        desc: 'Você tem uma excelente memória para mapas e geografia, e você sempre pode recordar o layout geral do terreno, assentamentos e outras características ao redor de você. Além disso, você pode encontrar comida e água fresca para você e até cinco outras pessoas a cada dia, desde que a terra ofereça bagas, pequenos animais, água e assim por diante.'
      }
    },
    sage: {
      id: 'sage', name: 'Sábio',
      skills: ['Arcanismo','História'],
      tools: [],
      languages: { choose: 2, choices: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal','Anão das Profundezas','Silvestre'] },
      equipment: ['Tinta negra', 'Uma pena', 'Um pequeno faca', 'Uma carta de um falecido colega', 'Um conjunto de roupas comuns', 'Uma algibeira contendo 10 po'],
      feature: {
        name: 'PESQUISADOR',
        desc: 'Quando você tenta aprender ou relembrar um pedaço de conhecimento, se você não souber a informação, você frequentemente sabe onde e como obtê-la. Normalmente, essa informação vem de uma biblioteca, scriptorium, universidade, ou sábio ou outro sábio. Seus contatos podem ser capazes de obter a informação para você ou podem saber alguém que pode.'
      }
    },
    sailor: {
      id: 'sailor', name: 'Marinheiro',
      skills: ['Atletismo','Percepção'],
      tools: ['Ferramentas de navegador', 'Veículos Aquáticos'],
      languages: { choose: 0 },
      equipment: ['Uma alavanca de ferro', 'Um cabo de seda', 'Um amuleto da sorte', 'Um conjunto de roupas comuns', 'Uma algibeira contendo 10 po'],
      feature: {
        name: 'NAVEGAÇÃO DO NAVIO',
        desc: 'Você pode obter passagem gratuita em navios para si mesmo e seus companheiros de aventura. Você pode navegar o navio se você for o único que sabe como. Os marinheiros tratam você com respeito.'
      }
    },
    urchin: {
      id: 'urchin', name: 'Órfão',
      skills: ['Furtividade','Prestidigitação'],
      tools: ['Ferramentas de Ladrão'],
      languages: { choose: 0 },
      equipment: ['Uma alavanca de ferro', 'Um conjunto de dados de osso', 'Um conjunto de roupas escuras comuns', 'Uma algibeira contendo 10 po'],
      feature: {
        name: 'SEGREDOS DA CIDADE',
        desc: 'Você conhece os segredos da cidade como as palmas das suas mãos. Você pode encontrar mensagens e pessoas que outros não conseguem. Você conhece um sistema de túneis, esgotos ou telhados que pode usar para se mover pela cidade sem ser detectado.'
      }
    }
  }.with_indifferent_access.freeze

  CACHE_KEY = 'background_rules_merged_v1'

  def self.clear_cache!
    Rails.cache.delete(CACHE_KEY)
  end

  def self.all
    Rails.cache.fetch(CACHE_KEY) { build_merged_hash }
  end

  def self.find(key)
    all[key.to_s]
  end

  def self.build_merged_hash
    out = {}.with_indifferent_access
    RULES.each { |sym, rule| out[sym.to_s] = rule.deep_dup.with_indifferent_access }

    if defined?(Background) && Background.connection.data_source_exists?('backgrounds')
      published = Background.published.order(:id).to_a
      parents = published.reject { |b| b.parent_api_index.present? }
      variants = published.select { |b| b.parent_api_index.present? }

      parents.each do |b|
        r = rule_row_from_record(b)
        out[b.api_index.to_s] = r.with_indifferent_access if r
      end

      # Variantes: várias passagens para suportar variante-de-variante (ordem de id irrelevante).
      pending = variants.dup
      max_passes = variants.size + 8
      max_passes.times do
        break if pending.empty?

        size_before = pending.size
        progress = false
        pending.reject! do |b|
          parent_key = b.parent_api_index.to_s
          base = out[parent_key].presence || fallback_rule_for_slug(parent_key)
          next false unless base

          delta = b.rules.is_a?(Hash) ? b.rules.deep_dup : {}
          merged = deep_merge_rules(base.deep_dup, delta)
          merged[:id] = b.api_index
          merged[:name] = b.name.to_s if b.name.present?
          attach_variant_lineage!(merged, parent_key, base)
          out[b.api_index.to_s] = merged.with_indifferent_access
          progress = true
          true
        end

        break unless progress

        if pending.size == size_before
          Rails.logger.warn(
            "BackgroundRules: variantes com pai ausente ou ciclo — ignoradas: #{pending.map(&:api_index).join(', ')}"
          )
          break
        end
      end
    end

    out
  end

  def self.attach_variant_lineage!(merged, parent_key, base)
    merged[:parent_background_index] = parent_key
    merged[:parent_background_name] = (base[:name] || base['name'] || parent_key).to_s
    merged[:is_variant] = true
  end

  def self.slug_known?(slug)
    s = slug.to_s
    return true if fallback_rule_for_slug(s).present?
    return false unless defined?(Background) && Background.connection.data_source_exists?('backgrounds')

    Background.where(api_index: s).exists?
  end

  def self.fallback_rule_for_slug(slug)
    s = slug.to_s
    RULES[s.to_sym] || RULES[s.tr('-', '_').to_sym]
  end

  def self.rule_row_from_record(b)
    if b.rules.is_a?(Hash) && b.rules.keys.size.positive?
      h = b.rules.deep_dup.deep_symbolize_keys
      h[:id] ||= b.api_index
      h[:name] ||= b.name
      if b.feature_name.present? && h[:feature].blank?
        h[:feature] = { name: b.feature_name, desc: (b.feature_desc || '').to_s }
      end
      h
    elsif (fb = fallback_rule_for_slug(b.api_index))
      fb.deep_dup
    else
      legacy_fallback_rule(b)
    end
  end

  def self.legacy_fallback_rule(bg)
    {
      id: bg.api_index,
      name: bg.name,
      skills: [],
      tools: [],
      languages: { choose: 0 },
      equipment: [],
      feature: {
        name: (bg.feature_name.presence || 'CARACTERÍSTICA').to_s,
        desc: (bg.feature_desc.presence || '').to_s
      }
    }
  end

  def self.deep_merge_rules(base, delta)
    b = (base.is_a?(Hash) ? base : {}).deep_stringify_keys
    d = (delta.is_a?(Hash) ? delta : {}).deep_stringify_keys
    b.deep_merge(d).deep_symbolize_keys
  end

  # Applies a selection (hash) and returns a normalized summary
  # selection: { key:, choices: { languages: [], tools: [], gaming_set: [], instrument: [], artisan_tools: [] } }
  def self.apply(selection)
    bg = find(selection[:key])
    raise ArgumentError, 'background não encontrado' unless bg
    choices = selection[:choices]
    choices = {} unless choices.is_a?(Hash)
    ch = choices.respond_to?(:with_indifferent_access) ? choices.with_indifferent_access : {}.with_indifferent_access

    langs = []
    if bg.dig(:languages, :choose).to_i > 0
      langs = Array(ch[:languages]).map { |x| (x.is_a?(Hash) ? x['name'] || x[:name] : x).to_s }
      langs = langs.first(bg[:languages][:choose].to_i)
    end

    tool_queue = Array(ch[:tools]).map { |x| (x.is_a?(Hash) ? (x['name'] || x[:name]) : x).to_s }.reject(&:blank?)

    tools = []
    Array(bg[:tools]).each do |t|
      if t.is_a?(Hash) && t[:gaming_set]
        opts = t[:gaming_set]
        n = opts[:choose].to_i.nonzero? || 1
        from_gs = Array(ch[:gaming_set]).map { |x| (x.is_a?(Hash) ? x['name'] || x[:name] : x).to_s }.reject(&:blank?)
        picked = from_gs.any? ? from_gs.first(n) : tool_queue.shift(n)
        label = Array(picked).flatten.compact.first
        tools << ('Jogo de ' + (label.presence || 'Escolher'))
      elsif t.is_a?(Hash) && t[:instrument]
        opts = t[:instrument]
        n = opts[:choose].to_i.nonzero? || 1
        from_ins = Array(ch[:instrument]).map { |x| (x.is_a?(Hash) ? x['name'] || x[:name] : x).to_s }.reject(&:blank?)
        picked = from_ins.any? ? from_ins.first(n) : tool_queue.shift(n)
        label = Array(picked).flatten.compact.first
        tools << (label.presence || 'Instrumento musical (escolher)')
      elsif t.is_a?(Hash) && t[:artisan_tools]
        opts = t[:artisan_tools]
        n = opts[:choose].to_i.nonzero? || 1
        from_at = Array(ch[:artisan_tools]).map { |x| (x.is_a?(Hash) ? x['name'] || x[:name] : x).to_s }.reject(&:blank?)
        picked = from_at.any? ? from_at.first(n) : tool_queue.shift(n)
        label = Array(picked).flatten.compact.first
        tools << (label.presence || 'Ferramentas de artesão (escolher)')
      else
        tools << t
      end
    end
    personality_traits = Array(ch[:personalityTraits]).map { |x| x.to_s.strip }.reject(&:blank?)
    ideals_chosen = Array(ch[:ideals]).map { |x| x.to_s.strip }.reject(&:blank?)
    bonds_chosen = Array(ch[:bonds]).map { |x| x.to_s.strip }.reject(&:blank?)
    flaws_chosen = Array(ch[:flaws]).map { |x| x.to_s.strip }.reject(&:blank?)

    {
      key: bg[:id],
      name: bg[:name],
      skills: Array(bg[:skills]),
      tools: tools,
      languages: langs,
      equipment: Array(bg[:equipment] || []),
      feature: bg[:feature] || {},
      personality_traits: personality_traits,
      ideals: ideals_chosen,
      bonds: bonds_chosen,
      flaws: flaws_chosen
    }
  end
end

