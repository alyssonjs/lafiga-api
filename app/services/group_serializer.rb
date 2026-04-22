# Serializa um Group no formato canônico consumido pelo frontend (DMHome,
# GroupManager, GroupContext, etc.). Fonte única — usado por
# `Api::V1::Admin::GroupsController` e `Api::V1::Player::GroupsController`.
#
# `sessions_count` agrega a contagem de schedules vinculados ao grupo,
# permitindo que a Home do DM mostre o card de campanha sem fazer N+1.
class GroupSerializer
  def self.serialize(group)
    return nil unless group

    schedules_assoc = group.schedules
    sessions_count =
      schedules_assoc.respond_to?(:loaded?) && schedules_assoc.loaded? ?
        schedules_assoc.size :
        schedules_assoc.count

    characters_assoc = group.characters
    characters =
      characters_assoc.respond_to?(:loaded?) && characters_assoc.loaded? ?
        characters_assoc.to_a :
        characters_assoc.to_a

    {
      id: group.id,
      name: group.name,
      description: group.description,
      season: group.season,
      day: group.day,
      year: group.year,
      cover_image_url: cover_image_url_for(group),
      dm_user_id: group.dm_user_id,
      sessions_count: sessions_count,
      character_ids: characters.map(&:id),
      members: characters.map { |c|
        { id: c.id, name: c.name, user_id: c.user_id }
      },
      created_at: group.created_at,
      updated_at: group.updated_at,
    }
  end

  def self.serialize_collection(groups)
    Array(groups).map { |g| serialize(g) }
  end

  # Prioridade da capa (Fase 4c):
  #   1. ActiveStorage blob anexado (`has_one_attached :cover_image`) →
  #      path relativo `/rails/active_storage/blobs/...` (sem host).
  #      O frontend prefixa com a baseURL da API quando precisar.
  #   2. URL livre na coluna `cover_image_url` → fallback para casos
  #      em que o DM cola um link externo direto (Imgur, Unsplash).
  #   3. nil → frontend usa gradiente da estação.
  #
  # Usamos `rails_blob_path` (não `rails_blob_url`) propositalmente para
  # evitar depender de `default_url_options[:host]` (que não está setado
  # em test e quebraria a serialização em jobs/broadcasts).
  def self.cover_image_url_for(group)
    if group.respond_to?(:cover_image) && group.cover_image.attached?
      Rails.application.routes.url_helpers.rails_blob_path(
        group.cover_image,
        only_path: true,
      )
    else
      group.cover_image_url
    end
  rescue StandardError
    group.cover_image_url
  end
end
