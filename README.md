# lafiga-api

API Rails (Lafiga). Stack típico: Ruby 3.2, Postgres, Redis; ver `Dockerfile` / `docker-compose.yml` em `lafiga-dev/` para desenvolvimento.

## Database seed

`db:seed` limpa vários modelos, cria roles/users/groups mínimos, importa **raças** de `config/race_rules.yml` e de seguida corre o pipeline D&D:

1. **`dnd:bootstrap`** (por defeito), ou `SKIP_DND_API=1` → só **`dnd:load_local`**.
2. **`dnd:import`** (API dnd5eapi): magias, backgrounds, alinhamentos, traits, classes, subclasses, etc.
3. **`dnd:load_local`**: `feats:import` (`config/feats_improved.yml`), `items:import_all` (`equipment.yml` + `magic_items.yml`), `subclasses:import`, overrides, magias de subclasse.

Não cria **Sheet** completa nem importa **`docs/imported_sheets.json`** automaticamente.

### Variáveis úteis

| Variável | Efeito |
|----------|--------|
| `SKIP_DND_API=1` | Não chama a API; só `dnd:load_local`. |
| `SEED_DND_TASK=dnd:load_local` | Força só o passo local (equivalente útil com `SKIP_DND_API`). |
| `SEED_ONLY=races` ou `RACE_ONLY=1` | Só raças + purge reduzido. |
| `SEED_MONSTERS=1` | No fim de `dnd:load_local`, corre `monsters:import` se existir `db/seeds/monsters.json`. |
| `SEED_IMPORTED_SHEETS_REHYDRATE=1` | No fim de `dnd:load_local`, corre `sheet_items:rehydrate_imported` se existir `docs/imported_sheets.json`. |

Exemplos:

```bash
# Seed normal (API + local)
bin/rails db:seed

# Sem rede para API SRD
SKIP_DND_API=1 bin/rails db:seed

# Seed + monstros (gerar JSON: ver task `monsters:import` em lib/tasks/monsters.rake)
SEED_MONSTERS=1 bin/rails db:seed

# Seed + re-hidratar itens/moedas de fichas P81 a partir do JSON (ver docs/README_imported_sheets.md)
SEED_IMPORTED_SHEETS_REHYDRATE=1 bin/rails db:seed
```

Docker (produção):

```bash
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.production exec \
  -e SEED_MONSTERS=1 -e SEED_IMPORTED_SHEETS_REHYDRATE=1 web bin/rails db:seed
```

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
