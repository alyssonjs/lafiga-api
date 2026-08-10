# Plano: Importar monstros da Open5e v2 → tabela `monsters`

> Objetivo: incorporar o catálogo de criaturas da Open5e (https://api.open5e.com/v2/creatures/)
> no nosso banco de monstros, **reusando o pipeline existente** (`MonsterEngineSyncService`
> → tabela `monsters`), sem quebrar os 66 monstros PT-BR curados.
>
> Grounded em dados REAIS puxados da API (Goblin `srd_goblin`, Lich) — ver "Dados reais".

## Decisões (confirmadas)

1. **Escopo/licença:** apenas **SRD 5.1** (`document.key = "srd-2014"`, publisher
   Wizards of the Coast, licença **OGL 1.0a**). ~330 criaturas, redistribuição
   segura com atribuição. Não importar docs CC-BY/ORC nesta fase.
2. **Tradução:** traduzir **campos estruturados** (tamanho/tipo/alinhamento/dano/
   condição via mapa) **E as descrições** (traits/ações/idiomas) para PT-BR.
3. **Ataques:** **preservar o ataque estruturado** (habilita NPC auto-rolar
   ataque/dano no combate) **E** gerar/traduzir a descrição em texto.

## Arquitetura atual (o que reusar)

```
front monsterDatabase.ts ─(dumpMonstersToJson.ts)→ api/db/seeds/monsters.json
    → MonsterEngineSyncService.call({monsters:[...]}, default_source:) → tabela `monsters`
```
- `MonsterEngineSyncService` aceita `{ "monsters" => [ {..MonsterEntry..} ] }`
  (array com `id`/`slug`) e faz **upsert idempotente por slug** — reusar como está.
- Model `Monster`: `sync_columns_from_payload` deriva `cr_numeric/size/monster_type/
  ac/hp/...` do `payload`; `to_payload` devolve o MonsterEntry pro front;
  `cr_to_number` converte "1/4"→0.25.
- ⚠️ `Monster::SOURCES = %w[srd homebrew]` → **adicionar `open5e`** (ou usar `srd`
  para os SRD, ver "De-dup").
- Front consome via `api/v1/public/monsters` (`MonsterContext`) + legacy
  `MONSTER_DATABASE`.

## Componentes novos (proposta)

1. **Snapshot** `api/db/seeds/open5e_srd_creatures.json` — dump cru da API filtrado
   por `document__key=srd-2014` (reprodutível/offline; evita depender da API em
   build/CI). Task para (re)baixar.
2. **`Open5eMonsterMapper`** (serviço Ruby puro, testável) — Open5e v2 creature →
   linha `MonsterEntry` (payload PT-BR + `attacks[]` estruturado + atribuição).
3. **`app/data/open5e_translation.rb`** (ou YAML) — mapas EN→PT determinísticos
   (size/type/alignment/damage/condition/skill). Prosa (traits/ações) via camada
   separada (ver "Tradução").
4. **Rake** `monsters:import_open5e` — lê o snapshot → mapper → `MonsterEngineSyncService`.
5. RSpec do mapper contra fixtures reais (goblin + lich).

## Mapeamento Open5e v2 → payload (MonsterEntry)

| Open5e v2 (real) | payload | Transformação |
|---|---|---|
| `key` ("srd_goblin") | `id`/`slug` | `open5e-<key sem 'srd_'>` → `open5e-goblin` |
| `name` | `name` + `nameEN` | `nameEN` = EN; `name` = tradução PT (fase 2) |
| `size.key` ("small") | `size` | mapa: small→Pequeno, medium→Medio, huge→Enorme… |
| `type.key` ("humanoid") | `type` | mapa: fiend→Infernal, ooze→Limo, aberration→Aberracao… |
| `alignment` ("neutral evil") | `alignment` | mapa EN→PT (2 palavras); "unaligned"→Sem Alinhamento; "any alignment"→Qualquer Alinhamento |
| `challenge_rating` (0.25) | `cr` (string) | 0.125→"1/8", 0.25→"1/4", 0.5→"1/2", senão inteiro |
| `experience_points` | `xp` | direto |
| `armor_class` + `armor_detail` | `ac` + `acType` | direto |
| `hit_points` + `hit_dice` | `hp` + `hitDice` | direto |
| `ability_scores{strength..}` | `stats{str..}` | rename |
| `speed_all{walk,fly,...,unit}` | `speed{walk,fly,...}` | largar `unit`; manter feet (nossos senses já usam feet); dropar campos 0 |
| `saving_throws` (só proficientes) | `savingThrows` | rename das chaves |
| `skill_bonuses` | `skills` | chave EN→PT (stealth→Furtividade…) |
| `darkvision_range`/`blindsight_range`/`tremorsense_range`/`truesight_range`, `passive_perception` | `senses{darkvision,...,passivePerception}` | direto (0/null → omitir) |
| `resistances_and_immunities.damage_resistances[].key` | `damageResistances[]` | **EN→PT** (cold→frio…) |
| `...damage_immunities` (+ `_display` p/ "from nonmagical") | `damageImmunities[]` | EN→PT; parsear o display composto "…from nonmagical attacks" → "físico não mágico" |
| `...damage_vulnerabilities[].key` | `damageVulnerabilities[]` | EN→PT |
| `...condition_immunities[].key` | `conditionImmunities[]` | **EN→PT** (charmed→encantado, frightened→amedrontado, exhaustion→exaustao…) ⚠️ ver playbook de condições §6 |
| `languages_as_string` ("Common, Goblin") | `languages[]` | split por vírgula; tradução PT dos idiomas comuns (fase 2) |
| `actions[]` (por `action_type`) | `actions` / `reactions` / `legendaryActions` / `bonusActions` | split: ACTION→actions, REACTION→reactions, LEGENDARY_ACTION→legendaryActions.actions, **BONUS_ACTION→bonusActions** (novo bucket no payload jsonb; nosso `MonsterEntry` não tem slot de ação bônus hoje — ex.: "Nimble Escape") |
| `actions[].desc` + `actions[].attacks[]` | `actions[].description` + `actions[].attacks[]` | ver "Ataques" (parsear o desc!) |
| `traits[]{name,desc}` | `traits[]{name,description}` | prosa → tradução PT (fase 2) |
| `environments[]` | `environment[]` | mapa EN→PT |
| `document` | `source` + `payload.attribution` | `source: 'open5e'`; guardar `{document:'srd-2014', publisher:'Wizards of the Coast', gamesystem:'5e-2014', license:'OGL-1.0a', permalink}` |

## ⚠️ Qualidade dos dados: ataques estruturados NÃO são confiáveis

Verificado no dado real: o Goblin SRD tem `attacks[0].damage_type = {name:"Thunder",key:"thunder"}`
para uma **cimitarra** — o correto é *slashing* (e o `desc` diz "slashing"). Também
`damage_bonus: null` embora o `desc` traga "1d6 + 2". **Pior: o campo VARIA por documento**
— o mesmo Goblin no A5E (a5e-mm) traz `damage_type: null` + `extra_damage_type:{key:"piercing"}`
e `damage_bonus: 1`. Ou seja, o tipo de dano ora está errado em `damage_type`, ora em
`extra_damage_type`, ora nulo. **Conclusão: `attacks[].damage_type`/`damage_bonus` NÃO são
confiáveis; o `desc` (template SRD rígido) é a fonte confiável.**

Estratégia dos ataques (decisão #3):
- **Derivar** os campos estruturados de combate **do `desc`** por parsing do template
  SRD: `"Melee|Ranged Weapon|Spell Attack: +X to hit, reach Y ft.|range Y/Z ft., ...
  Hit: N (dice) TYPE damage."` → `{ attackType, toHit, reach|range, damageDice,
  damageType, ... }`. Isso é determinístico e correto.
- **Guardar também** o `attacks[]` cru da Open5e em `payload.actions[].attacksRaw`
  (referência), mas o combate consome o derivado do desc.
- Gerar a `description` PT a partir do parse (mesmo estilo dos 66:
  "Ataque Corpo a Corpo com Arma: +4 para acertar, alcance 1,5 m, um alvo.
  Acerto: 5 (1d6+2) cortante."). Converter ft→m (5 ft → 1,5 m) como nos curados.

## Tradução (decisão #2)

Dois níveis:
- **Determinístico (fase 1):** enums finitos via mapa estático — size, type,
  alignment, damage types, condition ids, skills, environments. + geração PT das
  linhas de ATAQUE a partir do parse do desc (acima). Zero MT, 100% reprodutível.
- **Prosa (fase 2):** `name`, `traits[].desc`, ações não-ataque, idiomas. Opções:
  1. **Template para os recorrentes do SRD** (Legendary Resistance, Magic
     Resistance, Pack Tactics, Spellcasting, Innate Spellcasting, Amphibious,
     Keen Senses, Sunlight Sensitivity…) — mapa de ~30-50 traits cobre a maioria.
  2. **LLM bulk** para o long-tail — rodar um **workflow** (fan-out ~15 agentes,
     lotes de ~22 monstros) que traduz os campos de prosa → gera o snapshot PT
     `open5e_srd_creatures.pt.json` **commitado** (tradução em tempo de autoria,
     sem dependência de MT em runtime/CI).
  - Até a fase 2 rodar, importar com prosa em INGLÊS + `nameEN` (o app já mostra
    `nameEN`); os campos estruturados já vêm em PT.

## De-dup com os 66 curados

Os SRD curados (PT-BR polido) sobrepõem parte do SRD Open5e. Estratégia:
- Curados mantêm `source: 'srd'`, slug `mon-*`. Open5e entra como `source: 'open5e'`,
  slug `open5e-*` → **sem colisão de slug**.
- Precedência na UI: quando existir os dois para o mesmo `nameEN`, preferir o
  curado (`srd`) — a busca/listagem pode dedupar por `nameEN` priorizando `srd`.
- `Monster.by_source` já permite filtrar; adicionar índice/uso de `nameEN` para o
  dedupe.

## Rollout em fases

- **Fase 1 — infra + estruturado (verificável): ✅ CONCLUÍDA.** snapshot SRD,
  `Open5eMonsterMapper` (mapa determinístico + parse de ataque + atribuição), rake
  `monsters:import_open5e`/`reseed_open5e`, `SOURCES += open5e`, RSpec (22 ex.,
  fixtures goblin+lich). Prosa em EN.
  - **Resultado:** 325 criaturas SRD importadas (source=open5e), 0 erros.
  - **Ataques:** parseados do `desc` (não do estruturado bugado); 320/325 com ≥1
    ataque; os 5 restantes não têm ataque de dano (Donkey/Frog/Sea Horse sem ação;
    Rug of Smothering=agarra; Shrieker=alarme). Dado opcional cobre dano fixo (CR 0).
  - **Defesas:** `damage(Immunities|Resistances|Vulnerabilities)` vêm do **display
    string** (autoritativo), não do array — o array achata "X from nonmagical" em
    imunidade total de X (corrigido; ver `T.damage_display_list`).
  - **Qualidade:** 0 fallbacks EN em size/type/alignment/tipo-de-dano; 0 sem cr/xp/ac.
  - ⚠️ **Não commitado ainda** (aguardando revisão). Arquivos: `app/data/open5e_translation.rb`,
    `app/services/open5e_monster_mapper.rb`, `spec/services/open5e_monster_mapper_spec.rb`,
    `spec/fixtures/open5e/{goblin,lich}.json`, `db/seeds/open5e_srd_creatures.json`,
    `lib/tasks/monsters.rake`, `app/models/monster.rb` (SOURCES).
- **Fase 2 — tradução de prosa:** template dos traits recorrentes + workflow LLM
  p/ o long-tail → snapshot PT commitado → reimport.
- **Fase 3 — combate NPC:** front lê `actions[].attacks` (derivado) para o NPC
  auto-rolar ataque/dano (fecha o gap "NPC usa stat block manual" visto no trabalho
  de condições). Reaproveita `AttackRollFlow`/`getTargetRuntimeContext`.

## Dados reais (referência do mapper)

```jsonc
// Goblin — actions[0]
{ "name":"Scimitar",
  "desc":"Melee Weapon Attack: +4 to hit, reach 5 ft., one target. Hit: 5 (1d6 + 2) slashing damage.",
  "attacks":[{ "attack_type":"WEAPON","to_hit_mod":4,"reach":5,"range":null,
               "damage_die_count":1,"damage_die_type":"D6","damage_bonus":null,
               "damage_type":{"name":"Thunder","key":"thunder"}, /* ⚠️ ERRADO: é slashing */
               "distance_unit":"feet" }],
  "action_type":"ACTION" }
// alignment: "neutral evil" | size:{key:"small"} | type:{key:"humanoid"}
// document:{key:"srd-2014", publisher:{name:"Wizards of the Coast"}, gamesystem:{key:"5e-2014"}}

// Lich — resistances_and_immunities
"damage_resistances":[{"name":"Cold","key":"cold"},{"key":"lightning"},{"key":"necrotic"}]
"condition_immunities":[{"key":"charmed"},{"key":"exhaustion"},{"key":"frightened"},{"key":"paralyzed"},{"key":"poisoned"}]
"damage_immunities_display":"poison; bludgeoning, piercing, and slashing from nonmagical attacks"
// actions com action_type "ACTION" e "LEGENDARY_ACTION"
```

## Licença / atribuição (obrigatório)

SRD 5.1 é **OGL 1.0a** — redistribuível COM atribuição. Guardar em cada monstro
importado `payload.attribution = { source:'Open5e', document:'System Reference
Document 5.1', document_key:'srd-2014', publisher:'Wizards of the Coast',
license:'OGL-1.0a', permalink:'https://dnd.wizards.com/resources/systems-reference-document' }`
e **exibir crédito no `MonsterStatBlock`** (rodapé "Fonte: SRD 5.1 (OGL) via Open5e").
Não importar documentos fora do SRD nesta fase.
