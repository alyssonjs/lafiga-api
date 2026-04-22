# frozen_string_literal: true

require_relative 'subclass_rules_extended'

class SubclassRules
  # Regras estáticas para novas subclasses baseadas no arquivo novos_arquetipos.txt
  # Seguindo o padrão do ClassRules e RaceRules

  def self.rules
    Rails.cache.fetch('subclass_rules_v1', expires_in: 12.hours) { 
      SUBCLASS_RULES.merge(SubclassRulesExtended::EXTENDED_SUBCLASSES)
    }
  end

  def self.find(class_id, subclass_id)
    class_rules = rules[class_id.to_s]
    return nil unless class_rules
    
    class_rules[subclass_id.to_s]
  end

  def self.available_for_class(class_id)
    rules[class_id.to_s] || {}
  end

  # Aplica regras de uma subclasse específica
  def self.apply(class_id, subclass_id, level)
    rule = find(class_id, subclass_id)
    return nil unless rule

    {
      subclass_id: subclass_id,
      name: rule[:name],
      description: rule[:description],
      features: rule[:features] || {},
      spellcasting: rule[:spellcasting],
      proficiencies: rule[:proficiencies] || {},
      features_by_level: extract_features_for_level(rule, level)
    }
  end

  private

  def self.extract_features_for_level(rule, level)
    features = {}
    
    # Buscar features por nível
    (rule[:features] || {}).each do |feature_level, feature_data|
      if feature_level.to_i <= level
        features[feature_level] = feature_data
      end
    end
    
    features
  end

  # Regras das novas subclasses baseadas no arquivo novos_arquetipos.txt
  SUBCLASS_RULES = {
    'barbarian' => {
      'cicatrizes_runicas' => {
        name: 'Caminho do Bárbaro das Cicatrizes Rúnicas',
        description: 'Alguns bárbaros descobrem que possuem capacidades arcanas inatas ao cravarem runas místicas em sua carne.',
        spellcasting: {
          ability: 'CHA',
          spell_list: 'sorcerer',
          cantrips_known: { 3 => 2, 8 => 3, 14 => 4 },
          spells_known: { 3 => 1, 4 => 2, 7 => 3, 10 => 4, 13 => 5, 16 => 6, 19 => 7 },
          spell_slots: {
            3 => [2], 4 => [3], 5 => [3], 6 => [3], 7 => [4, 2], 8 => [4, 2], 9 => [4, 2],
            10 => [4, 3], 11 => [4, 3], 12 => [4, 3], 13 => [4, 3, 2], 14 => [4, 3, 2],
            15 => [4, 3, 2], 16 => [4, 3, 3], 17 => [4, 3, 3], 18 => [4, 3, 3],
            19 => [4, 3, 3, 1], 20 => [4, 3, 3, 1]
          }
        },
        features: {
          3 => {
            'Conjuração' => 'Você descobre uma energia selvagem dentro de si próprio que você pode despertar mesmo em fúria.'
          },
          6 => {
            'Runas de Poder' => 'Você aprende a canalizar poder arcano através de suas runas.'
          },
          10 => {
            'Runas de Proteção' => 'Suas runas podem absorver e refletir magia.'
          },
          14 => {
            'Runas de Destruição' => 'Você pode usar suas runas para causar devastação mágica.'
          }
        }
      },
      'desistente' => {
        name: 'Caminho do Desistente',
        description: 'Selvagens que vivem em algumas tribos isoladas costumam nutrir uma aversão aos efeitos místicos que permeiam o mundo.',
        features: {
          3 => {
            'Aversão à Magia' => 'Sua repulsa ao misticismo cria uma crescente descrença em você a tudo que não compreende ou considera antinatural.'
          },
          6 => {
            'Revigorante Natural' => 'Quando você concluir um descanso curto, você recupera uma quantidade de pontos de vida igual ao seu modificador de Constituição + seu nível de bárbaro.'
          },
          10 => {
            'Supersticioso Revoltado' => 'Sua raiva pela magia leva você a crer que ela é responsável pela destruição do mundo.'
          },
          14 => {
            'Fúria Absorvente' => 'Quando você está em fúria sua aversão à magia cria uma película protetora em volta do seu corpo que absorve efeitos mágicos potencializando sua raiva.'
          }
        }
      },
      'furioso_imortal' => {
        name: 'Caminho do Furioso Imortal',
        description: 'Alguns bárbaros simplesmente parecem não morrer, mesmo ostentando ferimentos aparentemente letais.',
        features: {
          3 => {
            'Fúria Imortal' => 'Você consegue se manter de pé mesmo diante dos castigos mais tremendos enquanto estiver no ápice de sua ira.'
          },
          6 => {
            'Guerreiro do Fogo e Gelo' => 'Sua estamina parece não acabar e você parece incansável mesmo sob as condições mais adversas.'
          },
          10 => {
            'Ira Sangrenta' => 'Você se torna cada vez mais forte conforme sofre mais e mais mazelas.'
          },
          14 => {
            'Fortitude Instintiva' => 'Você consegue se manter vivo de uma forma sobrenatural.'
          }
        }
      },
      'guerreiro_urso' => {
        name: 'Caminho do Guerreiro Urso',
        description: 'Bárbaros que seguem este caminho se conectam com o espírito do urso, um dos animais mais ferozes e resistentes da natureza.',
        features: {
          3 => {
            'Forma do Urso' => 'Você pode se transformar em um urso feroz.'
          },
          6 => {
            'Instinto Selvagem' => 'Você desenvolve sentidos aguçados como os de um urso.'
          },
          10 => {
            'Fúria do Urso' => 'Sua fúria se torna ainda mais devastadora, como a de um urso enraivecido.'
          },
          14 => {
            'Mestre dos Ursos' => 'Você pode convocar e comandar ursos para lutar ao seu lado.'
          }
        }
      },
      'protetor_tribal' => {
        name: 'Caminho do Protetor Tribal',
        description: 'Bárbaros que dedicam suas vidas a proteger suas tribos e comunidades.',
        features: {
          3 => {
            'Proteção Tribal' => 'Você pode usar sua fúria para proteger aliados próximos.'
          },
          6 => {
            'Vigilância Constante' => 'Você desenvolve sentidos aguçados para detectar perigos.'
          },
          10 => {
            'Defesa Inabalável' => 'Você se torna um bastião de proteção para sua tribo.'
          },
          14 => {
            'Líder Tribal' => 'Você pode inspirar e liderar sua tribo em batalha.'
          }
        }
      },
      'raivoso_elemental' => {
        name: 'Caminho do Raivoso Elemental',
        description: 'Bárbaros que canalizam a fúria dos elementos através de sua raiva.',
        features: {
          3 => {
            'Fúria Elemental' => 'Você pode canalizar poder elemental através de sua fúria.'
          },
          6 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Tempestade de Fúria' => 'Você pode criar tempestades elementais com sua raiva.'
          },
          14 => {
            'Avatar Elemental' => 'Você pode se transformar em um avatar elemental.'
          }
        }
      }
    },
    'bard' => {
      'busca_da_cancao' => {
        name: 'Colégio da Busca da Canção',
        description: 'Bardos que dedicam suas vidas à busca de canções perdidas e conhecimentos musicais antigos.',
        features: {
          3 => {
            'Busca Musical' => 'Você pode usar sua música para encontrar objetos e pessoas perdidas.'
          },
          6 => {
            'Canção da Memória' => 'Você pode preservar memórias através de suas canções.'
          },
          14 => {
            'Canção da Verdade' => 'Sua música pode revelar verdades ocultas.'
          }
        }
      },
      'comedia' => {
        name: 'Colégio da Comédia',
        description: 'Bardos que usam humor e comédia para entreter e inspirar.',
        features: {
          3 => {
            'Riso Contagioso' => 'Você pode usar humor para afetar o estado emocional dos outros.'
          },
          6 => {
            'Comédia de Situação' => 'Você pode usar comédia para criar vantagens táticas.'
          },
          14 => {
            'Show de Stand-up' => 'Você pode realizar um show que afeta todos os presentes.'
          }
        }
      },
      'fortuna' => {
        name: 'Colégio da Fortuna',
        description: 'Bardos que canalizam a sorte e a fortuna através de sua arte.',
        features: {
          3 => {
            'Sorte do Bardo' => 'Você pode influenciar a sorte dos outros.'
          },
          6 => {
            'Fortuna Favorece' => 'Você pode dar sorte a aliados ou azar a inimigos.'
          },
          14 => {
            'Destino Manipulado' => 'Você pode alterar o destino de forma limitada.'
          }
        }
      },
      'quietude' => {
        name: 'Colégio da Quietude',
        description: 'Bardos que usam silêncio e tranquilidade como ferramentas artísticas.',
        features: {
          3 => {
            'Silêncio Musical' => 'Você pode criar zonas de silêncio mágico.'
          },
          6 => {
            'Paz Interior' => 'Você pode acalmar emoções e conflitos.'
          },
          14 => {
            'Meditação Coletiva' => 'Você pode guiar outros em meditação profunda.'
          }
        }
      },
      'pavor' => {
        name: 'Colégio do Pavor',
        description: 'Bardos que usam música para incutir medo e terror nos corações dos inimigos.',
        features: {
          3 => {
            'Música do Terror' => 'Você pode usar música para causar medo.'
          },
          6 => {
            'Sinfonia do Horror' => 'Você pode criar ilusões aterrorizantes.'
          },
          14 => {
            'Concerto do Pânico' => 'Você pode causar pânico em massa.'
          }
        }
      },
      'virtuosismo' => {
        name: 'Colégio do Virtuosismo',
        description: 'Bardos que buscam a perfeição técnica em sua arte musical.',
        features: {
          3 => {
            'Perfeição Técnica' => 'Você domina completamente sua arte musical.'
          },
          6 => {
            'Virtuosismo Instrumental' => 'Você pode tocar qualquer instrumento com maestria.'
          },
          14 => {
            'Concerto Perfeito' => 'Você pode realizar performances perfeitas que afetam todos os presentes.'
          }
        }
      }
    },
    'warlock' => {
      'a_morte' => {
        name: 'A Morte',
        description: 'Bruxos que fazem pacto com entidades da morte e do submundo.',
        features: {
          1 => {
            'Pacto da Morte' => 'Você pode canalizar poder necromântico através de seu pacto.'
          },
          6 => {
            'Toque da Morte' => 'Você pode drenar vida dos inimigos.'
          },
          10 => {
            'Comando dos Mortos' => 'Você pode controlar criaturas mortas-vivas.'
          },
          14 => {
            'Avatar da Morte' => 'Você pode se transformar em uma encarnação da morte.'
          }
        }
      },
      'arcanjo_vingador' => {
        name: 'O Arcanjo Vingador',
        description: 'Bruxos que fazem pacto com arcanjos vingadores para combater o mal.',
        features: {
          1 => {
            'Pacto da Vingança' => 'Você pode canalizar poder divino vingativo.'
          },
          6 => {
            'Lâmina Vingadora' => 'Você pode conjurar uma lâmina de luz vingativa.'
          },
          10 => {
            'Justiça Divina' => 'Você pode julgar e punir os culpados.'
          },
          14 => {
            'Forma de Arcanjo' => 'Você pode assumir a forma de um arcanjo vingador.'
          }
        }
      },
      'espirito_heroico' => {
        name: 'O Espírito Heroico',
        description: 'Bruxos que fazem pacto com espíritos de heróis lendários.',
        features: {
          1 => {
            'Pacto Heroico' => 'Você pode canalizar poder de heróis lendários.'
          },
          6 => {
            'Inspiração Heroica' => 'Você pode inspirar aliados com coragem heroica.'
          },
          10 => {
            'Legado Heroico' => 'Você pode acessar conhecimentos de heróis do passado.'
          },
          14 => {
            'Ascensão Heroica' => 'Você pode se tornar um herói lendário.'
          }
        }
      },
      'supragenio' => {
        name: 'O Supragênio',
        description: 'Bruxos que fazem pacto com entidades de inteligência sobre-humana.',
        features: {
          1 => {
            'Pacto da Inteligência' => 'Você pode canalizar poder mental sobre-humano.'
          },
          6 => {
            'Telepatia Avançada' => 'Você pode ler mentes e comunicar telepaticamente.'
          },
          10 => {
            'Precognição' => 'Você pode ver brevemente o futuro.'
          },
          14 => {
            'Mente Suprema' => 'Você pode controlar mentes em massa.'
          }
        }
      },
      'tita_caido' => {
        name: 'O Titã Caído',
        description: 'Bruxos que fazem pacto com titãs caídos e exilados.',
        features: {
          1 => {
            'Pacto Titânico' => 'Você pode canalizar poder titânico antigo.'
          },
          6 => {
            'Força Titânica' => 'Você pode aumentar sua força física drasticamente.'
          },
          10 => {
            'Resistência Titânica' => 'Você desenvolve resistência sobre-humana.'
          },
          14 => {
            'Forma Titânica' => 'Você pode assumir uma forma titânica.'
          }
        }
      },
      'vazio' => {
        name: 'O Vazio',
        description: 'Bruxos que fazem pacto com entidades do vazio e do nada.',
        features: {
          1 => {
            'Pacto do Vazio' => 'Você pode canalizar poder do vazio primordial.'
          },
          6 => {
            'Absorção do Vazio' => 'Você pode absorver energia e matéria.'
          },
          10 => {
            'Manipulação do Vazio' => 'Você pode criar e manipular vazios.'
          },
          14 => {
            'Avatar do Vazio' => 'Você pode se tornar um avatar do vazio.'
          }
        }
      }
    },
    'cleric' => {
      'agua' => {
        name: 'Domínio da Água',
        description: 'Clérigos que canalizam o poder divino através do elemento água.',
        features: {
          1 => {
            'Domínio da Água' => 'Você pode controlar e manipular água.'
          },
          2 => {
            'Canalizar Divindade: Bolha Protetora' => 'Você pode criar uma bolha protetora de água.'
          },
          6 => {
            'Resistência à Água' => 'Você desenvolve resistência a dano de água.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino através da água.'
          },
          17 => {
            'Avatar Aquático' => 'Você pode se transformar em um avatar aquático.'
          }
        }
      },
      'criacao' => {
        name: 'Domínio da Criação',
        description: 'Clérigos que canalizam o poder divino da criação e da vida.',
        features: {
          1 => {
            'Domínio da Criação' => 'Você pode criar e dar vida a objetos.'
          },
          2 => {
            'Canalizar Divindade: Desconstruir' => 'Você pode desconstruir objetos complexos.'
          },
          6 => {
            'Canalizar Divindade: Criar Constructo' => 'Você pode criar constructos animados.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino da criação.'
          },
          17 => {
            'Avatar da Criação' => 'Você pode criar vida complexa.'
          }
        }
      },
      'mente' => {
        name: 'Domínio da Mente',
        description: 'Clérigos que canalizam o poder divino através da mente e do pensamento.',
        features: {
          1 => {
            'Domínio da Mente' => 'Você pode ler e influenciar mentes.'
          },
          2 => {
            'Canalizar Divindade: Controle Mental' => 'Você pode controlar mentes de criaturas.'
          },
          6 => {
            'Resistência Mental' => 'Você desenvolve resistência a efeitos mentais.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino mental.'
          },
          17 => {
            'Avatar Mental' => 'Você pode projetar sua consciência.'
          }
        }
      },
      'terra' => {
        name: 'Domínio da Terra',
        description: 'Clérigos que canalizam o poder divino através do elemento terra.',
        features: {
          1 => {
            'Domínio da Terra' => 'Você pode controlar e manipular terra e pedra.'
          },
          2 => {
            'Canalizar Divindade: Abraço da Terra' => 'Você pode envolver inimigos com terra.'
          },
          6 => {
            'Resistência à Terra' => 'Você desenvolve resistência a dano de terra.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino através da terra.'
          },
          17 => {
            'Avatar Terrestre' => 'Você pode se transformar em um avatar terrestre.'
          }
        }
      },
      'ar' => {
        name: 'Domínio do Ar',
        description: 'Clérigos que canalizam o poder divino através do elemento ar.',
        features: {
          1 => {
            'Domínio do Ar' => 'Você pode controlar e manipular ar e vento.'
          },
          2 => {
            'Canalizar Divindade: Vento Cortante' => 'Você pode criar ventos cortantes.'
          },
          6 => {
            'Resistência ao Ar' => 'Você desenvolve resistência a dano de ar.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino através do ar.'
          },
          17 => {
            'Avatar Aéreo' => 'Você pode se transformar em um avatar aéreo.'
          }
        }
      },
      'tempo' => {
        name: 'Domínio do Tempo',
        description: 'Clérigos que canalizam o poder divino através do tempo e da temporalidade.',
        features: {
          1 => {
            'Domínio do Tempo' => 'Você pode manipular o fluxo do tempo.'
          },
          2 => {
            'Canalizar Divindade: Aceleração Súbita' => 'Você pode acelerar o tempo para aliados.'
          },
          6 => {
            'Canalizar Divindade: Vórtice Temporal' => 'Você pode criar vórtices temporais.'
          },
          8 => {
            'Destruidor Divino' => 'Você pode canalizar poder divino temporal.'
          },
          17 => {
            'Avatar Temporal' => 'Você pode viajar no tempo.'
          }
        }
      }
    },
    'druid' => {
      'infestacao' => {
        name: 'Círculo da Infestação',
        description: 'Druidas que canalizam poder através de pragas e infestações.',
        features: {
          2 => {
            'Forma Selvagem: Infestação' => 'Você pode se transformar em criaturas infestadas.'
          },
          4 => {
            'Resistência à Infestação' => 'Você desenvolve resistência a doenças e pragas.'
          },
          6 => {
            'Círculo das Formas: Infestação' => 'Você pode criar infestações em áreas.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Infestação Maior' => 'Você pode criar infestações devastadoras.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Infestação Suprema' => 'Você pode criar infestações continentais.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer criatura infestada.'
          },
          20 => {
            'Avatar da Infestação' => 'Você se torna um avatar da infestação.'
          }
        }
      },
      'vida' => {
        name: 'Círculo da Vida',
        description: 'Druidas que canalizam poder através da vida e da natureza.',
        features: {
          2 => {
            'Forma Selvagem: Vida' => 'Você pode se transformar em criaturas da vida.'
          },
          4 => {
            'Resistência à Vida' => 'Você desenvolve resistência a efeitos de vida.'
          },
          6 => {
            'Círculo das Formas: Vida' => 'Você pode criar zonas de vida abundante.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Vida Maior' => 'Você pode criar florestas instantâneas.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Vida Suprema' => 'Você pode criar ecossistemas completos.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer criatura viva.'
          },
          20 => {
            'Avatar da Vida' => 'Você se torna um avatar da vida.'
          }
        }
      },
      'fadas' => {
        name: 'Círculo das Fadas',
        description: 'Druidas que canalizam poder através do reino das fadas.',
        features: {
          2 => {
            'Forma Selvagem: Fada' => 'Você pode se transformar em criaturas fadas.'
          },
          4 => {
            'Resistência à Fada' => 'Você desenvolve resistência a magia fada.'
          },
          6 => {
            'Círculo das Formas: Fada' => 'Você pode criar portais para o reino das fadas.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Fada Maior' => 'Você pode convocar fadas poderosas.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Fada Suprema' => 'Você pode criar reinos fadas.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer criatura fada.'
          },
          20 => {
            'Avatar das Fadas' => 'Você se torna um avatar das fadas.'
          }
        }
      },
      'feras' => {
        name: 'Círculo das Feras',
        description: 'Druidas que canalizam poder através de feras e predadores.',
        features: {
          2 => {
            'Forma Selvagem: Fera' => 'Você pode se transformar em feras poderosas.'
          },
          4 => {
            'Resistência à Fera' => 'Você desenvolve resistência a ataques de feras.'
          },
          6 => {
            'Círculo das Formas: Fera' => 'Você pode convocar feras para lutar.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Fera Maior' => 'Você pode convocar feras lendárias.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Fera Suprema' => 'Você pode convocar feras míticas.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer fera.'
          },
          20 => {
            'Avatar das Feras' => 'Você se torna um avatar das feras.'
          }
        }
      },
      'mundos' => {
        name: 'Círculo dos Mundos',
        description: 'Druidas que canalizam poder através de múltiplos mundos e planos.',
        features: {
          2 => {
            'Forma Selvagem: Mundo' => 'Você pode se transformar em criaturas de outros mundos.'
          },
          4 => {
            'Resistência ao Mundo' => 'Você desenvolve resistência a efeitos de outros mundos.'
          },
          6 => {
            'Círculo das Formas: Mundo' => 'Você pode criar portais para outros mundos.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Mundo Maior' => 'Você pode viajar entre mundos.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Mundo Supremo' => 'Você pode criar novos mundos.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer criatura de qualquer mundo.'
          },
          20 => {
            'Avatar dos Mundos' => 'Você se torna um avatar dos mundos.'
          }
        }
      },
      'verdejante' => {
        name: 'Círculo Verdejante',
        description: 'Druidas que canalizam poder através de plantas e vegetação.',
        features: {
          2 => {
            'Forma Selvagem: Verdejante' => 'Você pode se transformar em criaturas vegetais.'
          },
          4 => {
            'Resistência ao Verdejante' => 'Você desenvolve resistência a efeitos vegetais.'
          },
          6 => {
            'Círculo das Formas: Verdejante' => 'Você pode criar florestas instantâneas.'
          },
          8 => {
            'Resistência Elemental' => 'Você desenvolve resistência a dano elemental.'
          },
          10 => {
            'Círculo das Formas: Verdejante Maior' => 'Você pode criar jardins mágicos.'
          },
          12 => {
            'Resistência Elemental Maior' => 'Você desenvolve maior resistência elemental.'
          },
          14 => {
            'Círculo das Formas: Verdejante Supremo' => 'Você pode criar ecossistemas completos.'
          },
          16 => {
            'Resistência Elemental Suprema' => 'Você desenvolve resistência elemental suprema.'
          },
          18 => {
            'Forma Selvagem Ilimitada' => 'Você pode se transformar em qualquer criatura vegetal.'
          },
          20 => {
            'Avatar Verdejante' => 'Você se torna um avatar da vegetação.'
          }
        }
      }
    },
    'sorcerer' => {
      'feiticaria_espada' => {
        name: 'Feitiçaria da Espada',
        description: 'Feiticeiros que canalizam magia através de armas e combate.',
        features: {
          1 => { 'Magia da Espada' => 'Você pode canalizar magia através de armas corpo-a-corpo.' },
          6 => { 'Lâmina Mágica' => 'Você pode conjurar lâminas mágicas.' },
          14 => { 'Mestre da Espada Mágica' => 'Você domina completamente a magia da espada.' },
          18 => { 'Avatar da Espada' => 'Você pode se transformar em uma encarnação da espada mágica.' }
        }
      },
      'feiticaria_sangue' => {
        name: 'Feitiçaria do Sangue',
        description: 'Feiticeiros que canalizam magia através de seu próprio sangue.',
        features: {
          1 => { 'Magia do Sangue' => 'Você pode usar seu sangue como componente material para magias.' },
          6 => { 'Ritual de Sangue' => 'Você pode realizar rituais usando seu sangue.' },
          14 => { 'Mestre do Sangue' => 'Você domina completamente a magia do sangue.' },
          18 => { 'Avatar do Sangue' => 'Você pode se transformar em uma encarnação do sangue mágico.' }
        }
      },
      'linhagem_elemental' => {
        name: 'Linhagem Elemental',
        description: 'Feiticeiros com linhagem de elementos primordiais.',
        features: {
          1 => { 'Linhagem Elemental' => 'Você tem afinidade natural com um elemento específico.' },
          6 => { 'Resistência Elemental' => 'Você desenvolve resistência ao seu elemento.' },
          14 => { 'Mestre Elemental' => 'Você domina completamente seu elemento.' },
          18 => { 'Avatar Elemental' => 'Você pode se transformar em um avatar do seu elemento.' }
        }
      },
      'origem_aberrante' => {
        name: 'Origem Aberrante',
        description: 'Feiticeiros com origem em criaturas aberrantes e alienígenas.',
        features: {
          1 => { 'Origem Aberrante' => 'Você tem poderes alienígenas e aberrantes.' },
          6 => { 'Poderes Aberrantes' => 'Você desenvolve poderes mentais aberrantes.' },
          14 => { 'Mestre Aberrante' => 'Você domina completamente poderes aberrantes.' },
          18 => { 'Avatar Aberrante' => 'Você pode se transformar em uma criatura aberrante.' }
        }
      },
      'origem_abissal' => {
        name: 'Origem Abissal',
        description: 'Feiticeiros com origem no Abismo e em demônios.',
        features: {
          1 => { 'Origem Abissal' => 'Você tem poderes demoníacos e abissais.' },
          6 => { 'Poderes Abissais' => 'Você desenvolve poderes demoníacos.' },
          14 => { 'Mestre Abissal' => 'Você domina completamente poderes abissais.' },
          18 => { 'Avatar Abissal' => 'Você pode se transformar em um demônio poderoso.' }
        }
      },
      'origem_mutavel' => {
        name: 'Origem Mutável',
        description: 'Feiticeiros com origem em mutação e transformação.',
        features: {
          1 => { 'Origem Mutável' => 'Você pode se transformar e mutar constantemente.' },
          6 => { 'Poderes Mutáveis' => 'Você desenvolve poderes de transformação.' },
          14 => { 'Mestre Mutável' => 'Você domina completamente a mutação.' },
          18 => { 'Avatar Mutável' => 'Você pode se transformar em qualquer forma.' }
        }
      }
    }
    # Adicionar outras classes conforme necessário...
  }.freeze
end
