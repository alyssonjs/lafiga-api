module Combat
  # Serializadores canônicos das entidades de combate. Usados pelos
  # controllers REST e (Fase 1C) pelos broadcasts do `SessionRealtimeChannel`.
  # Devem ser estáveis: o front (sessionData.ts) consome o shape exato.
  module Serializers
    module_function

    def state(cs)
      return nil unless cs
      {
        id: cs.id,
        schedule_id: cs.schedule_id,
        active: cs.active,
        round: cs.round,
        current_turn_index: cs.current_turn_index,
        started_at: cs.started_at,
        ended_at: cs.ended_at,
        updated_at: cs.updated_at,
        movement_ledger: Array.wrap(cs.movement_ledger),
      }
    end

    def combatant(c)
      return nil unless c
      {
        id: c.id,
        combat_state_id: c.combat_state_id,
        type: c.combatable_type == 'CombatNpc' ? 'npc' : 'pc',
        combatable_id: c.combatable_id,
        name: c.name,
        position: c.position,
        initiative: c.initiative,
        initiative_bonus: c.initiative_bonus,
        tie_break_dex: c.tie_break_dex,
        hp_current: c.hp_current,
        hp_max: c.hp_max,
        ac: c.ac,
        temp_hp: c.temp_hp,
        is_delayed: c.is_delayed,
        is_concentrating: c.is_concentrating,
        concentration_spell: c.concentration_spell,
        is_stabilized: c.is_stabilized,
        is_dead: c.is_dead,
        conditions: Array(c.conditions),
        actions_used: Hash(c.actions_used),
        death_saves: Hash(c.death_saves),
        updated_at: c.updated_at,
      }
    end

    def combatants(collection)
      collection.map { |c| combatant(c) }
    end

    def npc(npc)
      return nil unless npc
      {
        id: npc.id,
        schedule_id: npc.schedule_id,
        name: npc.name,
        hp_current: npc.hp_current,
        hp_max: npc.hp_max,
        ac: npc.ac,
        base_ac: npc.base_ac,
        speed: npc.speed,
        cr: npc.cr,
        proficiency_bonus: npc.proficiency_bonus,
        monster_id: npc.monster_id,
        stats: Hash(npc.stats),
        saving_throws: Hash(npc.saving_throws),
        skills: Hash(npc.skills),
        attacks: Array(npc.attacks),
        equipment: Hash(npc.equipment),
        notes: npc.notes,
        defeated_at: npc.defeated_at,
        updated_at: npc.updated_at,
      }
    end

    def npcs(collection)
      collection.map { |n| npc(n) }
    end

    def log(entry)
      return nil unless entry
      {
        id: entry.id,
        schedule_id: entry.schedule_id,
        kind: entry.kind,
        actor: entry.actor,
        message: entry.message,
        roll_result: entry.roll_result,
        posted_at: entry.posted_at,
        created_at: entry.created_at,
      }
    end

    def logs(collection)
      collection.map { |l| log(l) }
    end
  end
end
