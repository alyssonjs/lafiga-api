#!/usr/bin/env ruby
# frozen_string_literal: true

# Aplica trechos alinhados ao Livro do Jogador (PHB) em português sobre
# config/dnd_translations.features.book.yml. Fontes: api/docs/livro_do_jogador.txt
# e, quando útil, docs/novos_arquetipos.txt (conteúdo opcional / subclasses extras).
#
# Uso (a partir de api/): ruby scripts/apply_livro_book_feature_patches.rb

require 'yaml'

ROOT = File.expand_path('..', __dir__)
CONFIG = File.join(ROOT, 'config')

TODO = File.join(CONFIG, 'dnd_translations.todo.yml')
DND = File.join(CONFIG, 'dnd_translations.yml')
BOOK_OUT = File.join(CONFIG, 'dnd_translations.features.book.yml')

HEADER = <<~HDR
  # Camada editorial alinhada ao Livro do Jogador (PHB). Material extra (outros caminhos/domínios): docs/novos_arquetipos.txt.
  # Ordem rake: build_features_pt → merge_features_pt → merge_features_book (ver lib/tasks/dnd_translations_sync.rake).
  # Após alterar o livro-texo ou política de glossário, rode: ruby scripts/apply_livro_book_feature_patches.rb

HDR

ASI_LIVRO = <<~TXT.strip
  Quando você atinge o 4º nível e novamente no 8º, 12º, 16º e 19º nível, você pode aumentar um valor de habilidade, à sua escolha, em 2, ou você pode aumentar dois valores de habilidade, à sua escolha, em 1. Como padrão, você não pode elevar um valor de habilidade acima de 20 com essa característica.
TXT

DIVINE_DOMAIN_LIVRO = <<~TXT.strip
  Escolha um domínio relacionado à sua divindade: Conhecimento, Enganação, Guerra, Luz, Natureza, Tempestade ou Vida. Cada domínio é detalhado ao final da descrição da classe e, cada um, fornece exemplos dos deuses associados a eles. Essa escolha, realizada no 1º nível, concede magias de domínio e outras características. Ela também concede a você outras formas de utilizar seu Canalizar Divindade quando você ganhá-lo no 2º nível, bem como outros benefícios no 6º, 8º e 17º níveis.
TXT

DOMAIN_SPELLS_LIVRO = <<~TXT.strip
  Cada domínio tem uma lista de magias – as magias de domínio – que você adquire nos níveis especificados pelo seu domínio. Quando você ganha uma magia de domínio, você sempre a tem preparada, e essa magia não conta no número de magias que você pode preparar a cada dia.

  Se você tem uma magia de domínio que não aparece na lista de magias de clérigo, mesmo assim ela é uma magia de clérigo para você.
TXT

SPELLCASTING_CLERIC_LIVRO = <<~TXT.strip
  Como um canalizador de poder divino, você pode conjurar magias de clérigo. Veja o capítulo 10 para as regras gerais de conjuração e o capítulo 11 para a lista de magias de clérigo.

  Truques
  Você conhece três truques, à sua escolha, da lista de magias de clérigo. Você aprende truques de clérigo adicionais, à sua escolha, em níveis mais altos, como mostrado na coluna Truques Conhecidos da tabela O Clérigo.

  Preparando e conjurando magias
  A tabela O Clérigo mostra quantos espaços de magia você tem para conjurar suas magias de 1º nível e superiores. Para conjurar uma dessas magias, você precisa gastar um espaço do nível da magia ou superior. Você recupera todos os espaços gastos quando termina um descanso longo.

  Você prepara a lista de magias disponíveis selecionando-as da lista de magias de clérigo. Você seleciona um número de magias igual ao seu modificador de Sabedoria + seu nível de clérigo (mínimo de uma magia). Essas magias devem ser de níveis para os quais você possui espaços de magia.

  Você pode modificar a sua lista de magias preparadas quando termina um descanso longo. Preparar uma nova lista de magias de clérigo requer tempo gasto em preces e meditação: no mínimo 1 minuto por nível de magia para cada magia preparada.

  Habilidade de conjuração
  Sabedoria é a sua habilidade para você conjurar suas magias de clérigo. O poder de suas magias vem da devoção que você tem ao seu deus. Você usa sua Sabedoria sempre que alguma magia se referir à sua habilidade de conjurar magias. Além disso, você usa o seu modificador de Sabedoria para definir a CD dos testes de resistência para as magias de clérigo que você conjura e quando você realiza uma jogada de ataque com uma magia.

  CD para suas magias = 8 + bônus de proficiência + seu modificador de Sabedoria
  Modificador de ataque de magia = seu bônus de proficiência + seu modificador de Sabedoria

  Conjuração de ritual
  Você pode conjurar qualquer magia de clérigo que você conheça como um ritual se ela possuir o descritor ritual.

  Foco de conjuração
  Você pode usar um símbolo sagrado (encontrado no capítulo 5) como foco de conjuração das suas magias de clérigo.
