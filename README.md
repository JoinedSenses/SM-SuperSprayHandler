### Syntax update of Super Spray Handler  
*Not thoroughly tested. Will maintain this plugin and bugfix if errors arise.*  
https://forums.alliedmods.net/showthread.php?t=281488

------------------------
# Super Spray Handler  
**By: TheWreckingCrew6**  
**The Complete Spray Management Plugin**  


**Credits:** This plugin is a combination of Shavit's Spray Manager plugin, which I (TheWreckingCrew6) have fixed up, and all the hard work of Nican132, CptMoore, and Lebson506th's Spray Trace plugin, which I have also fixed up. You could consider this a redux of both plugins.  

## Features:  
* Trace the owner of a spray  
* Remove a Spray  
* Admin Spray (Spray other peoples sprays)  
* Spray ban users  
* UnSprayban Users  
* Punish users directly through the plugin  

## Admin Menu Support:
* Admin Menu  
* Spray Menu  
* Punishment Menu  
* Bantimes Menu  
* Currently Connected Menu  
* SpraybanList Menu  

## Commands:  
* **sm_spraytrace** - Trace the owner of the spray you're looking at, and open the punishment menu.
* **sm_removespray** - Remove the spray you're looking at and open the punishment menu.
* **sm_qremovespray** - Removes the spray you're looking at and doesn't open the punishment menu.
* **sm_removeallsprays** - Removes all the sprays on the map at once.
* **sm_adminspray _<Steam_ID/Name>_** - Spray the persons spray where you are looking.
* **sm_sprayban** - Ban the user from spraying. Ever.
* **sm_sprayunban _<Steam_ID/Name>_** - Unban a Spray Banned user.
* **sm_offlinesprayban _<Steam_ID> [Name]_** - Spray ban someone not on the server.
* **sm_spraybans** - Shows a list of currently connected spray banned players.
  
  
### \*\*\*_All CVars are Automatically generated to "tf/cfg/sourcemod/plugin.ssh.cfg"_***  
## Convars:  
* **sm_ssh_enabled** - Defaults to 1, set to 0 to disable SSH.
* **sm_ssh_overlap** - Enable preventing users from spraying their sprays ontop of other sprays.
* **sm_ssh_auth** - (Default: 1) Which authentication identifiers should be seen in the HUD? This is a math cvar, add the proper numbers for your likings. (Example: 1 + 4 = 5/Name + IP address) 1 - Name 2 - SteamID 4 - IP address
* **sm_ssh_refresh** - (Default: 1.0) How often the program will trace to see player's spray to the HUD. 0 to disable.
* **sm_ssh_dista** - (Default: 50) How far away the spray will be traced to.
* **sm_ssh_enableban** - (Default: 1) Should banning be enabled in punishment menu?
* **sm_ssh_burntime** - (Default: 10) How long the burn punishment is for.
* **sm_ssh_slapdamage** - (Default: 5) How much damage the slap punishment is for. 0 to disable.
* **sm_ssh_enableslay** - (Default: 0) Enables the use of Slay as a punishment.
* **sm_ssh_enableburn** - (Default: 0) Enables the use of Burn as a punishment.
* **sm_ssh_enablepban** - (Default: 1) Enables the use of a Permanent Ban as a punishment.
* **sm_ssh_enablekick** - (Default: 1) Enables the use of Kick as a punishment.
* **sm_ssh_enablebeacon** - (Default: 0) Enables putting a beacon on the sprayer as a punishment.
* **sm_ssh_enablefreeze** - (Default: 0) Enables the use of Freeze as a punishment.
* **sm_ssh_enablefreezebomb** - (Default: 0) Enables the use of Freeze Bomb as a punishment.
* **sm_ssh_enablefirebomb** - (Default: 0) Enables the use of Fire Bomb as a punishment.
* **sm_ssh_enabletimebomb** - (Default: 0) Enables the use of Time Bomb as a punishment.
* **sm_ssh_enablespraybaninmenu** - (Default: 1) Enables Spray Ban in the Punishment Menu.
* **sm_ssh_drugtime** - (Default: 0) set the time a sprayer is drugged as a punishment. 0 to disable.
* **sm_ssh_autoremove** - (Default: 0) Enables automatically removing sprays when a punishment is dealt.
* **sm_ssh_restrict** - (Default: 1) Enables or disables restricting admins to punishments they are given access to. (1 = commands they have access to, 0 = all)
* **sm_ssh_useimmunity** - (Default: 1) Enables or disables using admin immunity to determine if one admin can punish another.
* **sm_ssh_global** - (Default: 1) Enables or disables global spray tracking. If this is on, sprays can still be tracked when a player leaves the server.
* **sm_ssh_location** - (Default: 1) Where players will see the owner of the spray that they're aiming at? 0 - Disabled 1 - Hud hint 2 - Hint text (like sm_hsay) 3 - Center text (like sm_csay) 4 - HUD
* **sm_ssh_hudtime** - (Default: 1.0) How long the HUD messages are displayed.
* **sm_ssh_confirmactions** - (Default: 1) Should you have to confirm spray banning or unspray banning someone?

## Installation Instructions:  
* Place supersprayhandler.smx in your plugins folder.
* Place translations/ssh.phrases.txt in your translations folder.
* Place the following code with your own sql info into your databases.cfg. Title it "ssh" in the file.

#### MySql:  
```
    "ssh"
    {
        "driver"      "default"
        "host"        "ip/hostname"
        "database"    "database"
        "user"        "username"
        "pass"        "password"
        "port"        "3306"
    }
```

#### SqLite:  
```
    "ssh"
    {
        "driver"      "sqlite"
        "database"     "ssh"
    }
```

