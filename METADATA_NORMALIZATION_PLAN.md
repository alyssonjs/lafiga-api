# Plano de Normalização do Metadata - Sheet

## Resumo
Este documento descreve o plano para normalizar dados que atualmente estão armazenados no campo `metadata` (JSONB) da tabela `sheets` em colunas específicas do banco de dados.

## Problema Atual
O campo `metadata` contém uma grande quantidade de informações estruturadas que poderiam ser normalizadas para melhor performance, integridade referencial e facilidade de consulta.

## Dados Identificados para Normalização

### 1. Alignment (Alinhamento)
- **Campo atual**: `metadata['alignment']`
- **Nova coluna**: `alignment_id` (FK para tabela `alignments`)
- **Migração**: `20250101000001_add_alignment_to_sheets.rb`

### 2. Background (Antecedente)
- **Campos atuais**: `metadata['background']`, `metadata['background_key']`
- **Novas colunas**: `background_id` (FK), `background_key` (string)
- **Migração**: `20250101000002_add_background_to_sheets.rb`

### 3. Current Level (Nível Atual)
- **Campo atual**: `metadata['current_level']`
- **Nova coluna**: `current_level` (integer)
- **Migração**: `20250101000003_add_current_level_to_sheets.rb`

### 4. Race Choices (Escolhas de Raça)
- **Campo atual**: `metadata['race_choices']`
- **Nova coluna**: `race_choices` (jsonb)
- **Migração**: `20250101000004_add_race_choices_to_sheets.rb`

### 5. Class Choices (Escolhas de Classe)
- **Campo atual**: `metadata['class_choices']`
- **Nova coluna**: `class_choices` (jsonb)
- **Migração**: `20250101000005_add_class_choices_to_sheets.rb`

### 6. Summaries (Resumos)
- **Campos atuais**: 
  - `metadata['race_summary']`
  - `metadata['class_summary']`
  - `metadata['background_summary']`
  - `metadata['features_by_level']`
- **Novas colunas**: 
  - `race_summary` (jsonb)
  - `class_summary` (jsonb)
  - `background_summary` (jsonb)
  - `features_by_level` (jsonb)
- **Migração**: `20250101000006_add_summaries_to_sheets.rb`

### 7. Race Bonuses Applied
- **Campo atual**: `metadata['race_bonuses_applied']`
- **Nova coluna**: `race_bonuses_applied` (jsonb)
- **Migração**: `20250101000007_add_race_bonuses_to_sheets.rb`

## Migrações Criadas

1. `20250101000001_add_alignment_to_sheets.rb` - Adiciona referência para alignment
2. `20250101000002_add_background_to_sheets.rb` - Adiciona referência para background
3. `20250101000003_add_current_level_to_sheets.rb` - Adiciona coluna current_level
4. `20250101000004_add_race_choices_to_sheets.rb` - Adiciona coluna race_choices
5. `20250101000005_add_class_choices_to_sheets.rb` - Adiciona coluna class_choices
6. `20250101000006_add_summaries_to_sheets.rb` - Adiciona colunas de summaries
7. `20250101000007_add_race_bonuses_to_sheets.rb` - Adiciona coluna race_bonuses_applied
8. `20250101000008_migrate_metadata_to_columns.rb` - Migra dados existentes

## Mudanças no Modelo

### Sheet Model
- Adicionadas associações:
  - `belongs_to :alignment, optional: true`
  - `belongs_to :background, optional: true`

## Benefícios da Normalização

1. **Performance**: Consultas mais rápidas com índices específicos
2. **Integridade**: Foreign keys garantem consistência dos dados
3. **Facilidade de consulta**: Queries SQL mais simples e eficientes
4. **Manutenibilidade**: Estrutura mais clara e organizada
5. **Escalabilidade**: Melhor performance com grandes volumes de dados

## Considerações

### Dados que permanecem no metadata
Alguns dados complexos e dinâmicos podem continuar no campo `metadata`:
- Configurações específicas do usuário
- Dados temporários de sessão
- Informações que mudam frequentemente

### Compatibilidade
- As migrações incluem rollback para reverter as mudanças se necessário
- Os serviços existentes continuarão funcionando durante a transição
- Dados migrados são preservados no metadata original

## Próximos Passos

1. **Executar migrações** em ambiente de desenvolvimento
2. **Testar funcionalidades** existentes
3. **Atualizar serviços** para usar as novas colunas
4. **Executar em produção** após validação completa
5. **Remover campos do metadata** após confirmação de funcionamento

## Exemplo de Uso Pós-Migração

```ruby
# Antes (usando metadata)
sheet.metadata['current_level']
sheet.metadata['alignment']['name']

# Depois (usando colunas normalizadas)
sheet.current_level
sheet.alignment.name
```

## Impacto nos Serviços

Os seguintes serviços precisarão ser atualizados para usar as novas colunas:
- `CharacterSheetSummaryService`
- `FeaturesAggregator`
- `LevelUpService`
- `BackgroundAssignmentService`
- `FeatAssignmentService`
- `RaceProfileService`
- `ClassProfileService`



