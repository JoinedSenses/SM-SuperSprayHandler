#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <ssh>
#include <smlib>
#undef REQUIRE_PLUGIN
#include <adminmenu>



//Used to easily access my cvars out of an array.
#define PLUGIN_VERSION "1.3.4"
enum {
	ENABLED = 0,
	ANTIOVERLAP,
	AUTH,
	MAXDIS,
	REFRESHRATE,
	USEBAN,
	BURNTIME,
	SLAPDMG,
	USESLAY,
	USEBURN,
	USEPBAN,
	USEKICK,
	USEFREEZE,
	USEBEACON,
	USEFREEZEBOMB,
	USEFIREBOMB,
	USETIMEBOMB,
	USESPRAYBAN,
	DRUGTIME,
	AUTOREMOVE,
	RESTRICT,
	IMMUNITY,
	GLOBAL,
	LOCATION,
	HUDTIME,
	CONFIRMACTIONS,
	NUMCVARS
}

#define MAX_CONNECTIONS 5
#define ZERO_VECTOR view_as<float>({0.0, 0.0, 0.0})

//Creates my array of CVars
ConVar g_arrCVars[NUMCVARS];

//Vital arrays that store all of our important information :D
char g_arrSprayName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_arrSprayID[MAXPLAYERS + 1][32];
char g_arrMenuSprayID[MAXPLAYERS + 1][32];
float g_fSprayVector[MAXPLAYERS+1][3];
int g_arrSprayTime[MAXPLAYERS + 1];
char g_sAuth[MAXPLAYERS+1][128];
bool g_bSpraybanned[MAXPLAYERS+1];
Database g_Database;

//Our Timer that will be initialized later
Handle g_hSprayTimer;

//Global boolean that is defined later on if your server can use the HUD. (sm_ssh_location == 4)
bool g_bCanUseHUD;
int g_iHudLoc;

//The HUD that will be initialized later IF your server supports the HUD.
Handle g_hHUD;

//Used later to decide what type of ban to place
ConVar g_hExternalBan;

int g_iConnections;

//Our main admin menu handle >.>
TopMenu g_hAdminMenu;
TopMenuObject menu_category;

//Forwards
Handle g_hBanForward;
Handle g_hUnbanForward;

//Were we late loaded?
bool g_bLate;

//Used for the glow that is applied when tracing a spray
int g_PrecacheRedGlow;

//The plugin info :D
public Plugin myinfo = {
	name = "Super Spray Handler",
	description = "Ultimate Tool for Admins to manage Sprays on their servers.",
	author = "shavit, Nican132, CptMoore, Lebson506th, and TheWreckingCrew6",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/member.php?u=163134"
}

//Used to create the natives for other plugins to hook into this beauty
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("ssh_BanClient", Native_BanClient);
	CreateNative("ssh_UnbanClient", Native_UnbanClient);
	CreateNative("ssh_IsBanned", Native_IsBanned);

	RegPluginLibrary("ssh");

	g_bLate = late;

	return APLRes_Success;
}

//What we want to do when this beauty starts up.
public void OnPluginStart() {
	//We want these translations files :D
	LoadTranslations("ssh.phrases");
	LoadTranslations("common.phrases");

	//Base convar obviously
	CreateConVar("sm_spray_version", PLUGIN_VERSION, "Super Spray Handler plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);


	//Beautiful Commands
	RegAdminCmd("sm_spraytrace", Command_TraceSpray, ADMFLAG_BAN, "Look up the owner of the logo in front of you.");
	RegAdminCmd("sm_removespray", Command_RemoveSpray, ADMFLAG_BAN, "Remove the logo in front of you.");
	RegAdminCmd("sm_adminspray", Command_AdminSpray, ADMFLAG_BAN, "Sprays the named player's logo in front of you.");
	RegAdminCmd("sm_qremovespray", Command_QuickRemoveSpray, ADMFLAG_BAN, "Removes the logo in front of you without opening punishment menu.");
	RegAdminCmd("sm_removeallsprays", Command_RemoveAllSprays, ADMFLAG_BAN, "Removes all sprays from the map.");

	RegAdminCmd("sm_sprayban", Command_Sprayban, ADMFLAG_BAN, "Usage: sm_sprayban <target>");
	RegAdminCmd("sm_sban", Command_Sprayban, ADMFLAG_BAN, "Usage: sm_sban <target>");

	RegAdminCmd("sm_offlinesprayban", Command_OfflineSprayban, ADMFLAG_BAN, "Usage: sm_offlinesprayban <steamid> [name]");
	RegAdminCmd("sm_offlinesban", Command_OfflineSprayban, ADMFLAG_BAN, "Usage: sm_offlinesban <steamid> [name]");

	RegAdminCmd("sm_sprayunban", Command_Sprayunban, ADMFLAG_UNBAN, "Usage: sm_sprayunban <target>");
	RegAdminCmd("sm_sunban", Command_Sprayunban, ADMFLAG_UNBAN, "Usage: sm_sunban <target>");

	RegAdminCmd("sm_sbans", Command_Spraybans, ADMFLAG_GENERIC, "Shows a list of all connected spray banned players.");
	RegAdminCmd("sm_spraybans", Command_Spraybans, ADMFLAG_GENERIC, "Shows a list of all connected spray banned players.");

	CreateConVar("sm_ssh_version", PLUGIN_VERSION, "Super Spray Handler version", FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_NOTIFY);

	//Spray Manager CVars
	g_arrCVars[ENABLED] = CreateConVar("sm_ssh_enabled", "1", "Enable \"Super Spray Handler\"?", 0, true, 0.0, true, 1.0);
	g_arrCVars[ANTIOVERLAP] = CreateConVar("sm_ssh_overlap", "0", "Prevent spray-on-spray overlapping?\nIf enabled, specify an amount of units that another player spray's distance from the new spray needs to be it or more, recommended value is 75.", 0, true, 0.0);
	g_arrCVars[AUTH] = CreateConVar("sm_ssh_auth", "1", "Which authentication identifiers should be seen in the HUD?\n- This is a \"math\" cvar, add the proper numbers for your likings. (Example: 1 + 4 = 5/Name + IP address)\n1 - Name\n2 - SteamID\n4 - IP address", 0, true, 1.0);

	//SSH CVars
	g_arrCVars[REFRESHRATE] = CreateConVar("sm_ssh_refresh","1.0","How often the program will trace to see player's spray to the HUD. 0 to disable.");
	g_arrCVars[MAXDIS] = CreateConVar("sm_ssh_dista","50.0","How far away the spray will be traced to.");
	g_arrCVars[USEBAN] = CreateConVar("sm_ssh_enableban","1","Whether or not banning is enabled. 0 to disable temporary banning.");
	g_arrCVars[BURNTIME] = CreateConVar("sm_ssh_burntime","10","How long the burn punishment is for.");
	g_arrCVars[SLAPDMG] = CreateConVar("sm_ssh_slapdamage","5","How much damage the slap punishment is for. 0 to disable.");
	g_arrCVars[USESLAY] = CreateConVar("sm_ssh_enableslay","0","Enables the use of Slay as a punishment.");
	g_arrCVars[USEBURN] = CreateConVar("sm_ssh_enableburn","0","Enables the use of Burn as a punishment.");
	g_arrCVars[USEPBAN] = CreateConVar("sm_ssh_enablepban","1","Enables the use of a Permanent Ban as a punishment.");
	g_arrCVars[USEKICK] = CreateConVar("sm_ssh_enablekick","1","Enables the use of Kick as a punishment.");
	g_arrCVars[USEBEACON] = CreateConVar("sm_ssh_enablebeacon","0","Enables putting a beacon on the sprayer as a punishment.");
	g_arrCVars[USEFREEZE] = CreateConVar("sm_ssh_enablefreeze","0","Enables the use of Freeze as a punishment.");
	g_arrCVars[USEFREEZEBOMB] = CreateConVar("sm_ssh_enablefreezebomb","0","Enables the use of Freeze Bomb as a punishment.");
	g_arrCVars[USEFIREBOMB] = CreateConVar("sm_ssh_enablefirebomb","0","Enables the use of Fire Bomb as a punishment.");
	g_arrCVars[USETIMEBOMB] = CreateConVar("sm_ssh_enabletimebomb","0","Enables the use of Time Bomb as a punishment.");
	g_arrCVars[USESPRAYBAN] = CreateConVar("sm_ssh_enablespraybaninmenu","1","Enables Spray Ban in the Punishment Menu.");
	g_arrCVars[DRUGTIME] = CreateConVar("sm_ssh_drugtime","0","set the time a sprayer is drugged as a punishment. 0 to disable.");
	g_arrCVars[AUTOREMOVE] = CreateConVar("sm_ssh_autoremove","0","Enables automatically removing sprays when a punishment is dealt.");
	g_arrCVars[RESTRICT] = CreateConVar("sm_ssh_restrict","1","Enables or disables restricting admins to punishments they are given access to. (1 = commands they have access to, 0 = all)");
	g_arrCVars[IMMUNITY] = CreateConVar("sm_ssh_useimmunity","1","Enables or disables using admin immunity to determine if one admin can punish another.");
	g_arrCVars[GLOBAL] = CreateConVar("sm_ssh_global","1","Enables or disables global spray tracking. If this is on, sprays can still be tracked when a player leaves the server.");
	g_arrCVars[LOCATION] = CreateConVar("sm_ssh_location","1","Where players will see the owner of the spray that they're aiming at? 0 - Disabled 1 - Hud hint 2 - Hint text (like sm_hsay) 3 - Center text (like sm_csay) 4 - HUD");
	g_arrCVars[HUDTIME] = CreateConVar("sm_ssh_hudtime","1.0","How long the HUD messages are displayed.");
	g_arrCVars[CONFIRMACTIONS] = CreateConVar("sm_ssh_confirmactions","1","Should you have to confirm spray banning and un-spraybanning?");

	g_arrCVars[REFRESHRATE].AddChangeHook(TimerChanged);
	g_arrCVars[LOCATION].AddChangeHook(LocationChanged);
	g_iHudLoc = g_arrCVars[LOCATION].IntValue;

	AutoExecConfig(true, "plugin.ssh");

	//Forwards
	g_hBanForward = CreateGlobalForward("ssh_OnBan", ET_Event, Param_Cell);
	g_hUnbanForward = CreateGlobalForward("ssh_OnUnban", ET_Event, Param_Cell);

	//Adds hook that looks for when a player sprays a decal.
	AddTempEntHook("Player Decal", Player_Decal);

	//Figures out what game you're running to then check for HUD support.
	char gamename[32];
	GetGameFolderName(gamename, sizeof gamename);

	//Checks for support of the HUD in current server, if not supported, changes sm_ssh_location to 1.
	g_bCanUseHUD = StrEqual(gamename,"tf", false)
		|| StrEqual(gamename,"hl2mp", false)
		|| StrEqual(gamename, "synergy", false)
		|| StrEqual(gamename,"sourceforts", false)
		|| StrEqual(gamename,"obsidian", false)
		|| StrEqual(gamename,"left4dead", false)
		|| StrEqual(gamename,"l4d", false);

	if (g_bCanUseHUD) {
		g_hHUD = CreateHudSynchronizer();
	}

	if (g_hHUD == null && g_arrCVars[LOCATION].IntValue == 4) {
		g_arrCVars[LOCATION].SetInt(1, true);

		LogError("[Super Spray Handler] This game can't use HUD messages, value of \"sm_ssh_location\" forced to 1.");
	}

	//Calls creating the admin menu, but checks to make sure server has admin menu plugin loaded.
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null)) {
		OnAdminMenuReady(topmenu);
	}

	SQL_Connector();
}

