# frozen_string_literal: true

# As ROLAGENS do servidor (09/10; L0.6, plano B2). Cada dado que o servidor rola fica aqui, selado, e SÓ ENTRA:
# a linha não muda nem some (`Dados::Rolagem#readonly?`). É o que o feed mostra com o selo e o `dados:verificar`
# reconfere.
#
# Campos:
#   - `chave`: a identidade da rolagem. Rolar de novo a mesma chave devolve esta linha, sem rolar outra vez (o retry,
#     a segunda aba, o reprocessamento da agenda);
#   - `fonte`: `segura` (`SecureRandom`, as ações do jogador) ou `hmac` (determinística pela chave, o mundo);
#   - `expressao`: a forma canônica (`2d20kh1+3`);
#   - `dados`: cada grupo, com os dados rolados e os mantidos;
#   - `detalhe`: o teste (atributo, proficiência, vantagem, CD, margem…), quando é um teste;
#   - `contexto`: quem e onde (a sessão, o usuário, o mundo, o evento, o rótulo);
#   - `selo`: o HMAC de tudo isso (`Dados::Selo`).
#
# Sem `updated_at`: a linha não é atualizada.
class CreateRolagens < ActiveRecord::Migration[6.0]
  def change
    create_table :rolagens do |t|
      t.string :chave, null: false
      t.string :fonte, null: false
      t.string :expressao, null: false
      t.jsonb :dados, null: false, default: []
      t.integer :total, null: false
      t.jsonb :detalhe, null: false, default: {}
      t.jsonb :contexto, null: false, default: {}
      t.string :selo, null: false
      t.datetime :created_at, null: false
    end
    add_index :rolagens, :chave, unique: true
  end
end
