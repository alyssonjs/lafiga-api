# frozen_string_literal: true

# Cria/atualiza a classe homebrew Espadachim Espiritual (cl-14 no front,
# `api_index: spirit-blade` no banco) e as 3 subclasses do arquetipo:
# Ceifeiro de Almas, Conjurador Espiritual e Especialista Elemental.
#
# Uso (dentro do container `lafiga_api`):
#   bin/rails custom:ensure_spirit_blade_class
#
# A task e' idempotente — pode rodar varias vezes sem duplicar registros.

namespace :custom do
  desc 'Garante a existencia da classe Espadachim Espiritual (api_index: spirit-blade) e suas 3 subclasses'
  task ensure_spirit_blade_class: :environment do
    api_index = 'spirit-blade'

    klass = Klass.find_or_initialize_by(api_index: api_index)
    klass.assign_attributes(
      name: 'Espadachim Espiritual',
      hit_die: 10,
      spellcasting_ability: nil, # marcial puro
      subclass_level: 3,
      primary_ability: 'Forca ou Destreza',
      saving_throws: %w[Sabedoria Constituicao],
      short_description: 'Marcial homebrew que forja uma arma do proprio espirito; Pacto Espiritual escala dado de dano d4 -> d12.',
      description: <<~HTML.strip,
        <p>Mestre marcial que forja uma arma a partir do proprio espirito. O Pacto Espiritual concede um dado de dano adicional por ataque que escala de d4 (1<sup>o</sup> nivel) ate d12 (17<sup>o</sup> nivel). O Arquetipo Espiritual define como o vinculo se manifesta em batalha.</p>
        <h3>Ataque Extra</h3>
        <p>2 ataques no 5<sup>o</sup>, 3 ataques no 12<sup>o</sup>.</p>
        <h3>Manifestacao Espiritual</h3>
        <p>No 6<sup>o</sup>, escolha permanente entre Molde Espiritual, Espirito Protetor ou Ataque Devastador.</p>
        <h3>Manifestacao Devastadora</h3>
        <p>No 14<sup>o</sup>, escolha permanente entre Carga, Blindagem Espiritual, Velocidade Insana ou Repreensao Rigorosa.</p>
        <h3>Marca da Morte (capstone)</h3>
        <p>No 20<sup>o</sup>, requer 1000+ espiritos consumidos pela Fome Espiritual; alvo marcado faz TR CON CD 15 ou fica incapacitado e pode morrer no turno seguinte.</p>
      HTML
      progression_table: <<~HTML.strip,
        <table>
          <thead>
            <tr><th>Nivel</th><th>Prof.</th><th>Caracteristicas</th><th>Dano do Pacto</th></tr>
          </thead>
          <tbody>
            <tr><td>1</td><td>+2</td><td>Pacto Espiritual</td><td>1d4</td></tr>
            <tr><td>2</td><td>+2</td><td>Estilo de Luta</td><td>1d4</td></tr>
            <tr><td>3</td><td>+2</td><td>Arquetipo Espiritual</td><td>1d4</td></tr>
            <tr><td>4</td><td>+2</td><td>Incremento no Valor de Habilidade</td><td>1d4</td></tr>
            <tr><td>5</td><td>+3</td><td>Ataque Extra</td><td>1d6</td></tr>
            <tr><td>6</td><td>+3</td><td>Manifestacao Espiritual</td><td>1d6</td></tr>
            <tr><td>7</td><td>+3</td><td>Caracteristica do Arquetipo Espiritual</td><td>1d6</td></tr>
            <tr><td>8</td><td>+3</td><td>Incremento no Valor de Habilidade</td><td>1d6</td></tr>
            <tr><td>9</td><td>+4</td><td>Fome Espiritual</td><td>1d8</td></tr>
            <tr><td>10</td><td>+4</td><td>Caracteristica do Arquetipo Espiritual</td><td>1d8</td></tr>
            <tr><td>11</td><td>+4</td><td>Meditacao Espiritual</td><td>1d8</td></tr>
            <tr><td>12</td><td>+4</td><td>Incremento no Valor de Habilidade / Ataque Extra (3)</td><td>1d8</td></tr>
            <tr><td>13</td><td>+5</td><td>—</td><td>1d10</td></tr>
            <tr><td>14</td><td>+5</td><td>Manifestacao Devastadora</td><td>1d10</td></tr>
            <tr><td>15</td><td>+5</td><td>Caracteristica do Arquetipo Espiritual</td><td>1d10</td></tr>
            <tr><td>16</td><td>+5</td><td>Incremento no Valor de Habilidade</td><td>1d10</td></tr>
            <tr><td>17</td><td>+6</td><td>—</td><td>1d12</td></tr>
            <tr><td>18</td><td>+6</td><td>Caracteristica do Arquetipo Espiritual</td><td>1d12</td></tr>
            <tr><td>19</td><td>+6</td><td>Incremento no Valor de Habilidade</td><td>1d12</td></tr>
            <tr><td>20</td><td>+6</td><td>Marca da Morte</td><td>1d12</td></tr>
          </tbody>
        </table>
      HTML
      rules: {
        id: 'spirit-blade',
        name: 'Espadachim Espiritual',
        hit_die: 'd10',
        primary_abilities: %w[STR DEX],
        saving_throws: %w[WIS CON],
        armor_proficiencies: %w[leve média],
        weapon_proficiencies: ['armas simples', 'armas marciais corpo-a-corpo'],
        tool_proficiencies: [],
        skill_proficiencies: {
          choose: 2,
          options: %w[Atletismo Acrobacia Intimidação Medicina Natureza Percepção Religião],
        },
        features_level1: ['Pacto Espiritual'],
        subclass: {
          choose_level: 3,
          options: {
            'soul-reaper': { id: 'soul-reaper', name: 'Ceifeiro de Almas' },
            'spirit-summoner': { id: 'spirit-summoner', name: 'Conjurador Espiritual' },
            'elemental-blade': { id: 'elemental-blade', name: 'Lâmina Elemental' },
          },
        },
        spellcasting: nil,
        resources: {
          spiritual_manifestation: { uses: 'Mod. SAB por descanso longo', recharge: 'LR' },
          devastating_manifestation: { uses: '1 por descanso longo', recharge: 'LR' },
          mark_of_death: { uses: '1', recharge: '1d6+1 dias' },
        },
        feature_rules: {
          spirit_blade: {
            pact_die: {
              levels: { 1 => 'd4', 5 => 'd6', 9 => 'd8', 13 => 'd10', 17 => 'd12' },
              once_per_turn: true,
              applies_per_attack_after: 5, # com Ataque Extra, vale por ataque
            },
            spirit_dc_formula: '8 + Prof + WIS',
            extra_attack: { at_level: 5, attacks: 2, upgrade_at: { 12 => 3 } },
            spiritual_manifestation: {
              available_at: 6,
              choose_one_permanent: %w[molde-espiritual espirito-protetor ataque-devastador],
            },
            spiritual_meditation: {
              available_at: 11,
              switchable_after_short_rest: true,
              options: %w[ataque-certeiro forca-de-espirito intuicao-extraordinaria sanidade-mental],
            },
            devastating_manifestation: {
              available_at: 14,
              choose_one_permanent: %w[carga blindagem-espiritual velocidade-insana repreensao-rigorosa],
            },
            mark_of_death: {
              available_at: 20,
              prerequisite: { spirits_consumed_min: 1000 },
              save_dc: 15,
              save_ability: 'CON',
            },
          },
        },
      },
    )
    klass.save!
    puts "[custom] Klass garantida: #{klass.name} (api_index=#{klass.api_index}, id=#{klass.id})"

    # 3 subclasses (placeholders ate o material das features chegar)
    subclasses = [
      {
        api_index: 'soul-reaper',
        name: 'Ceifeiro de Almas',
        subclass_flavor: 'Ceifa almas dos abatidos para fortalecer o vinculo espiritual',
        description: 'Arquetipo focado em colher almas dos abatidos para fortalecer o vinculo com a arma espiritual. Detalhes das caracteristicas (3o, 7o, 10o, 15o, 18o niveis) a confirmar.',
      },
      {
        api_index: 'spirit-summoner',
        name: 'Conjurador Espiritual',
        subclass_flavor: 'Canaliza o espirito da arma em manifestacoes auxiliares',
        description: 'Arquetipo que canaliza o espirito da arma em manifestacoes espirituais auxiliares e controle do campo. Detalhes a confirmar.',
      },
      {
        api_index: 'elemental-blade',
        name: 'Lâmina Elemental',
        subclass_flavor: 'Infunde a arma com energia elemental devastadora',
        description: 'Os espadachins que descobrem uma fonte elemental em seu espirito, repleta de energia natural, acabam se tornando verdadeiros destruidores em massa, apenas balancando suas armas e causando resultados catastroficos.',
      },
    ]

    # Renomear subklass legada (api_index antigo "spirit-elementalist")
    if (legacy = SubKlass.find_by(klass_id: klass.id, api_index: 'spirit-elementalist'))
      legacy.update!(api_index: 'elemental-blade', name: 'Lâmina Elemental')
      puts "  [custom]   SubKlass renomeada: spirit-elementalist -> elemental-blade"
    end

    subclasses.each do |attrs|
      sub = SubKlass.find_or_initialize_by(klass_id: klass.id, api_index: attrs[:api_index])
      sub.assign_attributes(
        name: attrs[:name],
        subclass_flavor: attrs[:subclass_flavor],
        description: attrs[:description],
      )
      sub.save!
      puts "  [custom]   SubKlass: #{sub.name} (api_index=#{sub.api_index}, id=#{sub.id})"
    end

    # =========================================================
    # Class Levels + Features
    # =========================================================
    # Pacto Espiritual descreve toda a progressao d4->d12 num unico Feature
    # anexado em L1 (mesmo padrao do Fighter Extra Attack que cobre L5/11/20
    # numa unica descricao). Idem para Ataque Extra (L5 + nota da progressao L12).

    features_def = [
      {
        api_index: 'spirit-blade-pacto-espiritual',
        name: 'Pacto Espiritual',
        levels: [1],
        description: <<~TXT.strip,
          No 1° nível, você teve sucesso na sua divisão espiritual para moldar uma arma a partir do seu espírito. Escolha uma arma da lista de armas que o espadachim seja proficiente, e essa arma passa a ser sua e apenas sua. Com uma ação bônus você pode materializar ou desmaterializar sua arma — você precisa estar com as mãos livres para fazer isso.

          Você pode optar por criar duas armas ao invés de uma com o Pacto Espiritual; o processo para criar uma arma nova é de 8 horas ininterruptas e não conta como tempo de descanso. Você pode também optar por mudar a forma de uma arma que você já possua para outra cujo espadachim seja proficiente — o processo leva 4 horas ininterruptas e também não conta como tempo de descanso. A sua arma é uma versão espiritual e não aceita que outras pessoas a empunhem, sendo impossível para qualquer um além de você segurá-la, a menos que você permita.

          Você pode fazer uma arma de cada vez, porém seu espírito não consegue suportar uma desfragmentação maior que duas armas — então não há como possuir uma terceira. As características do Pacto Espiritual só se aplicam enquanto você utilizar uma arma com o pacto. Você possui desvantagem no ataque com qualquer outra arma que não seja uma arma do pacto.

          Uma vez por turno, quando você realizar uma jogada de ataque com sua arma do Pacto Espiritual, ao acertar você pode rolar um dado de dano adicional conforme a tabela: 1d4 (1°), 1d6 (5°), 1d8 (9°), 1d10 (13°), 1d12 (17°). Quando você adquirir Ataque Extra, você pode rolar um dado de dano do Pacto Espiritual para cada ataque realizado.

          CD da Arma Espiritual = 8 + bônus de proficiência + seu modificador de Sabedoria.
        TXT
      },
      {
        api_index: 'spirit-blade-estilo-de-luta',
        name: 'Estilo de Luta',
        levels: [2],
        description: <<~TXT.strip,
          A partir do 2° nível você adota um estilo de combate particular que será sua especialidade. Escolha uma das opções: Combate com Armas Grandes, Combate com Duas Armas, Defesa ou Duelismo. Você não pode escolher o mesmo Estilo de Combate mais de uma vez.

          • Combate com Armas Grandes: re-rola 1s e 2s no dado de dano com armas duas mãos/versátil.
          • Combate com Duas Armas: adiciona o modificador de habilidade no dano do segundo ataque.
          • Defesa: +1 CA enquanto usar armadura.
          • Duelismo: +2 dano com arma corpo-a-corpo em uma mão (sem outra arma).
        TXT
      },
      {
        api_index: 'spirit-blade-arquetipo-espiritual-choose',
        name: 'Arquétipo Espiritual',
        levels: [3],
        description: 'No 3° nível, você escolhe um arquétipo: Ceifeiro de Almas, Conjurador Espiritual ou Lâmina Elemental. O arquétipo confere características especiais no 3°, 7°, 10°, 15° e 18° nível.',
      },
      {
        api_index: 'spirit-blade-incremento-valor-habilidade',
        name: 'Incremento no Valor de Habilidade',
        levels: [4, 8, 12, 16, 19],
        description: 'Você pode aumentar um valor de habilidade em 2, ou dois valores em 1. Como padrão, você não pode elevar um valor de habilidade acima de 20.',
      },
      {
        api_index: 'spirit-blade-ataque-extra',
        name: 'Ataque Extra',
        levels: [5],
        description: 'A partir do 5° nível, você pode atacar duas vezes, ao invés de uma, quando usar a ação Atacar durante o seu turno. O número de ataques aumenta para três quando você alcançar o 12° nível de espadachim espiritual.',
      },
      {
        api_index: 'spirit-blade-manifestacao-espiritual',
        name: 'Manifestação Espiritual',
        levels: [6],
        description: <<~TXT.strip,
          A partir do 6° nível, sua arma cria um vínculo ainda maior com você, revelando seu nome para o seu portador. Inimigos que tentem usar a arma sofrem dano necrótico (igual ao dado de dano da arma) por ataque. A espada jamais aceitará um mestre novo.

          Escolha permanentemente UMA das características como manifestação. Ative chamando o nome da arma. Usos = mod. SAB; recupera em descanso longo.

          • Molde Espiritual: arma assume forma de outra arma/objeto (10 min). Concede proficiência.
          • Espírito Protetor: +SAB na CA por 1 minuto (ação ou reação).
          • Ataque Devastador: +SAB nos ataques/dano por 1 min, mas −SAB CA. Crítico = hemorragia 1d8 turnos (TR CON), 2d4+2/turno.
        TXT
      },
      {
        api_index: 'spirit-blade-arquetipo-espiritual-feature',
        name: 'Característica do Arquétipo Espiritual',
        levels: [7, 10, 15, 18],
        description: 'Característica concedida pelo seu Arquétipo Espiritual (Ceifeiro de Almas, Conjurador Espiritual ou Especialista Elemental). Veja a descrição da subclasse.',
      },
      {
        api_index: 'spirit-blade-fome-espiritual',
        name: 'Fome Espiritual',
        levels: [9],
        description: <<~TXT.strip,
          No 9° nível, você e sua arma aprendem a absorver energia de objetos, itens e criaturas espirituais. Vantagem em testes de Sabedoria (Percepção) para localizar restos espirituais. Gaste 1 hora para absorver o poder espiritual de um objeto/criatura. Marcos de evolução:

          • 30 espíritos: +1 nas jogadas de ataque
          • 150 espíritos: arma se torna +1
          • 600 espíritos: arma se torna +2
          • 1700 espíritos: arma se torna +3

          Os espíritos fornecidos por cada objeto são definidos pelo Mestre.
        TXT
      },
      {
        api_index: 'spirit-blade-meditacao-espiritual',
        name: 'Meditação Espiritual',
        levels: [11],
        description: <<~TXT.strip,
          No 11° nível, após terminar um descanso curto, você pode meditar com sua arma e escolher um dos benefícios a seguir (válido enquanto empunhar a arma ou até nova meditação):

          • Ataque Certeiro: +1d8 de dano no primeiro ataque corpo-a-corpo de cada rodada (1 uso por descanso curto/longo).
          • Força de Espírito: vantagem em TRs contra Amedrontado.
          • Intuição Extraordinária: vantagem em iniciativa.
          • Sanidade Mental: vantagem em TRs contra Enfeitiçado.
        TXT
      },
      {
        api_index: 'spirit-blade-manifestacao-devastadora',
        name: 'Manifestação Devastadora',
        levels: [14],
        description: <<~TXT.strip,
          No 14° nível, como ação bônus enquanto a Manifestação Espiritual estiver ativa, escolha permanentemente UMA forma. Após uso, descanso longo para usar de novo.

          • Carga: escolha um número 1–4. Cada ataque, role 1d4; igual = ganha carga. Com 3 cargas, libere ataque conforme tipo da arma — Corta Céus (cone 9 m, 10d6+5 cortante), Ferroada (linha 12 m, 10d6+5 perfurante) ou Treme-Terra (raio 12 m, 8d8+5 concussivo + cair).
          • Blindagem Espiritual: por 10 min, vantagem em TRs FOR/CON, resistência cortante/concussivo/frio/fogo, imunidade veneno/ácido, +SAB CA, atacantes sofrem 1d4 força.
          • Velocidade Insana: por 1 min, deslocamento dobrado, vantagem em TRs DES, +1 ação/turno (apenas Atacar/Disparada/Desengajar/Usar Objeto). Inimigos corpo-a-corpo têm desvantagem.
          • Repreensão Rigorosa: por 1 min, aura 18 m. Hostis fazem TR SAB ou ficam impedidas. Repete TR no fim do turno; sucesso liberta e imuniza por 24h.
        TXT
      },
      {
        api_index: 'spirit-blade-marca-da-morte',
        name: 'Marca da Morte',
        levels: [20],
        description: 'Requer no mínimo 1000 espíritos consumidos pela Fome Espiritual. No 20° nível, como ação bônus, marque uma criatura visível. Ao acertar com a arma espiritual, alvo faz TR de Constituição (CD 15) ou fica incapacitado. Mantendo a arma em contato até o próximo turno, novo TR; falha = morte. Constritores e criaturas sem espírito são imunes. Recupera em 1d6+1 dias.',
      },
    ]

    # Cria/atualiza Features (uma vez cada, idempotente por api_index)
    feature_records = features_def.map do |fdef|
      feat = Feature.find_or_initialize_by(api_index: fdef[:api_index])
      feat.assign_attributes(
        name: fdef[:name],
        description: fdef[:description],
        category: :class_feature,
      )
      feat.dm_customized = true if feat.respond_to?(:dm_customized=)
      feat.save!
      [fdef, feat]
    end

    # Tabela do Bonus de Proficiencia por nivel
    prof_by_level = (1..20).map do |lvl|
      case lvl
      when 1..4   then 2
      when 5..8   then 3
      when 9..12  then 4
      when 13..16 then 5
      else 6
      end
    end

    # ASI cumulativo (ASI levels [4,8,12,16,19])
    asi_levels_set = [4, 8, 12, 16, 19].to_set
    asi_cumulative = 0
    asi_by_level = (1..20).map do |lvl|
      asi_cumulative += 1 if asi_levels_set.include?(lvl)
      asi_cumulative
    end

    # Cria/atualiza ClassLevel + associacoes
    (1..20).each do |level|
      cl = ClassLevel.find_or_initialize_by(klass_id: klass.id, level: level)
      cl.prof_bonus = prof_by_level[level - 1]
      cl.ability_score_bonuses = asi_by_level[level - 1]
      cl.save!

      # Limpa associacoes existentes (evita duplicar em re-runs) e re-anexa
      cl.features = []
      feature_records.each do |fdef, feat|
        cl.features << feat if fdef[:levels].include?(level)
      end
      cl.save!
    end
    puts "[custom] ClassLevels e Features sincronizados (#{features_def.size} features distintas em 20 niveis)."

    # =========================================================
    # Subclass Features (SubKlassLevel + features)
    # =========================================================
    subclass_features = {
      'soul-reaper' => [
        {
          api_index: 'spirit-blade-sr-visual-arrepiante',
          name: 'Visual Arrepiante',
          levels: [3],
          description: 'Entrando no caminho do ceifamento, o espadachim que escolhe esse caminho sofre algumas mudanças drásticas no seu visual. Quando você adquire esse arquétipo no 3° nível, você aprende os truques *toque macabro* e *taumaturgia*.',
        },
        {
          api_index: 'spirit-blade-sr-sentidos-aprimorados',
          name: 'Sentidos Aprimorados',
          levels: [3],
          description: 'A partir do 3° nível, sua visão se adapta às trevas. Você tem visão no escuro de 18m. Você também pode passar 1 minuto concentrado para adquirir percepção às cegas de 6m. Essa característica só funciona em locais escuros.',
        },
        {
          api_index: 'spirit-blade-sr-ataque-de-calafrios',
          name: 'Ataque de Calafrios',
          levels: [7],
          description: 'No 7° nível, quando você atacar uma criatura surpresa, seu espírito toca o espírito da criatura fazendo com que os piores pesadelos dela sejam você. A criatura atacada deve realizar um teste de resistência de Sabedoria. Se falhar, sofrerá 2d8 de dano psíquico e ficará amedrontada em relação a você por 1 minuto. A criatura pode refazer o teste de resistência no final de cada um de seus turnos, parando o efeito com um sucesso.',
        },
        {
          api_index: 'spirit-blade-sr-caminhante-das-sombras',
          name: 'Caminhante das Sombras',
          levels: [10],
          description: 'No 10° nível, você pode viajar através do Plano das Sombras. Com sua ação, você pode entrar na umbra e sair dela no início do seu próximo turno. No Plano das Sombras, você se move até o dobro do seu deslocamento de caminhada e pode se mover através de criaturas e objetos do Plano Material como se eles fossem terreno difícil, mas você não pode terminar seu turno em um espaço ocupado. Enquanto estiver lá, você não pode atacar nem ser atacado por ninguém no Plano Material, exceto por uma criatura que possa acessar o Plano da Sombras. Você pode usar esta característica duas vezes. Após isso, você precisa terminar um descanso curto ou longo para usá-la novamente.',
        },
        {
          api_index: 'spirit-blade-sr-marca-espiritual',
          name: 'Marca Espiritual',
          levels: [15],
          description: 'Quando você atingir o 15° nível, como uma ação bônus você direciona sua atenção para um alvo que possa **ver você**. Seu espírito o marca como o próximo para ser ceifado. Enquanto a marca estiver ativa, você tem desvantagem em jogadas de ataque contra qualquer outra criatura, e vantagem contra a criatura marcada. A criatura também sofre 10 de dano necrótico adicional no seu primeiro ataque realizado contra ela. Se o alvo for executado por você desta maneira, você absorve toda sua alma, transformando seu corpo em cinzas e fortalecendo sua *Fome Espiritual*.',
        },
        {
          api_index: 'spirit-blade-sr-circulo-de-absorcao',
          name: 'Círculo de Absorção Espiritual',
          levels: [18],
          description: 'No 18° nível, como uma ação você crava sua arma no chão e começa um ritual mágico que requer sua concentração. Num círculo de 7,5m de raio a partir de você, a área começa a se tornar escura e sombria, o chão fica envolto por trevas, mãos esqueléticas de almas que já foram ceifadas por você começam a sugar as almas das criaturas dentro da área e enviar forças para você. O local da magia se torna terreno difícil. Se você for atacado por uma criatura dentro do círculo enquanto realiza a maldição, a criatura sofre 4d8 de dano necrótico independente se acertar ou errar. Você deve realizar um teste de concentração para cada ataque; se falhar, a maldição se encerra e você só poderá fazê-la novamente após um descanso longo. No início do turno de cada criatura dentro do círculo, ela deve realizar um teste de resistência de Constituição. Se falhar, a criatura sofrerá 4d8 de dano necrótico. Se obtiver sucesso, a criatura sofrerá metade do dano. Você se cura em metade do dano causado por você enquanto assume esta forma.',
        },
      ],
      'spirit-summoner' => [
        {
          api_index: 'spirit-blade-ss-conjuracao',
          name: 'Conjuração',
          levels: [3],
          description: 'Quando você alcançar o 3° nível, você descobre um espírito conjurador através da sua arma. Escolha uma classe conjuradora entre **Druida ou Mago** — você não poderá trocar. Você passa a ter acesso a habilidades de conjuração da classe escolhida (third-caster, habilidade SAB). A CD de conjuração é a mesma da arma (8 + Prof + SAB), e a arma se torna o foco para suas conjurações. Você aprende dois truques, à sua escolha, da lista de magias da classe escolhida. Você aprende um truque adicional ao atingir o 10° nível. Magias de 1° nível e superiores devem ser das escolas: **Abjuração, Conjuração, Encantamento ou Evocação**.',
        },
        {
          api_index: 'spirit-blade-ss-leveza-de-espirito',
          name: 'Leveza de Espírito',
          levels: [3],
          description: 'No 3° nível, sua pureza espiritual faz com que seu corpo seja mais leve e fluido. Você ignora terreno difícil de locais que não sejam mágicos.',
        },
        {
          api_index: 'spirit-blade-ss-espirito-magico',
          name: 'Espírito Mágico',
          levels: [7],
          description: 'A partir do 7° nível, quando você usar sua ação para conjurar um truque, você pode realizar um ataque com sua arma como uma ação bônus.',
        },
        {
          api_index: 'spirit-blade-ss-magia-concentrada',
          name: 'Magia Concentrada',
          levels: [10],
          description: 'A partir do 10° nível você pode carregar sua arma espiritual com uma magia. Essa magia precisa ter um tempo de conjuração de uma ação, e deve ser de 1° nível ou superior. Você gasta um espaço de magia normalmente como se a estivesse conjurando. A magia se desfaz depois de 1 hora ou se você optar por conjurar uma outra magia através de sua arma. Quando você realizar uma jogada de ataque com a arma espiritual e acertar, como uma ação bônus você pode liberar a magia no alvo, acertando-a automaticamente.',
        },
        {
          api_index: 'spirit-blade-ss-impulsao-arcana',
          name: 'Impulsão Arcana',
          levels: [15],
          description: 'Ao atingir o 15° nível, você se torna um especialista no combate com armas e magias. Quando uma criatura atacar você e errar, você pode usar sua reação para lançar uma magia nela. A magia deve ter um tempo de conjuração de 1 ação e só pode afetar aquela criatura. Quando usar esta característica, só poderá ser utilizada novamente após um descanso longo.',
        },
        {
          api_index: 'spirit-blade-ss-espirito-magico-superior',
          name: 'Espírito Mágico Superior',
          levels: [18],
          description: 'A partir do 18° nível, quando você usar sua ação para conjurar uma magia, você pode realizar um ataque com sua arma, como uma ação bônus.',
        },
      ],
      'elemental-blade' => [
        {
          api_index: 'spirit-blade-eb-elemento-espiritual',
          name: 'Elemento Espiritual',
          levels: [3],
          description: 'No 3° nível quando você alcançar essa característica, escolha um dos elementos espirituais (Elétrico, Frio, Fogo ou Veneno). Você não poderá trocar. Este elemento passa a ser o dano do seu Pacto Espiritual. Você pode rolar 1d4 e deixar a sorte decidir: 1 = Elétrico, 2 = Frio, 3 = Fogo, 4 = Veneno.',
        },
        {
          api_index: 'spirit-blade-eb-ataque-do-elemento',
          name: 'Ataque do Elemento',
          levels: [3],
          description: 'Também no 3° nível, você pode conjurar via arma o truque característico do seu elemento — Elétrico: *Toque Chocante*; Frio: *Raio de Gelo*; Fogo: *Raio de Fogo*; Veneno: *Rajada de Veneno*. Adicione manualmente o truque correspondente aos seus truques conhecidos quando escolher o elemento.',
        },
        {
          api_index: 'spirit-blade-eb-manifestacao-furiosa',
          name: 'Manifestação Furiosa',
          levels: [7],
          description: <<~TXT.strip,
            No 7° nível, quando você estiver sob o efeito da Manifestação Espiritual, você adiciona um bônus nas jogadas de dano igual a metade do seu modificador de Sabedoria, arredondado para baixo (mín. 1). Você também obtém uma manifestação elemental furiosa de acordo com seu elemento. Toda manifestação tem a duração de 1 minuto, e você pode usar um número de vezes igual ao seu modificador de Sabedoria. Recupera os usos após um descanso longo.

            • Arma Relampejante (Elétrico): imbui a arma com densidade elétrica e descarrega num ataque. Acerto: +2d8 elétrico. Erro: pode usar reação para forçar TR de Constituição; falha = alvo impedido por 1 turno. Criaturas com resistência/imunidade a elétrico são imunes.
            • Espinhos de Gelo (Frio): ao atingir uma criatura, espinhos de gelo são liberados em uma linha de 4,5m no lado oposto. Criaturas atingidas fazem TR de Destreza ou sofrem 4d6 de frio e têm seus movimentos reduzidos pela metade por uma rodada.
            • Onda de Fogo (Fogo): a arma se envolve em chamas; use ação para um ataque em cone de 7,5m. Criaturas na área fazem TR de Destreza, sofrendo 6d6 flamejante; metade se passar.
            • Picada Mortal (Veneno): a arma é envolvida por gás nocivo. Pela duração, todo ataque que acertar causa +2d8 veneno e força TR de Constituição; falha = envenenada por 1 minuto.
          TXT
        },
        {
          api_index: 'spirit-blade-eb-implacavel',
          name: 'Implacável',
          levels: [10],
          description: <<~TXT.strip,
            Quando você atingir o 10° nível, sua natureza de espírito elemental lhe concede benefícios passivos de acordo com seu elemento:

            • Passo-Relâmpago (Elétrico): +1,5m de deslocamento de caminhada, resistência a dano elétrico, pode usar Disparada como ação bônus.
            • Sangue Frio (Frio): imune a dano de frio. Sempre que uma criatura fosse causar dano de frio, você é curado nessa quantidade.
            • Vontade do Fogo (Fogo): vantagem em testes de resistência contra magias.
            • Corpo Imortal (Veneno): imune a veneno e doenças. Não envelhece. Criaturas que provarem seu sangue fazem TR Constituição CD 15 ou ficam envenenadas por 1 hora.
          TXT
        },
        {
          api_index: 'spirit-blade-eb-manifestacao-devastadora',
          name: 'Manifestação Devastadora Elemental',
          levels: [15],
          description: <<~TXT.strip,
            No 15° nível, enquanto sob o efeito da Manifestação Devastadora, você adiciona +SAB/2 (mín. 1) ao dano com a arma espiritual e obtém uma manifestação elemental devastadora. Use 1×/descanso longo.

            • Forma de Relâmpago (Elétrico): por 1d4+1 turnos, você se torna o próprio relâmpago. Deslocamento dobrado, todo dano vira elétrico, ataques causam +2d8 elétrico extra. Combinado com *velocidade insana* ou magia *velocidade*: 3 níveis de exaustão ao terminar.
            • Coração de Gelo (Frio): por 1 minuto, +2 CA, criaturas a 1,5m têm deslocamento reduzido à metade e desvantagem em TR DES. Como ação, congele a água da atmosfera atingindo todas as criaturas a 1,5m (TR DES; falha = 5d8 frio; sucesso = metade). Criatura morta por essa habilidade é congelada e estilhaçada.
            • Ataque Vulcânico (Fogo): por 1 minuto, sua arma fica tão quente que perfura qualquer coisa; +2d6 fogo. Se usar duas armas, +1d6 fogo cada.
            • Veneno Mortal (Veneno): seu espírito concentra veneno e libera em ponto a até 18m. Veneno expande em raio de 6m envolvendo objetos e esquinas. Criaturas que iniciarem turno na área fazem TR Constituição (5d8 veneno se falharem; metade se passarem). Área se torna escura e terreno difícil. Dissipa-se por vento forte ou sucção.
          TXT
        },
        {
          api_index: 'spirit-blade-eb-poder-sem-limites',
          name: 'Poder Sem Limites',
          levels: [18],
          description: 'No nível 18, você pode maximizar o dano de um ataque de dano elemental realizado do mesmo tipo do seu elemento espiritual. Você precisa realizar um descanso curto ou longo para usar novamente esta característica.',
        },
      ],
    }

    subclass_features.each do |sub_api, feats|
      sub = SubKlass.find_by(klass_id: klass.id, api_index: sub_api)
      next unless sub

      feature_records = feats.map do |fdef|
        feat = Feature.find_or_initialize_by(api_index: fdef[:api_index])
        feat.assign_attributes(
          name: fdef[:name],
          description: fdef[:description],
          category: :subclass_feature,
        )
        feat.dm_customized = true if feat.respond_to?(:dm_customized=)
        feat.save!
        [fdef, feat]
      end

      # Limpa associacoes existentes (re-runs nao duplicam)
      sub.sub_klass_levels.includes(:features).each do |lvl|
        lvl.features = []
        lvl.save!
      end

      # Cria/atualiza SubKlassLevel + associa features
      [3, 7, 10, 15, 18].each do |level|
        skl = SubKlassLevel.find_or_initialize_by(sub_klass_id: sub.id, level: level)
        skl.save!
        feature_records.each do |fdef, feat|
          skl.features << feat if fdef[:levels].include?(level)
        end
        skl.save!
      end

      total = feature_records.size
      puts "  [custom]   SubKlass features sincronizadas: #{sub.name} (#{total} features distintas)"
    end

    puts '[custom] Pronto. Recarregue o front e a classe deve aparecer no compendium.'
  rescue StandardError => e
    puts "[custom] Falha: #{e.message}"
    raise
  end
end