//When the map starts we want to create timers, cache our glow effect, and clear any info that may have decided to stick around.
public void OnMapStart() {
	CreateTimers();

	g_PrecacheRedGlow = PrecacheModel("sprites/redglow1.vmt");

	for (int i = 1; i <= MaxClients; i++) {
		ClearVariables(i);
	}
}

//If sm_ssh_global = 0 then we want to get rid of a players spray when they leave.
public void OnClientDisconnect(int client) {
	if (!g_arrCVars[GLOBAL].BoolValue) {
		ClearVariables(client);
	}
}

//When a client joins we need to 1: default his spray to 0 0 0. 2: Check in the database if he is spray banned.
public void OnClientPutInServer(int client) {
	g_fSprayVector[client] = ZERO_VECTOR;
	g_bSpraybanned[client] = false;

	if (g_Database) {
		CheckBan(client);
	}
}

//If you unload the admin menu, we don't want to keep using it :/
public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "adminmenu")) {
		g_hAdminMenu = null;
	}
}


/******************************************************************************************
 *                           SPRAY TRACING TO THE HUD/HINT TEXT                           *
 ******************************************************************************************/

int g_iSprayTarget[MAXPLAYERS+1] = {-1, ...};
//0 is last look time, 1 is last actual hud text time
float g_fSprayTraceTime[MAXPLAYERS + 1][2];

//Handles tracing sprays to the HUD or hint message
public Action CheckAllTraces(Handle hTimer) {
	if (!GetClientCount(true)) {
		return;
	}

	char strMessage[128];
	int hudType = (g_bCanUseHUD ? g_iHudLoc : 0);
	float vecPos[3];
	bool bHudParamsSet = false;
	float flGameTime = GetGameTime();
	//Pray for the processor - O(n^2) (but better now)
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsValidClient(client) || IsFakeClient(client)) {
			g_iSprayTarget[client] = -1;
			continue;
		}

		//We don't want the message to show on our screen for years after we stopped looking at a spray. right?
		switch (hudType) {
			case 1: {
				Client_PrintKeyHintText(client, "");
			}
			case 2: {
				Client_PrintHintText(client, "");
			}
			case 3: {
				PrintCenterText(client, "");
			}
		}

		//Make sure you're looking at a valid location.
		if (!GetClientEyeEndLocation(client, vecPos)) {
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		//Do you REALLY have full access?
		bool bFullAccess = CheckCommandAccess(client, "ssh_hud_access_full", ADMFLAG_GENERIC, true);
		if (!bFullAccess && !CheckCommandAccess(client, "ssh_hud_access", 0, true)) {
			continue;
		}

		//Let's check if you can trace admins
		bool bTraceAdmins = CheckCommandAccess(client, "ssh_hud_can_trace_admins", 0, true);
		int target = -1;
		for (int a = 1; a <= MaxClients; a++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[a]) <= g_arrCVars[MAXDIS].FloatValue) {
				target = a;
				break;
			}
		}
		//Lets just figure out what target we're looking at?
		if (!IsValidClient(target)) {
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		//Check if you're an admin.
		bool bTargetIsAdmin = CheckCommandAccess(target, "ssh_hud_is_admin", ADMFLAG_GENERIC, true);
		if (!bTraceAdmins && bTargetIsAdmin) {
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		if (CheckForZero(g_fSprayVector[target])) {
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		//Generate the text that is to be shown on your screen.
		FormatEx(strMessage, sizeof strMessage, "Sprayed by:\n%s", bFullAccess ? g_sAuth[target] : g_arrSprayName[target]);


		switch (hudType) {
			case 1: {
				Client_PrintKeyHintText(client, strMessage);
			}
			//This is annoying af. Need to find a way to fix it.
			case 2: {
				Client_PrintHintText(client, strMessage);
			}
			case 3: {
				PrintCenterText(client, strMessage);
			}
			case 4: {
				if (!bHudParamsSet) {
					bHudParamsSet = true;
					//15s sounds reasonable
					//the color tends to get weird if you don't set it different each tick
					SetHudTextParams(0.04, 0.6, 15.0, 255, 12, 39, 240 + (RoundToFloor(flGameTime) % 2), _, 0.2);
				}

				if (flGameTime > g_fSprayTraceTime[client][1] + 14.5 || target != g_iSprayTarget[client]) {
					ShowSyncHudText(client, g_hHUD, strMessage);
					g_iSprayTarget[client] = target;
					g_fSprayTraceTime[client][1] = flGameTime;
				}

				g_fSprayTraceTime[client][0] = flGameTime;
			}
		}
	}
}

void ClearHud(int client, int hudType, float gameTime) {
	if (gameTime > g_fSprayTraceTime[client][0] + g_arrCVars[HUDTIME].FloatValue - g_arrCVars[REFRESHRATE].FloatValue) {
		//wow, such repeated code
		if (g_iSprayTarget[client] != -1) {
			if (g_hHUD != null) {
				ClearSyncHud(client, g_hHUD);
			}
			else {
				switch (hudType) {
					case 1: {
						Client_PrintKeyHintText(client, "");
					}
					case 2: {
						Client_PrintHintText(client, "");
					}
					case 3: {
						PrintCenterText(client, "");
					}
				}
			}
		}

		g_iSprayTarget[client] = -1;
	}
}

/******************************************************************************************
 *                           ADMIN MENU METHODS FOR CUSTOM MENU                           *
 ******************************************************************************************/

 //Our custom category needs to know what to do right?
public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayTitle) {
		FormatEx(buffer, maxlength, "Spray Commands: ");
	}

	else if (action == TopMenuAction_DisplayOption) {
		FormatEx(buffer, maxlength, "Spray Commands");
	}
}

