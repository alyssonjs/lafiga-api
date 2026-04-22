class AddDmUserIdToGroups < ActiveRecord::Migration[6.0]
  # Fase 1 (group ownership): registra o criador/owner do grupo (DM da
  # campanha). Antes a unica forma de associar usuario a grupo era via
  # Character#group_id, o que fazia o grupo "sumir" para o criador apos o
  # refresh quando ele ainda nao tinha personagem. Tambem usado em
  # `Group#member?` e `Player::GroupsController#set_group` para autorizacao.
  #
  # Nullable: grupos antigos do seed (criados antes desta feature) ficam com
  # `NULL` e ainda funcionam pelo caminho via :characters. Novas linhas
  # criadas pelo controller sempre populam dm_user_id.
  def change
    add_reference :groups, :dm_user, foreign_key: { to_table: :users }, null: true
  end
end
