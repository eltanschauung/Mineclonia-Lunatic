# Mineclonia-Lunatic
Lunatic is a Mineclonia fork that creates a Touhou-themed voxel game in Luanti. This repository contains the mods, assets and other relevant files for the mod, currently in early development. Implemented features include races, flight, weapons, ammunition, items, item/weapon rarity and new "nodes" (blocks). The purpose of this game is to provide an experience that has relative feature parity with modern Minecraft, but with a Gensokyo map and a large amount of Touhou related features and content in an MMORPG style. This game uses a Gensokyo map by the Touhoucraft project, see https://www.planetminecraft.com/project/touhou-gensokyo/

Mineclonia's repository: https://codeberg.org/mineclonia/mineclonia

# Map
The map was ported from Minecraft 1.16.2 to Mineclonia through my fork of the MC2MT tool: https://github.com/eltanschauung/MC2MT

~~Note: the tool was in fact forked to deal with certain errors found while attempting the conversion, the fork may be uploaded here on Github soon, but should you attempt it yourself, my methodology was to provide an AI agent the codebase and related errors, at which point it developed a fork, I recompiled the program and an output was successful.~~

Important note: to load the map without Mineclonia's generation damaging the terrain, disable the MCL level generation flags. This will be documented more in depth at a later time.

<img width="2000" height="1400" alt="image" src="https://github.com/user-attachments/assets/e27fb408-ddc1-4939-9091-eab4c74956bc" />

The map image above was generated with the C++ tool Minetestmapper and with the colors.txt file available in world/ along with some hue alteration in post processing.

# Planned
Magic broomsticks as vehicles in 3D space, mini-hakkero weapon, wolf tengu race, kappa race, flower fairy race, devil race, oji-san human villager race, ice fairy danmaku, frost walking effects for ice fairies, factions and faction reputations, NPCs with routines and faction alignments, magical protections of major locations for those without faction access, SDM goblin denizens, NPCs able to conduct repairs of their native locations, spellcards, spell tomes, quests, explosive danmaku (environmental damage), magic system, alchemy system, race-change methods such as completing certain quests or brewing certain potions, bartering system + currency with economy simulations, recoil on danmaku attacks, boat vehicles, replace hunger with a magical system for most non-human races, Minecraft style music system implementation, ambience system (such as rustling leaves sound effects when within range of outdoor leaves and so on)

# Early Video Preview of Features - Rather Promising Though!
<p align="center">
  <a href="https://www.youtube.com/watch?v=FlL5JzHz_dE">
    <img src="https://img.youtube.com/vi/FlL5JzHz_dE/0.jpg" alt="Video" />
  </a>
</p>