//When the admin menu is ready, lets define our topmenu object, and add our commands to it.
public void OnAdminMenuReady(Handle aTopMenu) {
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	if (menu_category == INVALID_TOPMENUOBJECT) {
		OnAdminMenuCreated(topmenu);
	}

	if (topmenu == g_hAdminMenu) {
		return;
	}

	g_hAdminMenu = topmenu;

	g_hAdminMenu.AddItem("sm_spraybans", AdminMenu_SprayBans, menu_category, "sm_spraybans", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_spraytrace", AdminMenu_TraceSpray, menu_category, "sm_spraytrace", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_removespray", AdminMenu_SprayRemove, menu_category, "sm_removespray", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_adminspray", AdminMenu_AdminSpray, menu_category, "sm_adminspray", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_sprayban", AdminMenu_SprayBan, menu_category, "sm_sprayban", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_sprayunban", AdminMenu_SprayUnban, menu_category, "sm_sprayunban", ADMFLAG_UNBAN);
	g_hAdminMenu.AddItem("sm_qremovespray", AdminMenu_QuickSprayRemove, menu_category, "sm_qremovespray", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("sm_removeallsprays", AdminMenu_RemoveAllSprays, menu_category, "sm_removeallsprays", ADMFLAG_BAN);
}

//When we have our admin menu created, lets make our custom category.
public void OnAdminMenuCreated(Handle aTopMenu) {
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
	/* Block us from being called twice */
	if (topmenu == g_hAdminMenu && menu_category != INVALID_TOPMENUOBJECT) {
		return;
	}

	menu_category = topmenu.AddCategory("Spray Commands", CategoryHandler);
}

/******************************************************************************************
 *                               SQL METHODS FOR SPRAY BANS                               *
 ******************************************************************************************/

 //Connects us to the database and reads the databases.cfg
void SQL_Connector() {
	delete g_Database;

	if (!SQL_CheckConfig("ssh")) {
		SetFailState("PLUGIN STOPPED - Reason: No config entry found for 'ssh' in databases.cfg - PLUGIN STOPPED");
	}

	Database.Connect(SQL_ConnectorCallback, "ssh");
}

//What actually is called to establish a connection to the database.
//public SQL_ConnectorCallback(Handle owner, Handle hndl, const char[] error, any data) {
public void SQL_ConnectorCallback(Database db, const char[] error, any data) {
	if (!db || error[0]) {
		LogError("Connection to SQL database has failed, reason: %s", error);

		g_iConnections++;

		SQL_Connector();

		if (g_iConnections == MAX_CONNECTIONS) {
			SetFailState("Connection to SQL database has failed too many times (%d), plugin unloaded to prevent spam.", MAX_CONNECTIONS);
		}

		return;
	}

	g_Database = db;

	DBDriver dbDriver = g_Database.Driver;
	char driver[16];
	dbDriver.GetIdentifier(driver, sizeof(driver));

	if (StrEqual(driver, "mysql", false)) {
		SQL_LockDatabase(g_Database);
		SQL_FastQuery(g_Database, "SET NAMES \"UTF8\"");
		SQL_UnlockDatabase(g_Database);

		g_Database.Query(SQL_CreateTableCallback, "CREATE TABLE IF NOT EXISTS `ssh` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32) DEFAULT '<unknown>', PRIMARY KEY (`auth`)) ENGINE = InnoDB CHARACTER SET utf8 COLLATE utf8_general_ci;");
	}
	else if (StrEqual(driver, "sqlite", false)) {
		g_Database.Query(SQL_CreateTableCallback, "CREATE TABLE IF NOT EXISTS `ssh` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32) DEFAULT '<unknown>', PRIMARY KEY (`auth`));");
	}

	delete dbDriver;
}

//More SQL Stuff
public void SQL_CreateTableCallback(Database db, DBResultSet results, const char[] error, any data) {
	if (!db || !results || error[0]) {
		LogError(error);
		return;
	}

	if (g_bLate) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

//What is called to check in the database if a player is spray banned.
void CheckBan(int client) {
	if (!IsValidClient(client) || !g_Database) {
		return;
	}

	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, 32, true)) {
		CreateTimer(5.0, timerCheckBan, GetClientUserId(client));
		return;
	}

	char query[256];
	FormatEx(query, sizeof query, "SELECT * FROM ssh WHERE auth = '%s'", auth);
	g_Database.Query(sqlQuery_CheckBan, query, GetClientUserId(client));
}

public Action timerCheckBan(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (!client) {
		return Plugin_Stop;
	}

	CheckBan(client);

	return Plugin_Stop;
}

public void sqlQuery_CheckBan(Database db, DBResultSet results, const char[] error, int userid) {
	if (!db || !results || error[0]) {
		LogError("CheckBan query failed. (%s)", error);
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client) {
		g_bSpraybanned[client] = results.FetchRow();
	}
}



/******************************************************************************************
 *                           OUR HOOKS :D TO ACTUALLY DO STUFF                            *
 ******************************************************************************************/

 //When a player trys to spray a decal.
public Action Player_Decal(const char[] name, const int[] clients, int count, float delay) {
	//Is this plugin enabled? If not then no need to run the rest of this.
	if (!g_arrCVars[ENABLED].BoolValue) {
		return Plugin_Continue;
	}

	//Gets the client that is spraying.
	int client = TE_ReadNum("m_nPlayer");

	//Is this even a valid client?
	if (IsValidClient(client) && !IsClientReplay(client) && !IsClientSourceTV(client)) {
		//We need to check if this player is spray banned, and if so, we will pre hook this spray attempt and block it.
		if (g_bSpraybanned[client]) {
			PrintToChat(client, "\x04[Super Spray Handler]\x01 You are Spray Banned and thus unable to Spray.");
			return Plugin_Handled;
		}

		//If we're here, they are obviously not spray banned. So lets find where they are spraying.
		float fSprayVector[3];
		TE_ReadVector("m_vecOrigin", fSprayVector);

		//Now we need to check if this spray is too close to another spray if sm_ssh_overlap > 0
		if (g_arrCVars[ANTIOVERLAP].FloatValue > 0) {
			for (int i = 1; i <= MaxClients; i++) {
				if (IsValidClient(i) && i != client && !CheckForZero(g_fSprayVector[i])) {
					if (GetVectorDistance(fSprayVector, g_fSprayVector[i]) <= g_arrCVars[ANTIOVERLAP].FloatValue) {
						PrintToChat(client, "\x04[Super Spray Handler]\x01 Your spray is too close to \x05%N\x01's spray.", i);

						return Plugin_Handled;
					}
				}
			}
		}

		//Either anti-overlapping isn't enabled or the spray was sprayed in an ok location
		//Now Let's store the Sprays Location, Time of Spray, Who Sprayed it, and the ID of the player.
		g_fSprayVector[client] = fSprayVector;
		g_arrSprayTime[client] = RoundFloat(GetGameTime());
		GetClientName(client, g_arrSprayName[client], sizeof g_arrSprayName[]);
		if (!GetClientAuthId(client, AuthId_Steam2, g_arrSprayID[client], sizeof g_arrSprayID[])) {
			g_arrSprayID[client][0] = '\0';
		}

		//This is where we generate what is displayed when tracing a spray to HUD/Hint
		g_sAuth[client][0] = '\0';

		//If our math variable includes a 1 in it, we will add the player's name into the string.
		if (g_arrCVars[AUTH].IntValue & 1) {
			Format(g_sAuth[client], sizeof g_sAuth[], "%s%N", g_sAuth[client], client);
		}

		//If our math variable includes a 2 in it, we will add the player's STEAM_ID into the string.
		if (g_arrCVars[AUTH].IntValue & 2) {
			Format(g_sAuth[client], sizeof g_sAuth[], "%s%s(%s)", g_sAuth[client], g_arrCVars[AUTH].IntValue & 1 ? "\n" : "", g_arrSprayID[client]);
		}

		//And lastly, if our math variable includes a 4 in it, we simply add the IP into the string.
		if (g_arrCVars[AUTH].IntValue & 4) {
			char IP[32];
			GetClientIP(client, IP, sizeof IP);

			Format(g_sAuth[client], sizeof g_sAuth[], "%s%s(%s)", g_sAuth[client], g_arrCVars[AUTH].IntValue & (1|2) ? "\n" : "", IP);
		}
	}

	//Now we're done here.
	return Plugin_Continue;
}

//When the Location cvar changes, this is called
public void LocationChanged(ConVar hConVar, const char[] szOldValue, const char[] szNewValue) {
	g_iHudLoc = hConVar.IntValue;
	g_arrCVars[LOCATION].SetInt(StringToInt(szNewValue), true, false);
}

/******************************************************************************************
 *                                   SPRAY BANNING >.>                                    *
 ******************************************************************************************/

 //What decides what happens when you select the Spray Ban option in the admin menu
public void AdminMenu_SprayBan(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		FormatEx(buffer, maxlength, "Spray Ban");
	}
	else if (action == TopMenuAction_SelectOption) {
		Menu menu = new Menu(MenuHandler_SprayBan);
		menu.SetTitle("Spray Ban:");

		int count;

		for (int i = 1; i <= MaxClients; i++) {
			if (!IsValidClient(i) || IsClientReplay(i) || IsClientSourceTV(i)) {
				continue;
			}

			if (g_bSpraybanned[i]) {
				continue;
			}

			char info[8];
			char name[MAX_NAME_LENGTH];

			IntToString(GetClientUserId(i), info, 8);
			GetClientName(i, name, MAX_NAME_LENGTH);

			menu.AddItem(info, name);

			count++;
		}

		if (!count) {
			menu.AddItem("none", "No matching players found");
		}

		menu.ExitBackButton = true;

		menu.Display(param, 20);
	}
}

//What happens when you use the spray ban menu?
public int MenuHandler_SprayBan(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			menu.GetItem(param2, info, 8);

			FakeClientCommand(param1, "sm_sprayban #%d", StringToInt(info));
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//What is called when you run !sm_sprayban
public Action Command_Sprayban(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}

	if (!args) {
		ReplyToCommand(client, "[SM] Usage: sm_sprayban <target>");
		return Plugin_Handled;
	}

	char arg1[MAX_TARGET_LENGTH];
	GetCmdArg(1, arg1, MAX_TARGET_LENGTH);

	int target = FindTarget(client, arg1);

	if (target == -1) {
		return Plugin_Handled;
	}

	if (g_bSpraybanned[target]) {
		ReplyToCommand(client, "[SM] Unable to spray ban %N, reason - already spray banned.", target);
		return Plugin_Handled;
	}

	if (g_arrCVars[CONFIRMACTIONS].BoolValue) {
		DisplayConfirmMenu(client, target, 0);
	}
	else {
		RunSprayBan(client, target);
	}

	return Plugin_Handled;
}

//What actually places the spray ban.
public void RunSprayBan(int client, int target) {
	char targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, MAX_NAME_LENGTH);

	int len = 2*strlen(targetName)+1;
	char[] targetSafeName = new char[len];
	g_Database.Escape(targetName, targetSafeName, len);

	char auth[32];
	if (GetClientAuthId(target, AuthId_Steam2, auth, sizeof auth)) {
		AddSprayBan(target, auth);
	}
	else {
		CreateTimer(5.0, timerAddSprayBan, GetClientUserId(target), TIMER_REPEAT);
	}

	ReplyToCommand(client, "[SM] Successfully spray banned %N.", target);
	PrintToChat(target, "\x04[Super Spray Handler]\x01 You've been spray banned.");

	LogAction(client, target, "Spray banned.");
	ShowActivity(client, "Spray banned %N", target);

	g_fSprayVector[target] = ZERO_VECTOR;

	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", ZERO_VECTOR);
	TE_WriteNum("m_nEntity", 0);
	TE_WriteNum("m_nPlayer", target);
	TE_SendToAll();

	g_bSpraybanned[target] = true;

	Call_StartForward(g_hBanForward);
	Call_PushCell(target);
	Call_Finish();
}