TXT

CHANNEL_DIVINITY_PALADIN_LIVRO = <<~TXT.strip
  Seu juramento permite que você canalize energia divina para abastecer efeitos mágicos. Cada opção de Canalizar Divindade concedida por um juramento explica como usá-la.

  Quando você usa o seu Canalizar Divindade, você escolhe qual opção usar. Você deve terminar um descanso curto ou longo para poder usar seu Canalizar Divindade novamente.

  Alguns efeitos de Canalizar Divindade exigem testes de resistência. Quando você usar um efeito assim desta classe, a CD é igual à CD de resistência às suas magias de paladino.
TXT

CHANNEL_DIVINITY_1_REST_LIVRO = <<~TXT.strip
  No 2º nível, você se torna capaz de canalizar energia diretamente de sua divindade, utilizando-a como combustível para efeitos mágicos. Você começa com dois efeitos: Expulsar Mortos-vivos e um efeito determinado pelo seu domínio. Alguns domínios conferem efeitos adicionais conforme você avança de nível, como consta na descrição de cada domínio.

  Quando você usar seu Canalizar Divindade, você escolhe qual efeito quer criar. Você precisa terminar um descanso curto ou longo para usar a característica de novo.

  Alguns efeitos requerem teste de resistência. Quando você usar um desses efeitos, a CD é igual a das suas magias de clérigo.

  A partir do 6º nível, você pode Canalizar Divindade duas vezes entre descansos e a partir do 18º nível, três vezes entre descansos. Você recupera os usos dessa característica quando termina um descanso curto ou longo.
TXT

CHANNEL_DIVINITY_REST_ONLY_LIVRO = <<~TXT.strip
  A partir do 6º nível, você pode Canalizar Divindade duas vezes entre descansos e a partir do 18º nível, três vezes entre descansos. Você recupera os usos dessa característica quando termina um descanso curto ou longo.
TXT

CHANNEL_TURN_UNDEAD_LIVRO = <<~TXT.strip
  Usando uma ação, você levanta seu símbolo sagrado e murmura uma prece repreendendo os mortos-vivos. Cada morto-vivo que puder ver ou ouvir você em um raio de 9 metros a partir de você deve fazer um teste de resistência de Sabedoria. Se falhar, a criatura está expulsa por 1 minuto ou até sofrer algum dano.

  Uma criatura expulsa deve usar seu turno para fugir da melhor forma possível e de forma alguma pode aproximar-se a mais de 9 metros de você por vontade própria. Ela também não pode usar reações. Como uma ação, a criatura pode apenas realizar uma Disparada ou tentar escapar de um efeito que a impeça de se mover. Se não há lugar para ir, a criatura pode usar a ação Esquivar.
TXT

DESTROY_UNDEAD_LIVRO = <<~TXT.strip
  A partir do 5º nível, quando um morto-vivo falhar no teste de resistência contra a sua característica Expulsar Mortos-vivos, ele é instantaneamente destruído se o Nível de Desafio dele for menor ou igual ao valor da tabela Destruir Mortos-vivos, de acordo com seu nível de clérigo.

  Nível de clérigo | Destrói mortos-vivos de ND
  5º | 1/2 ou menor
  8º | 1 ou menor
  11º | 2 ou menor
  14º | 3 ou menor
  17º | 4 ou menor
TXT

