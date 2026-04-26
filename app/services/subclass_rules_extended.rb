# frozen_string_literal: true

# Extensão do SubclassRules com as subclasses restantes
# Este arquivo contém as subclasses das classes: Guerreiro, Ladino, Mago, Monge, Paladino, Patrulheiro

module SubclassRulesExtended
  EXTENDED_SUBCLASSES = {
    'fighter' => {
      'atirador_inigualavel' => {
        name: 'Atirador Inigualável',
        description: 'Maestria com bestas, arcos e armas de munição (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Tiro Rápido' => 'Ação bônus: ataque à distância com arma de munição com desvantagem.' },
          7 => { 'Melhor Posição de Tiro' => 'Acrobacia; vantagem em escalar; +2 dano tiro de cima de alvo abaixo.' },
          10 => { 'Tiro Certeiro' => 'Ação, vantagem, +5d10 e efeito debilitante; recarga em descanso.' },
          15 => { 'Pontaria Aguçada' => 'Remove desvantagem do Tiro Rápido; vantagem no primeiro tiro de arco por turno.' },
          18 => { 'Um Tiro, Uma Morte' => 'Contra alvos de PV baixos, TS Con ou 0 PV; crítico amplia o limiar.' }
        }
      },
      'cavaleiro_implacavel' => {
        name: 'Cavaleiro Implacável',
        description: 'Combate montado, montaria fiel, investida e atropelamento (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Montaria Fiel' => 'Obtém e comanda uma montaria com PV reforçados; ação bônus para ordens de combate.' },
          7 => { 'Montaria Incansável' => 'Jornadas longas sem exaustão pelo ritmo descrito no livro.' },
          10 => { 'Investida Implacável' => 'Carga com vantagem e dano extra montado; escala com arma de haste e nível 20.' },
          12 => { 'Montaria dos Céus' => 'Pode adotar besta voadora (ND 1) como montaria a partir do 12º.' },
          15 => { 'Cavaleiro Protetor' => 'Bônus de proficiência em CA e TRs da montaria; reação para reduzir dano a ela.' },
          18 => { 'Atropelar' => 'Movimento em linha; TS Des em criaturas no caminho; usos limitados.' },
          20 => { 'Investida Suprema' => 'Ajuste de dado extra no ápice da investida, conforme o texto.' }
        }
      },
      'defensor_dedicado' => {
        name: 'Defensor Dedicado',
        description: 'Foco defensivo com escudo, proteção a aliados e controle de ameaças (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Postura Defensiva' => 'Resistência B/P/S, reação +3 CA, vantagem em TRs, deslocamento reduzido; recarga em descanso.' },
          7 => { 'Proteger Aliado' => 'Ação bônus: empresta bônus de escudo à CA de aliado adjacente.' },
          10 => { 'Provocar' => 'TS Sab ou inimigo deve priorizar aproximação a você; extensão com ação.' },
          15 => { 'Surto Defensivo' => 'Reação com vantagem em TR contra efeito nocivo (cargas limitadas).' },
          18 => { 'Baluarte Protetor' => 'Ignora ou força sucesso em efeitos persistentes de TR conforme o texto.' }
        }
      },
      'kensai' => {
        name: 'Kensai',
        description: 'Iaijutsu, perícias e meditação da lâmina (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Mestre do Iaijutsu' => 'Primeiro ataque de embainhado na 1ª rodada com vantagem e dano extra ligado à iniciativa.' },
          7 => { 'Busca da Autoperfeição' => 'Duas ferramentas de artesão; meia prof em ferramenta não proficiente.' },
          10 => { 'Meditação da Lâmina' => 'Após descanso curto, benefício temático (vantagens, reações, dano) até nova meditação.' },
          15 => { 'Movimento Antes do Pensamento' => 'Iniciativa, surpresa parcial, reação de iaijutsu em aproximação.' },
          18 => { 'Meditação Perfeita' => 'Dois efeitos de meditação ativos; dois benefícios após descanso curto.' }
        }
      },
      'mestre_correntes' => {
        name: 'Mestre das Correntes',
        description: 'Armas de corrente e corda; agarrar e manobras especiais (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Estilo de Combate Exótico' => 'Troca dano por agarrar; manobras Enrolar, Puxão, Rasteira, Desarme com ação bônus.' },
          7 => { 'Movimento da Corrente' => 'Bônus a movimentação com a arma; escalar corda/corrente sem custo extra.' },
          10 => { 'Maestria da Corrente' => 'Ferreiro, corrente forjada, vantagem e dano em agarras com corrente farpada.' },
          15 => { 'Alcance Estendido' => 'Ataque a distância estendida com armas de corrente indicadas.' },
          18 => { 'Ataque Giratório' => 'Ação: um ataque por inimigo no alcance; usos limitados.' }
        }
      },
      'mestre_arremesso' => {
        name: 'Mestre do Arremesso',
        description: 'Toda arma corpo a corpo vira arremesso; retorno, tensão e ricochete (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Arremesso Versátil' => 'Propriedade arremesso 6/18 em armas corpo a corpo proficientes.' },
          7 => { 'Ataque de Retorno' => 'Ação bônus para recuperar arma; a partir do 11º, sem ação bônus.' },
          10 => { 'Arremesso Estremecedor' => 'Trata arremessos como corpo a corpo (oportunidade, sem desvantagem em corpo a corpo); recarga em descanso.' },
          11 => { 'Retorno Instintivo' => 'Arma retorna após o ataque sem ação bônus.' },
          15 => { 'Ricochete Relâmpago' => 'Reação para segundo alvo após acerto a curta distância.' },
          18 => { 'Lâmina Giratória' => 'Ação: um tiro de cortante de arremesso em cada inimigo próximo; usos limitados.' }
        }
      }
    },
    'rogue' => {
      'cacador_tesouros' => {
        name: 'Caçador de Tesouros',
        description: 'Especialista em invadir e saquear locais perigosos; rastreia armadilhas, tesouros e rotas de fuga (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Invasor Profissional' => 'Vantagem para achar e desarmar fechaduras e armadilhas.',
            'Sentir Armadilha' => 'Resistência a dano de armadilha e vantagem em testes de resistência contra armadilhas.'
          },
          9 => { 'Evitar o Perigo' => 'Escalada ampliada, furtividade com cobertura, não rastreável sem magia.' },
          13 => { 'Encontrar Tesouro' => 'Percepção/Investigação passivas para tesouros; percebe magicidade ao tocar; pressente tesouro escondido a 6 m.' },
          17 => { 'Fuga Sobrenatural' => 'Atravessa barreira fina; vantagem vs agarrado, impedido, paralisado.' }
        }
      },
      'dancarino_sombras' => {
        name: 'Dançarino das Sombras',
        description: 'Poderes da Umbra: camuflagem, visão no escuro, projeção, viagem e forma sombria (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Camuflagem Sombria' => 'Vantagem em Furtividade em trevas/penumbra; inimigos têm desvantagem para acertar você.',
            'Ver nas Trevas' => 'Enxerga na penumbra a 18 m como luz plena; no escuro como penumbra.'
          },
          9 => { 'Projeção Sombria' => 'Ação: ataque a até 15 m a partir de sombra sem revelar posição.' },
          13 => { 'Viagem Umbral' => 'Ação: curto viagem pelo Plano das Sombras; 2 usos por descanso.' },
          17 => { 'Forma de Sombra' => '1 minuto: resistência a armas não mágicas; Viagem Umbral 1× por rodada.' }
        }
      },
      'face_fantasmagorica' => {
        name: 'Face Fantasmagórica',
        description: 'Clã de máscara apavorante: medo, ataque em surpresa, pesadelo e pavor (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Presença Intimidante' => 'Proficiência e vantagem em Intimidação; desvantagem em Persuasão; intimidar amedronta brevemente.',
            'Ataque Apavorante' => 'Contra surpresa, com máscara, ataque corpo a corpo e amedronta (TS Sab).'
          },
          9 => { 'Pesadelo Furtivo' => 'Ação bônus: quase invisível para o amedrontado (Furtividade CD 15).' },
          13 => { 'Inversão do Medo' => 'Vantagem em TR contra medo; reação para devolver medo a quem falhou em te amedrontar.' },
          17 => { 'Pavor Atormentador' => '4d10 psíquico a amedrontados; pode afetar imunes a medo (com vantagem no teste).' }
        }
      },
      'lamina_invisivel' => {
        name: 'Lâmina Invisível',
        description: 'Adagas: ataque tão rápido que o alvo demora a sentir, lâmina veloz e multidão (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Mão Invisível' => 'Ataque surpresa atrasado; vantagem em Prestidigitação com lâminas leves.',
            'Lâmina Veloz' => 'Ação bônus: saca arma leve e ataca com vantagem (Ataque Furtivo extra); recarga em descanso.'
          },
          9 => { 'Ataque Extra' => 'Dois ataques com a ação Ataque no turno.' },
          13 => { 'Desaparecer na Multidão' => 'Ação bônus, após passar atrás de aliado ou barreira: invisibilidade seletiva a inimigos.' },
          17 => { 'Técnica da Lâmina Furtiva' => '1 min: CA por Prestidigitação; riposta com furtivo se errarem; recarga em descanso longo.' }
        }
      },
      'larapio_almas' => {
        name: 'Larápio de Almas',
        description: 'Drena vitalidade, sente vida, rouba magia e pode arrancar almas (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Furto de Vida' => 'Troca furtivo por necrótico (TS Con), cura e reduz PV máx.; precisa drenar humanoide inconsciente 1/dia.',
            'Dependência de Vida' => 'Não come nem dorme; exige drenar ou sofre desvantagem.'
          },
          9 => { 'Sentir Vida' => 'Ação: detecta vidas a 18 m e depois o estado aproximado de um alvo escolhido.' },
          13 => { 'Drenar Energia Mística' => 'Rouba carga de magia (TS Car); arma fica mágica e bônus = nível do espaço; recarga em descanso.' },
          17 => { 'Usurpar a Alma' => 'Furtivo corpo a corpo vs alvo com menos de 40 PV: TS Con ou morte; vantagem após abate qualificado.' }
        }
      },
      'mimetizador' => {
        name: 'Mimetizador',
        description: 'Copia traços, habilidades e até magias que observa; pode usurpar do alvo (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Proficiência Adicional' => 'Enganação e Intuição.',
            'Copiar Habilidade' => 'Intuição CD 10: copia ação/traço ativo 1 h (passivos a partir do 11°).'
          },
          9 => { 'Simulação Avançada' => 'Intuição CD 15: copia 1× um traço de uso limitado; não Conjuração.' },
          13 => { 'Simular Conjuração' => 'Compreende magia (CD 15 + nível) e a conjura 1× em 1 h.' },
          17 => { 'Usurpar Característica' => 'Toca alvo: nega a habilidade copiada nele 1 h (TS Car); 2 usos, recarga longa.' }
        }
      }
    },
    'wizard' => {
      'arquearia_arcana' => {
        name: 'Arquearia Arcana',
        description: 'Magos que canalizam magia através de arcos e flechas.',
        features: {
          2 => { 'Arquearia Arcana' => 'Você pode canalizar magia através de arcos.' },
          6 => { 'Flechas Mágicas' => 'Você pode conjurar flechas mágicas.' },
          10 => { 'Arco Mágico' => 'Você pode conjurar arcos mágicos poderosos.' },
          14 => { 'Mestre da Arquearia Arcana' => 'Você domina completamente a arquearia arcana.' }
        }
      },
      'iniciacao_demonologia' => {
        name: 'Iniciação em Demonologia',
        description: 'Magos que estudam e controlam demônios.',
        features: {
          2 => { 'Iniciação em Demonologia' => 'Você pode conjurar e controlar demônios menores.' },
          6 => { 'Controle Demoníaco' => 'Você pode controlar demônios mais poderosos.' },
          10 => { 'Sumonar Demônios' => 'Você pode sumonar demônios poderosos.' },
          14 => { 'Mestre Demonologista' => 'Você se torna um mestre demonologista.' }
        }
      },
      'maestria_alquimica' => {
        name: 'Maestria Alquímica',
        description: 'Magos que dominam a alquimia e transformação de materiais.',
        features: {
          2 => { 'Maestria Alquímica' => 'Você pode criar poções e elixires alquímicos.' },
          6 => { 'Transmutação' => 'Você pode transmutar materiais.' },
          10 => { 'Alquimia Avançada' => 'Você pode criar itens alquímicos complexos.' },
          14 => { 'Mestre Alquimista' => 'Você se torna um mestre alquimista.' }
        }
      },
      'maestria_automatos' => {
        name: 'Maestria dos Autômatos',
        description: 'Magos que criam e controlam autômatos e constructos.',
        features: {
          2 => { 'Maestria dos Autômatos' => 'Você pode criar autômatos simples.' },
          6 => { 'Autômatos Avançados' => 'Você pode criar autômatos complexos.' },
          10 => { 'Constructos Mágicos' => 'Você pode criar constructos mágicos poderosos.' },
          14 => { 'Mestre dos Autômatos' => 'Você se torna um mestre dos autômatos.' }
        }
      },
      'navegacao_planar' => {
        name: 'Navegação Planar',
        description: 'Magos que dominam viagem e navegação entre planos.',
        features: {
          2 => { 'Navegação Planar' => 'Você pode viajar entre planos menores.' },
          6 => { 'Portais Planares' => 'Você pode criar portais para outros planos.' },
          10 => { 'Viagem Planar' => 'Você pode viajar para qualquer plano.' },
          14 => { 'Mestre Planar' => 'Você se torna um mestre da navegação planar.' }
        }
      },
      'teurgia_mistica' => {
        name: 'Teurgia Mística',
        description: 'Magos que canalizam poder divino através de magia arcana.',
        features: {
          2 => { 'Teurgia Mística' => 'Você pode canalizar poder divino através de magia.' },
          6 => { 'Magia Divina' => 'Você pode usar magia divina através de magia arcana.' },
          10 => { 'Teurgia Avançada' => 'Você pode canalizar poder divino poderoso.' },
          14 => { 'Mestre Teurgo' => 'Você se torna um mestre teurgo.' }
        }
      }
    },
    'monk' => {
      'caminho_aco' => {
        name: 'Caminho do Aço',
        description: 'Monge de ferro: armadura, Punho de Ferro e técnicas de força (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Proficiência e Técnicas do Monge de Ferro' => 'Armadura leve/média; trocas de Rajada/Defesa/Passo por Punho de Ferro, Defesa Blindada, Posição da Montanha.' },
          6 => { 'Golpe de Brutalidade Absoluta' => 'Gasto extra de ki: ataque com vantagem e crítico 18–20 com Punho de Ferro.' },
          11 => { 'Desarme Feroz' => 'Ataque desarmado para arrebatar arma ou impor desvantagem.' },
          17 => { 'Contra-ataque Devastador' => 'Reação com Punho de Ferro para crítico forçado com penalidade no ataque.' }
        }
      },
      'caminho_mestre_bebado' => {
        name: 'Caminho do Mestre Bêbado',
        description: 'Improviso, bebida e estilo bêbado (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Mestre do Improviso e Estilo do Mestre Bêbado' => 'Armas improvisadas; ações exóticas enquanto bêbado.' },
          6 => { 'Recuperação Ébria' => 'Teste de Con para recuperar ki ao beber.' },
          11 => { 'Hálito Flamejante' => 'Sopro em cone, dano de fogo em área.' },
          17 => { 'Sempre Bêbado' => 'Ativa estilo com bônus; ativa duas técnicas por ação bônus com ki.' }
        }
      },
      'caminho_monge_tatuado' => {
        name: 'Caminho do Monge Tatuado',
        description: 'Tatuagens místicas com animais e efeitos de ki (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Tatuador Experiente e Tatuagem Mística' => 'Ferramentas; despertar tatuagens com efeitos animais.' },
          6 => { 'Tatuagem de Poder' => 'Benefícios passivos por tatuagem possuída.' },
          11 => { 'Despertar adicional' => 'Terceira tatuagem ativa.' },
          17 => { 'Desencarnar Tatuagem' => 'Explosão de energia gasta a tatuagem.' },
          18 => { 'Quarta tatuagem' => 'Mais um despertar, opção ainda não usada.' }
        }
      },
      'caminho_ninjuts' => {
        name: 'Caminho do Ninjútsu',
        description: 'Ninja: armas de clã, Golpe Súbito, fumaça e etéreo (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Arte do Ninjútsu e Golpe Súbito' => 'Proficiências; dano furtivo escalonado.' },
          6 => { 'Técnicas de Ninjútsu' => 'Escalada veloz, bomba de fumaça, percepção às cegas.' },
          11 => { 'Mestre do Ocultismo' => 'Furtividade e fumaça aprimorada.' },
          17 => { 'Passo Fantasma' => 'Forma etérea com ki alto.' }
        }
      },
      'caminho_punho_sagrado' => {
        name: 'Caminho do Punho Sagrado',
        description: 'Conjuração de clérigo, domínios, punhos de chamas e armadura interior (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Conjuração, Domínios Sagrados e Energia Divina Interior' => 'Magias e empoderar com ki.' },
          6 => { 'Punho de Chamas Divinas' => 'Chamas sagradas no acerto com ki.' },
          11 => { 'Rajada de Chamas Divinas' => 'Rajada com truque em ambos os golpes.' },
          17 => { 'Armadura Interior' => 'CA e resistência com ki e espaço de magia.' }
        }
      },
      'caminho_sadhaka' => {
        name: 'Caminho do Sadhaka',
        description: 'Mantras, Akasha e nirvana (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Mantra de Poder' => 'Troca teto de ki por bônus 1d4 a testes, dano, TR, etc.' },
          6 => { 'Akasha Interior' => 'Aumenta teto de ki com dado após descanso longo.' },
          11 => { 'Concentração Inabalável' => 'Cura em descanso curto; dois mantras.' },
          17 => { 'Alcançar o Nirvana' => 'Sexto sentido e limpar a mente com muito ki.' }
        }
      }
    },
    'paladin' => {
      'juramento_danacao' => {
        name: 'Juramento de Danação',
        description: 'Paladinos que fazem juramento de danação e destruição.',
        features: {
          3 => { 'Juramento de Danação' => 'Você faz um juramento de danação e destruição.' },
          7 => { 'Aura de Danação' => 'Você emana uma aura de danação.' },
          15 => { 'Avatar da Danação' => 'Você se torna um avatar da danação.' },
          20 => { 'Mestre da Danação' => 'Você se torna um mestre da danação.' }
        }
      },
      'juramento_equilibrio' => {
        name: 'Juramento de Equilíbrio',
        description: 'Paladinos que fazem juramento de manter o equilíbrio entre bem e mal.',
        features: {
          3 => { 'Juramento de Equilíbrio' => 'Você faz um juramento de manter o equilíbrio.' },
          7 => { 'Aura de Equilíbrio' => 'Você emana uma aura de equilíbrio.' },
          15 => { 'Avatar do Equilíbrio' => 'Você se torna um avatar do equilíbrio.' },
          20 => { 'Mestre do Equilíbrio' => 'Você se torna um mestre do equilíbrio.' }
        }
      },
      'juramento_liberdade' => {
        name: 'Juramento de Liberdade',
        description: 'Paladinos que fazem juramento de defender a liberdade e a justiça.',
        features: {
          3 => { 'Juramento de Liberdade' => 'Você faz um juramento de defender a liberdade.' },
          7 => { 'Aura de Liberdade' => 'Você emana uma aura de liberdade.' },
          15 => { 'Avatar da Liberdade' => 'Você se torna um avatar da liberdade.' },
          20 => { 'Mestre da Liberdade' => 'Você se torna um mestre da liberdade.' }
        }
      },
      'juramento_misericordia' => {
        name: 'Juramento de Misericórdia',
        description: 'Paladinos que fazem juramento de mostrar misericórdia e compaixão.',
        features: {
          3 => { 'Juramento de Misericórdia' => 'Você faz um juramento de mostrar misericórdia.' },
          7 => { 'Aura de Misericórdia' => 'Você emana uma aura de misericórdia.' },
          15 => { 'Avatar da Misericórdia' => 'Você se torna um avatar da misericórdia.' },
          20 => { 'Mestre da Misericórdia' => 'Você se torna um mestre da misericórdia.' }
        }
      },
      'juramento_ordenacao' => {
        name: 'Juramento de Ordenação',
        description: 'Paladinos que fazem juramento de manter ordem e disciplina.',
        features: {
          3 => { 'Juramento de Ordenação' => 'Você faz um juramento de manter ordem.' },
          7 => { 'Aura de Ordenação' => 'Você emana uma aura de ordem.' },
          15 => { 'Avatar da Ordenação' => 'Você se torna um avatar da ordenação.' },
          20 => { 'Mestre da Ordenação' => 'Você se torna um mestre da ordenação.' }
        }
      },
      'juramento_pureza' => {
        name: 'Juramento de Pureza',
        description: 'Paladinos que fazem juramento de manter pureza e inocência.',
        features: {
          3 => { 'Juramento de Pureza' => 'Você faz um juramento de manter pureza.' },
          7 => { 'Aura de Pureza' => 'Você emana uma aura de pureza.' },
          15 => { 'Avatar da Pureza' => 'Você se torna um avatar da pureza.' },
          20 => { 'Mestre da Pureza' => 'Você se torna um mestre da pureza.' }
        }
      }
    },
    'ranger' => {
      'arqueiro_floresta_alta' => {
        name: 'Arqueiro da Floresta Alta',
        description: 'Entalhador, alcance com arco e floresta; emboscada nas copas (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Arqueiro Bem-Suprido e Visão Aguçada' => 'Cria flechas; Percepção e alcance de arco dobrado.' },
          7 => { 'Atirar e Esconder' => 'Após tiro, esconder-se; escalar com facilidade no terreno favorito.' },
          15 => { 'Tiro de Misericórdia e Flechas Perfeitas' => 'Execução em alvo fraco; flechas crítico 19–20 após ofício longo.' }
        }
      },
      'batedor' => {
        name: 'Batedor',
        description: 'Reconhece trilhas, luta em movimento, acelera e antecipa perigos (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Tática de Batedor' => 'Trilha rastreável; reação: alerta sonoro para aliados a 120 m.',
            'Escaramuça' => 'Após 6 m de movimento: +2d6 no primeiro ataque; reação: desvantagem no ataque de quem o atingiu se você já se moveu 6 m.'
          },
          7 => { 'Movimento de Batedor' => '+3 m se leve ou sem armadura; ação bônus: Disparada ou Desengajar; reação: faz errar ataque de oportunidade.' },
          11 => { 'Percepção Instintiva' => 'Vantagem em Percepção, Investigação e iniciativa.' },
          15 => { 'Liberdade de Movimentos' => 'Como movimentação livre contra efeitos que impedem o movimento.' }
        }
      },
      'flagelo_inimigos' => {
        name: 'Flagelo dos Inimigos',
        description: 'Inimigos favoritos extra, esquiva predileta, estudo tático e inimizade imediata (Livro de Novos Arquétipos).',
        features: {
          3 => {
            'Inimigo Favorito Adicional' => 'Mais um tipo e idioma; outro no 10°.',
            'Esquiva Predileta' => 'Reação: desvantagem no ataque de inimigo favorito; a partir do 13°, vantagem em TR (For/Des/Sab) contra eles.'
          },
          7 => { 'Caçador de Inimigos' => 'Vantagem no primeiro ataque/turno vs favorito; +1d8 (2d8 se surpreso).' },
          11 => { 'Estudar Inimigo' => 'Ação: Percepção CD 5 + ND para dado de informação; recarga em descanso.' },
          15 => { 'Inimizade Imediata' => 'Gasta 4° ou 5° para tratar um tipo como favorito 1 h ou 8 h; recarga longa.' }
        }
      },
      'guardiao_selvagem' => {
        name: 'Guardião Selvagem',
        description: 'Linguagem bestial, grito primitivo e instinto de caçador feral (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Linguagem Bestial e Grito Primitivo' => 'Fala com bestas; forma com garras e mordida.' },
          7 => { 'Instinto Animal' => 'Rastreio, iniciativa e percepção passiva aprimorados.' },
          11 => { 'Bote Dilacerador' => 'Carga e ataques múltiplos dilacerando com força.' },
          15 => { 'Território de Caça' => 'Bônus de combate e furtividade no terreno favorito.' }
        }
      },
      'mestre_bestas' => {
        name: 'Mestre das Bestas',
        description: 'Patrulheiros que dominam e controlam criaturas selvagens.',
        features: {
          3 => { 'Especialização em Bestas' => 'Você se torna um especialista em controlar bestas.' },
          7 => { 'Controle de Bestas' => 'Você pode controlar criaturas selvagens.' },
          11 => { 'Mestre das Bestas' => 'Você domina completamente o controle de bestas.' },
          15 => { 'Avatar das Bestas' => 'Você se torna um avatar do mestre das bestas.' }
        }
      },
      'rastreador_urbano' => {
        name: 'Rastreador Urbano',
        description: 'Explorador urbano, abate com magia e percepção em masmorras (Livro de Novos Arquétipos).',
        features: {
          3 => { 'Explorador Urbano' => 'Explorador natural em cidades; Persuasão para informação.' },
          7 => { 'Buscar e Abater' => 'Dano e bônus de ataque com gasto de espaço vs surpreso.' },
          11 => { 'Percepção do Antinatural' => 'Achados, ferramentas de ladrão, opção de exaustão em ataque bônus.' },
          15 => { 'Líder de Caçada' => 'Vantagem aliada vs alvo de Buscar e Abater.' }
        }
      }
    }
  }.freeze
end
