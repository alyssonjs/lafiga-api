# frozen_string_literal: true

# PERF: `ApiRequestAuth#verify_token` roda `ValidateJwtToken.where(token:).present?`
# em TODO request autenticado E em TODA conexão ActionCable (map/chat/session).
# Como `token` não tinha índice, cada verificação era um SEQ SCAN da tabela
# inteira — e para um token VÁLIDO (o caso comum, ausente da denylist) varria
# todas as linhas antes de concluir "não está revogado". Era o piso de latência
# compartilhado (~1.5s) que aparecia em Wallets/SheetItems/BattleMaps/Sheets.
#
# O token guardado é o header "Bearer eyJ..." (~250 chars), bem abaixo do limite
# de linha do btree, então um índice btree simples é seguro. CREATE INDEX
# CONCURRENTLY (fora de transação) evita travar a tabela em produção.
class AddIndexToValidateJwtTokensToken < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_validate_jwt_tokens_on_token'

  def up
    # Rails 6.0 não tem `if_not_exists:` no add_index; guardamos manualmente para
    # o passo ser idempotente (re-run seguro se um CONCURRENTLY anterior abortou).
    return if index_exists?(:validate_jwt_tokens, :token, name: INDEX_NAME)

    add_index :validate_jwt_tokens, :token, name: INDEX_NAME, algorithm: :concurrently
  end

  def down
    return unless index_exists?(:validate_jwt_tokens, :token, name: INDEX_NAME)

    remove_index :validate_jwt_tokens, name: INDEX_NAME, algorithm: :concurrently
  end
end
