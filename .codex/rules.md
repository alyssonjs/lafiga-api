---
description: Regras consolidadas para o backend Rails (lafiga/api)
globs: ["app/**/*.rb", "config/**/*.rb", "lib/**/*.rb"]
alwaysApply: true
---

# 🚀 REGRAS CONSOLIDADAS - BACKEND RAILS (lafiga/api)

## 📋 CONTEXTO DO PROJETO
- **Ruby**: 3.2.2
- **Rails**: ~> 6.0.3.6 (API JSON-first)
- **Auth**: JWT custom (middleware `ApiRequestAuth` + `Authorization: Bearer ...`)
- **DB**: PostgreSQL (ver `config/database.yml`)
- **Upload/Assets**: carrierwave
- **Serialize**: active_model_serializers (~> 0.10.x)
- **Paginação**: manual (limit/offset com `meta`), sem gem
- **Jobs/Redis**: não configurado neste projeto

## 🏗️ ARQUITETURA E LAYOUT
- **Controllers finos** → mover regras de negócio para Services quando crescer
- **AMS** para serialização quando aplicável; manter contratos estáveis
- **Paginação** simples via `limit/offset` e `meta` (ver exemplo abaixo)
- **N+1**: checar com `includes/preload/eager_load` nas consultas públicas/coleções
- **Autorização**: Admin gerencia tudo; Player gerencia apenas os próprios recursos; Público somente leitura
- **Erros**: padronizar envelope JSON e códigos; mensagens curtas

### 📁 Estrutura de Diretórios
- `app/services/**` para orquestração de domínio (já existe `ScheduleService`)
- `app/controllers/**` REST; strong params; handlers de erro
- `app/models/**` com validações e escopos curtos
- `lib/**` utilidades genéricas

## 📡 CONTRATO DE API
### Respostas Padrão (condizentes com os controllers atuais)
- **Coleção**: `{ characters: [...], meta: { page, per_page, total } }` (ou `sheets`, `groups`, etc.)
- **Recurso**: `{ character: { ... } }`
- **Erro**: `{ errors: "mensagem" }` ou `{ errors: ["..."] }`

### Paginação (manual)
- Query: `?page=1&per_page=25`
- `per_page` limitado a 100; `page` mínimo 1
- `meta.total` retorna `count` do escopo sem paginação

### Status HTTP
- `create`: `201 Created`
- `update`/`show`/`index`: `200 OK`
- `destroy`: `204 No Content`
- `unprocessable`: `422 Unprocessable Entity`
- `not found`: `404 Not Found`
- `unauthorized/forbidden`: `401/403` conforme regra

## 🎯 ESTILO E BOAS PRÁTICAS
- Respostas concisas e consistentes; campos previsíveis
- Evitar `.all` em endpoints; sempre paginar/limitar
- Preferir `includes(...)` em endpoints públicos com relações profundas
- Manter `strong parameters` em métodos privados do controller
- Não capturar `StandardError` genericamente no controller; prefira `ActiveRecord::RecordNotFound` e valide erros esperados

## 🗄️ BANCO DE DADOS E PERFORMANCE
- Indicar índices para FKs e campos de filtro
- Usar `includes` para evitar N+1 em coleções
- Consultas de listagem: `order(created_at: :desc)` por padrão

## 🔒 SEGURANÇA E AUTORIZAÇÃO
- `authorize_request` para rotas Player; `authorize_admin_request` para Admin
- Player só acessa seus próprios registros (`@current_user.<assoc>.find(params[:id])`)
- Público: somente leituras com includes controlados
- Mensagens de erro curtas (não vazar detalhes internos)

## 🧪 TESTES (RSpec)
- Gems: `rspec-rails`, `factory_bot_rails`
- Testar: status HTTP, contratos JSON, autorizações por perfil, validações de model
- Factories para `User`, `Character`, etc.

## 📝 PADRÕES DE CÓDIGO
### Controllers
- Orquestram: validar params, chamar serviços/escopos, renderizar JSON, tratar erros esperados
- Usar `render json: { ... }, status: :ok` (ou símbolo adequado)
- Centralizar `rescue_from ActiveRecord::RecordNotFound` no `ApplicationController` quando possível

### Models/ActiveRecord
- Validações explícitas (`presence`, etc.)
- Escopos curtos e composáveis
- Evitar callbacks pesados; prefira services/jobs quando for o caso

### Services
- Padrão `Service.call(...)` com método de classe `call`
- Puro e testável; side effects explícitos

## 🔧 EXEMPLOS DE PADRONIZAÇÃO
### Paginação simples em controller
```ruby
scope = Character.order(created_at: :desc)
page = params.fetch(:page, 1).to_i
per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
records = scope.limit(per_page).offset((page - 1) * per_page)

render json: {
  characters: records,
  meta: { page: page, per_page: per_page, total: scope.count }
}, status: :ok
```

### Inclusões seguras para público (evitar N+1)
```ruby
scope = Character
  .includes(sheet: [:race, :sub_race, :klasses, :sub_klasses])
  .order(created_at: :desc)

render json: {
  characters: scope.limit(per_page).offset(offset)
                 .as_json(include: { sheet: { include: [:race, :sub_race, :klasses, :sub_klasses] } }),
  meta: { page: page, per_page: per_page, total: scope.count }
}
```

## ✅ CHECKLIST ANTES DE ENVIAR MUDANÇAS
- Status HTTP corretos (`:created`, `:no_content`, etc.)
- Resposta segue o contrato `{ characters/resource, meta }`
- Paginação e `meta.total` presentes em coleções
- Sem N+1 em endpoints públicos/coleções
- `strong params` cobrindo apenas campos permitidos
- Mensagens de erro consistentes e curtas