RAGE_LIVRO = <<~TXT.strip
  Em batalha, você luta com uma ferocidade primitiva. No seu turno, você pode entrar em fúria com uma ação bônus.

  Enquanto estiver em fúria, você recebe os seguintes benefícios se você não estiver vestindo uma armadura pesada:
  • Você tem vantagem em testes de Força e testes de resistência de Força.
  • Quando você desferir um ataque com arma corpo a corpo usando Força, você recebe um bônus nas jogadas de dano que aumenta à medida que você adquire níveis de bárbaro, como mostrado na coluna Dano de Fúria na tabela O Bárbaro.
  • Você possui resistência contra dano de concussão, cortante e perfurante.

  Se você for capaz de conjurar magias, você não poderá conjurá-las ou se concentrar nelas enquanto estiver em fúria.

  Sua fúria dura por 1 minuto. Ela termina prematuramente se você cair inconsciente ou se seu turno acabar e você não tiver atacado nenhuma criatura hostil desde seu último turno ou tiver sofrido dano nesse período. Você também pode terminar sua fúria no seu turno com uma ação bônus.

  Quando você tiver usado a quantidade de fúrias mostrada para o seu nível de bárbaro na coluna Fúrias da tabela O Bárbaro, você precisará terminar um descanso longo antes de poder entrar em fúria novamente.
TXT

RECKLESS_LIVRO = <<~TXT.strip
  A partir do 2º nível, você pode desistir de toda preocupação com sua defesa para atacar com um desespero feroz. Quando você fizer o seu primeiro ataque no turno, você pode decidir atacar descuidadamente. Fazer isso lhe concede vantagem nas jogadas de ataque com armas corpo a corpo usando Força durante seu turno; porém, as jogadas de ataque feitas contra você possuem vantagem até o início do seu próximo turno.
TXT

DANGER_SENSE_LIVRO = <<~TXT.strip
  No 2º nível, você adquire um sentido sobrenatural de quando as coisas próximas não estão como deveriam, concedendo a você uma chance maior quando estiver evitando perigos.

  Você possui vantagem em testes de resistência de Destreza contra efeitos que você possa ver, como armadilhas e magias. Para receber esse benefício você não pode estar cego, surdo ou incapacitado.
TXT

FAST_MOVEMENT_LIVRO = <<~TXT.strip
  A partir do 5º nível, seu deslocamento aumenta em 3 metros enquanto você não estiver vestindo uma armadura pesada.
TXT

FERAL_INSTINCT_LIVRO = <<~TXT.strip
  No 7º nível, seu instinto está tão apurado que você recebe vantagem nas jogadas de iniciativa.

  Além disso, se você estiver surpreso no começo de um combate e não estiver incapacitado, você pode agir normalmente no seu primeiro turno, mas apenas se você entrar em fúria antes de realizar qualquer outra coisa neste turno.
TXT

BRUTAL_CRITICAL_LIVRO = <<~TXT.strip
  A partir do 9º nível, você pode rolar um dado de dano de arma adicional quando estiver determinando o dano extra de um acerto crítico com uma arma corpo a corpo.

  Isso aumenta para dois dados adicionais no 13º nível e três dados adicionais no 17º nível.
TXT

RELENTLESS_RAGE_LIVRO = <<~TXT.strip
  A partir do 11º nível, sua fúria pode manter você lutando independentente da gravidade dos seus ferimentos. Se você cair para 0 pontos de vida enquanto estiver em fúria e não morrer, você pode realizar um teste de resistência de Constituição CD 10. Se você for bem sucedido, você volta para 1 ponto de vida ao invés disso.

  Cada vez que você utilizar essa característica após a primeira, a CD aumenta em 5. Assim que você terminar um descanso curto ou longo a CD volta para 10.
TXT

PERSISTENT_RAGE_LIVRO = <<~TXT.strip
  A partir do 15º nível, sua fúria é tão brutal que ela só termina prematuramente se você cair inconsciente ou se você decidir terminá-la.
TXT

INDOMITABLE_MIGHT_LIVRO = <<~TXT.strip
  A partir do 18º nível, se o total de um teste de Força seu for menor que o seu valor de Força, você pode usar esse valor no lugar do resultado.
TXT

PRIMAL_CHAMPION_LIVRO = <<~TXT.strip
  No 20º nível, você incorpora os poderes da natureza. Seus valores de Força e Constituição aumentam em 4. Seu máximo para esses valores agora é 24.
TXT

BARBARIAN_UNARMORED_LIVRO = <<~TXT.strip
  Quando você não estiver vestindo qualquer armadura, sua Classe de Armadura será 10 + seu modificador de Destreza + seu modificador de Constituição. Você pode usar um escudo e continuar a receber esse benefício.
