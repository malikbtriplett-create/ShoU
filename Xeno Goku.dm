/*
    Xeno Goku
    Combat Blocking Instructor

    Foundation NPC.

    Uses the existing mob/Enemy architecture.
    Combat behavior will be added in controlled phases.
*/

mob/Enemy/Xeno_Goku
    name = "Xeno Goku"
    icon = 'Icons/New NPCS/Xeno Goku-NPC.dmi'
    icon_state = "no name"

    Race = "Yasai"
    Docile = 1
    NPC_Activated = 0

    BP = 100
    base_bp = 100
    static_bp = 0

    Str = 5
    End = 1
    Spd = 1
    Pow = 1
    Res = 1
    Off = 1
    Def = 1

    max_ki = 100
    Ki = 100
    Health = 100

    Spawn_Timer = 0
    no_disable = 1

    var/tmp/turf/xeno_test_origin
    var/tmp/mob/xeno_test_target
    var/tmp/xeno_test_running = 0

    New()
        . = ..()
        Docile = 1
        NPC_Activated = 0
        npcTargetingRange = 0
        icon_state = "no name"

    Click()
        if(usr && ismob(usr))
            usr << "DEBUG: Xeno Goku Click() received."
        if(!usr || !ismob(usr)) return
        if(usr == src) return

        var/mob/player = usr

        if(xeno_test_running)
            player << "Xeno Goku is already preparing a test."
            return

        var/choice = input(player, "What do you want to test?", "Xeno Goku") in list("Melee Blocking", "Projectile Blocking", "Cancel")

        if(!player || choice == "Cancel")
            return

        xeno_test_target = player
        xeno_test_origin = loc

        if(choice == "Melee Blocking")
            player << "Xeno Goku: Melee Blocking test selected."
            player << "Xeno Goku: Test target recorded."
            spawn Xeno_Melee_Block_Test(player)
        else
            player << "Xeno Goku: Projectile Blocking test selected."
            player << "Xeno Goku: Test target recorded."

/*
    Temporary controlled deployment for the Xeno Goku
    combat-instructor development milestone.

    Xeno is a real mob/Enemy and therefore uses the
    existing NPC initialization architecture.
*/

mob/Admin5/verb/Spawn_Xeno_Goku()
    set category = "Admin"

    if(!usr || !usr.loc)
        return

    var/turf/spawn_loc = get_step(usr, usr.dir)

    if(!spawn_loc || spawn_loc.density)
        spawn_loc = usr.loc

    var/mob/Enemy/Xeno_Goku/X = new(spawn_loc)

    if(!X)
        usr << "Xeno Goku could not be spawned."
        return

    X.dir = usr.dir
    X.icon_state = "no name"

    usr << "Xeno Goku spawned."

/*
    Xeno Goku Melee Blocking Test

    Uses the real DU melee system.

    Xeno approaches the selected player, waits until adjacent,
    faces the player, and performs a real Melee() attack.

    The Block / Perfect Block result is handled entirely by
    the normal combat system.

    This test intentionally does not create a special Xeno
    version of blocking.
*/

mob/Enemy/Xeno_Goku/proc/Scale_To_Strongest_Player()
    set waitfor = 0

    var/mob/strongest = null
    var/highest_bp = 0

    // Find the strongest active player currently online.
    for(var/mob/M in world)
        if(!M || !M.client || !M.loc)
            continue
        if(M == src)
            continue
        if(M.BP > highest_bp)
            highest_bp = M.BP
            strongest = M

    if(!strongest)
        return 0

    // Xeno stays exactly 1,000 BP above the strongest active player.
    BP = strongest.BP + 1000
    base_bp = BP

    // Remove the previous Xeno benchmark source before recalculating.
    RemoveAllStatModifierSources("xeno_benchmark")

    var/list/authoritative_names = GetAuthoritativeStatNames()
    var/list/xeno_modifiers = new/list

    // Xeno is exactly +1.0 effective stat above the benchmark player.
    // Calculate the required source modifier after accounting for
    // Xeno's existing racial modifiers.
    for(var/stat_name in authoritative_names)
        var/player_value = strongest.GetEffectiveStat(stat_name)
        var/target_value = player_value + 1.0
        var/current_value = GetEffectiveStat(stat_name)
        xeno_modifiers[stat_name] = target_value - current_value

    SetStatModifierSource("xeno_benchmark", xeno_modifiers, null, "temporary")

    // Translate the desired authoritative physical stats into the
    // legacy raw stat scale used by the existing combat engine.
    // Legacy combat uses floor((raw - 6) / 3), so raw = 6 +
    // (desired * 3) gives the closest compatible representation.
    var/xeno_strength = GetEffectiveStat("Strength")
    var/xeno_durability = GetEffectiveStat("Durability")
    var/xeno_speed = GetEffectiveStat("Speed")
    var/xeno_force = GetEffectiveStat("Force")
    var/xeno_resistance = GetEffectiveStat("Resistance")
    var/xeno_accuracy = GetEffectiveStat("Accuracy")

    Str = 6 + (xeno_strength * 3)
    End = 6 + (xeno_durability * 3)
    Spd = 6 + (xeno_speed * 3)
    Pow = 6 + (xeno_force * 3)
    Res = 6 + (xeno_resistance * 3)
    Off = 6 + (xeno_accuracy * 3)

    // Energy uses Eff directly rather than GetStatMod().
    Eff = GetEffectiveStat("Energy")

    // Regeneration and Recovery are direct legacy multipliers.
    regen = GetEffectiveStat("Regeneration")
    recov = GetEffectiveStat("Recovery")

    // Keep Xeno's runtime resources synchronized with the scaled profile.
    max_ki = Math.Max(100, 5000 * Eff)
    Ki = max_ki

    // Give Xeno enough HP to remain a reusable instructor.
    Health = Math.Max(100, BP)

    return 1

mob/Enemy/Xeno_Goku/proc/Xeno_Melee_Block_Test(mob/player)
    set waitfor = 0

    if(!player || !player.loc)
        xeno_test_running = 0
        return

    if(xeno_test_running)
        return

    xeno_test_running = 1
    xeno_test_target = player

    // Scale Xeno to the strongest active player for this test.
    if(!Scale_To_Strongest_Player())
        player << "Xeno Goku: No active player benchmark found. Using current profile."


    player << "Xeno Goku: Beginning melee blocking test."

    while(src && player && player.loc && xeno_test_running)
        if(player.KO)
            player << "Xeno Goku: Melee blocking test ended."
            break

        if(getdist(src, player) > 1)
            dir = get_dir(src, player)
            step_towards(src, player)
            sleep(world.tick_lag)
            continue

        dir = get_dir(src, player)

        // Use the actual DU melee attack.
        Melee()

        // Give the real melee system time to resolve.
        sleep(TickMult(8))

        if(!src || !player || !player.loc)
            break

        // Return toward the recorded test origin naturally.
        while(src && player && player.loc && xeno_test_origin && getdist(src, xeno_test_origin) > 0)
            if(getdist(src, player) <= 1)
                break

            dir = get_dir(src, xeno_test_origin)
            step_towards(src, xeno_test_origin)
            sleep(world.tick_lag)

        sleep(TickMult(4))

    xeno_test_running = 0
    xeno_test_target = null

    if(src && player)
        player << "Xeno Goku: Melee blocking test ended."
