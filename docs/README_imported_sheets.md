# Imported Character Sheets (xlsx → JSON)

Extracao das 39 fichas de personagem em
`api/docs/Ficha de acompanhamento Pre (1).xlsx` para um JSON estruturado
normalizado, util para:

- Gerar **fixtures de teste** em RSpec/Vitest com dados reais de campanha.
- **Refinar o modelo** do projeto (descobrir campos/regras de casa que ainda
  nao temos no backend/frontend).
- **Gap analysis** entre o que a planilha rastreia e o que o
  `CharacterSheetSummaryService` entrega hoje.

## Como gerar

```bash
python3 api/scripts/extract_xlsx_sheets.py
```

Saidas:

- `api/docs/imported_sheets.json` (~340 KB, 39 fichas)
- `api/docs/imported_sheets.summary.txt` (relatorio human-readable)

## Re-hidratação de itens/moedas (Rails)

Com `imported_sheets.json` presente e fichas já provisionadas na BD, podes
correr `sheet_items:rehydrate_imported` à mão (ver `lib/tasks/sheet_items_rehydrate.rake`).

Para encadear no mesmo fluxo do `db:seed` / `dnd:load_local`, usa
`SEED_IMPORTED_SHEETS_REHYDRATE=1` (documentado em `api/README.md`).

## Re-provision com mesmo dono / grupo / chibi (Phase 8.1)

O script `front-lafiga/scripts/provision-imported-as-bob.ts` pode reler um manifest
gerado a partir do banco **antes** de apagar as fichas `[P81]`:

1. **Auditar** quem está com cada ficha (tab estimado, `user_id`, `group_id`, chaves do chibi):
   `docker exec -e DISABLE_SPRING=1 lafiga_api bin/rake phase81:audit_p81`
2. **Exportar** `api/docs/imported_sheets_provision_manifest.json` (chave = `tab_name` do JSON importado):
   `docker exec -e DISABLE_SPRING=1 lafiga_api bin/rake phase81:export_manifest`
3. **Limpar** fichas de teste: `docker exec -e DISABLE_SPRING=1 lafiga_api bin/rake phase81:cleanup`
4. **Rodar** o script TS; se o manifest existir e tiver entradas com `user_id`, o fluxo usa
   login do DM (`dm@lafiga.com` / `LAFIGA_DM_EMAIL`) e `POST /api/v1/admin/characters/provision`.
   `group_id` e `wizard.avatar.customization` vêm do manifest para todas as linhas que casarem a aba.

Schema do manifest (exemplo):

```json
{
  "Lyra": {
    "user_id": 2,
    "user_email": "bob@lafiga.com",
    "group_id": 1,
    "avatarCustomization": { "hairColor": "#553322" }
  }
}
```

**Nota:** a hidratação pós-provision de moedas/inventário (PATCH player) só roda quando o dono é Bob;
para outros usuários, complete inventário logado como o jogador ou amplie endpoints admin.

## Schema (por ficha)

```jsonc
{
  "tab_name": "Allan",
  "meta": {
    "name_raw": "Lyra El'Asah (Wood Elf)",
    "name": "Lyra El'Asah",
    "race": {
      "raw": "Wood Elf",
      "race_api_index": "elf",
      "subrace_api_index": "wood"
    },
    "klass": {
      "raw": "Patrulheiro Flagelo dos inimigos",
      "class_api_index": "ranger",
      "subclass_raw": "flagelo dos inimigos",
      "subclass_api_index": null,
      "is_homebrew_class": false,
      "is_homebrew_subclass": true
    },
    "xp": 29846,
    "level": 7,
    "proficiency_bonus": 3,
    "encumbrance": {
      "light_threshold_kg": 50, "light_dex_penalty": -3,
      "heavy_threshold_kg": 100, "heavy_dex_penalty": -6
    }
  },
  "abilities": { "strength": {"score": 20, "mod": 5}, "...": "..." },
  "skills": [
    { "key": "athletics", "label": "Atletismo", "ability": "str",
      "training_hours": 95.0 }
  ],
  "saving_throws": [
    { "ability": "constitution", "training_hours": 170.0,
      "total_hours_pool": 170.0 }
  ],
  "additional_proficiencies": [
    { "name": "Armadura Pesada", "training_hours": 50.0 }
  ],
  "hit_points": { "total": 53, "current": 0 },
  "hp_extra": 7.0,
  "combat": { "ac": 16, "speed_m": 9.0, "spell_save_dc": 15,
               "spell_attack": 7, "passive_perception": 11,
               "passive_insight": 14 },
  "weight": { "max_personal_kg": 150, "current_personal_kg": 51.9,
              "max_backpack_kg": 15, "current_backpack_kg": 9.3 },
  "coins": { "copper": 7, "silver": 12, "gold": 13, "platinum": 26 },
  "folego": { "full": 9.6, "current": -0.4 },
  "languages": ["Comum", "Élfico"],
  "spell_slots": [ {"level": 1, "total": 4} ],
  "spells_listed": [
    { "level": 0, "name": "Raio de Gelo", "marker": null,
      "always_prepared": false }
  ],
  "synced_items": { "max": 3, "current": 1 },
  "aljava": [ {"name": "Flecha", "quantity": 20, "weight_each_kg": 0.05} ],
  "inventory_bag": [ {"name": "Capa", "quantity": 1, "weight_each_kg": 1.0} ],
  "armor_weapons": {
    "armor":   [{"name": "Cota de Malha", "weight_kg": 27.5}],
    "weapons": [{"name": "Cimitrra", "weight_kg": 1.5}],
    "wearing": [{"name": "Cantil", "weight_kg": 2.5}]
  },
  "class_resources_signals": {
    "action_surge": { "raw_label": "Surto de Ação", "...": "..." },
    "indomitable":  { "...": "..." }
  },
  "feats": ["Observador", "Mobilidade"],
  "fighting_style": "Arquearia",
  "ranger_choices": {
    "favored_enemy": ["Bestas"],
    "favored_terrain": ["Florestas"]
  },
  "rage": { "raw": "1 de 3P", "used": 1, "total": 3 },
  "mount": {
    "items": [{"name": "Trajes finos", "quantity": 1, "weight_each_kg": 3.0}],
    "mounted": false,
    "load_kg": 240.0
  },
  "exhaustion_level": 1
}
```

