# frozen_string_literal: true

# Normaliza o nome canónico do papel (Role.name no DB) para o contrato que o
# front consome (`'dm' | 'player' | 'guest'`). O front compara em minúsculas
# (`user.role === 'dm'`); o banco guarda capitalizado (`'DM'`, `'Player'`,
# `'Admin'`) porque `Role.name` é a chave canônica usada em policies.
#
# - `Admin` é tratado como `dm` (alias legado: enquanto não migramos os
#   usuários antigos, qualquer Admin é DM no front).
# - `User` (papel legado do seed antigo) é tratado como `player`.
#
# Compartilhado entre `AuthenticationController` (login/signup) e
# `Api::V1::MeController` (refresh do estado da sessão) para evitar
# divergência de contrato entre as respostas de auth.
module RoleSerializer
  extend ActiveSupport::Concern

  private

  def serialize_role(role_name)
    return 'guest' if role_name.blank?

    normalized = role_name.to_s.downcase
    return 'dm' if normalized == 'admin'
    return 'player' if normalized == 'user' # legado: 'User' role no seed antigo

    normalized
  end
end