public Action timerAddSprayBan(Handle timer, int userid) {
	int client = GetClientUserId(userid);
	if (!client) {
		return Plugin_Stop;
	}

	char auth[32];
	if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof auth)) {
		AddSprayBan(client, auth);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void AddSprayBan(int client, const char[] auth) {
	char query[256];
	g_Database.Format(query, sizeof query, "INSERT INTO ssh (auth, name) VALUES ('%s', '%N');", auth, client);

	SQL_LockDatabase(g_Database);
	SQL_FastQuery(g_Database, query);
	SQL_UnlockDatabase(g_Database);
}

/******************************************************************************************
 *                                 SPRAY UN-BANNING >.>                                   *
 ******************************************************************************************/

//What handles when you select to Un-Spray ban someone
public void AdminMenu_SprayUnban(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		FormatEx(buffer, maxlength, "Spray Unban");
	}
	else if (action == TopMenuAction_SelectOption) {
		Menu menu = new Menu(MenuHandler_SprayUnban);
		menu.SetTitle("Spray Unban:");

		int count;

		for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				if (g_bSpraybanned[i]) {
					char info[8];
					char name[MAX_NAME_LENGTH];

					IntToString(GetClientUserId(i), info, sizeof info);
					GetClientName(i, name, MAX_NAME_LENGTH);

					menu.AddItem(info, name);

					count++;
				}
			}
		}

		if (!count) {
			menu.AddItem("none", "No matching players found");
		}

		menu.ExitBackButton = true;

		menu.Display(param, 20);
	}
}

//What handles your selection on who to unspray ban.
public int MenuHandler_SprayUnban(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			menu.GetItem(param2, info, 8);

			FakeClientCommand(param1, "sm_sprayunban #%d", StringToInt(info));
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//What is called when you run !sm_sprayunban
public Action Command_Sprayunban(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}

	if (!args) {
		ReplyToCommand(client, "[SM] Usage: sm_sprayunban <target>");
		return Plugin_Handled;
	}

	char arg1[MAX_TARGET_LENGTH];
	GetCmdArg(1, arg1, MAX_TARGET_LENGTH);

	int target = FindTarget(client, arg1);

	if (target == -1) {
		return Plugin_Handled;
	}

	if (!g_bSpraybanned[target]) {
		ReplyToCommand(client, "[SM] Unable to spray unban %N, reason - not spray banned.", target);
		return Plugin_Handled;
	}

	if (g_arrCVars[CONFIRMACTIONS].BoolValue) {
		DisplayConfirmMenu(client, target, 1);
	}
	else {
		RunUnSprayBan(client, target);
	}

	return Plugin_Handled;
}

//What actually handles un-spraybanning a player.
public void RunUnSprayBan(int client, int target) {
	char auth[32];
	if (!GetClientAuthId(target, AuthId_Steam2, auth, sizeof auth)) {
		ReplyToCommand(client, "Unable to spray unban %N. Unable to retrieve their steam id. Try again later.", target);
		return;
	}

	g_bSpraybanned[target] = false;

	char sQuery[256];
	FormatEx(sQuery, sizeof sQuery, "DELETE FROM ssh WHERE auth = '%s';", auth);

	SQL_LockDatabase(g_Database);
	SQL_FastQuery(g_Database, sQuery);
	SQL_UnlockDatabase(g_Database);

	LogAction(client, target, "Spray unbanned.");
	ShowActivity(client, "Spray unbanned %N", target);

	Call_StartForward(g_hUnbanForward);
	Call_PushCell(target);
	Call_Finish();

	ReplyToCommand(client, "[SM] Successfully spray unbanned %N.", target);
	PrintToChat(target, "\x04[Super Spray Handler]\x01 You've been spray unbanned.");
}

/******************************************************************************************
 *                              LISTING OUR SPRAYBANNED PLAYERS                           *
 ******************************************************************************************/

 //What is called to display the Options Menu
 public void DisplayListOptionsMenu(int client) {
	Menu menu = new Menu(MenuHandler_ListOptions);
	menu.SetTitle("What Spray-Banned Clients to you wish to list?");

	menu.AddItem("1", "Currently Connected Spray-Banned Clients");
	menu.AddItem("2", "All Spray-Banned clients");

	menu.ExitButton = true;

	menu.Display(client, 20);
 }

 //Menu Handler for the Options Menu