## Cobertura por campo (39 fichas)

Universais (>= 90% das fichas):

- `meta.{name, class_label, level, xp, proficiency_bonus}`
- `meta.encumbrance.{light_threshold_kg, heavy_threshold_kg, ...}`
- `abilities.*`, `skills[*].training_hours`, `saving_throws[*].training_hours`
- `hit_points`, `combat.{ac, passive_perception, passive_insight, speed_m}`
- `weight.*`, `additional_proficiencies`, `inventory_bag`, `folego`

Frequentes (50–90%):

- `coins.gold`, `languages`, `spells_listed`, `synced_items`,
  `combat.spell_save_dc`

Opcionais por classe/setup (≤50%):

- `hp_extra`, `aljava`, `spell_slots` (so casters), `coins.platinum`,
  `class_resources_signals.*`
- `feats` (13/39), `fighting_style` (8/39 — guerreiro/patrulheiro/paladino),
  `ranger_choices.{favored_enemy, favored_terrain}` (3/39 — patrulheiros),
  `rage` (4/39 — barbaros), `mount` (6/39 — quem tem montaria),
  `exhaustion_level` (1/39 — so quem esta com exaustao ativa)

## Mapeamento canonico de Race / Klass

O extrator mapeia rotulos das fichas para os `api_index` canonicos do
projeto (`Race`, `SubRace`, `Klass`, `SubKlass`):

- **Raca**: extraida de parenteses no nome (`"(Wood Elf)"` → `elf/wood`),
  com fallback para sufixos sem parenteses (`"Nikos Humano"` → `human/standard`).
- **Classe + subclasse**: parse da string de classe da ficha
  (`"Guerreira Mestre de Batalha"` → `fighter/battlemaster`).
- Quando o rotulo da ficha NAO bate com nada canonico, o campo
  `is_homebrew_class` ou `is_homebrew_subclass` fica `true` e o rotulo cru
  fica preservado em `klass.subclass_raw` para inspecao manual.

### Subclasses HOMEBREW detectadas (nao existem no projeto)

| Classe | Subclasse na ficha | Personagem |
|---|---|---|
| ranger | Batedor (Scout) | Adimael |
| ranger | Flagelo dos Inimigos | Lyra |
| rogue | Cacador de Tesouro | Stivi Magal |
| paladin | Misericordia | Amani |
| barbarian | Cicatrizes Runicas | Bult Seewell |
| bard | Comedia | Joe |
| bard | Fortuna | Ainor |
| bard | Pavor | Pandora |
| sorcerer | Espada | Kanlu |
| wizard | Planar | Avalon |
| wizard | Mestre dos Automatos | Valac |
| warlock | Morte | Angelina |
| druid | Circulo Verdejante | Tony Ramos |
| monk | Bebado (Drunken Master) | Sanda |

### Classes inteiras HOMEBREW

| Classe | Personagem |
|---|---|
| Atirador Inigualavel (Gunslinger) | Aberama Gold |

## Conceitos NOVOS detectados (house rules ainda nao no projeto)

1. **Treino em horas** por pericia, resistencia e proficiencia adicional
   (`skills[*].training_hours`, `saving_throws[*].training_hours`,
   `additional_proficiencies[*].training_hours`).
2. **Sobrecarga em 2 niveis** com penalidade em DEX e velocidade
   (`meta.encumbrance.{light,heavy}_*`).
3. **Folego** (full / atual) — recurso de fadiga estendido.
4. **Capacidade dividida** Pessoal vs Mochila (`weight.*`).
5. **Itens Sincronizados** com cap configuravel (`synced_items`) — sistema
   de attunement custom.
6. **Aljava** como slot dedicado de municao.
7. **Moedas detalhadas** PC/PP/PO/PL (`coins.*`).

## Estrategia de extracao

- Posicoes **fixas** para o que e estavel em 100% das fichas (habilidades,
  pericias, resistencias, HP, CA, deslocamento, sobrecarga, peso, etc).
- Busca por **label** (regex normalizado) para o que varia de aba para aba
  (Folego, HP Extra, Espacos de Magia, Itens Sincronizados, Aljava, etc).
- O extrator e idempotente: rode quantas vezes quiser; o JSON e regerado.

## Limitacoes conhecidas

- Algumas fichas grandes (Nayara, Lucinano) tem **sub-blocos extras**
  (Status do Homunculo, Bau Pessoal, Estante, Maleta de Alquimia,
  Ingredientes de crafting) que NAO sao extraidos ainda — sao layouts
  unicos por ficha. Adicionar handlers especificos quando precisar.
- Spell list nao distingue **espaco gasto** (so total) — fichas usam celulas
  separadas para "preparadas" vs "gastos" que variam de layout.
