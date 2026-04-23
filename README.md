# lafiga-api

API Rails (Lafiga). Stack típico: Ruby 3.2, Postgres, Redis; ver `Dockerfile` / `docker-compose.yml` em `lafiga-dev/` para desenvolvimento.

## Importação de dados D&D no banco de dados

O conteúdo de jogo na BD divide-se em **duas camadas**:

| Camada | Origem | O que popula |
|--------|--------|----------------|
| **Esqueleto SRD** | Rede (`dnd:import`) ou **dump** de Postgres | `Klass`, `Spell`, `ClassLevel`, `SubKlass` PHB, backgrounds, alinhamentos, traits, etc. |
| **Dados locais (YAML / regras)** | Repositório (`config/*.yml`, `SubclassRules`) | Feats, equipamento, overrides de classe/subclasse, subclasses homebrew em `SubclassRules`, petiscos do Cozinheiro, etc. |

Não existe hoje um único rake que substitua **completamente** o `dnd:import` por ficheiros locais para todas as tabelas SRD. Para um ambiente **novo** precisas de **uma** das opções: correr **`dnd:import` uma vez** (com rede) ou restaurar um **dump** já populado.

### Ordem correta (referência)

**1. Esqueleto (uma vez por base de dados vazia, ou após migrações que esvaziem o catálogo)**

```bash
bin/rails dnd:import
```

**2. Materializar tudo o que vem do repo (idempotente — podes repetir sempre que mudarem os YAMLs)**

Opção **mínima** (só o que `dnd:bootstrap` também corre no fim):

```bash
bin/rails dnd:load_local
```

Ordem interna de `dnd:load_local` (definida em `lib/tasks/dnd_pipeline.rake`, módulo `Dnd::LocalYaml`):

1. `feats:import` — `config/feats_improved.yml`
2. `items:import_all` — `equipment.yml` + `magic_items.yml` → tabela `items`
3. `subclasses:import` — subclasses novas em `SubclassRules` / `SubclassRulesExtended`
4. `dnd:apply_subclass_overrides` — `config/subclass_overrides.yml` (+ grants, sync de `SubKlassLevel`/features a partir de `levels_json`)
5. `subclasses:import_spells` — `subclass_spells.yml` / `subclass.yml`
6. Opcional: `SEED_MONSTERS=1` → `monsters:import` se existir `db/seeds/monsters.json`
7. Opcional: `SEED_IMPORTED_SHEETS_REHYDRATE=1` → `sheet_items:rehydrate_imported` se existir `docs/imported_sheets.json`

Opção **recomendada** para alinhar também classes homebrew, overrides de classe PHB, Cozinheiro e petiscos **num único comando**:

```bash
bin/rails dnd:load_local_full
```

Isto corre **antes** do mesmo núcleo acima:

- `classes:apply_overrides` — `config/class_overrides.yml`
- `custom:ensure_cook_class` — classe `cozinheiro`
- `snacks:import` — `config/cook_snacks.yml`

Depois executa o mesmo núcleo + opcionais que `dnd:load_local`.

**3. Atalho “API + local” (desenvolvimento ou primeira subida)**

```bash
bin/rails dnd:bootstrap
```

Equivalente a: `dnd:import` (se não usares `SKIP_DND_API=1`) **seguido de** `dnd:load_local`.

**4. Validação de nomes de magias usados no JSON de fichas importadas** (opcional, útil em CI)

```bash
bin/rails spells:audit_imported
```

Lê `docs/imported_sheets.json` (`spells_listed`) e falha se algum nome não for resolvido pelo `SpellResolver` (ajustar `config/spell_aliases.yml` ou o JSON). Ignora ruído típico do XLSX (linhas só numéricas, cabeçalhos).

### O que estes rakes **não** fazem

- Não criam **fichas de personagem** completas nem consomem `docs/imported_sheets.json` para criar `Sheet` (isso é o fluxo de provision no front / `docs/README_imported_sheets.md`).
- Não rebuildam `config/dnd_translations.yml` — isso é o namespace `dnd_translations:*` (workflow de tradução, não deploy típico de catálogo de jogo).

---

## Database seed

`db:seed` faz purge de vários modelos (exceto modo `SEED_ONLY=races` / `RACE_ONLY=1`), cria dados mínimos (roles, users, groups, agendas, etc.), importa **raças** de `config/race_rules.yml` e de seguida corre **uma** tarefa D&D:

| Situação | Tarefa invocada |
|----------|-----------------|
| Por defeito | `dnd:bootstrap` → `dnd:import` + `dnd:load_local` |
| `SKIP_DND_API=1` | só `dnd:load_local` |
| `SEED_DND_TASK=…` | força o nome da task (ex.: `dnd:load_local_full`) |

Se `SEED_DND_TASK` falhar, o seed tenta `dnd:load_local` como fallback (ver `db/seeds.rb`).

### Variáveis úteis

| Variável | Efeito |
|----------|--------|
| `SKIP_DND_API=1` | O `dnd:bootstrap` do seed não chama a API; só corre `dnd:load_local`. |
| `SEED_DND_TASK=dnd:load_local` | Força só o passo local mínimo. |
| `SEED_DND_TASK=dnd:load_local_full` | Seed com YAML local **completo** (classes + cook + snacks + núcleo). |
| `SEED_ONLY=races` ou `RACE_ONLY=1` | Só raças + purge reduzido. |
| `SEED_MONSTERS=1` | No fim de `dnd:load_local` / `dnd:load_local_full`, corre `monsters:import` se existir `db/seeds/monsters.json`. |
| `SEED_IMPORTED_SHEETS_REHYDRATE=1` | No fim, corre `sheet_items:rehydrate_imported` se existir `docs/imported_sheets.json`. |

Exemplos:

```bash
# Seed normal (API SRD + YAML local mínimo)
bin/rails db:seed

# Sem rede: só YAML local mínimo (exige BD já com SRD ou dump)
SKIP_DND_API=1 bin/rails db:seed

# Seed com pipeline local completo (classes + cook + snacks + núcleo)
SEED_DND_TASK=dnd:load_local_full bin/rails db:seed

# Seed + monstros (gerar JSON: ver `lib/tasks/monsters.rake`)
SEED_MONSTERS=1 bin/rails db:seed

# Seed + re-hidratar itens/moedas P81 (ver docs/README_imported_sheets.md)
SEED_IMPORTED_SHEETS_REHYDRATE=1 bin/rails db:seed
```

Docker (produção):

```bash
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.production exec \
  -e SEED_MONSTERS=1 -e SEED_IMPORTED_SHEETS_REHYDRATE=1 web bin/rails db:seed
```

Fluxo manual típico em **produção** (sem `db:seed` completo): deploy da API → `db:migrate` se necessário → `dnd:import` **ou** restore de dump → `dnd:load_local_full` (e variáveis opcionais acima).

### Utilizadores de produção (`@lafiga.com`)

Após `db:seed` (roles + utilizadores demo), podes criar os admins e alinhar emails dos demos com `config/production_users.yml`:

```bash
PROD_BOOTSTRAP_PASSWORD='senha_inicial_forte' bin/rails lafiga:users:seed_production
```

Em **production** a variável `PROD_BOOTSTRAP_PASSWORD` é obrigatória se ainda não existirem os admins no ficheiro. Utilizadores demo só têm o **email** atualizado (por `username`); passwords não são alteradas.

## Testes

```bash
bundle exec rspec
```

## Documentação extra

- `docs/README_imported_sheets.md` — pipeline do JSON de fichas importadas.
