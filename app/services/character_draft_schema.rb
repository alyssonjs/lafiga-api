# Versioned schema for Character#draft_data.
#
# Goals:
#   - Document the per-step shape used by the wizard (see STEP_KEYS).
#   - Provide a migrate/1 that uplifts older blobs (no `_version` key) to the
#     current shape so per-step services can rely on consistent structure.
#   - Keep the contract single-source-of-truth: frontend mirrors this in
#     front-lafiga/src/services/characterDraft/types.ts
#
# We deliberately stay tolerant: unknown keys are preserved (passthrough),
# missing fields default to safe empties, and migration is idempotent.
class CharacterDraftSchema
  DRAFT_SCHEMA_VERSION = 1

  # Canonical step keys (must match front shared.tsx BASE_STEPS + PROGRESSION_STEP).
  STEP_KEYS = %w[general race background class abilities skills progression equipment alignment avatar review].freeze

  # Top-level keys allowed in draft_data (besides _version and current_step).
  # Anything not listed is preserved untouched.
  KNOWN_TOP_LEVEL_KEYS = %w[
    name playerName isNPC npcRole npcFaction npcLocation npcStatus dmNotes
    level isDMMode
    selectedRace selectedSubrace raceChoices selectedFeat
    selectedClass selectedSubclass classSkillPicks selectedSkills
    abilityScores
    selectedBackground backgroundToolChoices backgroundLanguageChoices
    backgroundPersonalityTraits backgroundIdeals backgroundBonds backgroundFlaws
    selectedAlignment
    equipmentMode equipmentChoices equipmentGenericSelections startingGoldRolled
    avatarCustomization avatarUserEdited
    level1Choices levelChoices spellSelections progressionSubLevel level1HpChoice
    _raceId _classId _bgId _bgName _alignId _featId
  ].freeze
  # ZS11 do segundo audit: `avatarUserEdited` foi adicionado a esta lista junto com
  # a fix ZX4. Sem isso, qualquer outro consumidor do schema que itere por
  # KNOWN_TOP_LEVEL_KEYS (futuras validacoes, sanitizacao) nao reconheceria a
  # flag e poderia descarta-la silenciosamente.

  class << self
    # Returns a copy of `data` migrated to the current version.
    # Idempotent: calling again with already-current data is a no-op clone.
    def migrate(data)
      base = data.is_a?(Hash) ? data.deep_stringify_keys : {}
      base = base.dup

      ver = base['_version'].to_i
      base = migrate_to_v1(base) if ver < 1

      base['_version'] = DRAFT_SCHEMA_VERSION
      base
    end

    # Read just the fragment relevant to a given step (used by GET /character_drafts/:id?step=...).
    # Returns a Hash with the canonical keys for that step (may be empty).
    # The actual mapping lives in the per-step service `read` method; this is a fallback.
    def read_step(data, step_key)
      data = migrate(data)
      case step_key.to_s
      when 'general'
        data.slice('name', 'playerName', 'level', 'isNPC', 'npcRole', 'npcFaction', 'npcLocation', 'npcStatus', 'dmNotes')
      when 'race'
        data.slice('selectedRace', 'selectedSubrace', 'raceChoices', 'selectedFeat', '_raceId').merge(
          'avatarGender' => data.dig('avatarCustomization', 'gender')
        )
      when 'background'
        data.slice(
          'selectedBackground', '_bgId', '_bgName',
          'backgroundToolChoices', 'backgroundLanguageChoices',
          'backgroundPersonalityTraits', 'backgroundIdeals', 'backgroundBonds', 'backgroundFlaws'
        )
      when 'class'
        data.slice('selectedClass', '_classId', 'selectedSubclass', 'classSkillPicks', 'level1Choices')
      when 'abilities'
        data.slice('abilityScores')
      when 'skills'
        # ZS9 do segundo audit: a versao antiga lia `selectedSkills` literal,
        # ignorando o fallback `level1Choices.skills` (canonico per_level). Em
        # drafts recentes que ja salvaram via SkillsStepService novo, `selectedSkills`
        # e populado em paralelo, mas drafts vindos de provision-service direto ou
        # antes do bug B7.x tinham so `level1Choices.skills`. Agora unimos ambas
        # as fontes — paridade com SkillsEditService#read.
        skills = (Array(data['selectedSkills']) | Array(data.dig('level1Choices', 'skills'))).map(&:to_s).uniq
        {
          'selectedSkills' => skills,
          'expertise'      => Array(data.dig('level1Choices', 'expertise'))
        }
      when 'progression'
        data.slice('levelChoices', 'progressionSubLevel', 'spellSelections', 'level1HpChoice')
      when 'equipment'
        data.slice('equipmentMode', 'equipmentChoices', 'equipmentGenericSelections', 'startingGoldRolled')
      when 'alignment'
        # ZS10 do segundo audit: paridade com AlignmentEditService#read, que
        # devolve `{ alignmentId, alignmentIndex }` (slug). Antes este path so
        # devolvia `selectedAlignment` aninhado, gerando shape diferente entre
        # creation e edit — o front tinha que ramificar o consumidor.
        sel = data['selectedAlignment']
        ref = sel.is_a?(Hash) ? (sel['id'] || sel[:id]) : sel
        ref ||= data['_alignId']
        {
          'selectedAlignment' => sel,
          '_alignId'          => data['_alignId'],
          'alignmentId'       => ref&.to_s,
          'alignmentIndex'    => (ref && ref.to_s.match?(/\A[a-z]/) ? ref.to_s : nil)
        }.compact
      when 'avatar'
        data.slice('avatarCustomization')
      when 'review'
        {}
      else
        {}
      end
    end

    private

    # v0 -> v1: legacy drafts had no _version. Normalize known scalar/array fields and
    # ensure structural keys exist with safe defaults.
    def migrate_to_v1(data)
      d = data.dup

      d['level'] = (d['level'] || 1).to_i
      d['isDMMode'] = !!d['isDMMode']
      d['isNPC'] = !!d['isNPC']

      d['raceChoices'] ||= {}
      d['classSkillPicks'] ||= []
      d['selectedSkills'] ||= []
      d['level1Choices'] ||= {}
      d['levelChoices'] ||= []
      d['spellSelections'] ||= { 'cantrips' => [], 'known' => [], 'spellbook' => [], 'prepared' => [] }
      d['equipmentChoices'] ||= []
      d['equipmentGenericSelections'] ||= {}
      d['backgroundToolChoices'] ||= []
      d['backgroundLanguageChoices'] ||= []
      d['backgroundPersonalityTraits'] ||= []
      d['backgroundIdeals'] ||= []
      d['backgroundBonds'] ||= []
      d['backgroundFlaws'] ||= []
      d['avatarCustomization'] ||= {}

      d['progressionSubLevel'] = (d['progressionSubLevel'] || 1).to_i

      d
    end
  end
end
