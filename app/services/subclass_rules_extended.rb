# frozen_string_literal: true

# Extensão do SubclassRules com as subclasses restantes
# Este arquivo contém as subclasses das classes: Guerreiro, Ladino, Mago, Monge, Paladino, Patrulheiro

module SubclassRulesExtended
  EXTENDED_SUBCLASSES = {
    'fighter' => {
      'atirador_inigualavel' => {
        name: 'Atirador Inigualável',
        description: 'Guerreiros especializados em combate à distância com armas de fogo e arco.',
        features: {
          3 => { 'Especialização em Tiro' => 'Você se torna um especialista em combate à distância.' },
          7 => { 'Tiro Preciso' => 'Você pode fazer tiros extremamente precisos.' },
          10 => { 'Tiro Múltiplo' => 'Você pode atirar múltiplos projéteis simultaneamente.' },
          15 => { 'Tiro Supremo' => 'Você pode fazer tiros impossíveis.' },
          18 => { 'Mestre do Tiro' => 'Você domina completamente o combate à distância.' }
        }
      },
      'cavaleiro_implacavel' => {
        name: 'Cavaleiro Implacável',
        description: 'Guerreiros montados que dominam o combate equestre.',
        features: {
          3 => { 'Especialização Montada' => 'Você se torna um especialista em combate montado.' },
          7 => { 'Carga Devastadora' => 'Você pode realizar cargas devastadoras montado.' },
          10 => { 'Domínio do Campo' => 'Você domina o campo de batalha montado.' },
          15 => { 'Cavaleiro Supremo' => 'Você se torna um cavaleiro supremo.' },
          18 => { 'Mestre Montado' => 'Você domina completamente o combate montado.' }
        }
      },
      'defensor_dedicado' => {
        name: 'Defensor Dedicado',
        description: 'Guerreiros especializados em proteção e defesa de aliados.',
        features: {
          3 => { 'Especialização Defensiva' => 'Você se torna um especialista em defesa.' },
          7 => { 'Proteção Ativa' => 'Você pode proteger ativamente seus aliados.' },
          10 => { 'Bastião' => 'Você se torna um bastião de proteção.' },
          15 => { 'Defensor Supremo' => 'Você se torna um defensor supremo.' },
          18 => { 'Mestre Defensivo' => 'Você domina completamente a defesa.' }
        }
      },
      'kensai' => {
        name: 'Kensai',
        description: 'Guerreiros que dominam uma única arma com perfeição absoluta.',
        features: {
          3 => { 'Arma Escolhida' => 'Você escolhe uma arma e a domina completamente.' },
          7 => { 'Perfeição da Arma' => 'Você alcança perfeição com sua arma escolhida.' },
          10 => { 'Mestre da Arma' => 'Você se torna um mestre absoluto de sua arma.' },
          15 => { 'Kensai Supremo' => 'Você se torna um kensai supremo.' },
          18 => { 'Mestre da Perfeição' => 'Você domina completamente a perfeição marcial.' }
        }
      },
      'mestre_correntes' => {
        name: 'Mestre das Correntes',
        description: 'Guerreiros que dominam armas de corrente e fléchete.',
        features: {
          3 => { 'Especialização em Correntes' => 'Você se torna um especialista em armas de corrente.' },
          7 => { 'Controle de Correntes' => 'Você pode controlar correntes mágicamente.' },
          10 => { 'Rede de Correntes' => 'Você pode criar redes de correntes.' },
          15 => { 'Mestre Supremo das Correntes' => 'Você se torna um mestre supremo das correntes.' },
          18 => { 'Mestre das Correntes' => 'Você domina completamente as correntes.' }
        }
      },
      'mestre_arremesso' => {
        name: 'Mestre do Arremesso',
        description: 'Guerreiros especializados em arremesso de armas e objetos.',
        features: {
          3 => { 'Especialização em Arremesso' => 'Você se torna um especialista em arremesso.' },
          7 => { 'Arremesso Preciso' => 'Você pode arremessar com extrema precisão.' },
          10 => { 'Arremesso Múltiplo' => 'Você pode arremessar múltiplos objetos simultaneamente.' },
          15 => { 'Mestre Supremo do Arremesso' => 'Você se torna um mestre supremo do arremesso.' },
          18 => { 'Mestre do Arremesso' => 'Você domina completamente o arremesso.' }
        }
      }
    },
    'rogue' => {
      'cacador_tesouros' => {
        name: 'Caçador de Tesouros',
        description: 'Ladinos especializados em encontrar e recuperar tesouros.',
        features: {
          3 => { 'Especialização em Tesouros' => 'Você se torna um especialista em encontrar tesouros.' },
          9 => { 'Detecção de Tesouros' => 'Você pode detectar tesouros mágicos.' },
          13 => { 'Recuperação de Tesouros' => 'Você pode recuperar tesouros de locais perigosos.' },
          17 => { 'Mestre dos Tesouros' => 'Você se torna um mestre dos tesouros.' }
        }
      },
      'dancarino_sombras' => {
        name: 'Dançarino das Sombras',
        description: 'Ladinos que usam dança e movimento para combater nas sombras.',
        features: {
          3 => { 'Dança das Sombras' => 'Você pode usar dança para se mover nas sombras.' },
          9 => { 'Movimento das Sombras' => 'Você pode se teletransportar através das sombras.' },
          13 => { 'Performance das Sombras' => 'Você pode usar dança para confundir inimigos.' },
          17 => { 'Mestre das Sombras' => 'Você se torna um mestre das sombras.' }
        }
      },
      'face_fantasmagorica' => {
        name: 'Face Fantasmagórica',
        description: 'Ladinos especializados em disfarce e ilusão.',
        features: {
          3 => { 'Disfarce Fantasmagórico' => 'Você pode criar disfarces ilusórios perfeitos.' },
          9 => { 'Ilusão Avançada' => 'Você pode criar ilusões complexas.' },
          13 => { 'Transformação Fantasmagórica' => 'Você pode se transformar em outras criaturas.' },
          17 => { 'Mestre Fantasmagórico' => 'Você se torna um mestre das ilusões.' }
        }
      },
      'lamina_invisivel' => {
        name: 'Lâmina Invisível',
        description: 'Ladinos que dominam a invisibilidade e ataques furtivos.',
        features: {
          3 => { 'Invisibilidade' => 'Você pode se tornar invisível por curtos períodos.' },
          9 => { 'Invisibilidade Avançada' => 'Você pode se tornar invisível por períodos mais longos.' },
          13 => { 'Ataque Invisível' => 'Você pode atacar enquanto invisível sem revelar sua posição.' },
          17 => { 'Mestre da Invisibilidade' => 'Você se torna um mestre da invisibilidade.' }
        }
      },
      'larapio_almas' => {
        name: 'Larápio de Almas',
        description: 'Ladinos que podem roubar almas e poderes de outras criaturas.',
        features: {
          3 => { 'Roubo de Alma' => 'Você pode roubar fragmentos de alma de criaturas.' },
          9 => { 'Absorção de Poder' => 'Você pode absorver poderes de criaturas derrotadas.' },
          13 => { 'Domínio de Almas' => 'Você pode controlar almas roubadas.' },
          17 => { 'Mestre das Almas' => 'Você se torna um mestre das almas.' }
        }
      },
      'mimetizador' => {
        name: 'Mimetizador',
        description: 'Ladinos que podem imitar perfeitamente outras criaturas.',
        features: {
          3 => { 'Mimetismo' => 'Você pode imitar perfeitamente outras criaturas.' },
          9 => { 'Mimetismo Avançado' => 'Você pode imitar habilidades de outras criaturas.' },
          13 => { 'Mimetismo Perfeito' => 'Você pode imitar qualquer criatura perfeitamente.' },
          17 => { 'Mestre Mimetizador' => 'Você se torna um mestre da imitação.' }
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
        description: 'Monges que dominam armas de aço e combate armado.',
        features: {
          3 => { 'Caminho do Aço' => 'Você pode usar armas de aço como extensões de seu corpo.' },
          6 => { 'Mestre do Aço' => 'Você domina completamente armas de aço.' },
          11 => { 'Aço Perfeito' => 'Você alcança perfeição com armas de aço.' },
          17 => { 'Avatar do Aço' => 'Você se torna um avatar do aço.' }
        }
      },
      'caminho_mestre_bebado' => {
        name: 'Caminho do Mestre Bêbado',
        description: 'Monges que usam embriaguez e movimento errático como técnica de combate.',
        features: {
          3 => { 'Caminho do Mestre Bêbado' => 'Você usa embriaguez para combater de forma imprevisível.' },
          6 => { 'Movimento Bêbado' => 'Você pode se mover de forma errática e imprevisível.' },
          11 => { 'Mestre Bêbado' => 'Você domina completamente o estilo bêbado.' },
          17 => { 'Avatar Bêbado' => 'Você se torna um avatar do mestre bêbado.' }
        }
      },
      'caminho_monge_tatuado' => {
        name: 'Caminho do Monge Tatuado',
        description: 'Monges que canalizam poder através de tatuagens mágicas.',
        features: {
          3 => { 'Caminho do Monge Tatuado' => 'Você pode canalizar poder através de tatuagens.' },
          6 => { 'Tatuagens Mágicas' => 'Você pode criar tatuagens mágicas.' },
          11 => { 'Monge Tatuado' => 'Você domina completamente tatuagens mágicas.' },
          17 => { 'Avatar Tatuado' => 'Você se torna um avatar do monge tatuado.' }
        }
      },
      'caminho_ninjuts' => {
        name: 'Caminho do Ninjútsu',
        description: 'Monges que dominam técnicas ninja e furtividade.',
        features: {
          3 => { 'Caminho do Ninjútsu' => 'Você domina técnicas ninja básicas.' },
          6 => { 'Ninjútsu Avançado' => 'Você domina técnicas ninja avançadas.' },
          11 => { 'Mestre Ninja' => 'Você se torna um mestre ninja.' },
          17 => { 'Avatar Ninja' => 'Você se torna um avatar ninja.' }
        }
      },
      'caminho_punho_sagrado' => {
        name: 'Caminho do Punho Sagrado',
        description: 'Monges que canalizam poder divino através de seus punhos.',
        features: {
          3 => { 'Caminho do Punho Sagrado' => 'Você pode canalizar poder divino através de seus punhos.' },
          6 => { 'Punho Sagrado' => 'Você pode abençoar seus punhos com poder divino.' },
          11 => { 'Mestre do Punho Sagrado' => 'Você domina completamente o punho sagrado.' },
          17 => { 'Avatar do Punho Sagrado' => 'Você se torna um avatar do punho sagrado.' }
        }
      },
      'caminho_sadhaka' => {
        name: 'Caminho do Sadhaka',
        description: 'Monges que seguem o caminho da meditação e iluminação espiritual.',
        features: {
          3 => { 'Caminho do Sadhaka' => 'Você segue o caminho da meditação e iluminação.' },
          6 => { 'Meditação Profunda' => 'Você pode entrar em meditação profunda.' },
          11 => { 'Iluminação' => 'Você alcança um estado de iluminação.' },
          17 => { 'Avatar Iluminado' => 'Você se torna um avatar iluminado.' }
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
        description: 'Patrulheiros especializados em combate à distância em florestas altas.',
        features: {
          3 => { 'Especialização Florestal' => 'Você se torna um especialista em florestas altas.' },
          7 => { 'Tiro Florestal' => 'Você pode atirar através de vegetação densa.' },
          11 => { 'Mestre Florestal' => 'Você domina completamente florestas altas.' },
          15 => { 'Avatar Florestal' => 'Você se torna um avatar da floresta alta.' }
        }
      },
      'batedor' => {
        name: 'Batedor',
        description: 'Patrulheiros especializados em reconhecimento e exploração.',
        features: {
          3 => { 'Especialização em Batedor' => 'Você se torna um especialista em reconhecimento.' },
          7 => { 'Reconhecimento Avançado' => 'Você pode obter informações detalhadas sobre áreas.' },
          11 => { 'Mestre Batedor' => 'Você domina completamente o reconhecimento.' },
          15 => { 'Avatar Batedor' => 'Você se torna um avatar do batedor.' }
        }
      },
      'flagelo_inimigos' => {
        name: 'Flagelo dos Inimigos',
        description: 'Patrulheiros especializados em caçar e eliminar inimigos específicos.',
        features: {
          3 => { 'Especialização em Flagelo' => 'Você se torna um especialista em caçar inimigos.' },
          7 => { 'Caça de Inimigos' => 'Você pode rastrear e caçar inimigos específicos.' },
          11 => { 'Mestre Flagelo' => 'Você domina completamente a caça de inimigos.' },
          15 => { 'Avatar Flagelo' => 'Você se torna um avatar do flagelo.' }
        }
      },
      'guardiao_selvagem' => {
        name: 'Guardião Selvagem',
        description: 'Patrulheiros que protegem áreas selvagens e criaturas da natureza.',
        features: {
          3 => { 'Especialização em Guardião' => 'Você se torna um especialista em proteger áreas selvagens.' },
          7 => { 'Proteção Selvagem' => 'Você pode proteger áreas selvagens de intrusos.' },
          11 => { 'Mestre Guardião' => 'Você domina completamente a proteção selvagem.' },
          15 => { 'Avatar Guardião' => 'Você se torna um avatar do guardião selvagem.' }
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
        description: 'Patrulheiros especializados em operações urbanas e rastreamento em cidades.',
        features: {
          3 => { 'Especialização Urbana' => 'Você se torna um especialista em operações urbanas.' },
          7 => { 'Rastreamento Urbano' => 'Você pode rastrear criaturas em ambientes urbanos.' },
          11 => { 'Mestre Urbano' => 'Você domina completamente operações urbanas.' },
          15 => { 'Avatar Urbano' => 'Você se torna um avatar do rastreador urbano.' }
        }
      }
    }
  }.freeze
end