public int MenuHandler_ListOptions(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[32];
			menu.GetItem(param2, choice, sizeof(choice));

			switch (StringToInt(choice)) {
				case 1: {
					DisplaySprayBans(param1);
				}
				case 2: {
					g_Database.Query(AllSprayBansCallback, "SELECT * FROM ssh", GetClientSerial(param1));
				}
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//What happens when you select to list currently connected spray banned players?
public void AdminMenu_SprayBans(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	switch (action) {
		case TopMenuAction_DisplayOption: {
			FormatEx(buffer, maxlength, "Spray Ban List");
		}
		case TopMenuAction_SelectOption: {
			DisplayListOptionsMenu(param);
		}
	}
}

//What happens when you run !sm_spraybans?
public Action Command_Spraybans(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}

	DisplayListOptionsMenu(client);

	return Plugin_Handled;
}

//Display the currently connected spray banned players.
public void DisplaySprayBans(int client) {
	Menu menu = new Menu(MenuHandler_SprayBans);
	menu.SetTitle(
		"----------------------------------------------\n"
	... "Spray Banned Players: (Select a client to un-sprayban)\n"
	... "----------------------------------------------\n"
	... "(Select a client to un-sprayban)"
	);

	int count;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			if (g_bSpraybanned[i]) {
				char auth[MAX_STEAMAUTH_LENGTH];
				if (!GetClientAuthId(i, AuthId_Steam2, auth, sizeof auth)) {
					strcopy(auth, sizeof auth, "SteamID Unavailable");
				}

				char name[MAX_NAME_LENGTH];
				GetClientName(i, name, sizeof name);

				char Display[128];
				FormatEx(Display, sizeof Display, "%s - %s", name, auth);

				char info[64];
				IntToString(i, info, sizeof(info));

				menu.AddItem(info, Display);

				count++;
			}
		}
	}

	if (!count) {
		menu.AddItem("none", "No spray banned players are connected.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 20);
}

//Menu HAndler for the spray bans menu
public int MenuHandler_SprayBans(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			if (!CheckCommandAccess(param1, "sm_sprayunban", ADMFLAG_UNBAN)) {
				return 0;
			}

			char info[32];
			menu.GetItem(param2, info, 32);

			int target = StringToInt(info);

			char auth[MAX_STEAMAUTH_LENGTH];
			if (!GetClientAuthId(target, AuthId_Steam2, auth, sizeof auth)) {
				PrintToChat(param1, "Unable to spray unban %N. Steam id unavailable. Try again later.", target);
				return 0;
			}

			char name[MAX_NAME_LENGTH];
			GetClientName(target, name, sizeof(name));



			if (!StrEqual(info, "none")) {
				Menu menu2 = new Menu(MenuHandler_Spraybans_Ban);
				menu2.SetTitle("Are you sure you want to spray un-ban %s (%s)?", name, auth);

				menu2.AddItem(info, "Yes");
				menu2.AddItem("none", "No");

				menu2.ExitBackButton = true;

				menu2.Display(param1, 20);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayListOptionsMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//Menu HAndler for the un-banning part of the list.
public int MenuHandler_Spraybans_Ban(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[32];
			menu.GetItem(param2, info, 32);

			int target = StringToInt(info);

			if (!StrEqual(info, "none")) {
				RunUnSprayBan(param1, target);
			}
			else {
				DisplaySprayBans(param1);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				Command_Spraybans(param1, -1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//What is called to list all the spray bans there are in yoru database
//public void AllSprayBansCallback(Handle owner, Handle hndl, const char[] error, any data) {
public void AllSprayBansCallback(Database db, DBResultSet results, const char[] error, any data) {
	if (!db || !results || error[0]) {
		LogError("SQL error in Listing All Spray Bans: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if (!IsValidClient(client)) {
		return;
	}

	Menu menu = new Menu(MenuHandler_AllSpraybans);
	menu.SetTitle("----------------------------------------------\n"
	... "Spray Banned Players: (Select a client to un-sprayban)\n"
	... "----------------------------------------------\n"
	... "(Select a client to un-sprayban)");

	while (results.FetchRow()) {
		char auth[MAX_STEAMAUTH_LENGTH];
		results.FetchString(0, auth, MAX_STEAMAUTH_LENGTH);

		char auth2[MAX_STEAMAUTH_LENGTH];
		FormatEx(auth2, MAX_STEAMAUTH_LENGTH, auth);
		ReplaceString(auth2, MAX_STEAMAUTH_LENGTH, "STEAM_", "", false);

		char name[MAX_NAME_LENGTH];
		results.FetchString(1, name, MAX_NAME_LENGTH);
		ReplaceString(name, MAX_NAME_LENGTH, ";", "", false);

		char Display[128];
		FormatEx(Display, sizeof Display, "%s - %s", name, auth);

		char info[64];
		FormatEx(info, sizeof info, "%s;%s", name, auth);

		// debug
		//PrintToChat(client, "%s", info);

		menu.AddItem(info, Display);
	}

	if (!menu.ItemCount) {
		menu.AddItem("none", "There are no spray banned players.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 20);

	delete results;
}

//Menu Handler for the full list of spray banned players
public int MenuHandler_AllSpraybans(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			if (CheckCommandAccess(param1, "sm_sprayunban", ADMFLAG_UNBAN, false)) {
				char info[64];
				menu.GetItem(param2, info, 64);
				//PrintToChat(param1, "%s", info);

				if (!StrEqual(info, "none")) {
					char tokens[64][64];
					ExplodeString(info, ";", tokens, sizeof(tokens), sizeof(tokens[]));

					//PrintToChat(param1, "%i", sizeof(tokens));
					//PrintToChat(param1, "%s", tokens[1]);

					Menu menu2 = new Menu(MenuHandler_AllSpraybans_Ban);
					menu2.SetTitle("Are you sure you want to spray un-ban %s (%s)?", tokens[0], tokens[1]);

					menu2.AddItem(tokens[1], "Yes");
					menu2.AddItem("none", "No");

					menu2.ExitBackButton = true;

					menu2.Display(param1, 20);
				}
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayListOptionsMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//Unbanning handler for the all spray bans menu
public int MenuHandler_AllSpraybans_Ban(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[32];
			menu.GetItem(param2, info, 32);

			if (!StrEqual(info, "none")) {
				char sQuery[128];
				FormatEx(sQuery, sizeof sQuery, "DELETE FROM ssh WHERE auth = '%s'", info);

				DataPack pack = new DataPack();
				pack.WriteCell(GetClientSerial(param1));
				pack.WriteString(info);

				g_Database.Query(Offlinebans_UnbanCallback, sQuery, pack);
			}

			else {
				g_Database.Query(AllSprayBansCallback, "SELECT * FROM ssh", GetClientSerial(param1));
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				g_Database.Query(AllSprayBansCallback, "SELECT * FROM ssh", GetClientSerial(param1));
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

/******************************************************************************************
 *                               OFFLINE SPRAY BANNING                                    *
 ******************************************************************************************/

//Its like spray-banning, but offline...Allows you to target offline clients.
public Action Command_OfflineSprayban(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}

	if (!args) {
		ReplyToCommand(client, "[SM] Usage: sm_offlinesprayban <\"steamid\"> [name]");
		return Plugin_Handled;
	}


	char authp1[MAX_STEAMAUTH_LENGTH];
	GetCmdArg(1, authp1, MAX_STEAMAUTH_LENGTH);

	char authp2[MAX_STEAMAUTH_LENGTH];
	GetCmdArg(2, authp2, MAX_STEAMAUTH_LENGTH);

	char authp3[MAX_STEAMAUTH_LENGTH];
	GetCmdArg(3, authp3, MAX_STEAMAUTH_LENGTH);

	char authp4[MAX_STEAMAUTH_LENGTH];
	GetCmdArg(4, authp4, MAX_STEAMAUTH_LENGTH);

	char authp5[MAX_STEAMAUTH_LENGTH];
	GetCmdArg(5, authp5, MAX_STEAMAUTH_LENGTH);

	char auth[MAX_STEAMAUTH_LENGTH];
	Format(auth, MAX_STEAMAUTH_LENGTH, "%s%s%s%s%s", authp1, authp2, authp3, authp4, authp5);

	if (args == 1 && !StrEqual(auth, "STEAM_")) {
		ReplyToCommand(client, "[SM] Invalid SteamID. Valid SteamIDs are formmated in this way - STEAM_A:B:XXXXXXX.");

		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	FormatEx(targetName, MAX_NAME_LENGTH, "<unknown>");

	if (args >= 6) {
		GetCmdArg(6, targetName, MAX_NAME_LENGTH);
	}

	int len = 2*strlen(targetName)+1;
	char[] targetSafeName = new char[len];
	SQL_LockDatabase(g_Database);
	g_Database.Escape(targetName, targetSafeName, len);
	SQL_UnlockDatabase(g_Database);

	char Driver[64];
	SQL_ReadDriver(g_Database, Driver, sizeof(Driver));
	//PrintToChat(client, "%s", Driver);

	char sQuery[256];
	if (StrEqual(Driver, "mysql")) {
		FormatEx(sQuery, sizeof sQuery, "INSERT INTO ssh (auth, name) VALUES ('%s', '%s') ON DUPLICATE KEY UPDATE name = '%s';", auth,  targetSafeName, targetSafeName);
	}
	else {
		FormatEx(sQuery, sizeof sQuery, "INSERT OR REPLACE INTO ssh (auth, name) VALUES ('%s', COALESCE((SELECT name FROM ssh WHERE auth = '%s'), '%s'))", auth, auth, targetSafeName);
	}
	//PrintToChat(client, "%s", sQuery);

	SQL_LockDatabase(g_Database);
	SQL_FastQuery(g_Database, sQuery);
	SQL_UnlockDatabase(g_Database);

	ShowActivity(client, "Spray banned %s. (%s)", targetSafeName, auth);

	int target = -1;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			char sAuth[32];
			if (!GetClientAuthId(i, AuthId_Steam2, sAuth, sizeof sAuth)) {
				continue;
			}

			if (StrEqual(sAuth, auth)) {
				target = i;

				break;
			}
		}
	}

	if (target != -1) {
		g_fSprayVector[target] = ZERO_VECTOR;

		TE_Start("Player Decal");
		TE_WriteVector("m_vecOrigin", ZERO_VECTOR);
		TE_WriteNum("m_nEntity", 0);
		TE_WriteNum("m_nPlayer", target);
		TE_SendToAll();

		g_bSpraybanned[target] = true;

		Call_StartForward(g_hBanForward);
		Call_PushCell(target);
		Call_Finish();

		LogAction(client, target, "Spray banned.");

		PrintToChat(target, "\x04[Super Spray Handler]\x01 You've been spray banned.");
	}

	return Plugin_Handled;
}

/******************************************************************************************
 *                              OFFLINE UN-SPRAY BANNING                                  *
 ******************************************************************************************/

 //Its like spray-unbanning, but offline...Allows you to target offline clients.
public void Offlinebans_UnbanCallback(Database db, DBResultSet results, const char[] error, DataPack dp) {
	if (!db || !results || error[0]) {
		delete dp;
		LogError("SQL error in MenuHandler_AllSpraybans_Ban: %s", error);
		return;
	}

	dp.Reset();

	int client = GetClientFromSerial(dp.ReadCell());

	char auth[MAX_STEAMAUTH_LENGTH];
	dp.ReadString(auth, MAX_STEAMAUTH_LENGTH);

	delete dp;

	if (!IsValidClient(client)) {
		return;
	}

	LogToFile("addons/sourcemod/logs/ssh.log", "%L: Spray unbanned %s.", client, auth);

	int target = -1;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			char sAuth[32];
			if (!GetClientAuthId(i, AuthId_Steam2, sAuth, sizeof sAuth)) {
				continue;
			}

			if (StrEqual(sAuth, auth)) {
				target = i;

				break;
			}
		}
	}

	if (target != -1) {
		g_bSpraybanned[target] = false;

		Call_StartForward(g_hUnbanForward);
		Call_PushCell(target);
		Call_Finish();

		PrintToChat(target, "\x04[Super Spray Handler]\x01 You've been spray unbanned.");
	}

	delete results;
}

/******************************************************************************************
 *                                         NATIVES                                        *
 ******************************************************************************************/

 //Native to spray-ban a client.
public int Native_BanClient(Handle plugin, int numParams) {
	int client = GetNativeCell(1);

	if (!IsValidClient(client)) {
		ThrowError("Player index %d is invalid.", client);
	}

	if (g_bSpraybanned[client]) {
		ThrowError("Player index %d is already spray banned.", client);
	}

	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof auth)) {
		CreateTimer(5.0, timerAddSprayBan, GetClientUserId(client), TIMER_REPEAT);
	}
	else {
		AddSprayBan(client, auth);
	}

	if (!!GetNativeCell(2)) {
		TE_Start("Player Decal");
		TE_WriteVector("m_vecOrigin", ZERO_VECTOR);
		TE_WriteNum("m_nEntity", 0);
		TE_WriteNum("m_nPlayer", client);
		TE_SendToAll();

		g_fSprayVector[client] = ZERO_VECTOR;
	}

	g_bSpraybanned[client] = true;

	PrintToChat(client, "\x04[Super Spray Handler]\x01 You've been spray banned.");
}

//Native to un-sprayban a client.
public int Native_UnbanClient(Handle plugin, int numParams) {
	int client = GetNativeCell(1);

	if (!IsValidClient(client)) {
		ThrowError("Player index %d is invalid.", client);
	}

	if (!g_bSpraybanned[client]) {
		ThrowError("Player index %d is not spray banned.", client);
	}

	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof auth)) {
		// Should probably notify client calling native.
		return;
	}

	char sQuery[256];
	FormatEx(sQuery, 256, "DELETE FROM ssh WHERE auth = '%s';", auth);

	SQL_LockDatabase(g_Database);
	SQL_FastQuery(g_Database, sQuery);
	SQL_UnlockDatabase(g_Database);

	g_bSpraybanned[client] = false;

	PrintToChat(client, "\x04[Super Spray Handler]\x01 You've been spray unbanned.");
}

//Native to check if a client is spray banned.
public int Native_IsBanned(Handle plugin, int numParams) {
	int client = GetNativeCell(1);

	if (!IsValidClient(client)) {
		ThrowError("Player index %i is invalid.", client);
		return 0;
	}

	return g_bSpraybanned[client];
}

/******************************************************************************************
 *                                         TIMERS :D                                      *
 ******************************************************************************************/

//sm_spray_refresh handlers for tracing to HUD or hint message
public void TimerChanged(ConVar hConVar, const char[] szOldValue, const char[] szNewValue) {
	delete g_hSprayTimer;
	CreateTimers();
}

//Now we make the timers, and start them up.
stock void CreateTimers() {
	float timer = g_arrCVars[REFRESHRATE].FloatValue;

	if (timer > 0.0) {
		g_hSprayTimer = CreateTimer(timer, CheckAllTraces, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

/******************************************************************************************
 *                                     TRACING SPRAYS                                     *
 ******************************************************************************************/

//What happens when you run the !sm_spraytrace command?
public Action Command_TraceSpray(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos)) {
	 	for (int i = 1; i <= MaxClients; i++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue) {
				int time = RoundFloat(GetGameTime()) - g_arrSprayTime[i];

				PrintToChat(client, "[SSH] %T", "Spray By", client, g_arrSprayName[i], g_arrSprayID[i], time);
				GlowEffect(client, g_fSprayVector[i], 2.0, 0.3, 255, g_PrecacheRedGlow);
				PunishmentMenu(client, i);

				return Plugin_Handled;
			}
		}
	}

	PrintToChat(client, "[SSH] %T", "No Spray", client);

	return Plugin_Handled;
}

//Admin Menu Handler for the spray trace function.
public void AdminMenu_TraceSpray(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "Trace", param);
		}
		case TopMenuAction_SelectOption: {
			Command_TraceSpray(param, 0);
		}
	}
}

/******************************************************************************************
 *                                    REMOVING SPRAYS                                     *
 ******************************************************************************************/

 //What happens when you run !sm_removespray?
public Action Command_RemoveSpray(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos)) {
		char szAdminName[32];

		GetClientName(client, szAdminName, sizeof szAdminName);

	 	for (int i = 1; i <= MaxClients; i++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue) {
				float vecEndPos[3];

				PrintToChat(client, "[SSH] %T", "Spray By", client, g_arrSprayName[i], g_arrSprayID[i], RoundFloat(GetGameTime()) - g_arrSprayTime[i]);

				SprayDecal(i, 0, vecEndPos);

				g_fSprayVector[i] = ZERO_VECTOR;

				PrintToChat(client, "[SSH] %T", "Spray Removed", client, g_arrSprayName[i], g_arrSprayID[i], szAdminName);
				LogAction(client, -1, "[SSH] %T", "Spray Removed", LANG_SERVER, g_arrSprayName[i], g_arrSprayID[i], szAdminName);
				PunishmentMenu(client, i);

				return Plugin_Handled;
			}
		}
	}

	PrintToChat(client, "[SSH] %T", "No Spray", client);

	return Plugin_Handled;
}

