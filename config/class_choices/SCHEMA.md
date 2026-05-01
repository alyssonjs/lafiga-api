# Class Choices Catalog Schema

Catálogo canônico de opções de escolha por classe (metamágicas, invocações, manobras, disciplinas, snacks, hunter features, etc.) usado tanto pelo backend (`LevelUpGuardService`) quanto pelo front (via endpoint público).

## Localização

```
api/config/class_choices/
├── SCHEMA.md                    # este arquivo
├── metamagic.yml                # Kit 1.PoC
├── eldritch_invocations.yml     # Kit 1.invocations
├── maneuvers.yml                # Kit 1.maneuvers
├── elemental_disciplines.yml    # Kit 1.disciplines
├── snacks.yml                   # Kit 1.snacks
└── hunter_features.yml          # Kit 1.hunter
```

## Formato YAML

Cada arquivo segue o mesmo schema. Top-level: lista de entradas.

```yaml
- slug: mm-careful                        # ID canônico, único, kebab-case (nunca muda)
  name_pt: Magia Cuidadosa                # Display PT-BR (PHB oficial)
  name_en: Careful Spell                  # PHB original em inglês (referência)
  aliases:                                # Nomes legados aceitos por compat (opcional)
    - Suturar Magia
  description: |                          # Texto completo da habilidade
    Quando você conjura uma magia que obriga outras criaturas...
  mechanical_summary: Aliados na AoE passam automaticamente no TR  # Resumo curto
  cost: 1                                 # Custo em pontos de feitiçaria (opcional)
  classes:                                # Quais classes podem escolher (default: [classe-pai])
    - sorcerer
  # Campos opcionais top-level (string livre, sem schema fechado):
  school: Transmutation                   # escola arcana (cookbook etc)
  range: Touch                            # alcance ("Touch", "Self", "9 m radius", ...)
  duration: 10 minutes                    # duração ("Instantaneous", "1 minute", ...)
  higher_level: |                         # escalonamento (opcional)
    No 7º: 3d6.
  prereqs:                                # Pré-requisitos estruturados (opcional)
    level: 5                              # Nível mínimo da classe
    pact: chain                           # Pacto requerido (warlock)
    spell: eldritch_blast                 # Magia/cantrip requerido
    class: warlock                        # Classe requerida
    subclass: sous-chef                   # Subclasse requerida (api_index canônico)
    ability_min:                          # Atributos mínimos
      DEX: 13
```

## Regras de validação

O loader (`ClassChoicesCatalog`) faz **validação estrita** ao carregar:

1. **slug obrigatório**, kebab-case (`^[a-z0-9-]+$`), único no arquivo
2. **name_pt obrigatório**, único no arquivo
3. **name_en obrigatório**
4. **description obrigatória**, mínimo 30 caracteres
5. **mechanical_summary obrigatório**, máximo 100 caracteres
6. **cost** se presente: integer >= 0 OU string em `VALID_COST_STRINGS` (`'spell_level'` para custo igual ao nível da magia, `'variable'` para custo variável explicado em `mechanical_summary` — ex.: 0 ou 1 Ki)
7. **classes** se presente: array de strings (api_index de classes)
8. **prereqs** se presente: hash com chaves opcionais conhecidas (`level`, `pact`, `spell`, `class`, `blast`, `ability_min`)
9. **aliases** se presente: array de strings, NÃO pode haver alias duplicado entre entries

Falhas de validação são fatais no boot do Rails (não há fallback silencioso).

## Cache

`ClassChoicesCatalog.load(:metamagic)` faz parse + validação na primeira chamada e mantém em memória. Após mudar YAML em dev, restart o container para invalidar cache (`docker restart lafiga_api`).

## Compat — Aliases

Para evitar quebrar chars existentes (que podem ter nomes legados em `metadata.class_choices`), o loader expõe:

```ruby
ClassChoicesCatalog.resolve(:metamagic, 'Suturar Magia')
# => { slug: 'mm-careful', name_pt: 'Magia Cuidadosa', ... }
```

A resolução procura match em `slug`, `name_pt`, `name_en`, depois `aliases`. Se nada bate, retorna `nil`.

## Integração com `LevelUpGuardService`

```ruby
# Em ClassRules:
required_choices_at_level: {
  3 => {
    metamagic: {
      choose: 2,
      options: :metamagic,                # Symbol → resolve via dictionaries
      validate_subset: true               # opt-in (Kit 3)
    }
  }
}

# E em ClassRules.dictionaries:
def self.dictionaries
  {
    # ... legacy keys ...
    metamagic: ClassChoicesCatalog.load(:metamagic)  # Array<Hash> formato novo
  }
end
```

O guard resolve `:metamagic` → array de hashes → extrai `slug` para validar subset.

## Endpoint público

`GET /api/v1/public/class_rules` retorna `dictionaries.metamagic` automaticamente (já está no controller). Front consome via `fetchPublicClassChoices('metamagic')` e cacheia.