TXT

def apply_patches!(fd)
  fd.each_key do |k|
    fd[k] = ASI_LIVRO if k.match?(/-ability-score-improvement-\d+\z/)
  end

  %w[divine-domain divine-domain-improvement-1 divine-domain-improvement-2 divine-domain-improvement-3
     divine-domain-improvement-4].each { |k| fd[k] = DIVINE_DOMAIN_LIVRO if fd.key?(k) }

  %w[domain-spells-1 domain-spells-2 domain-spells-3 domain-spells-4 domain-spells-5].each do |k|
    fd[k] = DOMAIN_SPELLS_LIVRO if fd.key?(k)
  end

  fd['spellcasting-cleric'] = SPELLCASTING_CLERIC_LIVRO if fd.key?('spellcasting-cleric')

  fd['channel-divinity'] = CHANNEL_DIVINITY_PALADIN_LIVRO if fd.key?('channel-divinity')

  fd['channel-divinity-1-rest'] = CHANNEL_DIVINITY_1_REST_LIVRO if fd.key?('channel-divinity-1-rest')
  fd['channel-divinity-2-rest'] = CHANNEL_DIVINITY_REST_ONLY_LIVRO if fd.key?('channel-divinity-2-rest')
  fd['channel-divinity-3-rest'] = CHANNEL_DIVINITY_REST_ONLY_LIVRO if fd.key?('channel-divinity-3-rest')
  fd['channel-divinity-turn-undead'] = CHANNEL_TURN_UNDEAD_LIVRO if fd.key?('channel-divinity-turn-undead')

  %w[destroy-undead-cr-1-2-or-below destroy-undead-cr-1-or-below destroy-undead-cr-2-or-below
     destroy-undead-cr-3-or-below destroy-undead-cr-4-or-below].each do |k|
    fd[k] = DESTROY_UNDEAD_LIVRO if fd.key?(k)
  end

  %w[rage].each { |k| fd[k] = RAGE_LIVRO if fd.key?(k) }
  fd['reckless-attack'] = RECKLESS_LIVRO if fd.key?('reckless-attack')
  fd['danger-sense'] = DANGER_SENSE_LIVRO if fd.key?('danger-sense')
  fd['fast-movement'] = FAST_MOVEMENT_LIVRO if fd.key?('fast-movement')
  fd['feral-instinct'] = FERAL_INSTINCT_LIVRO if fd.key?('feral-instinct')
  %w[brutal-critical-1-die brutal-critical-2-dice brutal-critical-3-dice].each do |k|
    fd[k] = BRUTAL_CRITICAL_LIVRO if fd.key?(k)
  end
  fd['relentless-rage'] = RELENTLESS_RAGE_LIVRO if fd.key?('relentless-rage')
  fd['persistent-rage'] = PERSISTENT_RAGE_LIVRO if fd.key?('persistent-rage')
  fd['indomitable-might'] = INDOMITABLE_MIGHT_LIVRO if fd.key?('indomitable-might')
  fd['primal-champion'] = PRIMAL_CHAMPION_LIVRO if fd.key?('primal-champion')
  fd['barbarian-unarmored-defense'] = BARBARIAN_UNARMORED_LIVRO if fd.key?('barbarian-unarmored-defense')
end

todo = YAML.load_file(TODO) || {}
dnd = YAML.load_file(DND) || {}
book = YAML.load_file(BOOK_OUT) || {}

fd = (book['feature_descs'] || {}).transform_keys(&:to_s)
ft = (book['features'] || {}).transform_keys(&:to_s)

(todo['features'] || {}).each_key do |k|
  k = k.to_s
  next unless dnd['features']&.key?(k)

  ft[k] = dnd['features'][k].to_s
end

apply_patches!(fd)

ordered_fd = {}
(todo['feature_descs'] || {}).each_key do |k|
  k = k.to_s
  next unless fd.key?(k)

  ordered_fd[k] = fd[k]
end

out = {
  'features' => ft.sort.to_h,
  'feature_descs' => ordered_fd
}

File.write(BOOK_OUT, HEADER + out.to_yaml(line_width: -1))
warn "[apply_livro_book_feature_patches] gravado #{BOOK_OUT} (#{ordered_fd.size} feature_descs, #{ft.size} features)"
