class FeatRules
  # Nome canônico de cada perícia conforme `config/skills.yml` (PHB PT-BR).
  # NÃO usar 'Adestrar Animais' — o canônico é 'Lidar com Animais'. Manter
  # essa lista alinhada com `config/skills.yml` evita divergência de match
  # quando services/yamls referenciam perícias por nome.
  CANONICAL_SKILL_NAMES = [
    'Atletismo',
    'Acrobacia', 'Furtividade', 'Prestidigitação',
    'Arcanismo', 'História', 'Investigação', 'Natureza', 'Religião',
    'Lidar com Animais', 'Intuição', 'Medicina', 'Percepção', 'Sobrevivência',
    'Atuação', 'Enganação', 'Intimidação', 'Persuasão'
  ].freeze

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
      # PT alternativo usado em fichas legadas / planilhas de jogadores
      # (campanhas antigas anotam como "Iniciado em Magia" ou EN "Magic Initiate").
      aliases: ['Iniciado em Magia', 'Iniciado em magia', 'Magic Initiate'],
      description: 'Você aprendeu alguns truques de magia.',
      prerequisites: {},
      # PHB 5e: Magic Initiate NAO e half-feat — sem +1 atributo. Espelha
      # `config/feats_improved.yml` e `front-lafiga/src/app/data/featsData.ts`.
      # Cobertura: spec da Camada B+ em
      # `front-lafiga/src/app/data/__tests__/feats.parity.bdd.test.ts`.
      ability_bonuses: {},
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
    },
    'mestre_de_armas_duplas' => {
      id: 'mestre_de_armas_duplas',
      name: 'Mestre de Armas Duplas',
      # Apelido coloquial usado em fichas de jogadores ("Ambidestro" e a
      # tradução vernacular comum de Dual Wielder). NAO confundir com
      # o estilo de luta "Combate com Duas Armas" (que e diferente).
      aliases: ['Ambidestro', 'Dual Wielder', 'Two-Weapon Fighting Feat'],
      description: 'Você é treinado para lutar com duas armas ao mesmo tempo.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Mestre de Armas Duplas',
        desc: 'Você pode usar duas armas de uma mão que não sejam leves. Quando você está segurando duas armas de uma mão, você ganha +1 de CA.'
      },
      special_rules: {
        equipment_modifiers: {
          armor_class_bonus: {
            implementation: 'equipment_ac_bonus',
            parameters: { condition: 'duas_armas', bonus: 1 }
          },
          weapon_restriction_removal: {
            implementation: 'remove_weapon_restriction',
            parameters: 'armas_duplas_não_leves'
          },
          dual_wield_draw: {
            implementation: 'dual_wield_draw',
            parameters: { action: 'sacar_ou_guardar', weapons: 2 }
          }
        }
      }
    },
    'mobilidade' => {
      id: 'mobilidade',
      name: 'Mobilidade',
      description: 'Sua velocidade e agilidade superam os oponentes.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Agilidade de Combate',
        desc: 'Seu deslocamento aumenta em 3 m; quando usa Disparada, terreno difícil não custa movimento extra; quando ataca uma criatura, não provoca ataque de oportunidade dela pelo resto do turno.'
      },
      special_rules: {
        movement_modifiers: {
          speed_bonus: {
            implementation: 'add_to_speed',
            parameters: { bonus: 3, unit: 'metros' }
          },
          difficult_terrain_immunity: {
            implementation: 'ignore_difficult_terrain',
            parameters: { condition: 'disparada' }
          }
        },
        combat_modifiers: {
          opportunity_attack_immunity: {
            implementation: 'no_oa_after_attack',
            parameters: { condition: 'após_atacar_criatura' }
          }
        }
      }
    },
    'atirador_eximio' => {
      id: 'atirador_eximio',
      name: 'Atirador Exímio',
      description: 'Treino rigoroso com armas de ataque à distância.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Precisão Letal',
        desc: 'Ignora cobertura leve e média; ataques à longa distância não sofrem desvantagem; antes de atacar, pode aplicar -5 na jogada de ataque para adicionar +10 no dano.'
      },
      special_rules: {
        combat_modifiers: {
          cover_immunity: {
            implementation: 'ignore_cover_types',
            parameters: ['leve', 'média']
          },
          range_advantage: {
            implementation: 'no_long_range_disadvantage',
            parameters: { weapon_type: 'ranged' }
          },
          power_attack: {
            implementation: 'power_attack_option',
            parameters: { attack_penalty: -5, damage_bonus: 10, weapon_type: 'ranged' }
          }
        }
      }
    },
    'mestre_de_armas_grandes' => {
      id: 'mestre_de_armas_grandes',
      name: 'Mestre de Armas Grandes',
      # Sigla "M.A.G." e abreviacao usada em planilhas de campanha
      # para Great Weapon Master.
      aliases: ['M.A.G.', 'MAG', 'Great Weapon Master'],
      description: 'Você aprendeu a usar o peso de armas pesadas a seu favor.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Ataques Poderosos',
        desc: 'Quando acertar um crítico ou reduzir inimigo a 0 PV, pode fazer um ataque corpo a corpo adicional com ação bônus. Antes de atacar com arma pesada proficiente, pode aplicar –5 no ataque para +10 de dano.'
      },
      special_rules: {
        combat_modifiers: {
          bonus_action_attack: {
            implementation: 'bonus_action_attack_on_crit_or_kill',
            parameters: { trigger: ['crítico', 'reduzir_a_0_pv'], attack_type: 'corpo_a_corpo' }
          },
          power_attack: {
            implementation: 'power_attack_option',
            parameters: { attack_penalty: -5, damage_bonus: 10, weapon_type: 'pesada' }
          }
        }
      }
    },
    'sortudo' => {
      id: 'sortudo',
      name: 'Sortudo',
      description: 'Você tem uma sorte incomum que pode inclinar as probabilidades a seu favor.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Pontos de Sorte',
        desc: 'Você tem 3 pontos de sorte. Pode gastar 1 para rolar novamente um d20 (ataque, teste ou salvaguarda) e escolher qual dado usar. Também pode gastar para forçar o inimigo a rolar de novo um ataque contra você. Recupera todos os pontos após um descanso longo.'
      },
      special_rules: {
        dice_modifiers: {
          luck_points: {
            implementation: 'luck_points',
            parameters: { points: 3, recovery: 'descanso_longo', uses: ['ataque', 'teste', 'salvaguarda', 'forçar_rerrolar_inimigo'] }
          }
        }
      }
    },
    'robusto' => {
      id: 'robusto',
      name: 'Robusto',
      description: 'Sua vitalidade é excepcional.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'PV Aumentados',
        desc: 'Seu PV máximo aumenta em 2 × seu nível ao adquirir o talento; depois, +2 PV a cada nível ganho.'
      },
      special_rules: {
        dice_modifiers: {
          hit_points_bonus: {
            implementation: 'hit_points_per_level',
            parameters: { bonus_per_level: 2, retroactive: true }
          }
        }
      }
    },
    'conjurador_de_batalha' => {
      id: 'conjurador_de_batalha',
      name: 'Conjurador de Batalha',
      # PT alternativo / EN: jogadores frequentemente registram como
      # "Conjurador de Guerra" ou "War Caster" (PHB).
      aliases: ['Conjurador de Guerra', 'War Caster'],
      description: 'Treino para conjurar em combate, mesmo com as mãos ocupadas.',
      prerequisites: { spellcasting: true },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Concentração e Gestos',
        desc: 'Pode fazer componentes somáticos mesmo segurando armas/escudo; quando um inimigo provocar seu ataque de oportunidade, você pode usar a reação para conjurar uma magia de 1 ação que tenha apenas um alvo na criatura.'
      },
      special_rules: {
        magic_modifiers: {
          somatic_components_with_hands_full: {
            implementation: 'somatic_with_hands_full',
            parameters: { equipment: ['armas', 'escudo'] }
          },
          spell_as_opportunity_attack: {
            implementation: 'spell_as_oa',
            parameters: { spell_action: '1 ação', target_restriction: 'único alvo' }
          }
        }
      }
    },
    'especialista_em_besta' => {
      id: 'especialista_em_besta',
      name: 'Especialista em Besta',
      description: 'Treino extensivo com bestas.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Domínio de Bestas',
        desc: 'Ignora a propriedade recarga de bestas com as quais é proficiente; estar a 1,5 m de criatura hostil não impõe desvantagem nos ataques à distância; ao usar a ação Atacar com uma arma de uma mão, pode usar a ação bônus para atacar com uma besta de mão carregada empunhada.'
      },
      special_rules: {
        equipment_modifiers: {
          weapon_property_ignore: {
            implementation: 'ignore_weapon_property',
            parameters: { property: 'recarga', weapon_type: 'bestas' }
          }
        },
        combat_modifiers: {
          range_advantage: {
            implementation: 'no_close_range_disadvantage',
            parameters: { weapon_type: 'ranged', condition: '1,5m_de_criatura_hostil' }
          },
          bonus_action_attack: {
            implementation: 'bonus_action_attack',
            parameters: { weapon: 'besta_de_mão', condition: 'após_ataque_com_arma_de_uma_mão' }
          }
        }
      }
    },
    'mestre_do_escudo' => {
      id: 'mestre_do_escudo',
      name: 'Mestre do Escudo',
      description: 'Domina o uso do escudo para ataque e defesa.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Controle Defensivo',
        desc: 'Empurrão (ação bônus) ao atacar; adiciona escudo a testes de DES que afetem só você; reduz a 0 com reação em DES por metade.'
      },
      special_rules: {
        combat_modifiers: {
          bonus_action_shove: {
            implementation: 'bonus_action_shove',
            parameters: { trigger: 'após_ataque', requires: 'escudo' }
          },
          shield_bonus_to_dex_save: {
            implementation: 'shield_bonus_to_dex_save',
            parameters: { self_only: true }
          },
          shield_master_reaction: {
            implementation: 'shield_master_reaction',
            parameters: { reaction: true, requires: 'escudo' }
          }
        }
      }
    },
    'duelista_defensivo' => {
      id: 'duelista_defensivo',
      name: 'Duelista Defensivo',
      description: 'Reage com perícia para se proteger.',
      prerequisites: { ability_score: { dex: 13 } },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Reação Defensiva',
        desc: 'Com arma de finesse, usa reação para adicionar proficiência à CA contra um ataque corpo a corpo.'
      },
      special_rules: {
        defense_modifiers: {
          reaction_ac_bonus: {
            implementation: 'reaction_ac_bonus',
            parameters: 'proficiency_bonus'
          }
        }
      }
    },
    'mestre_arma_de_haste' => {
      id: 'mestre_arma_de_haste',
      name: 'Mestre de Arma de Haste',
      description: 'Controle de alcance e uso da outra extremidade.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Controle de Alcance',
        desc: 'Ataque extra (ação bônus) com extremidade; OA dispara quando entram no seu alcance.'
      },
      special_rules: {
        combat_modifiers: {
          bonus_action_attack: {
            implementation: 'bonus_action_attack',
            parameters: { damage: '1d4', damage_type: 'concussão', weapon: 'extremidade' }
          },
          opportunity_attack_enhancement: {
            implementation: 'oa_on_enter_reach',
            parameters: { weapon_list: ['glaive', 'alabarda', 'lança_longa', 'bordão'] }
          }
        }
      }
    },
    'perito' => {
      id: 'perito',
      name: 'Perito',
      description: 'Versatilidade em perícias e ferramentas.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {
        skills_or_tools: {
          choose: { amount: 3, options: ['qualquer perícia ou ferramenta'] }
        }
      },
      special_rules: {},
      features: {
        name: 'Treinamento Amplo',
        desc: 'Proficiência em três perícias e/ou ferramentas à escolha.'
      }
    },
    'poliglota' => {
      id: 'poliglota',
      name: 'Poliglota',
      description: 'Estudioso de idiomas e códigos.',
      prerequisites: {},
      ability_bonuses: { int: 1 },
      proficiency_bonuses: { languages_choose: 3 },
      special_rules: {
        utility_modifiers: {
          create_cipher: {
            implementation: 'create_cipher',
            parameters: { decipher_dc: 'int_mod + proficiency_bonus', alt: ['instructor_help', 'magic'] }
          }
        }
      },
      features: {
        name: 'Criptografia',
        desc: 'Cria cifra escrita; outros decifram com instrução, teste de INT (CD INT+prof) ou magia.'
      }
    },
    'protecao_leve' => {
      id: 'protecao_leve',
      name: 'Proteção Leve',
      description: 'Treino com armaduras leves.',
      prerequisites: {},
      ability_bonuses: { str: 1 },
      proficiency_bonuses: { armors: ['leve'] },
      special_rules: {},
      features: {
        name: 'Armadura Leve',
        desc: 'Ganha proficiência com armaduras leves e +1 FOR.'
      }
    },
    'protecao_moderada' => {
      id: 'protecao_moderada',
      name: 'Proteção Moderada',
      description: 'Treino com armaduras médias e escudos.',
      prerequisites: { proficiencies: { armors: ['leve'] } },
      ability_bonuses: { str: 1 },
      proficiency_bonuses: { armors: ['média'], shields: true },
      special_rules: {},
      features: {
        name: 'Armadura Média + Escudo',
        desc: 'Proficiência com armaduras médias e escudos e +1 FOR.'
      }
    },
    'protecao_pesada' => {
      id: 'protecao_pesada',
      name: 'Proteção Pesada',
      description: 'Treino com armaduras pesadas.',
      prerequisites: { proficiencies: { armors: ['média'] } },
      ability_bonuses: { str: 1 },
      proficiency_bonuses: { armors: ['pesada'] },
      special_rules: {},
      features: {
        name: 'Armadura Pesada',
        desc: 'Proficiência com armaduras pesadas e +1 FOR.'
      }
    },
    'duelista_montado' => {
      id: 'duelista_montado',
      name: 'Duelista Montado',
      description: 'Domina combate montado.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Controle de Montaria',
        desc: 'Vantagem vs. criaturas menores que a montaria; pode fazer ataques contra a montaria mirarem em você; DES/½ vira 0 p/ montaria se passar.'
      },
      special_rules: {
        combat_modifiers: {
          advantage_vs_smaller: {
            implementation: 'advantage_melee_vs_smaller_than_mount',
            parameters: {}
          },
          redirect_attack_to_self: {
            implementation: 'redirect_attack_from_mount',
            parameters: { once_per_turn: true }
          },
          mount_evasion_like: {
            implementation: 'dex_save_half_to_zero_for_mount',
            parameters: { on_success: 'no_damage' }
          }
        }
      }
    },
    'atacante_selvagem' => {
      id: 'atacante_selvagem',
      name: 'Atacante Selvagem',
      description: 'Brutalidade amplifica seus golpes.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Dano Brutal',
        desc: 'Uma vez por turno, pode rerrolar dados de dano de ataque corpo a corpo e escolher o resultado.'
      },
      special_rules: {
        dice_modifiers: {
          damage_reroll: {
            implementation: 'damage_reroll',
            parameters: { frequency: 'once_per_turn', attack_type: 'melee' }
          }
        }
      }
    },
    'sorrateiro' => {
      id: 'sorrateiro',
      name: 'Sorrateiro',
      description: 'Mestre em mover-se nas sombras.',
      prerequisites: { ability_score: { dex: 13 } },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Predador das Sombras',
        desc: 'Pode se esconder quando levemente obscurecido; errar um ataque à distância não revela sua posição; penumbra não impõe desvantagem em Percepção (visão).'
      },
      special_rules: {
        movement_modifiers: {
          stealth_conditions: {
            implementation: 'stealth_in_light_obscurement',
            parameters: {}
          }
        },
        combat_modifiers: {
          missed_ranged_attack_does_not_reveal: {
            implementation: 'stay_hidden_on_missed_ranged_attack',
            parameters: {}
          }
        },
        skill_modifiers: {
          dim_light_no_disadvantage_on_perception: {
            implementation: 'remove_dim_light_perception_disadvantage',
            parameters: {}
          }
        }
      }
    },
    'lider_inspirador' => {
      id: 'lider_inspirador',
      name: 'Líder Inspirador',
      description: 'Você encoraja aliados com um discurso vigoroso.',
      prerequisites: { ability_score: { cha: 13 } },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Discurso Inspirador',
        desc: 'Após 10 min, até 6 criaturas (incluindo você) ganham PV temporários iguais ao seu nível + mod. de Carisma; cada criatura só pode receber novamente após descanso curto ou longo.'
      },
      special_rules: {
        temporary_hp_modifiers: {
          inspiring_speech: {
            implementation: 'grant_temp_hp_after_speech',
            parameters: {
              cast_time: '10_minutos',
              targets_max: 6,
              include_self: true,
              amount_formula: { level: 'self_level', ability_mod: 'cha_mod', sum: true },
              cooldown: { per_target: true, refresh: ['short_rest', 'long_rest'] }
            }
          }
        }
      }
    },
    'explorador_de_cavernas' => {
      id: 'explorador_de_cavernas',
      name: 'Explorador de Cavernas',
      description: 'Alerta a armadilhas e portas secretas.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Farejador de Perigos',
        desc: 'Vantagem para achar portas secretas; vantagem em salvaguardas contra armadilhas e resistência ao dano delas; pode procurar armadilhas em ritmo normal.'
      },
      special_rules: {
        skill_modifiers: {
          skill_advantage: {
            implementation: 'skill_advantage',
            parameters: ['Percepção', 'Investigação']
          },
          saving_throw_advantage: {
            implementation: 'saving_throw_advantage',
            parameters: { condition: 'armadilhas' }
          }
        },
        defense_modifiers: {
          damage_resistance: {
            implementation: 'damage_resistance',
            parameters: ['armadilhas']
          }
        },
        exploration_modifiers: {
          search_traps_at_normal_pace: {
            implementation: 'trap_search_no_slowdown',
            parameters: {}
          }
        }
      }
    },
    'curandeiro' => {
      id: 'curandeiro',
      name: 'Curandeiro',
      description: 'Você domina primeiros socorros no campo de batalha.',
      prerequisites: {},
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Kit de Primeiros Socorros Aprimorado',
        desc: 'Ao estabilizar com kit, o alvo recupera 1 PV; como ação, gasta 1 uso do kit para curar 1d6+4 + dados de vida do alvo (1/descanso por alvo).'
      },
      special_rules: {
        healing_modifiers: {
          stabilize_restores_1hp: {
            implementation: 'healers_kit_stabilize_plus_1hp',
            parameters: {}
          },
          battle_medic_heal: {
            implementation: 'healers_kit_restore_hp_action',
            parameters: {
              resource: 'healers_kit_use',
              heal_formula: {
                base_die: '1d6',
                flat_bonus: 4,
                plus_target_hd: true
              },
              cooldown: { per_target: true, refresh: ['short_rest', 'long_rest'] }
            }
          }
        }
      }
    },
    'imobilizador' => {
      id: 'imobilizador',
      name: 'Imobilizador',
      description: 'Aperto de ferro no corpo a corpo.',
      prerequisites: { ability_score: { str: 13 } },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Aperto de Ferro',
        desc: 'Vantagem nas jogadas de ataque contra criatura que você esteja agarrando; pode usar ação para tentar imobilizar (ambos ficam Restritos até escape).'
      },
      special_rules: {
        combat_modifiers: {
          advantage_vs_grappled: {
            implementation: 'advantage_on_attack_vs_grappled_target',
            parameters: {}
          },
          pin_as_action: {
            implementation: 'attempt_pin_grappled_target',
            parameters: {
              result: { attacker: 'restrained', target: 'restrained' },
              duration: 'while_grappled',
              escape: { action: 'escape_grapple' }
            }
          }
        }
      }
    },
    'conjurador_de_ritual' => {
      id: 'conjurador_de_ritual',
      name: 'Conjurador de Ritual',
      description: 'Aprende rituais e mantém um livro de rituais.',
      prerequisites: { ability_score: { int_or_wis: 13 } },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Livro de Rituais',
        desc: 'Ganha livro com 2 rituais de 1º nível; pode copiar e conjurar como ritual do livro.'
      },
      special_rules: {
        magic_modifiers: {
          ritual_book: {
            implementation: 'ritual_book_init',
            parameters: { level: 1, count: 2, class_choice: ['bardo', 'bruxo', 'clérigo', 'druida', 'feiticeiro', 'mago'] }
          },
          ritual_copying: {
            implementation: 'copy_ritual_cost',
            parameters: { time_per_level_hours: 2, gold_per_level: 50 }
          },
          ritual_casting: {
            implementation: 'cast_from_book_as_ritual_only',
            parameters: { requires_book_in_hand: true }
          }
        }
      }
    },
    'sniper_magico' => {
      id: 'sniper_magico',
      name: 'Sniper Mágico',
      description: 'Você é um conjurador que foca em ataques de precisão à distância.',
      prerequisites: { spellcasting: true },
      ability_bonuses: {},
      proficiency_bonuses: {},
      features: {
        name: 'Magias de Precisão',
        desc: 'Dobra o alcance das magias de ataque à distância; ignora cobertura leve e média; aprende um truque de ataque à distância da lista de magias de uma classe à sua escolha, usando o atributo de conjuração daquela classe.'
      },
      special_rules: {
        combat_modifiers: {
          cover_immunity: {
            implementation: 'ignore_cover_types',
            parameters: ['leve', 'média']
          },
          spell_range_double: {
            implementation: 'double_spell_range',
            parameters: { spell_type: 'ataque_à_distância' }
          }
        },
        magic_modifiers: {
          learn_cantrip: {
            implementation: 'learn_cantrip',
            parameters: { type: 'ataque_à_distância', class_choice: true }
          }
        }
      }
    }
  }.with_indifferent_access.freeze

  # Aceita value vindo do DB como Hash/Array ja desserializado (jsonb/json), JSON
  # cru (text com `to_json`) ou Ruby Hash#inspect string (text com Hash direto —
  # legado da rake `import_feats` antes do fix; ver tmp/audit_feat_inspect_corruption.rb).
  # Retorna o valor original quando nao conseguir interpretar, para nao mascarar
  # problemas inesperados.
  # Aceita value vindo do DB como Hash/Array ja desserializado (jsonb/json), JSON
  # cru (text com `to_json`) ou Ruby Hash#inspect string (text com Hash direto —
  # legado da rake `import_feats` antes do fix; ver tmp/audit_feat_inspect_corruption.rb).
  # Hashes sao retornados com `with_indifferent_access` para que `apply` consiga
  # acessar via simbolo (ex.: `ability_bonuses[:choose]`) tanto vindo do YAML
  # (string keys via JSON.parse) quanto das RULES estaticas (symbol keys).
  # Retorna o valor original quando nao conseguir interpretar, para nao mascarar
  # problemas inesperados.
  def self.parse_jsonish(value)
    return value.with_indifferent_access if value.is_a?(Hash)
    return value if value.is_a?(Array)
    return value unless value.is_a?(String)
    return value if value.strip.empty?

    parsed = nil

    # Caminho feliz: JSON valido.
    begin
      parsed = JSON.parse(value)
    rescue StandardError
      # cai p/ tentativa de Ruby Hash#inspect
    end

    # Fallback: converte Ruby Hash#inspect (`"{\"k\"=>1, :sym=>2}"`) -> JSON valido.
    # Casos cobertos:
    #   - String keys com hashrocket: "k"=>1 -> "k":1
    #   - Symbol keys: :sym=>1       -> "sym":1
    #   - Nil/true/false sao validos JSON; numeros idem.
    # Risco residual: strings de valor que contenham `=>` literal. Para os feats
    # do D&D no nosso catalogo isso nao ocorre; se ocorrer, JSON.parse falha e
    # o valor original e retornado (idempotencia preservada).
    if parsed.nil?
      candidate = value
                    .gsub(/:([A-Za-z_][A-Za-z0-9_]*)\s*=>/, '"\1":')
                    .gsub('=>', ':')
      begin
        parsed = JSON.parse(candidate)
      rescue StandardError
        Rails.logger.warn("FeatRules.parse_jsonish: falha ao parsear (#{value.bytesize} bytes): #{candidate[0, 80]}...") rescue nil
      end
    end

    return parsed.with_indifferent_access if parsed.is_a?(Hash)
    return parsed if parsed.is_a?(Array)
    value
  end

  def self.all
    # Try to get from database first, fallback to static rules
    begin
      db_feats = Feat.all.index_by(&:api_index)
      # Merge database feats with static rules (database takes precedence)
      merged_rules = RULES.dup
      db_feats.each do |api_index, feat|
        static = RULES[api_index] || {}
        db_prereq = parse_jsonish(feat.prerequisites)
        db_abi    = parse_jsonish(feat.ability_bonuses)
        db_prof   = parse_jsonish(feat.proficiency_bonuses)
        db_can    = parse_jsonish(feat.cantrips)
        db_sp     = parse_jsonish(feat.spells)
        db_feat   = parse_jsonish(feat.features)
        db_spec   = parse_jsonish(feat.special_rules)

        merged_rules[api_index] = {
          id: feat.api_index,
          name: feat.name,
          description: feat.description,
          prerequisites: (db_prereq.presence || static[:prerequisites] || {}),
          ability_bonuses: (db_abi.presence || static[:ability_bonuses] || {}),
          proficiency_bonuses: (db_prof.presence || static[:proficiency_bonuses] || {}),
          cantrips: (db_can.presence || static[:cantrips] || {}),
          spells: (db_sp.presence || static[:spells] || {}),
          features: (db_feat.presence || static[:features] || {}),
          special_rules: (db_spec.presence || static[:special_rules] || {})
        }
      end
      merged_rules
    rescue => e
      Rails.logger.warn "Failed to load feats from database: #{e.message}, using static rules"
      RULES
    end
  end

  def self.find(feat_id)
    # Try database first, then static rules
    begin
      feat = Feat.find_by(api_index: feat_id)
      if feat
        static = RULES[feat_id] || {}
        db_prereq = parse_jsonish(feat.prerequisites)
        db_abi    = parse_jsonish(feat.ability_bonuses)
        db_prof   = parse_jsonish(feat.proficiency_bonuses)
        db_can    = parse_jsonish(feat.cantrips)
        db_sp     = parse_jsonish(feat.spells)
        db_feat   = parse_jsonish(feat.features)
        db_spec   = parse_jsonish(feat.special_rules)

        {
          id: feat.api_index,
          name: feat.name,
          description: feat.description,
          prerequisites: (db_prereq.presence || static[:prerequisites] || {}),
          ability_bonuses: (db_abi.presence || static[:ability_bonuses] || {}),
          proficiency_bonuses: (db_prof.presence || static[:proficiency_bonuses] || {}),
          cantrips: (db_can.presence || static[:cantrips] || {}),
          spells: (db_sp.presence || static[:spells] || {}),
          features: (db_feat.presence || static[:features] || {}),
          special_rules: (db_spec.presence || static[:special_rules] || {})
        }
      else
        RULES[feat_id]
      end
    rescue => e
      Rails.logger.warn "Failed to load feat from database: #{e.message}, using static rules"
      RULES[feat_id]
    end
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
    if proficiency_bonuses[:skills_or_tools]
      chosen = choices[:skills_or_tools] || choices['skills_or_tools'] ||
               choices[:skillsAndTools] || choices['skillsAndTools'] ||
               choices[:proficiencies] || choices['proficiencies'] || []
      skill_picks, tool_picks = split_skills_and_tools(chosen)
      resolved = {}
      resolved['skills'] = skill_picks if skill_picks.any?
      resolved['tools'] = tool_picks if tool_picks.any?
      proficiency_bonuses = resolved if resolved.any?
    elsif proficiency_bonuses[:choose]
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
    # Normalize prerequisites: parse JSON strings and enable indifferent access
    begin
      if prereqs.is_a?(String)
        parsed = JSON.parse(prereqs) rescue nil
        prereqs = parsed if parsed.is_a?(Hash)
      end
    rescue StandardError
      # ignore parse issues; will treat as empty
    end
    prereqs = (prereqs.is_a?(Hash) ? prereqs : {}).with_indifferent_access

    # prerequisites keys expected: ability_score, spellcasting, race, proficiencies
    Rails.logger.info "=== check_prerequisites Debug ==="
    Rails.logger.info "feat_id: #{feat_id}"
    Rails.logger.info "prereqs: #{prereqs.inspect}"
    Rails.logger.info "sheet attributes: str=#{sheet.str}, dex=#{sheet.dex}, con=#{sheet.con}, int=#{sheet.int}, wis=#{sheet.wis}, cha=#{sheet.cha}"
    
    # Check ability score prerequisites
    if prereqs[:ability_score]
      prereqs[:ability_score].each do |ability, min_score|
        ability_key = ability.to_s.downcase
        # Handle composite keys like "int_or_wis" (pass if any meets min)
        if ability_key.include?("_or_")
          options = ability_key.split("_or_").map(&:strip)
          meets = options.any? do |opt|
            begin
              val = sheet.send(opt) || 0
              Rails.logger.info "Checking #{opt} for #{ability_key}: current=#{val}, required=#{min_score}"
              val.to_i >= min_score.to_i
            rescue StandardError
              false
            end
          end
          unless meets
            Rails.logger.error "Prerequisite failed: none of #{options.join(' or ')} >= #{min_score}"
            return false
          end
        else
          # Simple single-ability prerequisite
          begin
            current_score = sheet.send(ability_key) || 0
          rescue StandardError
            current_score = 0
          end
          Rails.logger.info "Checking #{ability}: current=#{current_score}, required=#{min_score}"
          if current_score.to_i < min_score.to_i
            Rails.logger.error "Prerequisite failed: #{ability} #{current_score} < #{min_score}"
            return false
          end
        end
      end
    end

    # Check spellcasting capability if required
    if prereqs[:spellcasting]
      has_casting = sheet_has_spellcasting?(sheet)
      unless has_casting
        Rails.logger.error "Prerequisite failed: requires spellcasting"
        return false
      end
    end

    # Check race prerequisite if specified (by id or name)
    if prereqs[:race]
      allowed = Array(prereqs[:race]).map { |x| x.to_s.downcase }
      begin
        meta = sheet.metadata || {}
        rname = (meta.dig('race_summary','name') || meta.dig('race_summary','id') || '').to_s.downcase
        if rname.empty?
          # fallback to persisted race association name if available
          rname = sheet.race&.name.to_s.downcase if sheet.respond_to?(:race)
        end
        unless allowed.include?(rname)
          Rails.logger.error "Prerequisite failed: race not allowed (#{rname} not in #{allowed})"
          return false
        end
      rescue StandardError
        # if cannot determine, do not block
      end
    end

    # Check proficiencies prerequisite (armor/weapons/skills/tools)
    if prereqs[:proficiencies]
      begin
        required = prereqs[:proficiencies]
        meta = sheet.metadata || {}
        cs = meta['class_summary'] || {}
        armor = Array(cs['armor_proficiencies']).map(&:to_s).map(&:downcase)
        weapons = Array(cs['weapon_proficiencies']).map(&:to_s).map(&:downcase)
        skills = Array(cs['skills']).map(&:to_s).map(&:downcase)
        tools = Array(cs['tools']).map(&:to_s).map(&:downcase)
        if required[:armor]
          Array(required[:armor]).each do |a|
            unless armor.any? { |x| x.include?(a.to_s.downcase) }
              Rails.logger.error "Prerequisite failed: armor proficiency #{a}"
              return false
            end
          end
        end
        if required[:weapons]
          Array(required[:weapons]).each do |w|
            unless weapons.any? { |x| x.include?(w.to_s.downcase) }
              Rails.logger.error "Prerequisite failed: weapon proficiency #{w}"
              return false
            end
          end
        end
        if required[:skills]
          Array(required[:skills]).each do |s|
            unless skills.any? { |x| x.include?(s.to_s.downcase) }
              Rails.logger.error "Prerequisite failed: skill proficiency #{s}"
              return false
            end
          end
        end
        if required[:tools]
          Array(required[:tools]).each do |t|
            unless tools.any? { |x| x.include?(t.to_s.downcase) }
              Rails.logger.error "Prerequisite failed: tool proficiency #{t}"
              return false
            end
          end
        end
      rescue StandardError
        # permissive when not enough context
      end
    end

    Rails.logger.info "All prerequisites met"
    true
  end

  def self.sheet_has_spellcasting?(sheet)
    return false unless sheet

    begin
      meta = (sheet.metadata || {}).deep_stringify_keys
      cs = meta['class_summary'] || {}
      return true if cs['spellcasting'].present? || cs['conjuration'].present?

      sel = meta['spell_selections'] || {}
      return true if %w[cantrips known spellbook prepared].any? { |k| Array(sel[k]).any? }

      per_level = meta.dig('class_choices', 'per_level') || {}
      per_level.each_value do |row|
        next unless row.is_a?(Hash)

        return true if %w[cantrips spells spellbook prepared].any? { |k| Array(row[k]).any? }
      end
    rescue StandardError
      # continue with relational checks
    end

    begin
      if SheetKlass.column_names.include?('spellcasting')
        return true if sheet.sheet_klasses.joins(:klass).where.not(spellcasting: nil).exists?
      end
    rescue StandardError
      # older/imported rows may not have this denormalized column populated
    end

    begin
      sheet.sheet_klasses.includes(:sub_klass, klass: { class_levels: :spellcasting }).any? do |sk|
        klass = sk.klass
        next false unless klass

        klass.spellcasting_ability.present? ||
          SpellRules.sc_for(klass, sk.level).present? ||
          SpellRules.subclass_sc_for(sk).present?
      end
    rescue StandardError
      false
    end
  end

  def self.split_skills_and_tools(values)
    skill_keys = CANONICAL_SKILL_NAMES.index_by { |name| fold_key(name) }
    skills = []
    tools = []
    Array(values).each do |raw|
      value = raw.is_a?(Hash) ? (raw['name'] || raw[:name] || raw['id'] || raw[:id]) : raw
      name = value.to_s.strip
      next if name.empty?

      if skill_keys.key?(fold_key(name))
        skills << name
      else
        tools << name
      end
    end
    [skills.uniq, tools.uniq]
  end

  def self.fold_key(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end
end