//Admin menu handler for the Spray Removal selection
public void AdminMenu_SprayRemove(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "Remove", param);
		}
		case TopMenuAction_SelectOption: {
			Command_RemoveSpray(param, 0);
		}
	}
}

/******************************************************************************************
 *                                 QUICK REMOVING SPRAYS                                  *
 ******************************************************************************************/

 //What happens when you run !sm_qremovespray?
public Action Command_QuickRemoveSpray(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos)) {
		char szAdminName[MAX_NAME_LENGTH];

		GetClientName(client, szAdminName, sizeof szAdminName);

	 	for (int i = 1; i <= MaxClients; i++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue) {
				float vecEndPos[3];

				PrintToChat(client, "[SSH] %T", "Spray By", client, g_arrSprayName[i], g_arrSprayID[i], RoundFloat(GetGameTime()) - g_arrSprayTime[i]);

				SprayDecal(i, 0, vecEndPos);

				g_fSprayVector[i] = ZERO_VECTOR;

				PrintToChat(client, "[SSH] %T", "Spray Removed", client, g_arrSprayName[i], g_arrSprayID[i], szAdminName);
				LogAction(client, -1, "[SSH] %T", "Spray Removed", LANG_SERVER, g_arrSprayName[i], g_arrSprayID[i], szAdminName);

				return Plugin_Handled;
			}
		}
	}

	PrintToChat(client, "[SSH] %T", "No Spray", client);

	return Plugin_Handled;
}

//Admin Menu handler for the QuickSprayRemove Selection
public void AdminMenu_QuickSprayRemove(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "Quickly Remove Spray", param);
		}
		case TopMenuAction_SelectOption: {
			Command_QuickRemoveSpray(param, 0);
			g_hAdminMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

/******************************************************************************************
 *                                  Removing All Sprays                                   *
 ******************************************************************************************/

public Action Command_RemoveAllSprays(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	char szAdminName[MAX_NAME_LENGTH];

	GetClientName(client, szAdminName, sizeof szAdminName);

	for (int i = 1; i <= MaxClients; i++) {
		float vecEndPos[3];

		SprayDecal(i, 0, vecEndPos);

		g_fSprayVector[i] = ZERO_VECTOR;
	}

	PrintToChat(client, "[SSH] %T", "Sprays Removed", client, szAdminName);
	LogAction(client, -1, "[SSH] %T", "Sprays Removed", LANG_SERVER, szAdminName);

	return Plugin_Handled;
}

//Admin Menu handler for the RemoveAll Selection
public void AdminMenu_RemoveAllSprays(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "Remove All Sprays", param);
		}
		case TopMenuAction_SelectOption: {
			Command_RemoveAllSprays(param, 0);
			g_hAdminMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

/******************************************************************************************
 *                                     ADMIN SPRAYING                                     *
 ******************************************************************************************/

//What happens when you run the !sm_adminspray <target> command.
public Action Command_AdminSpray(int client, int args) {
	if (!IsValidClient(client)) {
		if (client == 0) {
			ReplyToCommand(client, "[SSH] Command is in-game only.");
		}
		return Plugin_Handled;
	}
	char arg[MAX_NAME_LENGTH];
	int target = client;
	if (args >= 1) {
		GetCmdArg(1, arg, sizeof arg);

		target = FindTarget(client, arg, false, false);

		if (!IsValidClient(target)) {
			//ReplyToCommand(client, "[SSH] %T", "Could Not Find Name", client, arg);
			return Plugin_Handled;
		}
	}

	if (!GoSpray(client, target)) {
		ReplyToCommand(client, "%s[SSH] %T", GetCmdReplySource() == SM_REPLY_TO_CHAT ? "\x04" : "", "Cannot Spray", client);
	}
	else {
		ReplyToCommand(client, "%s[SSH] %T", GetCmdReplySource() == SM_REPLY_TO_CHAT ? "\x04" : "", "Admin Sprayed", client, client, target);
		LogAction(client, -1, "[SSH] %T", "Admin Sprayed", LANG_SERVER, client, target);
	}

	return Plugin_Handled;
}

//Displays the admin spray menu and adds targets to it.
void DisplayAdminSprayMenu(int client, int iPos = 0) {
	if (!IsValidClient(client)) {
		return;
	}

	Menu menu = new Menu(MenuHandler_AdminSpray);

	menu.SetTitle("%T", "Admin Spray Menu", client);
	menu.ExitBackButton = true;

	for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				if (!g_bSpraybanned[i]) {
					if (!IsClientReplay(i) && !IsClientSourceTV(i)) {
						char info[8];
						char name[MAX_NAME_LENGTH];

						IntToString(GetClientUserId(i), info, 8);
						GetClientName(i, name, MAX_NAME_LENGTH);

						menu.AddItem(info, name);
					}
				}
			}
		}
	if (iPos == 0) {
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else {
		menu.DisplayAt(client, iPos, MENU_TIME_FOREVER);
	}
}

//Menu Handler for the admin spray selection menu
public int MenuHandler_AdminSpray(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[32];
			int target;

			menu.GetItem(param2, info, sizeof(info));

			target = GetClientOfUserId(StringToInt(info));

			if (target == 0 || !IsClientInGame(target)) {
				PrintToChat(param1, "[SSH] %T", "Could Not Find", param1);
			}
			else if (g_bSpraybanned[target]) {
				PrintToChat(param1, "[SSH} %T", "Player is Spray Banned", param1);
			}
			else {
				GoSpray(param1, target);
			}

			DisplayAdminSprayMenu(param1, menu.Selection);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack && g_hAdminMenu != null) {
				g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
}

//Admin Menu handler for the Admin Spray Selection
public void AdminMenu_AdminSpray(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "AdminSpray", param);
		}
		case TopMenuAction_SelectOption: {
			DisplayAdminSprayMenu(param);
		}
	}
}

/******************************************************************************************
 *                                  SPRAYING THE SPRAYS                                   *
 ******************************************************************************************/

//Called before SprayDecal() to receive a player's decal file and find where to spray it.
public bool GoSpray(int client, int target) {
	//Receives the player decal file.
	char spray[8];
	if (!GetPlayerDecalFile(target, spray, sizeof(spray))) {
		return false;
	}
	float vecEndPos[3];

	//Finds where to spray the spray.
	if (!GetClientEyeEndLocation(client, vecEndPos)) {
		return false;
	}
	int traceEntIndex = TR_GetEntityIndex();
	if (traceEntIndex < 0) {
		traceEntIndex = 0;
	}

	//What actually sprays the decal
	SprayDecal(target, traceEntIndex, vecEndPos);
	EmitSoundToAll("player/sprayer.wav", SOUND_FROM_WORLD, SNDCHAN_VOICE, SNDLEVEL_TRAFFIC, SND_NOFLAGS, _, _, _, vecEndPos);

	return true;
}

//Called to spray a players decal. Used for admin spray.
public void SprayDecal(int client, int entIndex, float vecPos[3]) {
	if (!IsValidClient(client)) {
		return;
	}

	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", vecPos);
	TE_WriteNum("m_nEntity", entIndex);
	TE_WriteNum("m_nPlayer", client);
	TE_SendToAll();
}

/******************************************************************************************
 *                                    PUNISHMENT MENU                                     *
 ******************************************************************************************/

