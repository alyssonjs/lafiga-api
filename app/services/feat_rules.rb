class FeatRules
  # Define all available feats with their rules
  RULES = {
    'observador' => {
      id: 'observador',
      name: 'Observador',
      description: 'Você desenvolveu uma atenção especial aos detalhes e uma memória aguçada.',
      prerequisites: { ability_score: { wis: 13 } },
      ability_bonuses: { wis: 1, int: 1 },
      proficiency_bonuses: { skills: ['Percepção'] },
      features: {
        name: 'Observador',
        desc: 'Você pode ler lábios quando pode ver a criatura falando e entende o idioma. Você tem vantagem em testes de Investigação e Percepção.'
      }
    },
    'duravel' => {
      id: 'duravel',
      name: 'Durável',
      description: 'Você desenvolveu uma resistência excepcional.',
      prerequisites: { ability_score: { con: 13 } },
      ability_bonuses: { con: 1 },
      proficiency_bonuses: {},
      features: {
        name: 'Durável',
        desc: 'Quando você rola um dado de vida para recuperar pontos de vida, você pode rerrolar o dado se rolar um 1 e deve usar o novo resultado.'
      }
    },
    'atirador_agucado' => {
      id: 'atirador_agucado',
      name: 'Atirador Aguçado',
      description: 'Você é um especialista em ataques à distância.',
      prerequisites: { ability_score: { dex: 13 } },
      ability_bonuses: { dex: 1 },
      proficiency_bonuses: {},
      features: {
        name: 'Atirador Aguçado',
        desc: 'Você ignora a cobertura parcial e a cobertura de três quartos. Você não tem desvantagem em ataques à distância quando está dentro de 1,5 metro de um inimigo hostil.'
      }
    },
    'sentinela' => {
      id: 'sentinela',
      name: 'Sentinela',
      description: 'Você desenvolveu uma habilidade especial para proteger os outros.',
      prerequisites: { ability_score: { str: 13, con: 13 } },
      ability_bonuses: { str: 1, con: 1 },
      proficiency_bonuses: {},
      features: {
        name: 'Sentinela',
        desc: 'Quando você atinge uma criatura com um ataque de oportunidade, a velocidade da criatura se torna 0 pelo resto do turno. Criaturas provocam ataques de oportunidade mesmo quando se afastam de você usando a ação Disparar.'
      }
    },
    'resiliente' => {
      id: 'resiliente',
      name: 'Resiliente',
      description: 'Você desenvolveu uma resistência mental excepcional.',
      prerequisites: {},
      ability_bonuses: { choose: { amount: 1, options: ['str', 'dex', 'con', 'int', 'wis', 'cha'] } },
      proficiency_bonuses: { saving_throws: { choose: { amount: 1, options: ['str', 'dex', 'con', 'int', 'wis', 'cha'] } } },
      features: {
        name: 'Resiliente',
        desc: 'Você ganha proficiência em uma salvaguarda de sua escolha.'
      }
    },
    'atleta' => {
      id: 'atleta',
      name: 'Atleta',
      description: 'Você desenvolveu uma habilidade atlética excepcional.',
      prerequisites: { ability_score: { str: 13 } },
      ability_bonuses: { choose: { amount: 1, options: ['str', 'dex'] } },
      proficiency_bonuses: { skills: ['Atletismo'] },
      features: {
        name: 'Atleta',
        desc: 'Você pode escalar sem gastar movimento extra. Você pode fazer um salto em distância ou altura após se mover apenas 1,5 metro a pé, em vez de 3 metros.'
      }
    },
    'especialista_em_armas' => {
      id: 'especialista_em_armas',
      name: 'Especialista em Armas',
      description: 'Você desenvolveu uma habilidade especial com armas.',
      prerequisites: { ability_score: { str: 13 } },
      ability_bonuses: { choose: { amount: 1, options: ['str', 'dex'] } },
      proficiency_bonuses: { weapons: { choose: { amount: 4, options: ['arma_simples', 'arma_marcial'] } } },
      features: {
        name: 'Especialista em Armas',
        desc: 'Você ganha proficiência com quatro armas de sua escolha.'
      }
    },
    'magico_iniciante' => {
      id: 'magico_iniciante',
      name: 'Mágico Iniciante',
      description: 'Você aprendeu alguns truques de magia.',
      prerequisites: {},
      ability_bonuses: { choose: { amount: 1, options: ['int', 'wis', 'cha'] } },
      proficiency_bonuses: {},
      cantrips: { choose: { amount: 2, class_options: ['mago', 'bruxo', 'bardo', 'clérigo', 'druida', 'feiticeiro', 'paladino', 'patrulheiro'] } },
      spells: { choose: { amount: 1, level: 1, class_options: ['mago', 'bruxo', 'bardo', 'clérigo', 'druida', 'feiticeiro', 'paladino', 'patrulheiro'] } },
      features: {
        name: 'Mágico Iniciante',
        desc: 'Você aprende dois truques de uma lista de magias de uma classe de sua escolha. Você também aprende uma magia de 1º nível dessa mesma lista.'
      }
    },
    'especialista_em_armadura' => {
      id: 'especialista_em_armadura',
      name: 'Especialista em Armadura',
      description: 'Você desenvolveu uma habilidade especial com armaduras.',
      prerequisites: { ability_score: { str: 15 } },
      ability_bonuses: { str: 1 },
      proficiency_bonuses: { armor: ['armadura_pesada'] },
      features: {
        name: 'Especialista em Armadura',
        desc: 'Você ganha proficiência com armaduras pesadas.'
      }
    },
    'especialista_em_escudo' => {
      id: 'especialista_em_escudo',
      name: 'Especialista em Escudo',
      description: 'Você desenvolveu uma habilidade especial com escudos.',
      prerequisites: { ability_score: { str: 13 } },
      ability_bonuses: { choose: { amount: 1, options: ['str', 'dex'] } },
      proficiency_bonuses: {},
      features: {
        name: 'Especialista em Escudo',
        desc: 'Você pode usar escudos como armas improvisadas. Quando você usa um escudo como arma, ele causa 1d4 de dano contundente.'
      }
    }
  }.with_indifferent_access.freeze

  def self.all
    RULES
  end

  def self.find(feat_id)
    RULES[feat_id]
  end

  def self.apply(feat_id, choices = {})
    feat = find(feat_id)
    raise ArgumentError, 'feat não encontrado' unless feat

    # Get ability bonuses
    ability_bonuses = feat[:ability_bonuses] || {}
    if ability_bonuses[:choose]
      chosen_ability = choices[:ability] || choices['ability']
      ability_bonuses = { chosen_ability => ability_bonuses[:choose][:amount] } if chosen_ability
    end

    # Get proficiency bonuses
    proficiency_bonuses = feat[:proficiency_bonuses] || {}
    if proficiency_bonuses[:choose]
      chosen_proficiencies = choices[:proficiencies] || choices['proficiencies'] || []
      proficiency_bonuses = { 'skills' => chosen_proficiencies } if chosen_proficiencies.any?
    end

    # Get cantrips
    cantrips = feat[:cantrips] || {}
    if cantrips[:choose]
      chosen_cantrips = choices[:cantrips] || choices['cantrips'] || []
      cantrips = { 'cantrips' => chosen_cantrips } if chosen_cantrips.any?
    end

    # Get spells
    spells = feat[:spells] || {}
    if spells[:choose]
      chosen_spells = choices[:spells] || choices['spells'] || []
      spells = { 'spells' => chosen_spells } if chosen_spells.any?
    end

    {
      key: feat[:id],
      name: feat[:name],
      description: feat[:description],
      ability_bonuses: ability_bonuses,
      proficiency_bonuses: proficiency_bonuses,
      cantrips: cantrips,
      spells: spells,
      features: feat[:features] || {}
    }
  end

  def self.check_prerequisites(feat_id, sheet)
    feat = find(feat_id)
    return false unless feat

    prereqs = feat[:prerequisites] || {}
    Rails.logger.info "=== check_prerequisites Debug ==="
    Rails.logger.info "feat_id: #{feat_id}"
    Rails.logger.info "prereqs: #{prereqs.inspect}"
    Rails.logger.info "sheet attributes: str=#{sheet.str}, dex=#{sheet.dex}, con=#{sheet.con}, int=#{sheet.int}, wis=#{sheet.wis}, cha=#{sheet.cha}"
    
    # Check ability score prerequisites
    if prereqs[:ability_score]
      prereqs[:ability_score].each do |ability, min_score|
        current_score = sheet.send(ability.downcase) || 0
        Rails.logger.info "Checking #{ability}: current=#{current_score}, required=#{min_score}"
        if current_score < min_score
          Rails.logger.error "Prerequisite failed: #{ability} #{current_score} < #{min_score}"
          return false
        end
      end
    end

    # Check other prerequisites (level, class, etc.)
    # TODO: Implement other prerequisite checks as needed

    Rails.logger.info "All prerequisites met"
    true
  end
end
