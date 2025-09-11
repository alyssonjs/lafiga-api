# lib/tasks/dnd_import.rake
require 'net/http'
require 'json'
require 'yaml'
require 'set'

namespace :dnd do
  # === Helpers compartilhados para Backgrounds (PHB via docs/livro_do_jogador.txt) ===
  def phb_background_catalog
    # slug => { name_pt:, feature_title_pt: }
    @phb_background_catalog ||= {
      'acolyte'        => { name_pt: 'Acólito',          feature_title_pt: 'ABRIGO DOS FIÉIS' },
      'charlatan'      => { name_pt: 'Charlatão',        feature_title_pt: 'IDENTIDADE FALSA' },
      'criminal'       => { name_pt: 'Criminoso',        feature_title_pt: 'CONTATO CRIMINAL' },
      'entertainer'    => { name_pt: 'Artista',          feature_title_pt: 'PELA DEMANDA POPULAR' },
      'folk-hero'      => { name_pt: 'Herói do Povo',    feature_title_pt: 'HOSPITALIDADE RÚSTICA' },
      'guild-artisan'  => { name_pt: 'Artesão da Guilda',feature_title_pt: 'ASSOCIADOS DA GUILDA' },
      'hermit'         => { name_pt: 'Eremita',          feature_title_pt: 'DESCOBERTA' },
      'noble'          => { name_pt: 'Nobre',            feature_title_pt: 'POSIÇÃO PRIVILEGIADA' },
      'outlander'      => { name_pt: 'Forasteiro',       feature_title_pt: 'ANDARILHO' },
      'sage'           => { name_pt: 'Sábio',            feature_title_pt: 'PESQUISADOR' },
      'sailor'         => { name_pt: 'Marinheiro',       feature_title_pt: 'PASSAGEM DE NAVIO' },
      'soldier'        => { name_pt: 'Soldado',          feature_title_pt: 'PATENTE MILITAR' },
      'urchin'         => { name_pt: 'Órfão',            feature_title_pt: 'SEGREDOS DA CIDADE' }
    }
  end

  def livro_do_jogador_path
    # Try repo root docs first: ../../docs/livro_do_jogador.txt
    root_docs = Rails.root.join('..','..','docs','livro_do_jogador.txt')
    return root_docs.to_s if File.exist?(root_docs)
    # Fallback to api/docs if present
    api_docs = Rails.root.join('docs','livro_do_jogador.txt')
    return api_docs.to_s if File.exist?(api_docs)
    raise "Arquivo docs/livro_do_jogador.txt não encontrado"
  end

  def extract_feature_block(feature_title_pt)
    path = livro_do_jogador_path
    lines = File.read(path, mode: 'r:UTF-8').split(/\r?\n/)
    # find line that starts with "CARACTERÍSTICA: <title>"
    start_idx = lines.index do |l|
      s = l.strip
      s.start_with?("CARACTERÍSTICA:") && s.gsub(/^CARACTER[ÍI]STICA:\s*/,'')&.start_with?(feature_title_pt)
    end
    return [feature_title_pt, nil] unless start_idx

    feat_name = feature_title_pt
    desc_lines = []
    i = start_idx + 1
    while i < lines.size
      line = lines[i]
      break if line.nil?
      stripped = line.strip
      break if stripped.start_with?("CARACTERÍSTICAS SUGERIDAS")
      break if stripped.start_with?("VARIAÇÃO")
      break if stripped.match?(/^d\d+\s+/)
      desc_lines << line
      i += 1
    end
    text = desc_lines.join("\n").strip
    [feat_name, text.presence]
  rescue
    [feature_title_pt, nil]
  end

  def alignment_indices_for_tag(tag)
    tag = (tag || '').to_s.strip.downcase
    all = %w[lawful-good neutral-good chaotic-good lawful-neutral neutral chaotic-neutral lawful-evil neutral-evil chaotic-evil]
    case tag
    when 'leal', 'lawful'
      %w[lawful-good lawful-neutral lawful-evil]
    when 'bom', 'good'
      %w[lawful-good neutral-good chaotic-good]
    when 'caótico', 'caotico', 'chaotic'
      %w[chaotic-good chaotic-neutral chaotic-evil]
    when 'mal', 'evil'
      %w[lawful-evil neutral-evil chaotic-evil]
    when 'neutro', 'neutral'
      %w[lawful-neutral neutral chaotic-neutral]
    else
      all # Qualquer
    end
  end

  def parse_enumerated_list(lines, start_label_regex, expected_count)
    idx = lines.index { |l| l.strip =~ start_label_regex }
    return [] unless idx
    i = idx + 1
    items = []
    current = nil
    while i < lines.size && items.size < expected_count
      line = lines[i]
      break if line.nil?
      if line =~ /^\s*(\d+)\s+(.+)/
        items << current.strip if current
        current = $2
      else
        if current
          current << ' ' unless current.end_with?(' ')
          current << line.strip
        end
      end
      i += 1
    end
    items << current.strip if current
    items
  end

  def extract_bg_block(meta)
    path = livro_do_jogador_path
    lines = File.read(path, mode: 'r:UTF-8').split(/\r?\n/)

    # find feature block first to locate section
    feat_name, feat_desc = extract_feature_block(meta[:feature_title_pt])

    # locate feature line index
    feat_line_idx = lines.index { |l| l.strip.start_with?("CARACTERÍSTICA:") && l.include?(meta[:feature_title_pt]) } || 0

    # scan upwards for key lines (within 80 lines)
    scan_from = [0, feat_line_idx - 80].max
    scan_to   = [lines.size - 1, feat_line_idx + 10].max
    scan = lines[scan_from..scan_to]
    skills = []
    tools = []
    languages_choose = 0
    starting_equipment = []

    scan.each_with_index do |l, j|
      s = l.strip
      if s.start_with?("Proficiência em Perícias:")
        list = s.split(":",2)[1].to_s.strip
        skills = list.split(/,\s*/).map { |x| x.gsub(/\.$/,'').strip }
      elsif s.start_with?("Proficiência em Ferramentas:")
        list = s.split(":",2)[1].to_s.strip
        tools = list.split(/,\s*/).map { |x| x.gsub(/\.$/,'').strip }
      elsif s.start_with?("Idiomas:")
        rest = s.split(":",2)[1].to_s
        if rest =~ /(\d+)/
          languages_choose = $1.to_i
        else
          languages_choose = 0
        end
      elsif s.start_with?("Equipamento:")
        # capture this line and following wrapped lines until blank or next section
        eq = s.split(":",2)[1].to_s
        k = j + 1
        while (k < scan.size)
          nxt = scan[k]
          break if nxt.nil?
          st = nxt.strip
          break if st.empty? || st.start_with?("CARACTERÍSTICA:") || st =~ /^d\d+\s/
          eq << " " << st
          k += 1
        end
        # split by "," as rough list
        starting_equipment = eq.split(/,\s*/).map { |x| x.strip }.reject(&:empty?)
      end
    end

    # Traits/Ideals/Bonds/Flaws — after "CARACTERÍSTICAS SUGERIDAS"
    sug_idx = lines.index { |l| l.strip.start_with?("CARACTERÍSTICAS SUGERIDAS") && l } || feat_line_idx
    tail = lines[sug_idx..-1]
    traits = parse_enumerated_list(tail, /^d?8\s+Traço de Personalidade/i, 8)
    ideals_raw = parse_enumerated_list(tail, /^d?6\s+Ideal/i, 6)
    bonds = parse_enumerated_list(tail, /^d?6\s+Vínculo/i, 6)
    flaws = parse_enumerated_list(tail, /^d?6\s+Defeito/i, 6)

    ideals = ideals_raw.map do |t|
      if t =~ /(.*)\(([^\)]+)\)\s*$/
        desc = $1.strip.gsub(/\.$/,'')
        tag  = $2.strip
        { 'desc' => desc, 'alignments' => alignment_indices_for_tag(tag) }
      else
        { 'desc' => t, 'alignments' => alignment_indices_for_tag('Qualquer') }
      end
    end

    {
      'name' => meta[:name_pt],
      'starting_proficiencies' => {
        'skills' => skills,
        'tools' => tools
      },
      'language_options' => {
        'choose' => languages_choose,
        'type' => 'languages'
      },
      'starting_equipment' => starting_equipment,
      'starting_equipment_options' => [],
      'feature' => {
        'name' => feat_name,
        'desc' => feat_desc.to_s.split(/\n{2,}/)
      },
      'personality_traits' => { 'choose' => 2, 'options' => traits },
      'ideals' => { 'choose' => 1, 'options' => ideals },
      'bonds' => { 'choose' => 1, 'options' => bonds },
      'flaws' => { 'choose' => 1, 'options' => flaws }
    }
  end

  def build_backgrounds_from_book
    phb_background_catalog.each_with_object({}) do |(slug, meta), acc|
      acc[slug] = extract_bg_block(meta)
    end
  end

  desc "Importa magias e classes do D&D 5e API para o banco"
  task import: :environment do
    BASE = ENV['DND_API_BASE'].presence || 'https://www.dnd5eapi.co'

    # --- translations helpers (pt-BR) -------------------------------------
    PT_SCHOOL_MAP = {
      'Abjuration'=>'Abjuração','Conjuration'=>'Conjuração','Divination'=>'Adivinhação','Enchantment'=>'Encantamento',
      'Evocation'=>'Evocação','Illusion'=>'Ilusão','Necromancy'=>'Necromancia','Transmutation'=>'Transmutação'
    }.freeze

    def load_dnd_translations
      path = Rails.root.join('config','dnd_translations.yml')
      File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    end
    TR = load_dnd_translations

    def tr_pt(category, key, fallback=nil)
      return fallback unless TR.is_a?(Hash)
      TR.dig(category.to_s, key.to_s) || fallback
    end

    # Collect missing keys to help completing translations
    MISSING = Hash.new { |h,k| h[k] = {} }
    def mark_missing(category, key, original)
      return if key.nil? || key.to_s.strip.empty?
      MISSING[category.to_s][key.to_s] ||= original
    end

    # --- manual overrides for missing/poor subclass data -------------------
    SUBCLASS_OVERRIDES = {
      'barbarian' => {
        'totem-warrior' => {
          name: 'Caminho do Guerreiro Totêmico',
          flavor: 'Primal Path',
          description: 'Bárbaros que seguem espíritos animais para obter poderes em fúria.',
          levels: [
            { level: 3, features: [
              { name: 'Buscador de Espíritos', description: 'Aprende ritos xamânicos e escolhe um Espírito Totêmico.' },
              { name: 'Espírito Totêmico', description: 'Benefícios do animal escolhido quando em fúria.' }
            ]},
            { level: 6, features: [ { name: 'Aspecto da Besta', description: 'Bônus passivo do totem escolhido.' } ]},
            { level: 10, features: [ { name: 'Andarilho Espiritual', description: 'Comunica-se/interage com espíritos.' } ]},
            { level: 14, features: [ { name: 'Afinidade Totêmica', description: 'Benefício adicional do totem quando em fúria.' } ]}
          ]
        }
      },
      'bard' => {
        'college-of-valor' => {
          name: 'Colégio do Valor',
          flavor: 'Bard College',
          description: 'Bardos treinados para o campo de batalha, combinando magia e combate marcial.',
          levels: [
            { level: 3, features: [
              { name: 'Proficiências Bônus', description: 'Proficiência com armaduras médias, escudos e armas marciais.' },
              { name: 'Inspiração de Combate', description: 'Aliados podem usar o dado de Inspiração para dano ou CA (reação).' }
            ]},
            { level: 6, features: [ { name: 'Ataque Extra', description: 'Realiza dois ataques ao usar a ação de Ataque.' } ]},
            { level: 14, features: [ { name: 'Magia de Batalha', description: 'Após conjurar magia (ação), faz um ataque com arma como ação bônus.' } ]}
          ]
        }
      },
      'warlock' => {
        'archfey' => {
          name: 'Pacto — Arquifada', flavor: 'Otherworldly Patron', description: 'Ilusões e controle feérico.',
          levels: [ {level:1,features:[{name:'Presença Feérica', description:'Ameaça/encanto em área curta.'}]}, {level:6,features:[{name:'Evasão Feérica', description:'Teleporte curto ao sofrer dano.'}]}, {level:10,features:[{name:'Manto da Sombra Feérica', description:'Furtividade/ilusão aprimorada.'}]}, {level:14,features:[{name:'Banquete dos Sonhos', description:'Encantar/adormecer inimigos.'}]} ]
        },
        'great-old-one' => {
          name: 'Pacto — O Grande Antigo', flavor: 'Otherworldly Patron', description: 'Poderes psíquicos e telepatia.',
          levels: [ {level:1,features:[{name:'Sussurros Telepáticos', description:'Telepatia com criaturas.'}]}, {level:6,features:[{name:'Defesa Entrópica', description:'Impor desvantagem a ataques.'}]}, {level:10,features:[{name:'Mente Insondável', description:'Resistência a leitura de mente.'}]}, {level:14,features:[{name:'Criatura Tétrica', description:'Efeito/servo enlouquecedor.'}]} ]
        }
      },
      'cleric' => {
        'light' => { name: 'Domínio da Luz', flavor: 'Divine Domain', description: 'Magias de fogo/luz e controle de brilho.', levels: [ {level:1,features:[{name:'Bênção da Luz', description:'Magias do domínio sempre preparadas.'}]}, {level:2,features:[{name:'Canalizar: Cegante', description:'Explosão de luz que cega.'}]}, {level:6,features:[{name:'Luz Radiante', description:'Dano extra radiante.'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano radiante adicional em ataque.'}]}, {level:17,features:[{name:'Aura de Luz', description:'Aura brilhante poderosa.'}]} ] },
        'knowledge' => { name: 'Domínio do Conhecimento', flavor: 'Divine Domain', description: 'Perícias e saber divino.', levels: [ {level:1,features:[{name:'Bênçãos do Conhecimento', description:'Perícias/idiomas; domínios de magia.'}]}, {level:2,features:[{name:'Canalizar: Conhecimento', description:'Inspiração de saber temporário.'}]}, {level:6,features:[{name:'Leituras', description:'Entendimento ampliado.'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano adicional.'}]}, {level:17,features:[{name:'Saber Supremo', description:'Conhecimento extraordinário.'}]} ] },
        'nature' => { name: 'Domínio da Natureza', flavor: 'Divine Domain', description: 'Afinidade com a natureza.', levels: [ {level:1,features:[{name:'Iniciado Druídico', description:'Cantrip druídico; magias do domínio.'}]}, {level:2,features:[{name:'Canalizar: Encantar Natureza', description:'Acalmar/encantar animais/plantas.'}]}, {level:6,features:[{name:'Dampenar Elementos', description:'Reduz dano elemental (reação).'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano adicional.'}]}, {level:17,features:[{name:'Mestre da Natureza', description:'Comandar criaturas naturais.'}]} ] },
        'tempest' => { name: 'Domínio da Tempestade', flavor: 'Divine Domain', description: 'Trovão/relâmpago e retaliação.', levels: [ {level:1,features:[{name:'Ira das Tempestades', description:'Reação: dano elétrico/trovoada.'}]}, {level:2,features:[{name:'Canalizar: Destruição', description:'Maximiza dano elétrico/trovoada.'}]}, {level:6,features:[{name:'Retaliação Trovejante', description:'Empurra/derruba inimigos.'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano adicional.'}]}, {level:17,features:[{name:'Tempestade Divina', description:'Grande poder tempestuoso.'}]} ] },
        'trickery' => { name: 'Domínio da Trapaça', flavor: 'Divine Domain', description: 'Ilusão, duplicidade e furtividade.', levels: [ {level:1,features:[{name:'Bênção da Trapaça', description:'Vantagem em Furtividade para aliado.'}]}, {level:2,features:[{name:'Canalizar: Duplicidade', description:'Cria duplicata ilusória.'}]}, {level:6,features:[{name:'Duplicidade Aprimorada', description:'Múltiplas ilusões.'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano adicional.'}]}, {level:17,features:[{name:'Mestre da Trapaça', description:'Ilusões poderosas.'}]} ] },
        'war' => { name: 'Domínio da Guerra', flavor: 'Divine Domain', description: 'Combate marcial sob bênção.', levels: [ {level:1,features:[{name:'Discípulo da Guerra', description:'Proficiências marciais; magias do domínio.'}]}, {level:2,features:[{name:'Canalizar: Guia de Guerra', description:'Ataque adicional como reação.'}]}, {level:6,features:[{name:'Golpes Abençoados', description:'Bônus de dano.'}]}, {level:8,features:[{name:'Golpe Abençoado', description:'Dano adicional.'}]}, {level:17,features:[{name:'Avatar de Batalha', description:'Poder marcial supremo.'}]} ] }
      },
      'druid' => {
        'moon' => { name: 'Círculo da Lua', flavor: 'Druid Circle', description: 'Forma Selvagem poderosa e versátil.', levels: [ {level:2,features:[{name:'Forma Selvagem Aprimorada', description:'Transformações mais fortes.'}]}, {level:6,features:[{name:'Ataques Primais', description:'Ataques contam como mágicos.'}]}, {level:10,features:[{name:'Forma Elemental', description:'Acesso a formas elementais.'}]}, {level:14,features:[{name:'Forma Incansável', description:'Sustentação superior.'}]} ] }
      },
      'fighter' => {
        'battle-master' => { name: 'Mestre de Batalha', flavor: 'Martial Archetype', description: 'Maneuvers e dados de superioridade.', levels: [ {level:3,features:[{name:'Superioridade em Combate', description:'Maneuvers + dados.'}]}, {level:7,features:[{name:'Conhecimento de Campo', description:'Benefícios táticos.'}]}, {level:10,features:[{name:'Maneuvers Adicionais', description:'Novas opções.'}]}, {level:15,features:[{name:'Esquiva Superior', description:'Defesa melhorada.'}]}, {level:18,features:[{name:'Supremacia', description:'Dados aprimorados.'}]} ] },
        'eldritch-knight' => { name: 'Cavaleiro Arcano', flavor: 'Martial Archetype (third-caster)', description: 'Conjuração leve (Abjuração/Evocação).', levels: [ {level:3,features:[{name:'Magias & Laço de Arma', description:'Ganha cantrips/magias e vínculo.'}]}, {level:7,features:[{name:'Guerreiro Arcano', description:'Defesas/Reações mágicas.'}]}, {level:10,features:[{name:'Ataque Místico', description:'Combina ataques e magia.'}]}, {level:15,features:[{name:'Teleporte de Guerra', description:'Movimento mágico.'}]}, {level:18,features:[{name:'Assalto Arcano', description:'Explosões/controle.'}]} ] }
      },
      'monk' => {
        'shadow' => { name: 'Caminho da Sombra', flavor: 'Monastic Tradition', description: 'Furtividade e mobilidade sombria.', levels: [ {level:3,features:[{name:'Artes da Sombra', description:'Técnicas de ki sombrias.'}]}, {level:6,features:[{name:'Passo das Sombras', description:'Teleporte entre sombras.'}]}, {level:11,features:[{name:'Manto das Sombras', description:'Invisibilidade/escuro.'}]}, {level:17,features:[{name:'Forma das Sombras', description:'Mestria sombria.'}]} ] },
        'four-elements' => { name: 'Caminho dos Quatro Elementos', flavor: 'Monastic Tradition', description: 'Disciplinas elementais de ki.', levels: [ {level:3,features:[{name:'Discípulo dos Elementos', description:'Escolhe disciplinas.'}]}, {level:6,features:[{name:'Aprimorar Disciplinas', description:'Novas opções.'}]}, {level:11,features:[{name:'Controle Elemental', description:'Efeitos mais fortes.'}]}, {level:17,features:[{name:'Mestre Elemental', description:'Poderes elevados.'}]} ] }
      },
      'paladin' => {
        'ancients' => { name: 'Juramento dos Anciões', flavor: 'Sacred Oath', description: 'Luz/natureza protetiva.', levels: [ {level:3,features:[{name:'Juramento & Magias do Juramento', description:'Lista de magias + Channel Divinity.'}]}, {level:7,features:[{name:'Aura Protetiva', description:'Resistências/controle.'}]}, {level:15,features:[{name:'Sentinela da Luz', description:'Proteções especiais.'}]}, {level:20,features:[{name:'Forma Ancestral', description:'Transformação sagrada.'}]} ] },
        'vengeance' => { name: 'Juramento da Vingança', flavor: 'Sacred Oath', description: 'Perseguir e punir inimigos.', levels: [ {level:3,features:[{name:'Juramento & Magias do Juramento', description:'Lista de magias + Channel Divinity focada em caça.'}]}, {level:7,features:[{name:'Aura de Vingança', description:'Controle contra fuga.'}]}, {level:15,features:[{name:'Vingador Implacável', description:'Mobilidade/reação contra alvo marcado.'}]}, {level:20,features:[{name:'Anjo da Vingança', description:'Forma ofensiva.'}]} ] }
      },
      'ranger' => {
        'beast-master' => { name: 'Mestre das Feras', flavor: 'Ranger Conclave', description: 'Companheiro animal e sinergia.', levels: [ {level:3,features:[{name:'Companheiro Animal', description:'Escolhe e vincula uma besta.'}]}, {level:7,features:[{name:'Cooperação Tática', description:'Ações coordenadas.'}]}, {level:11,features:[{name:'Fera Extraordinária', description:'Aprimoramentos ao companheiro.'}]}, {level:15,features:[{name:'Sinergia Perfeita', description:'Grande eficácia conjunta.'}]} ] }
      },
      'rogue' => {
        'assassin' => { name: 'Assassino', flavor: 'Roguish Archetype', description: 'Golpes letais e infiltração.', levels: [ {level:3,features:[{name:'Assassinar', description:'Vantagem e críticos contra surpreendidos.'}]}, {level:9,features:[{name:'Imitação', description:'Falsificar identidades.'}]}, {level:13,features:[{name:'Infiltração', description:'Assumir personas.'}]}, {level:17,features:[{name:'Golpe Mortal', description:'Críticos devastadores.'}]} ] },
        'arcane-trickster' => { name: 'Trapaceiro Arcano', flavor: 'Roguish Archetype (third-caster)', description: 'Conjuração leve (Ilusão/Encantamento).', levels: [ {level:3,features:[{name:'Mão Mágica Arcana', description:'Cantrips e mão mágica aprimorada.'}]}, {level:9,features:[{name:'Truques Místicos', description:'Controle adicional.'}]}, {level:13,features:[{name:'Truque Invisível', description:'Infiltração mágica.'}]}, {level:17,features:[{name:'Mestre Arcano', description:'Uso eficiente de truques.'}]} ] }
      },
      'sorcerer' => {
        'wild-magic' => { name: 'Magia Selvagem', flavor: 'Sorcerous Origin', description: 'Surtos de magia caótica e metamagia dinâmica.', levels: [ {level:1,features:[{name:'Surto de Magia Selvagem', description:'Efeitos aleatórios após conjuração.'}]}, {level:6,features:[{name:'Marés do Caos', description:'Vantagem ocasional; recarga com surto.'}]}, {level:14,features:[{name:'Controle do Caos', description:'Manipular resultados de surto.'}]}, {level:18,features:[{name:'Tempestade Mágica', description:'Grande caos mágico.'}]} ] }
      },
      'wizard' => {
        'abjuration' => { name: 'Escola de Abjuração', flavor: 'Arcane Tradition', description: 'Defesas e proteções mágicas.', levels: [ {level:2,features:[{name:'Salvaguarda Arcana', description:'Escudo protetor; custos reduzidos.'}]}, {level:6,features:[{name:'Proteção Projetada', description:'Desviar dano de aliados.'}]}, {level:10,features:[{name:'Abjuração Aprimorada', description:'Reservas maiores.'}]}, {level:14,features:[{name:'Resistência Arcana', description:'Defesas potentes.'}]} ] },
        'conjuration' => { name: 'Escola de Conjuração', flavor: 'Arcane Tradition', description: 'Conjurar/teleportar com eficiência.', levels: [ {level:2,features:[{name:'Conjurador Sábio', description:'Custos reduzidos; conjurar objetos.'}]}, {level:6,features:[{name:'Recuperar Conjuração', description:'Criar objetos simples.'}]}, {level:10,features:[{name:'Teletransporte Focado', description:'Teleporte melhorado.'}]}, {level:14,features:[{name:'Conjuração Duradoura', description:'Invocações persistentes.'}]} ] },
        'divination' => { name: 'Escola de Adivinhação', flavor: 'Arcane Tradition', description: 'Controle de probabilidades e presságios.', levels: [ {level:2,features:[{name:'Presságio', description:'Substitui rolagens com dados de presságio.'}]}, {level:6,features:[{name:'Olho do Vidente', description:'Vigiar à distância.'}]}, {level:10,features:[{name:'Oportunidade Calculada', description:'Apoio às rolagens de aliados.'}]}, {level:14,features:[{name:'Presságios Maiores', description:'Mais/maiores presságios.'}]} ] },
        'enchantment' => { name: 'Escola de Encantamento', flavor: 'Arcane Tradition', description: 'Encantos e controle de mentes.', levels: [ {level:2,features:[{name:'Encantador', description:'Custos reduzidos; amigos temporários.'}]}, {level:6,features:[{name:'Hipnotizar', description:'Controle leve de alvos.'}]}, {level:10,features:[{name:'Dividir Encanto', description:'Atinge dois alvos.'}]}, {level:14,features:[{name:'Dominar', description:'Encantamentos poderosos.'}]} ] },
        'illusion' => { name: 'Escola de Ilusão', flavor: 'Arcane Tradition', description: 'Criação/manipulação de ilusões.', levels: [ {level:2,features:[{name:'Ilusionista', description:'Custos reduzidos; truques adicionais.'}]}, {level:6,features:[{name:'Imagem Maleável', description:'Moldar ilusões.'}]}, {level:10,features:[{name:'Ilusões Persistentes', description:'Duram mais.'}]}, {level:14,features:[{name:'Realidade Ilusória', description:'Torna ilusões parcialmente reais.'}]} ] },
        'necromancy' => { name: 'Escola de Necromancia', flavor: 'Arcane Tradition', description: 'Controle de vida e morte.', levels: [ {level:2,features:[{name:'Necromante', description:'Custos reduzidos; vitalidade de mortos.'}]}, {level:6,features:[{name:'Ceifar Vida', description:'Recupera vida ao matar com magia.'}]}, {level:10,features:[{name:'Comandar Mortos', description:'Mais mortos-vivos.'}]}, {level:14,features:[{name:'Mestre dos Mortos', description:'Aprimora mortos-vivos.'}]} ] },
        'transmutation' => { name: 'Escola de Transmutação', flavor: 'Arcane Tradition', description: 'Modificar matéria e forma.', levels: [ {level:2,features:[{name:'Transmutador', description:'Custos reduzidos; pedra da transmutação.'}]}, {level:6,features:[{name:'Forma Menor', description:'Alterações úteis.'}]}, {level:10,features:[{name:'Metamorfose Aprimorada', description:'Transformações melhores.'}]}, {level:14,features:[{name:'Mestre Transmutador', description:'Poderes da pedra de transmutação.'}]} ] }
      }
    }.freeze

    def load_yaml_overrides
      path = Rails.root.join('config','subclass_overrides.yml')
      return {} unless File.exist?(path)
      YAML.load_file(path) || {}
    rescue
      {}
    end

    def merged_overrides
      yaml = load_yaml_overrides
      if SUBCLASS_OVERRIDES.respond_to?(:deep_merge)
        # Preferir conteúdo do YAML sobre o interno
        SUBCLASS_OVERRIDES.deep_merge(yaml)
      else
        # fallback shallow merge per top-level class (YAML sobrescreve)
        SUBCLASS_OVERRIDES.merge(yaml) { |_k, a, b| (a || {}).merge(b || {}) }
      end
    end

    def apply_subclass_overrides!(klass)
      all = merged_overrides
      overrides = all[klass.api_index]
      return unless overrides.present?
      overrides.each do |sub_idx, data|
        sub = SubKlass.find_or_initialize_by(api_index: sub_idx, klass_id: klass.id)
        begin
          parsed_levels = sub.levels_json.present? ? JSON.parse(sub.levels_json) : []
        rescue
          parsed_levels = []
        end
        needs_levels = parsed_levels.blank?
        needs_desc   = sub.description.blank?
        if needs_levels || needs_desc || sub.name.blank?
          sub.name = data[:name] if data[:name].present?
          sub.subclass_flavor = data[:flavor] if data[:flavor].present?
          sub.description = data[:description] if needs_desc && data[:description].present?
          if needs_levels && data[:levels].present?
            sub.levels_json = data[:levels].to_json
          end
          sub.save!
          puts "    • Override aplicado: #{sub.api_index} (#{sub.name})"
        end
      end
    end

    def fetch(path, limit = 5)
      raise 'redirect too deep' if limit <= 0
      uri = URI(BASE + path)
      res = Net::HTTP.get_response(uri)
      case res
      when Net::HTTPSuccess
        begin
          return JSON.parse(res.body)
        rescue JSON::ParserError => e
          puts "  • JSON inválido em #{path}: #{e.message}"
          return nil
        end
      when Net::HTTPRedirection
        location = res['location']
        if location
          new_uri = URI(location)
          # normaliza para path relativo do mesmo host
          new_path = new_uri.path
          return fetch(new_path, limit - 1)
        end
        puts "  • Redirecionado sem Location em #{path}"
        nil
      else
        puts "  • Erro HTTP #{res.code} em #{path}"
        nil
      end
    end

    def fetch_first(paths)
      Array(paths).each do |p|
        data = fetch(p)
        return data if data.present?
      end
      nil
    end

    def ensure_phb_background_fallbacks!(already_imported)
      # Build a set of indexes already present (from API import or existing DB)
      imported = already_imported.map(&:to_s).to_set
      phb_background_catalog.each do |slug, meta|
        next if imported.include?(slug)
        # Skip if DB already has it
        next if Background.where(api_index: slug).exists?

        # Preferir YAML se disponível
        yaml_path = Rails.root.join('config','backgrounds_phb.yml')
        if File.exist?(yaml_path)
          begin
            yml = YAML.load_file(yaml_path) || {}
            bg_data = yml.dig('backgrounds', slug)
            if bg_data.present?
              feat = bg_data['feature'] || {}
              Background.create!(
                api_index: slug,
                name: bg_data['name'] || meta[:name_pt],
                feature_name: feat['name'],
                feature_desc: Array(feat['desc']).join("\n\n"),
                data_json: bg_data.to_json
              )
              puts "  • (fallback YAML) #{bg_data['name'] || meta[:name_pt]}"
              next
            end
          rescue => e
            warn "[fallback backgrounds] erro ao ler YAML: #{e.message}"
          end
        end

        # Fallback mínimo a partir do livro
        name_pt = meta[:name_pt]
        feat_name_pt, feat_desc_pt = extract_feature_block(meta[:feature_title_pt])
        data_hash = {
          index: slug,
          name: name_pt,
          feature: { name: feat_name_pt, desc: Array(feat_desc_pt.to_s.split(/\n{2,}/)).presence || [] }
        }
        Background.create!(
          api_index: slug,
          name: name_pt,
          feature_name: feat_name_pt,
          feature_desc: feat_desc_pt,
          data_json: data_hash.to_json
        )
        puts "  • (fallback livro) #{name_pt}"
      end
    end

    # === MAGIAS ===
    unless ENV['SKIP_ALL_SPELLS']
      puts "Importando magias… (todas)"
      # lista todas as magias (tenta /api, /api/2014 e /v1)
      list = fetch_first(['/api/spells','/api/2014/spells','/v1/spells']) || {}
      spells_index = list['results'] || []

      spells_index.each do |s|
        data = fetch(s['url'])
        next unless data

        spell = Spell.find_or_initialize_by(api_index: data['index'] || data['slug'] || data['name'].to_s.parameterize)
        school_name = data['school'].is_a?(Hash) ? data.dig('school','name') : data['school']
        school_pt   = tr_pt('schools', school_name, PT_SCHOOL_MAP[school_name] || school_name)
        name_pt     = tr_pt('spells', (data['index'] || data['slug']), data['name'])
        mark_missing('schools', school_name, school_name) if school_pt == school_name && !PT_SCHOOL_MAP.key?(school_name)
        mark_missing('spells', (data['index'] || data['slug'] || data['name'].to_s.parameterize), data['name']) if name_pt == data['name']
        spell.update!(
          name:          name_pt,
          level:         data['level'],
          school:        school_pt,
          range:         data['range'],
          components:    Array(data['components']).to_json,
          material:      data['material'],
          ritual:        data['ritual'],
          duration:      data['duration'],
          concentration: data['concentration'],
          casting_time:  data['casting_time'],
          desc:          Array(data['desc']).to_json,
          higher_level:  Array(data['higher_level']).to_json
        )
        puts "  • #{spell.name}"
      end
    else
      puts "Pulando importação global de magias (SKIP_ALL_SPELLS=1)"
    end

    # === ANTECEDENTES (Backgrounds) ===
    unless ENV['SKIP_BACKGROUNDS']
      puts "\nImportando backgrounds (antecedentes)…"
      imported_bg_indexes = []
      bg_list = fetch_first(['/api/backgrounds','/api/2014/backgrounds','/v1/backgrounds']) || {}
      (bg_list['results'] || []).each do |b|
        b_data = fetch_first([b['url'], "/api/2014/backgrounds/#{b['index']}", "/api/backgrounds/#{b['index']}"]) || {}
        idx = b_data['index'] || b['index'] || b['name'].to_s.parameterize
        name_pt = tr_pt('backgrounds', idx, (b_data['name'] || b['name']))
        mark_missing('backgrounds', idx, (b_data['name'] || b['name'])) if name_pt == (b_data['name'] || b['name'])

        feature = b_data['feature'] || {}
        f_name = feature['name']
        f_desc_en = Array(feature['desc']).join("\n\n")
        f_desc_pt = tr_pt('background_descs', idx, f_desc_en)
        mark_missing('background_descs', idx, f_desc_en) if f_desc_pt == f_desc_en && f_desc_en.present?

        payload = {
          name: name_pt,
          feature_name: f_name,
          feature_desc: f_desc_pt,
          data_json: b_data.to_json
        }
        rec = Background.find_or_initialize_by(api_index: idx)
        rec.update!(payload)
        imported_bg_indexes << rec.api_index
        puts "  • #{rec.name}"
      end

      # Fallback: ensure PHB backgrounds exist, parsing feature from docs/livro_do_jogador.txt
      begin
        ensure_phb_background_fallbacks!(imported_bg_indexes)
      rescue => e
        warn "[fallback backgrounds] aviso: #{e.message}"
      end
    else
      puts "Pulando importação de backgrounds (SKIP_BACKGROUNDS=1)"
    end

    # === ALINHAMENTOS (Alignments) ===
    unless ENV['SKIP_ALIGNMENTS']
      puts "\nImportando alinhamentos…"
      al_list = fetch_first(['/api/alignments','/api/2014/alignments','/v1/alignments']) || {}
      (al_list['results'] || []).each do |a|
        a_data = fetch_first([a['url'], "/api/2014/alignments/#{a['index']}", "/api/alignments/#{a['index']}"]) || {}
        idx = a_data['index'] || a['index'] || a['name'].to_s.parameterize
        name_pt = tr_pt('alignments', idx, (a_data['name'] || a['name']))
        mark_missing('alignments', idx, (a_data['name'] || a['name'])) if name_pt == (a_data['name'] || a['name'])
        abbr = a_data['abbreviation'] || a_data['abbr']
        desc_en = a_data['desc'].to_s
        desc_pt = tr_pt('alignment_descs', idx, desc_en)
        mark_missing('alignment_descs', idx, desc_en) if desc_pt == desc_en && desc_en.present?

        rec = Alignment.find_or_initialize_by(api_index: idx)
        rec.update!(name: name_pt, abbreviation: abbr, desc: desc_pt)
        puts "  • #{rec.name} (#{rec.abbreviation})"
      end
    else
      puts "Pulando importação de alinhamentos (SKIP_ALIGNMENTS=1)"
    end

    # === TRAITS (opcional) ===
    unless ENV['SKIP_TRAITS']
      puts "\nImportando traits (traços raciais)…"
      traits_list = fetch_first(['/api/traits','/api/2014/traits','/v1/traits']) || {}
      (traits_list['results'] || []).each do |t|
        t_data = fetch_first([t['url'], "/api/2014/traits/#{t['index']}", "/api/traits/#{t['index']}"])
        next unless t_data
        api_idx = t_data['index'] || t_data['slug'] || t_data['name'].to_s.parameterize
        name_pt = tr_pt('traits', api_idx, t_data['name'])
        mark_missing('traits', api_idx, t_data['name']) if name_pt == t_data['name']
        desc_en = Array(t_data['desc']).join("\n\n")
        desc_pt = tr_pt('trait_descs', api_idx, desc_en)
        mark_missing('trait_descs', api_idx, desc_en) if desc_pt == desc_en && desc_en.present?
        Trait.find_or_initialize_by(api_index: api_idx).tap do |tt|
          tt.name = name_pt
          tt.description = desc_pt
          tt.save!
        end
      end
    else
      puts "Pulando importação de traits (SKIP_TRAITS=1)"
    end

    # === CLASSES ===
    puts "\nImportando classes…"
    cls_list = fetch_first(['/api/classes','/api/2014/classes','/v1/classes']) || {}
    classes_index = cls_list['results'] || []

    only = (ENV['CLASSES'] || '').split(',').map(&:strip).reject(&:empty?)

    classes_index.each do |c|
      next if only.any? && !only.include?(c['index'])
      klass_data = fetch(c['url'])  # "/api/classes/wizard" (ou equivalente)
      next unless klass_data

      klass = Klass.find_or_initialize_by(api_index: klass_data['index'])
      name_pt = tr_pt('classes', klass_data['index'], klass_data['name'])
      mark_missing('classes', klass_data['index'], klass_data['name']) if name_pt == klass_data['name']
      klass.update!(
        name:                  name_pt,
        hit_die:               klass_data['hit_die'],
        spellcasting_ability:  klass_data.dig('spellcasting','spellcasting_ability','name')
      )

      klass.class_levels.destroy_all
      levels = fetch_first([
        "/api/classes/#{klass.api_index}/levels",
        "/api/2014/classes/#{klass.api_index}/levels",
        "/v1/classes/#{klass.api_index}/levels",
        "/v1/levels?class=#{klass.api_index}"
      ]) || []
      levels.each do |lvl|
        lvl_rec = klass.class_levels.create!(
          level:                  lvl['level'],
          prof_bonus:            lvl['prof_bonus'],
          ability_score_bonuses: lvl['ability_score_bonuses']
        )
        (lvl['features'] || []).each do |feat|
          api_idx = (feat['index'] || feat['slug'] || feat['name'].to_s.parameterize)
          fname   = tr_pt('features', api_idx, feat['name'])
          mark_missing('features', api_idx, feat['name']) if fname == feat['name']

          # Fetch feature details for description (try both 2014 + default)
          f_data = fetch_first([
            feat['url'],
            (feat['url'].to_s.include?('/2014/') ? feat['url'].to_s.sub('/2014','') : "/api/2014/features/#{api_idx}")
          ]) || {}
          desc_en = Array(f_data['desc']).join("\n\n")
          fdesc_pt = tr_pt('feature_descs', api_idx, desc_en)
          mark_missing('feature_descs', api_idx, desc_en) if fdesc_pt == desc_en && desc_en.present?

          f = Feature.find_or_initialize_by(api_index: api_idx)
          f.name = fname
          f.description = fdesc_pt if f.respond_to?(:description=)
          f.category = :class_feature if f.respond_to?(:category) && f.category.blank?
          f.save!
          lvl_rec.features << f unless lvl_rec.features.include?(f)
        end
        # Deriva spellcasting/slots do payload por nível
        sc = lvl['spellcasting']
        slot_map = {}
        # slots espalhados como spell_slots_level_X (dnd5eapi 2014) — estão dentro de spellcasting
        (1..9).each do |n|
          key = "spell_slots_level_#{n}"
          val = sc && sc[key]
          slot_map[n.to_s] = val if val && val.to_i > 0
        end
        # fallback: slots em hash (5e-bits)
        if slot_map.empty? && sc && sc['slots'].is_a?(Hash)
          sc['slots'].each do |k,v|
            num = k.to_s.scan(/\d+/).first
            slot_map[num] = v if num && v.to_i > 0
          end
        end
        if sc || slot_map.any?
          # Deriva nível de magia permitido neste nível (maior nível com slots > 0)
          max_slot_level = slot_map.keys.map(&:to_i).max.to_i
          attrs = {
            level:          max_slot_level, # nível de magia permitido (não confundir com nível da classe)
            cantrips_known: sc&.dig('cantrips_known'),
            spells_known:   sc&.dig('spells_known'),
            spell_slots:    slot_map.to_json
          }
          # Pact magic (Warlock): deduz do maior nível com slots > 0 (slots são todos daquele nível)
          if klass.api_index == 'warlock' && slot_map.any?
            pact_lvl, pact_qty = slot_map.max_by { |k,v| k.to_i }
            attrs[:pact_slot_level] = pact_lvl.to_i
            attrs[:pact_slots] = { 'pact' => pact_qty }.to_json
            # para warlock, 'level' também deve refletir o nível do pacto
            attrs[:level] = pact_lvl.to_i
          end
          lvl_rec.create_spellcasting!(attrs)
        end
        puts "  • #{klass.name} niv.#{lvl_rec.level}"
      end

      # Importar subclasses e seus níveis/descrições
      puts "  • Importando subclasses para #{klass.name}…"
      sub_list = fetch_first([
        "/api/classes/#{klass.api_index}/subclasses",
        "/api/2014/classes/#{klass.api_index}/subclasses",
        "/v1/subclasses?class=#{klass.api_index}",
        "/api/subclasses?class=#{klass.api_index}"
      ]) || {}
      (sub_list['results'] || []).each do |sc|
        sdata = fetch_first([sc['url'], "/api/2014/subclasses/#{sc['index']}", "/api/subclasses/#{sc['index']}"]) || {}
        sub_idx = (sdata['index'] || sc['index'] || sc['name'].to_s.parameterize)
        sname_pt = tr_pt('subclasses', sub_idx, (sdata['name'] || sc['name']))
        mark_missing('subclasses', sub_idx, (sdata['name'] || sc['name'])) if sname_pt == (sdata['name'] || sc['name'])
        desc_en = Array(sdata['desc']).join("\n\n")
        sdesc_pt = tr_pt('subclass_descs', sub_idx, desc_en)
        mark_missing('subclass_descs', sub_idx, desc_en) if sdesc_pt == desc_en && desc_en.present?
        flavor = sdata['subclass_flavor']

        # Subclass levels and features
        levels_data = []
        begin
          sub_lvls = fetch_first([sdata['subclass_levels'], "/api/2014/subclasses/#{sub_idx}/levels"]) || []
          sub_lvls.each do |row|
            lvl_no = row['level']
            feats = []
            Array(row['features']).each do |rf|
              fdet = fetch_first([rf['url'], "/api/2014/features/#{rf['index']}"]) || {}
              fname = tr_pt('features', (fdet['index'] || rf['index']), (fdet['name'] || rf['name']))
              fdesc = tr_pt('feature_descs', (fdet['index'] || rf['index']), Array(fdet['desc']).join("\n\n"))
              mark_missing('features', (fdet['index'] || rf['index']), (fdet['name'] || rf['name'])) if fname == (fdet['name'] || rf['name'])
              feats << { index: (fdet['index'] || rf['index']), name: fname, description: fdesc }
            end
            levels_data << { level: lvl_no, features: feats }
          end
        rescue => e
          puts "    • Falha ao carregar níveis da subclasse #{sub_idx}: #{e.message}"
        end

        sub = SubKlass.find_or_initialize_by(api_index: sub_idx, klass_id: klass.id)
        sub.name = sname_pt
        sub.klass_id = klass.id
        sub.subclass_flavor = flavor
        sub.description = sdesc_pt
        sub.levels_json = levels_data.to_json
        sub.save!

        # Populate normalized SubKlassLevels + features linkage (idempotent)
        begin
          parsed = JSON.parse(sub.levels_json) rescue []
          parsed.each do |row|
            lvl = sub.sub_klass_levels.find_or_create_by!(level: row['level'].to_i)
            Array(row['features']).each do |f|
              api_idx = (f['index'] || f['name'].to_s.parameterize)
              ft = Feature.find_or_initialize_by(api_index: api_idx)
              ft.name = f['name'] if ft.name.blank?
              ft.description = f['description'] if ft.respond_to?(:description=) && ft.description.blank?
              ft.category = :subclass_feature if ft.respond_to?(:category) && ft.category.blank?
              ft.save!
              lvl.features << ft unless lvl.features.exists?(ft.id)
            end
          end
        rescue => e
          puts "    • Falha ao normalizar níveis da subclasse #{sub_idx}: #{e.message}"
        end
      end

      # Aplicar overrides manuais para subclasses com dados ausentes
      apply_subclass_overrides!(klass)

      # Importar magias concedidas por Subclasses (ex.: Domínios do Clérigo, Juramentos do Paladino, Círculos do Druida)
      # 5e API costuma expor em /api/subclasses/:index/spells e/ou /api/2014/subclasses/:index/spells
      begin
        subs_for_class = SubKlass.where(klass_id: klass.id)
        subs_for_class.find_each do |sub|
          next if sub.api_index.blank?
          sc_spells = fetch_first([
            "/api/subclasses/#{sub.api_index}/spells",
            "/api/2014/subclasses/#{sub.api_index}/spells",
            "/v1/subclasses/#{sub.api_index}/spells"
          ]) || {}
          total = 0
          (sc_spells['results'] || []).each do |sp|
            sp_data = fetch(sp['url'])
            next unless sp_data
            db_spell = Spell.find_or_initialize_by(api_index: (sp_data['index'] || sp_data['slug'] || sp_data['name'].to_s.parameterize))
            school_name = sp_data['school'].is_a?(Hash) ? sp_data.dig('school','name') : sp_data['school']
            db_spell.update!(
              name:          sp_data['name'],
              level:         sp_data['level'],
              school:        school_name,
              range:         sp_data['range'],
              components:    Array(sp_data['components']).to_json,
              material:      sp_data['material'],
              ritual:        sp_data['ritual'],
              duration:      sp_data['duration'],
              concentration: sp_data['concentration'],
              casting_time:  sp_data['casting_time'],
              desc:          Array(sp_data['desc']).to_json,
              higher_level:  Array(sp_data['higher_level']).to_json
            )
            # Tentar detectar o nível mínimo a partir de 'prerequisites'
            min_level = nil
            begin
              prereq = Array(sp_data['prerequisites']) + Array(sp['prerequisites'])
              maybe = prereq.find { |p| p.is_a?(Hash) && (p['level'] || p['minimum_level'] || p['min_level']) }
              min_level = (maybe && (maybe['level'] || maybe['minimum_level'] || maybe['min_level'])).to_i if maybe
              min_level = nil if min_level && min_level <= 0
            rescue
              min_level = nil
            end
            SpellSource.find_or_create_by!(source_type: 'SubKlass', source_id: sub.id, spell_id: db_spell.id) do |ss|
              ss.always_prepared = true
              ss.min_class_level = min_level if min_level
              ss.notes = 'Importado do endpoint de Subclasse — marcado como sempre preparado'
            end
            total += 1
          end
          puts "  • Subclasse #{sub.name}: #{total} magias vinculadas (sempre preparadas)" if total > 0
        end
      rescue => e
        puts "  • Aviso: falha ao importar magias de subclasses para #{klass.name}: #{e.message}"
      end

      # Importar lista de magias da classe para SpellSource (se endpoint existir)
      class_spells = fetch_first([
        "/api/classes/#{klass.api_index}/spells",
        "/api/2014/classes/#{klass.api_index}/spells",
        "/v1/classes/#{klass.api_index}/spells"
      ]) || {}
      spells_total = 0
      cantrips_total = 0
      (class_spells['results'] || []).each do |sp|
        sp_data = fetch(sp['url'])
        next unless sp_data
        spells_total += 1
        cantrips_total += 1 if sp_data['level'].to_i == 0
        db_spell = Spell.find_or_initialize_by(api_index: (sp_data['index'] || sp_data['slug'] || sp_data['name'].to_s.parameterize))
        school_name = sp_data['school'].is_a?(Hash) ? sp_data.dig('school','name') : sp_data['school']
        db_spell.update!(
          name:          sp_data['name'],
          level:         sp_data['level'],
          school:        school_name,
          range:         sp_data['range'],
          components:    Array(sp_data['components']).to_json,
          material:      sp_data['material'],
          ritual:        sp_data['ritual'],
          duration:      sp_data['duration'],
          concentration: sp_data['concentration'],
          casting_time:  sp_data['casting_time'],
          desc:          Array(sp_data['desc']).to_json,
          higher_level:  Array(sp_data['higher_level']).to_json
        )
        SpellSource.find_or_create_by!(source_type: 'Klass', source_id: klass.id, spell_id: db_spell.id)
      end
      puts "  • #{klass.name}: #{spells_total} magias (#{cantrips_total} cantrips) vinculadas à classe"
    end

    # Dump missing translations to a TODO yaml for convenience
    unless MISSING.empty?
      require 'fileutils'
      cfg_dir = Rails.root.join('config')
      FileUtils.mkdir_p(cfg_dir)
      todo_path = cfg_dir.join('dnd_translations.todo.yml')
      sorted = MISSING.transform_values { |h| h.sort.to_h }
      File.open(todo_path, 'w') do |f|
        f.puts sorted.to_yaml
      end
      puts "\nTraduções pendentes salvas em #{todo_path} (preencha e mova para dnd_translations.yml)."
    end

    puts "\nImportação concluída!"
  end

  desc "Extrai Backgrounds do Livro do Jogador e gera YAML em config/backgrounds_phb.yml"
  task extract_backgrounds_yml: :environment do
    out_path = Rails.root.join('config','backgrounds_phb.yml')
    bgs = build_backgrounds_from_book
    data = { 'version' => 1, 'source' => File.basename(livro_do_jogador_path), 'backgrounds' => bgs }
    File.open(out_path, 'w:UTF-8') { |f| f.write(data.to_yaml) }
    puts "Gerado: #{out_path} (#{bgs.keys.size} backgrounds)"
  end

  desc "Relatório das SubKlasses e campos ausentes"
  task report_subclasses: :environment do
    puts "Listando SubKlasses…"
    header = %w[id klass api_index name desc? levels]
    puts header.join(" | ")
    puts "-" * 72
    missing = []
    SubKlass.includes(:klass).order('klasses.name asc, sub_klasses.name asc').find_each do |s|
      level_count = begin
        lj = s.levels_json.to_s
        lj.present? ? (JSON.parse(lj) rescue []).size : 0
      rescue
        0
      end
      has_desc = s.description.present? ? 1 : 0
      row = [s.id, s.klass&.name || '-', s.api_index || '-', s.name || '-', has_desc, level_count]
      puts row.join(" | ")
      missing << s if has_desc == 0 || level_count == 0
    end
    puts "\nFaltando informação: #{missing.size} SubKlasses (sem descrição e/ou sem níveis)"
  end

  desc "Remove SubKlasses legadas sem api_index e sem dados (não referenciadas)"
  task cleanup_subclasses_legacy: :environment do
    doomed = SubKlass.where("(api_index IS NULL OR api_index = '' OR api_index = '-') AND (COALESCE(description,'') = '' OR COALESCE(levels_json,'') = '')")
    doomed = doomed.left_joins(:klass).left_joins("LEFT JOIN sheet_klasses sk ON sk.sub_klass_id = sub_klasses.id")
    doomed = doomed.where("sk.id IS NULL") # não remover se houver referência em sheet_klasses
    count = doomed.count
    if count.zero?
      puts "Nada para remover."
    else
      rows = doomed.pluck(:id, :name)
      doomed.delete_all
      puts "Removidos #{count} registros de SubKlass sem dados: #{rows.map{|r| "##{r[0]}(#{r[1]})"}.join(', ')}"
    end
  end
end