//Called to open the punishment menu.
void PunishmentMenu(int client, int sprayer) {
	if (!IsValidClient(client)) {
		return;
	}

	g_arrMenuSprayID[client] = g_arrSprayID[sprayer];
	Menu hMenu = new Menu(PunishmentMenuHandler);

	hMenu.SetTitle("%T", "Title", client, g_arrSprayName[sprayer], g_arrSprayID[sprayer], RoundFloat(GetGameTime()) - g_arrSprayTime[sprayer]);


	//Makes life simpler later
	//Gos ahead and creates all the booleans that decide what is put into the punishment menu

	//Is the restriction cvar = to 1?
	bool isRestricted = g_arrCVars[RESTRICT].BoolValue;

	bool useSlap = (g_arrCVars[SLAPDMG].IntValue > 0) && (isRestricted ? CheckCommandAccess(client, "sm_slap", ADMFLAG_SLAY, false) : true);
	bool useSlay = (g_arrCVars[USESLAY].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_slay", ADMFLAG_SLAY, false) : true);
	bool useBurn = (g_arrCVars[USEBURN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_burn", ADMFLAG_SLAY, false) : true);
	bool useFreeze = (g_arrCVars[USEFREEZE].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_freeze", ADMFLAG_SLAY, false) : true);
	bool useBeacon = (g_arrCVars[USEBEACON].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_beacon", ADMFLAG_SLAY, false) : true);
	bool useFreezeBomb = (g_arrCVars[USEFREEZEBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_freezebomb", ADMFLAG_SLAY, false) : true);
	bool useFireBomb = (g_arrCVars[USEFIREBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_firebomb", ADMFLAG_SLAY, false) : true);
	bool useTimeBomb = (g_arrCVars[USETIMEBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_timebomb", ADMFLAG_SLAY, false) : true);
	bool useDrug = (g_arrCVars[DRUGTIME].IntValue > 0) && (isRestricted ? CheckCommandAccess(client, "sm_drug", ADMFLAG_SLAY, false) : true);
	bool useKick = (g_arrCVars[USEKICK].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, false) : true);
	bool useBan = (g_arrCVars[USEBAN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, false) : true);
	bool useSprayBan = (g_arrCVars[USESPRAYBAN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_sprayban", ADMFLAG_BAN, false) : true);

	//Adding Punishments to Punishment Menu
	char szWarn[128];
	Format(szWarn, sizeof szWarn, "%T", "Warn", client);
	hMenu.AddItem("warn", szWarn);

	if (useSlap) {
		char szSlap[128];
		Format(szSlap, sizeof szSlap, "%T", "SlapWarn", client, g_arrCVars[SLAPDMG].IntValue);
		hMenu.AddItem("slap", szSlap);
	}

	if (useSlay) {
		char szSlay[128];
		Format(szSlay, sizeof szSlay, "%T", "Slay", client);
		hMenu.AddItem("slay", szSlay);
	}

	if (useBurn) {
		char szBurn[128];
		Format(szBurn, sizeof szBurn, "%T", "BurnWarn", client, g_arrCVars[BURNTIME].IntValue);
		hMenu.AddItem("burn", szBurn);
	}

	if (useFreeze) {
		char szFreeze[128];
		Format(szFreeze, sizeof szFreeze, "%T", "Freeze", client);
		hMenu.AddItem("freeze", szFreeze);
	}

	if (useBeacon) {
		char szBeacon[128];
		Format(szBeacon, sizeof szBeacon, "%T", "Beacon", client);
		hMenu.AddItem("beacon", szBeacon);
	}

	if (useFreezeBomb) {
		char szFreezeBomb[128];
		Format(szFreezeBomb, sizeof szFreezeBomb, "%T", "FreezeBomb", client);
		hMenu.AddItem("freezebomb", szFreezeBomb);
	}

	if (useFireBomb) {
		char szFireBomb[128];
		Format(szFireBomb, sizeof szFireBomb, "%T", "FireBomb", client);
		hMenu.AddItem("firebomb", szFireBomb);
	}

	if (useTimeBomb) {
		char szTimeBomb[128];
		Format(szTimeBomb, sizeof szTimeBomb, "%T", "TimeBomb", client);
		hMenu.AddItem("timebomb", szTimeBomb);
	}

	if (useDrug) {
		char szDrug[128];
		Format(szDrug, sizeof szDrug, "%T", "szDrug", client);
		hMenu.AddItem("drug", szDrug);
	}

	if (useKick) {
		char szKick[128];
		Format(szKick, sizeof szKick, "%T", "Kick", client);
		hMenu.AddItem("kick", szKick);
	}

	if (useBan) {
		char szBan[128];
		Format(szBan, sizeof szBan, "%T", "Ban", client);
		hMenu.AddItem("ban", szBan);
	}

	if (useSprayBan) {
		char szSPBan[128];
		Format(szSPBan, sizeof szSPBan, "%T", "SPBan", client);
		hMenu.AddItem("spban", szSPBan);
	}

	hMenu.ExitButton = true;
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);

	return;
}

//Handler for the Punishment Menu
public int PunishmentMenuHandler(Menu hMenu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char szInfo[32];
			char szSprayerName[MAX_NAME_LENGTH];
			char szSprayerID[32];
			char szAdminName[MAX_NAME_LENGTH];
			int sprayer;

			szSprayerID = g_arrMenuSprayID[param1];
			sprayer = GetClientFromAuthID(g_arrMenuSprayID[param1]);
			szSprayerName = g_arrSprayName[sprayer];
			GetClientName(param1, szAdminName, sizeof(szAdminName));
			hMenu.GetItem(param2, szInfo, sizeof(szInfo));

			//If you selected to ban someone, we arent going to run the rest of this, calls the ban times menu.
			if (strcmp(szInfo, "ban") == 0) {
				DisplayBanTimesMenu(param1);
			}
			//Guess you selected not to ban someone, so now we do this stuff.
			else if (sprayer && IsClientInGame(sprayer)) {
				AdminId sprayerAdmin = GetUserAdmin(sprayer);
				AdminId clientAdmin = GetUserAdmin(param1);

				//Uh Oh. You can't target this person. Now they're going to kill you.
				if (((sprayerAdmin != INVALID_ADMIN_ID) && (clientAdmin != INVALID_ADMIN_ID)) && g_arrCVars[IMMUNITY].BoolValue && !clientAdmin.CanTarget(sprayerAdmin)) {
					PrintToChat(param1, "\x04[SSH] %T", "Admin Immune", param1, szSprayerName);
					LogAction(param1, -1, "[SSH] %T", "Admin Immune Log", LANG_SERVER, szAdminName, szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//Wag that finger at them. You're doing good.
				else if (strcmp(szInfo, "warn") == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Warned", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Warned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					PunishmentMenu(param1, sprayer);
				}
				//SMACK! SLAP THAT HOE INTO THE NEXT DIMENSION.
				else if (strcmp(szInfo, "slap") == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Slapped And Warned", param1, szSprayerName, szSprayerID, g_arrCVars[SLAPDMG].IntValue);
					LogAction(param1, -1, "[SSH] %T", "Log Slapped And Warned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, g_arrCVars[SLAPDMG].IntValue);
					SlapPlayer(sprayer, g_arrCVars[SLAPDMG].IntValue);
					PunishmentMenu(param1, sprayer);
				}
				//Now they're dead...>.>
				else if (strcmp(szInfo, "slay") == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Slayed And Warned", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Slayed And Warned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_slay \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//You get to watch them scream in agony :D
				else if (strcmp(szInfo, "burn") == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Burnt And Warned", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Burnt And Warned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_burn \"%s\" %d", szSprayerName, g_arrCVars[BURNTIME].IntValue);
					PunishmentMenu(param1, sprayer);
				}
				//All of a sudden. Their legs don't work anymore. odd.
				else if (strcmp(szInfo, "freeze", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Froze", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Froze", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_freeze \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//BEEP. BEEP. BEEP. Now the whole server knows where they are.
				else if (strcmp(szInfo, "beacon", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Beaconed", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Beaconed", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_beacon \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//Their legs and anyone's legs around them are magically going to stop working in like....10 seconds...
				else if (strcmp(szInfo, "freezebomb", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "FreezeBombed", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log FreezeBombed", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_freezebomb \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//Now this is just cruel. You're going to hurt other people too....
				else if (strcmp(szInfo, "firebomb", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "FireBombed", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log FireBombed", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_firebomb \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//This is just horrible. You're straight murdering other people too...
				else if (strcmp(szInfo, "timebomb", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "TimeBombed", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log TimeBombed", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_timebomb \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//Slip something into their drink?
				else if (strcmp(szInfo, "drug", false) == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					PrintToChat(param1, "\x04[SSH] %T", "Drugged", param1, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Drugged", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					CreateTimer(g_arrCVars[DRUGTIME].FloatValue, Undrug, sprayer, TIMER_FLAG_NO_MAPCHANGE);
					ClientCommand(param1, "sm_drug \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
				//GTFO
				else if (strcmp(szInfo, "kick") == 0) {
					KickClient(sprayer, "%T", "Bad Spray Logo", sprayer);
					PrintToChatAll("\x03[SSH] %T", "Kicked", LANG_SERVER, szSprayerName, szSprayerID);
					LogAction(param1, -1, "[SSH] %T", "Log Kicked", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
				}
				//No more spraying for you :)
				else if (strcmp(szInfo, "spban") == 0) {
					PrintToChat(sprayer, "\x03[SSH] %T", "Please change", sprayer);
					//PrintToChat(param1, "\x04[SSH] %T", "SPBanned", param1, szSprayerName, szSprayerID);
					//LogAction(param1, -1, "[SSH] %T", "Log SPBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
					ClientCommand(param1, "sm_sprayban \"%s\"", szSprayerName);
					PunishmentMenu(param1, sprayer);
				}
			}
			//Nice. That's not a person.
			else {
				PrintToChat(param1, "\x04[SSH] %T", "Could Not Find Name ID", param1, szSprayerName, szSprayerID);
				LogAction(param1, -1, "[SSH] %T", "Could Not Find Name ID", LANG_SERVER, szSprayerName, szSprayerID);
			}

			//If you want to auto-remove their spray after punishing, this does it.
			if (g_arrCVars[AUTOREMOVE].BoolValue) {
				float vecEndPos[3];
				SprayDecal(sprayer, 0, vecEndPos);

				PrintToChat(param1, "[SSH] %T", "Spray Removed", param1, szSprayerName, szSprayerID, szAdminName);
				LogAction(param1, -1, "[SSH] %T", "Spray Removed", LANG_SERVER, szSprayerName, szSprayerID, szAdminName);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, param1);
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}

/******************************************************************************************
 *                                     BAN TIMES MENU                                     *
 ******************************************************************************************/

//Called to display the list of ban times.
void DisplayBanTimesMenu(int client) {
	char szSprayerName[MAX_NAME_LENGTH];
	char szSprayerID[32];
	char szAdminName[MAX_NAME_LENGTH];
	int sprayer;

	szSprayerID = g_arrMenuSprayID[client];
	sprayer = GetClientFromAuthID(g_arrMenuSprayID[client]);
	szSprayerName = g_arrSprayName[sprayer];
	GetClientName(client, szAdminName, sizeof(szAdminName));

	if (!IsValidClient(client)) {
		return;
	}

	Menu menu = new Menu(MenuHandler_BanTimes);

	menu.SetTitle("Ban %s for...", szSprayerName);
	menu.ExitBackButton = true;

	if (g_arrCVars[USEPBAN].BoolValue) {
		menu.AddItem("0", "Permanent");
	}

	menu.AddItem("180", "3 Hours");
	menu.AddItem("360", "6 Hours");
	menu.AddItem("720", "12 Hours");
	menu.AddItem("1440", "1 Day");
	menu.AddItem("4320", "3 Days");
	menu.AddItem("10080", "1 Week");
	menu.AddItem("5", "5 Minutes");
	menu.AddItem("15", "15 Minutes");
	menu.AddItem("30", "30 Minutes");
	menu.AddItem("60", "1 Hour");
	menu.AddItem("43800", "1 Month");

	menu.Display(client, MENU_TIME_FOREVER);
}

//Handler for the ban times menu
public int MenuHandler_BanTimes(Menu hMenu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char szSprayerID[32];
			szSprayerID = g_arrMenuSprayID[param1];
			int sprayer = GetClientFromAuthID(g_arrMenuSprayID[param1]);
			char szSprayerName[MAX_NAME_LENGTH];
			szSprayerName = g_arrSprayName[sprayer];

			if (sprayer) {
				char szInfo[32];
				char szAdminName[MAX_NAME_LENGTH];

				szSprayerID = g_arrMenuSprayID[param1];
				sprayer = GetClientFromAuthID(g_arrMenuSprayID[param1]);
				szSprayerName = g_arrSprayName[sprayer];
				GetClientName(param1, szAdminName, sizeof(szAdminName));
				hMenu.GetItem(param2, szInfo, sizeof(szInfo));

				int iTime = StringToInt(szInfo);
				char szBad[128];
				Format(szBad, 127, "%T", "Bad Spray Logo", LANG_SERVER);

				g_hExternalBan = FindConVar("sb_version");

				//SourceBans integration
				if (g_hExternalBan != null) {
					ClientCommand(param1, "sm_ban #%d %d \"%s\"", GetClientUserId(sprayer), iTime, szBad);

					if (iTime == 0) {
						LogAction(param1, -1, "[SSH] %T", "EPBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, "SourceBans");
					}
					else {
						LogAction(param1, -1, "[SSH] %T", "EBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, iTime, "SourceBans");
					}

					delete g_hExternalBan;
				}
				else {
					g_hExternalBan = FindConVar("mysql_bans_version");

					//MySQL Bans integration
					if (g_hExternalBan != null) {
						ClientCommand(param1, "mysql_ban #%d %d \"%s\"", GetClientUserId(sprayer), iTime, szBad);

						if (iTime == 0) {
							LogAction(param1, -1, "[SSH] %T", "EPBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, "MySQL Bans");
						}
						else {
							LogAction(param1, -1, "[SSH] %T", "EBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, iTime, "MySQL Bans");
						}

						delete g_hExternalBan;
					}
					else {
						//Normal Ban
						BanClient(sprayer, iTime, BANFLAG_AUTHID, szBad, szBad);

						if (iTime == 0) {
							LogAction(param1, -1, "[SSH] %T", "PBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
						}
						else {
							LogAction(param1, -1, "[SSH] %T", "Banned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, iTime);
						}
					}
				}

				if (iTime == 0) {
					PrintToChatAll("\x03[SSH] %T", "PBanned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID);
				}
				else {
					PrintToChatAll("\x03[SSH] %T", "Banned", LANG_SERVER, szAdminName, szSprayerName, szSprayerID, iTime);
				}
			}
			else {
				PrintToChat(param1, "\x04[SSH] %T", "Could Not Find Name ID", param1, szSprayerName, szSprayerID);
				LogAction(param1, -1, "[SSH] %T", "Could Not Find Name ID", LANG_SERVER, szSprayerName, szSprayerID);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				PunishmentMenu(param1, GetClientFromAuthID(g_arrMenuSprayID[param1]));
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}

/******************************************************************************************
 *                               CONFIRM YOUR ACTIONS MENU                                *
 ******************************************************************************************/

 //Called to display the Yes/No Menu for confirming your actions
void DisplayConfirmMenu(int client, int target, int type) {
	if (!IsValidClient(client)) {
		return;
	}

	switch (type) {
		case 0: {
			Menu menu = new Menu(MenuHandler_SprayBanConf);

			menu.SetTitle("SprayBan %N?", target);
			menu.ExitBackButton = true;

			char info[8];
			IntToString(target, info, sizeof info);

			menu.AddItem(info, "Yes!");
			menu.AddItem("-1", "No!");

			menu.Display(client, MENU_TIME_FOREVER);
		}
		case 1: {
			Menu menu = new Menu(MenuHandler_UnSprayBanConf);

			menu.SetTitle("Un-SprayBan %N?", target);
			menu.ExitBackButton = true;

			char info[8];
			IntToString(target, info, sizeof info);

			menu.AddItem(info, "Yes!");
			menu.AddItem("-1", "No!");

			menu.Display(client, MENU_TIME_FOREVER);
		}
	}
}

//Menu Handler for confirming spraybanning someone.
public int MenuHandler_SprayBanConf(Menu hMenu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			hMenu.GetItem(param2, info, sizeof info);
			int choice = StringToInt(info);
			// Some stupid shit going on here. choice shouldnt be -1 because it would be used for an index
// 			if (choice == -1) {
// 				PunishmentMenu(param1, choice);
// 			}
// 			else {
			if (choice != -1) {
				RunSprayBan(param1, choice);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				PunishmentMenu(param1, 0);
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}

//Menu Handler for confirming un-spraybanning someone.
public int MenuHandler_UnSprayBanConf(Menu hMenu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			hMenu.GetItem(param2, info, sizeof info);
			int choice = StringToInt(info);
			// Some stupid shit going on here. choice shouldnt be -1 because it would be used for an index
// 			if (choice == -1) {
// 				PunishmentMenu(param1, choice);
// 			}
// 			else {
			if (choice != -1) {
				RunUnSprayBan(param1, choice);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				PunishmentMenu(param1, 0);
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}

/******************************************************************************************
 *                                     HELPER METHODS                                     *
 ******************************************************************************************/

 //Used to clear a player from existence in this plugin.
public void ClearVariables(int client) {
	g_fSprayVector[client] = ZERO_VECTOR;
	g_arrSprayName[client][0] = '\0';
	g_sAuth[client][0] = '\0';
	g_arrSprayID[client][0] = '\0';
	g_arrMenuSprayID[client][0] = '\0';
	g_arrSprayTime[client] = 0;
	g_bSpraybanned[client] = false;
}

//Converts a clients auth id back into a client index
public int GetClientFromAuthID(const char[] szAuthID) {
	char szOtherAuthID[32];
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			if (GetClientAuthId(i, AuthId_Steam2, szOtherAuthID, sizeof szOtherAuthID)) {
				if (strcmp(szOtherAuthID, szAuthID) == 0) {
					return i;
				}
			}
		}
	}
	return 0;
}

public bool TraceEntityFilter_NoPlayers(int entity, int contentsMask) {
	return entity > MaxClients;
}

public bool TraceEntityFilter_OnlyWorld(int entity, int contentsMask) {
	return entity == 0;
}

//Used to make fix removing a spray when sm_ssh_overlap != 0
public bool CheckForZero(float vecPos[3]) {
	return (vecPos[0] == 0 && vecPos[1] == 0 && vecPos[2] == 0);
}

//Applies the glow effect on a spray when you trace the spray
public void GlowEffect(int client, float vecPos[3], float flLife, float flSize, int bright, int model) {
	if (!IsValidClient(client)) {
		return;
	}

	int arrClients[1];
	arrClients[0] = client;
	TE_SetupGlowSprite(vecPos, model, flLife, flSize, bright);
	TE_Send(arrClients, 1);
}

//Handles actually making drugs work on a timer.
public Action Undrug(Handle hTimer, any client) {
	if (IsValidClient(client)) {
		ServerCommand("sm_undrug \"%N\"", client);
	}

	return Plugin_Handled;
}

//Pretty obvious what this accomplishes :/
stock bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}

//What is used to find the exact location a player is looking. Used for tracing sprays to the hud/hint and other functions.
public bool GetClientEyeEndLocation(int client, float vector[3]) {
	if (!IsValidClient(client)) {
		return false;
	}

	float vOrigin[3];
	float vAngles[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle hTraceRay = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, ValidSpray);

	if (TR_DidHit(hTraceRay)) {
		TR_GetEndPosition(vector, hTraceRay);
		delete hTraceRay;

		return true;
	}

	delete hTraceRay;

	return false;
}

//Checks to make sure a spray is of a valid client.
public bool ValidSpray(int entity, int contentsmask) {
	return entity > MaxClients;
}