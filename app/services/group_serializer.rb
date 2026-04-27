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
      members: characters.map { |c| serialize_member_for_roster(c) },
      created_at: group.created_at,
      updated_at: group.updated_at,
    }
  end

  def self.serialize_collection(groups)
    Array(groups).map { |g| serialize(g) }
  end

  # Prefixo de import legado (ex.: provision `[P81] Nome`) — só afeta rótulo na UI.
  ROSTER_IMPORT_NAME_PREFIX = /\A\[P\d+\]\s*/i.freeze

  # Dados públicos de roster (calendário / mesa): jogadores da mesma campanha veem
  # nível, classe, chibi (avatar_customization) uns dos outros; não expõe stats,
  # magias ou notas.
  def self.serialize_member_for_roster(character)
    raw_name = character.name.to_s
    stripped = raw_name.sub(ROSTER_IMPORT_NAME_PREFIX, '').strip

    h = {
      id: character.id,
      name: raw_name,
      display_name: stripped.present? ? stripped : raw_name,
      user_id: character.user_id,
      level: nil,
      race_name: nil,
      class_name: nil,
      subclass_name: nil,
      klass_api_index: nil,
    }
    sheet = character.sheet
    return h unless sheet

    h[:level] = CharacterRules.total_level(sheet)
    h[:race_name] = sheet.race&.name
    pk = roster_primary_sheet_klass(sheet)
    if pk&.klass
      h[:class_name] = pk.klass.name
      h[:klass_api_index] = pk.klass.api_index
    end
    if pk&.sub_klass
      h[:subclass_name] = pk.sub_klass.name
    elsif pk&.klass_id.present?
      # Fallback: outra linha da mesma classe com subclasse (import / dados parciais).
      sk = roster_first_sheet_klass_with_subclass(sheet, pk.klass_id)
      h[:subclass_name] = sk.sub_klass.name if sk&.sub_klass
    end

    ac = sheet.avatar_customization
    h[:avatar_customization] = ac.deep_stringify_keys if ac.is_a?(Hash) && ac.present?

    h
  end

  # Fallback de subclasse: equivalente a `order(level: :desc, id: :asc).detect { sub_klass }`,
  # sem SQL quando `sheet_klasses` já veio no preload (ex.: calendário público).
  def self.roster_first_sheet_klass_with_subclass(sheet, klass_id)
    if sheet.association(:sheet_klasses).loaded?
      sub = sheet.sheet_klasses.select { |r| r.klass_id == klass_id && r.sub_klass.present? }
      return nil if sub.empty?

      sub.min_by { |r| [-r.level, r.id] }
    else
      sheet.sheet_klasses
        .where(klass_id: klass_id)
        .order(level: :desc, id: :asc)
        .detect { |row| row.sub_klass.present? }
    end
  end

  # Mesmo critério geral que a summary (nível desc); reforça subclasse quando a
  # linha "principal" veio sem `sub_klass_id` mas existe outra linha da classe.
  def self.roster_primary_sheet_klass(sheet)
    rows = if sheet.association(:sheet_klasses).loaded?
      sheet.sheet_klasses.to_a.sort_by { |r| [-r.level, r.id] }
    else
      sheet.sheet_klasses.includes(:klass, :sub_klass).order(level: :desc, id: :asc).to_a
    end
    return nil if rows.empty?

    pk = rows.first
    return pk if pk.sub_klass.present? || pk.klass_id.blank?

    rows.find { |sk| sk.klass_id == pk.klass_id && sk.sub_klass.present? } || pk
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
