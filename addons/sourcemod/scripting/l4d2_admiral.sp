/* =============================================================================================================== *
 *			                       _____   _         _    _                                                        *
 *			                      |  __ \ | |       | |  (_)                                                       *
 *			                      | |__) || |  __ _ | |_  _  _ __   _   _  _ __ ___                                *
 *			                      |  ___/ | | / _` || __|| || '_ \ | | | || '_ ` _ \                               *
 *			                      | |     | || (_| || |_ | || | | || |_| || | | | | |                              *
 *			                      |_|     |_| \__,_| \__||_||_| |_| \__,_||_| |_| |_|                              *
 *                                                                                                                 *
 * ============================================================================================================== */

/* =============================================================================================================== *
 *										Pragma, Includes and Defines			   								   *
 *================================================================================================================ */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>
#include <colors>
#include <left4dhooks>

#define PLUGIN_VERSION "1.3"
#define MYSQL "mysql"

// --- Asset paths ---
#define SPRITE_BEAMS "materials/sprites/laserbeam.vmt"
#define SPRITE_HALOS "materials/sprites/halo01.vmt"

#define PET_JOCKEY_MODEL "models/infected/jockey.mdl"
#define PET_MELISA_MODEL "models/pet/melisa/melisa.mdl"
#define PET_DANGO_MODEL  "models/pet/dango/dango.mdl"
#define PET_QIQI_MODEL   "models/pet/qiqi/qiqi.mdl"

// --- Pet movement tuning ---
#define STEP_REACH_DISTANCE 20.0
#define CLIENT_NEAR_DISTANCE 80.0
#define TELEPORT_DISTANCE 800.0
#define MAX_STEPS_MEMORY 512
#define PET_MOVE_INTERVAL 0.1

// --- Limits & delays ---
#define HISTORY_LIMIT 7
#define MAX_TRAIL_ENTITIES 8
#define TRAIL_HEIGHT_TRIM 6.0
#define TRAIL_LINEAR_BACK_OFFSET 12.0
#define DATABASE_CACHE_LIMIT 128
#define DATABASE_LOAD_START_DELAY 0.2
#define DATABASE_LOAD_STEP_DELAY 0.04
#define CHALLENGE_SAVE_RETRY_DELAY 0.5

// --- Redeem result codes ---
#define REDEEM_RESULT_NO_BALANCE 1
#define REDEEM_RESULT_PERMANENT 2
#define REDEEM_RESULT_DB_ERROR 3
#define MAX_ADMIRAL_TAGS 64

// --- Permanent time code ---
#define TIME_FOREVER -1

// --- Team Naming ---
enum
{
	L4D2Team_Unknown = -1,
	L4D2Team_Unassigned,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
}

enum
{
	L4D2Class_Unknown = 0,
	L4D2Class_Smoker,
	L4D2Class_Boomer,
	L4D2Class_Hunter,
	L4D2Class_Spitter,
	L4D2Class_Jockey,
	L4D2Class_Charger,
	L4D2Class_Witch,
	L4D2Class_Tank,
	L4D2Class_Survivor
};

/* =============================================================================================================== *
 *												Late Load Variable			   									   *
 *================================================================================================================ */

bool g_bLateLoad;

/* =============================================================================================================== *
 *												Database Connection			   									   *
 *================================================================================================================ */

Database g_hDatabase;
bool g_bDbConnecting;
char g_SQLDriver[16];
char g_SQLBuffer[1500];

/* =============================================================================================================== *
 *												Config file (KeyValues)		   									   *
 *================================================================================================================ */

KeyValues g_KeyValue;
char g_sData_Path[PLATFORM_MAX_PATH];

char g_sAdmiralTagCache[MAX_ADMIRAL_TAGS][64];
int g_iAdmiralTagRequirement[MAX_ADMIRAL_TAGS];
int g_iAdmiralTagCount;

/* =============================================================================================================== *
 *											Admin Menu Targeting Variables			   							   *
 *================================================================================================================ */

enum MENU_ACTION
{
	MENU_ADD_ADMIRAL,
	MENU_ADD_TIME,
	MENU_ADD_DB_TIME
}

int g_iMenusTarget[MAXPLAYERS+1];
MENU_ACTION g_eMenuAction[MAXPLAYERS+1];

/* =============================================================================================================== *
 *												Admiral Data Variables			   								   *
 *================================================================================================================ */

enum struct CPlayer
{
    char m_sName[MAX_NAME_LENGTH];

    // Admiral access
    int m_iJoinTime;
    int m_iTimeDuration;
    int m_iTimeLeft;

    // Reputation balance + redeem history
    int m_iCurrentRep;
    int m_iTotalRep;
    int m_iRepHistCount;
    int m_iRepHistCost[HISTORY_LIMIT];
    int m_iRepHistHours[HISTORY_LIMIT];
    int m_iRepHistTime[HISTORY_LIMIT];
}

CPlayer CPlayers[MAXPLAYERS+1];
char g_sAdmiralSteamId[MAXPLAYERS+1][32];

/* =============================================================================================================== *
 *												 Data Load Varoables			   								   *
 *================================================================================================================ */

bool g_bCookiesLoaded[MAXPLAYERS+1];
bool g_bDataLoaded[MAXPLAYERS+1];
bool g_bDataLoading[MAXPLAYERS+1];
bool g_bLoadQueued[MAXPLAYERS+1];
bool g_bPrivCleared[MAXPLAYERS+1];
int g_iDataRevision[MAXPLAYERS+1];
int g_iLoadRetries[MAXPLAYERS+1];


/* =============================================================================================================== *
 *												Reputation Flow Variables			   							   *
 *================================================================================================================ */

bool g_bRepPending[MAXPLAYERS+1];
bool g_bRedeemPending[MAXPLAYERS+1];
bool g_bTotalRepLoaded[MAXPLAYERS+1];
bool g_bTotalRepLoading[MAXPLAYERS+1];
bool g_bRepHistoryLoaded[MAXPLAYERS+1];
bool g_bRepHistoryLoading[MAXPLAYERS+1];
bool g_bOpenRepHistoryAfterLoad[MAXPLAYERS+1];
bool g_bOpenTagMenuAfterRepLoad[MAXPLAYERS+1];

/* =============================================================================================================== *
 *												Daily Challenge Variables			   							   *
 *================================================================================================================ */

enum struct CDailyChallenge
{
	char m_sName[64];
	char m_sType[24];
	int m_iTarget;
	int m_iRewardHours;
	int m_iRewardRep;
}

CDailyChallenge g_ChallengeOfDay[7];
bool g_bChallengesConfigured;

int g_iChallengeProgress[MAXPLAYERS+1];
int g_iChallengeDateIndex[MAXPLAYERS+1];
bool g_bChallengeCompletedToday[MAXPLAYERS+1];
bool g_bChallengeDataLoaded[MAXPLAYERS+1];
bool g_bChallengeSaveBusy[MAXPLAYERS+1];
bool g_bChallengeHunterPouncing[MAXPLAYERS+1];
int g_iChallengePreHealHealth[MAXPLAYERS+1];

static const char g_sChallengeDayNames[7][] =
{
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday"
};

/* =============================================================================================================== *
 *												Browser Admiral Data			   								   *
 *================================================================================================================ */

char g_sManageDbSteamId[MAXPLAYERS+1][32];
char g_sManageDbName[MAXPLAYERS+1][MAX_NAME_LENGTH];

bool g_bCacheLoaded;
bool g_bCacheLoading;
bool g_bCacheRefreshQueued;
bool g_bSchemaReady;
bool g_bWriteBusy;
int g_iCacheCount;

enum struct CDbAdmiral
{
    char m_sSteam[32];
    char m_sName[MAX_NAME_LENGTH];
    int m_iJoinTime;
    int m_iTimeDuration;
    int m_iTimeLeft;
}

CDbAdmiral g_DbAdmirals[DATABASE_CACHE_LIMIT];

/* =============================================================================================================== *
 *											Admiral Cosmotic Variables			   								   *
 *================================================================================================================ */

char g_sSkinColor[MAXPLAYERS+1][16];
char g_sAuraColor[MAXPLAYERS+1][16];
char g_sTrailColor[MAXPLAYERS+1][3][16];
char g_sTrailStyle[MAXPLAYERS+1][24];
char g_sTrailLength[MAXPLAYERS+1][16];
char g_sChatColor[MAXPLAYERS+1][16];
char g_sAdmiralTag[MAXPLAYERS+1][32];
int g_iEntTrails[MAXPLAYERS+1][MAX_TRAIL_ENTITIES];

/* =============================================================================================================== *
 *													Cookies			   											   *
 *================================================================================================================ */

Cookie g_hPetSettings;
Cookie g_hTextColorCookie;
Cookie g_hAppearanceSettingsCookie;
Cookie g_hTrailSettingsCookie;
Cookie g_hAdmiralTagCookie;

/* =============================================================================================================== *
 *												Pets System Variables			   								   *
 *================================================================================================================ */
 
int g_iPet_Entity[MAXPLAYERS+1];
int g_iPet_MoveType[MAXPLAYERS+1];
int g_iSavedStep[MAXPLAYERS+1];
int g_iLoadedStep[MAXPLAYERS+1];
int g_iFollowTarget[MAXPLAYERS+1];
int g_iLastTeleportTime[MAXPLAYERS+1];

bool g_bPetPaused[MAXPLAYERS+1];
bool g_bIsTeleportPet[MAXPLAYERS+1];

float g_fPlayerSteps[MAX_STEPS_MEMORY][MAXPLAYERS+1][3];
float g_fLastStepWriteTime[MAXPLAYERS+1];
float g_fPet_AnimLock[MAXPLAYERS+1];

char g_sPet_Name[MAXPLAYERS+1][16];
char g_sPet_Aura[MAXPLAYERS+1][16];
char g_sPet_Size[MAXPLAYERS+1][16];

Handle g_hTimer_MoveIn[MAXPLAYERS+1];
Handle g_hTimer_MoveOut[MAXPLAYERS+1];

Handle g_hTimer_DatabaseRetry;
Handle g_hTimer_PrivilegeCheck;

/* =============================================================================================================== *
 *										Cvars and ConvarChanged Variables										   *
 *================================================================================================================ */

ConVar g_Cvar_PluginEnable;
ConVar g_Cvar_PetMenuEnable;
ConVar g_Cvar_PetsCustomEnable;
ConVar g_Cvar_SkinColorMenuEnable;
ConVar g_Cvar_AuraColorMenuEnable;
ConVar g_Cvar_TrailsMenuEnable;
ConVar g_Cvar_ChatColorMenuEnable;
ConVar g_Cvar_TagMenuEnable;
ConVar g_Cvar_Server_MenuSound;
ConVar g_Cvar_RepCooldown;
ConVar g_Cvar_RepDailyLimit;
ConVar g_Cvar_DataBase;

bool g_bPluginEnable;
bool g_bPetMenuEnable;
bool g_bPetsCustomEnable;
bool g_bSkinColorMenuEnable;
bool g_bAuraColorMenuEnable;
bool g_bTrailsMenuEnable;
bool g_bChatColorMenuEnable;
bool g_bTagMenuEnable;
int g_iRepCooldown;
int g_iRepDailyLimit;
char g_sDataBase[64];

/* =================================================================================================================== *
 *													Plugin Info			   										 	   *
 *==================================================================================================================== */

public Plugin myinfo =
{
	name = "L4D2 Admiral",
	author = "AlasfourOM",
	description = "Adds special features for dedicated players.",
	version = "1.3",
	url = "https://forums.alliedmods.net"
};


/* =================================================================================================================== *
 *                                            Plugin Lifecycle & Forwards                                              *
 *==================================================================================================================== */

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	EngineVersion test = GetEngineVersion();
	
	if(test != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
	
	g_bLateLoad = late;
	return APLRes_Success; 
}

public void OnPluginStart()
{
	CreateConVar("l4d2_admiral_version", PLUGIN_VERSION, "L4D2 Admiral", FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_Cvar_PluginEnable = CreateConVar("l4d2_admiral_enable", "1", "Enable L4D2 Admiral plugin. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_PetMenuEnable = CreateConVar("l4d2_admiral_pet_menu_enable", "1", "Enable Admiral pet menu and pet spawning. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_PetsCustomEnable = CreateConVar("l4d2_admiral_pet_custom_enable", "0", "Enable Custom Pets 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_SkinColorMenuEnable = CreateConVar("l4d2_admiral_skin_color_menu_enable", "1", "Enable Admiral survivor skin color menu and saved skin color effect. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_AuraColorMenuEnable = CreateConVar("l4d2_admiral_aura_color_menu_enable", "0", "Enable Admiral survivor aura color menu and saved aura effect. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_TrailsMenuEnable = CreateConVar("l4d2_admiral_trails_menu_enable", "1", "Enable Admiral trails menu and saved trails effect. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_ChatColorMenuEnable = CreateConVar("l4d2_admiral_chat_color_menu_enable", "1", "Enable Admiral chat color menu and saved chat color effect. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_TagMenuEnable = CreateConVar("l4d2_admiral_tag_menu_enable", "1", "Enable Admiral tag menu and saved chat tag effect. 0 = Disable, 1 = Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_RepCooldown = CreateConVar("l4d2_admiral_rep_cooldown", "3", "How many days before the same player can give reputation to the same target again. 0 = no same-target cooldown.", FCVAR_NOTIFY, true, 0.0);
	g_Cvar_RepDailyLimit = CreateConVar("l4d2_admiral_rep_daily_limit", "5", "Maximum +rep a player can give within 24 hours. 0 = unlimited.", FCVAR_NOTIFY, true, 0.0);
	g_Cvar_DataBase = CreateConVar("l4d2_admiral_database", "admiral", "Database config name from databases.cfg used by Admiral. (MySQL & SQLite supported)", FCVAR_PROTECTED);

	HookConVarChanges();
	
	g_Cvar_Server_MenuSound = FindConVar("sm_menu_sounds");
	
	g_hPetSettings = RegClientCookie("l4d2_admiral_pet_settings", "Stores Admiral pet settings", CookieAccess_Protected);
	g_hTextColorCookie = RegClientCookie("l4d2_admiral_text_color", "Stores Admiral chat text color", CookieAccess_Protected);
	g_hAppearanceSettingsCookie = RegClientCookie("l4d2_admiral_appearance_settings", "Stores Admiral skin and aura colors", CookieAccess_Protected);
	g_hTrailSettingsCookie = RegClientCookie("l4d2_admiral_trail_settings", "Stores Admiral trail color and style", CookieAccess_Protected);
	g_hAdmiralTagCookie = RegClientCookie("l4d2_admiral_tag", "Stores Admiral chat tag", CookieAccess_Protected);
	
	GetCvars();
	AutoExecConfig(true, "l4d2_admiral");
	
	RegAdminCmd("sm_admiral_reload", Command_AdmiralReload, ADMFLAG_ROOT, "Reload Data File");
	RegConsoleCmd("sm_admiral", Command_AdmiralMenu, "Display Admiral Menu");
	RegConsoleCmd("sm_admirals", Command_AdmiralsMenu, "Display Online Admirals And Admins");
	RegConsoleCmd("sm_rep", Command_ReputationMenu, "Give reputation to a player");
	RegConsoleCmd("sm_thanks", Command_ReputationMenu, "Give reputation to a player");
	RegConsoleCmd("sm_myrep", Command_MyReputation, "View and redeem your reputation");
	RegConsoleCmd("sm_mythanks", Command_MyReputation, "View and redeem your reputation");
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_FinaleWin, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_StatusChanged);
	HookEvent("player_team", Event_StatusChanged);
	HookEvent("player_death", Event_StatusChanged);
	HookEvent("player_disconnect", Event_StatusChanged);

	// Daily Challenges Events Related
	HookEvent("player_death", Event_ChallengePlayerDeath);
	HookEvent("infected_death", Event_ChallengeInfectedDeath);
	HookEvent("charger_killed", Event_ChallengeChargerKilled);
	HookEvent("witch_killed", Event_ChallengeWitchKilled);
	HookEvent("player_hurt", Event_ChallengeTankDamage);
	HookEvent("heal_begin", Event_ChallengeHealBegin);
	HookEvent("heal_success", Event_ChallengeHealSuccess);
	HookEvent("ability_use", Event_ChallengeAbilityUse);
	
	CleanupAdmiralEffectsOnUnload();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		if (AreClientCookiesCached(i)) OnClientCookiesCached(i);
	}
	
	BuildPath(Path_SM, g_sData_Path, PLATFORM_MAX_PATH, "data/l4d2_admiral.cfg");
	if (LoadConfig())
	{
		char sErrorReport[2048];
		int iStartUpError = ValidateAdmiralConfig(sErrorReport, sizeof(sErrorReport));
		if (iStartUpError > 0) LogError("[Admiral] Config validation found %d issue(s) in %s at startup:\n%s", iStartUpError, g_sData_Path, sErrorReport);
	}
	
	delete g_hTimer_PrivilegeCheck;
	g_hTimer_PrivilegeCheck = CreateTimer(1.0, Timer_EnforceAdmiralPrivileges, _, TIMER_REPEAT);
	
	if (g_bLateLoad) RefreshPlayersData();
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++) SavePlayerProgressAndTime(i);

	CleanupAdmiralEffectsOnUnload();
	delete g_hTimer_PrivilegeCheck;
	delete g_hTimer_DatabaseRetry;
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++) SavePlayerProgressAndTime(i);

	CleanupAdmiralEffectsOnUnload();
}

public void OnMapStart()
{
	if(g_bPetsCustomEnable)
	{
		AddFileToDownloadsTable("models/pet/melisa/melisa.dx90.vtx");
		AddFileToDownloadsTable("models/pet/melisa/melisa.vvd");
		AddFileToDownloadsTable("models/pet/melisa/melisa.mdl");
		AddFileToDownloadsTable("models/pet/melisa/pet_melisa.dx90.vtx");
		AddFileToDownloadsTable("models/pet/melisa/pet_melisa.vvd");
		AddFileToDownloadsTable("models/pet/melisa/pet_melisa.mdl");
		AddFileToDownloadsTable("materials/models/pet/melisa/face.vtf");
		AddFileToDownloadsTable("materials/models/pet/melisa/face.vmt");
		AddFileToDownloadsTable("materials/models/pet/melisa/body.vtf");
		AddFileToDownloadsTable("materials/models/pet/melisa/body.vmt");
	
		AddFileToDownloadsTable("models/pet/dango/dango.dx90.vtx");
		AddFileToDownloadsTable("models/pet/dango/dango.vvd");
		AddFileToDownloadsTable("models/pet/dango/dango.mdl");
		AddFileToDownloadsTable("models/pet/dango/pet_dango.dx90.vtx");
		AddFileToDownloadsTable("models/pet/dango/pet_dango.vvd");
		AddFileToDownloadsTable("models/pet/dango/pet_dango.mdl");
		AddFileToDownloadsTable("materials/models/pet/dango/body.vmt");
		AddFileToDownloadsTable("materials/models/pet/dango/body.vtf");
		AddFileToDownloadsTable("materials/models/pet/dango/face.vmt");
		AddFileToDownloadsTable("materials/models/pet/dango/face.vtf");
		AddFileToDownloadsTable("materials/models/pet/dango/items.vmt");
		AddFileToDownloadsTable("materials/models/pet/dango/items.vtf");
	
		AddFileToDownloadsTable("models/pet/qiqi/qiqi.dx90.vtx");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi.vvd");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi.mdl");
		AddFileToDownloadsTable("models/pet/qiqi/pet_qiqi.dx90.vtx");
		AddFileToDownloadsTable("models/pet/qiqi/pet_qiqi.vvd");
		AddFileToDownloadsTable("models/pet/qiqi/pet_qiqi.mdl");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_ring.dx90.vtx");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_ring.vvd");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_ring.mdl");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail.dx90.vtx");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail.vvd");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail.mdl");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail2.dx90.vtx");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail2.vvd");
		AddFileToDownloadsTable("models/pet/qiqi/qiqi_tail2.mdl");
		AddFileToDownloadsTable("materials/models/pet/qiqi/body.vmt");
		AddFileToDownloadsTable("materials/models/pet/qiqi/body.vtf");
		AddFileToDownloadsTable("materials/models/pet/qiqi/ring.vmt");
		AddFileToDownloadsTable("materials/models/pet/qiqi/ring.vtf");
	
		PrecacheModel(PET_MELISA_MODEL, true);
		PrecacheModel(PET_DANGO_MODEL, true);
		PrecacheModel(PET_QIQI_MODEL, true);
	}
	
	PrecacheModel(PET_JOCKEY_MODEL, true);
	PrecacheModel(SPRITE_BEAMS, true);
	PrecacheModel(SPRITE_HALOS, true);
	
	int index = -1;
	while((index = FindEntityByClassname(index, "env_spritetrail")) != -1)
	{
		if (IsValidEdict(index)) RequestFrame(Frame_FixSpriteTrail, EntIndexToEntRef(index));
	}
	
	if (g_Cvar_Server_MenuSound != null) g_Cvar_Server_MenuSound.SetInt(0);
}

void HookConVarChanges()
{
	g_Cvar_PluginEnable.AddChangeHook(ConVarChanged);
	g_Cvar_PetMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_PetsCustomEnable.AddChangeHook(ConVarChanged);
	g_Cvar_SkinColorMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_AuraColorMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_TrailsMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_ChatColorMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_TagMenuEnable.AddChangeHook(ConVarChanged);
	g_Cvar_RepCooldown.AddChangeHook(ConVarChanged);
	g_Cvar_RepDailyLimit.AddChangeHook(ConVarChanged);
	g_Cvar_DataBase.AddChangeHook(ConVarChanged);
}

public void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_bPluginEnable = g_Cvar_PluginEnable.BoolValue;
	g_bPetMenuEnable = g_Cvar_PetMenuEnable.BoolValue;
	g_bPetsCustomEnable = g_Cvar_PetsCustomEnable.BoolValue;
	g_bSkinColorMenuEnable = g_Cvar_SkinColorMenuEnable.BoolValue;
	g_bAuraColorMenuEnable = g_Cvar_AuraColorMenuEnable.BoolValue;
	g_bTrailsMenuEnable = g_Cvar_TrailsMenuEnable.BoolValue;
	g_bChatColorMenuEnable = g_Cvar_ChatColorMenuEnable.BoolValue;
	g_bTagMenuEnable = g_Cvar_TagMenuEnable.BoolValue;
	g_iRepCooldown = g_Cvar_RepCooldown.IntValue;
	g_iRepDailyLimit = g_Cvar_RepDailyLimit.IntValue;
	g_Cvar_DataBase.GetString(g_sDataBase, sizeof(g_sDataBase));
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;

		EnforcePetCustomAvailability(i, true);

		if (!g_bPluginEnable || !g_bPetMenuEnable) RemovePet(i);
		else if (!g_bPetsCustomEnable && g_iPet_Entity[i] > MaxClients && IsValidEntity(g_iPet_Entity[i]))
		{
			char sModel[PLATFORM_MAX_PATH];
			GetEntPropString(g_iPet_Entity[i], Prop_Data, "m_ModelName", sModel, sizeof(sModel));
			
			if (StrContains(sModel, "jockey", false) == -1) RemovePet(i);
		}
		
		if (!g_bPluginEnable || !g_bSkinColorMenuEnable) ResetSkinColor(i);
		if (!g_bPluginEnable || !g_bAuraColorMenuEnable) ResetAuraColor(i);
		if (!g_bPluginEnable || !g_bTrailsMenuEnable) KillTrailEntities(i);
	}
}

public void OnConfigsExecuted()
{
	if (g_Cvar_Server_MenuSound != null) g_Cvar_Server_MenuSound.SetInt(0);
	
	GetCvars();
	Database_OnConfigExecuted();
}

void ResetClientAdmiralRuntime(int client)
{
	if (client <= 0 || client > MaxClients) return;

	// Identity
	g_sAdmiralSteamId[client][0] = '\0';
	strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), "");

	// Database load state
	g_iDataRevision[client]++;
	g_bDataLoaded[client] = false;
	g_bDataLoading[client] = false;
	g_bLoadQueued[client] = false;
	g_iLoadRetries[client] = 0;

	// Admiral access/runtime
	CPlayers[client].m_iJoinTime = 0;
	CPlayers[client].m_iTimeDuration = 0;
	CPlayers[client].m_iTimeLeft = 0;

	// Reputation cache/history
	ResetClientReputationHistory(client);

	// Privilege cleanup state
	g_bPrivCleared[client] = true;
}

public void OnClientConnected(int client)
{
	ResetClientAdmiralRuntime(client);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client)) return;

	// Identity
	g_sAdmiralSteamId[client][0] = '\0';
	Admiral_GetClientSteamID(client, g_sAdmiralSteamId[client], sizeof(g_sAdmiralSteamId[]));

	// Cookie state
	g_bCookiesLoaded[client] = false;

	// Database load state
	g_iDataRevision[client]++;
	g_bDataLoaded[client] = false;
	g_bDataLoading[client] = false;
	g_bLoadQueued[client] = false;
	g_iLoadRetries[client] = 0;

	// Admiral access/runtime time
	strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), "");
	CPlayers[client].m_iJoinTime = 0;
	CPlayers[client].m_iTimeDuration = 0;
	CPlayers[client].m_iTimeLeft = 0;

	// Reputation cache/history
	CPlayers[client].m_iCurrentRep = 0;
	CPlayers[client].m_iTotalRep = 0;
	g_bTotalRepLoaded[client] = false;
	g_bTotalRepLoading[client] = false;
	g_bOpenRepHistoryAfterLoad[client] = false;
	g_bOpenTagMenuAfterRepLoad[client] = false;
	ResetClientReputationHistory(client);

	// Admin DB manage state
	g_sManageDbSteamId[client][0] = '\0';
	g_sManageDbName[client][0] = '\0';

	// Privilege cleanup state
	g_bPrivCleared[client] = false;

	// Default appearance/chat settings until cookies load
	strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), "Default");
	strcopy(g_sAdmiralTag[client], sizeof(g_sAdmiralTag[]), "Default");
	strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");
	strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), "Default");

	strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), "Disabled");
	strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), "Disabled");
	strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), "Disabled");
	strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Disabled");
	strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");

	SetDefaultPetSettings(client);

	if (g_hDatabase != null && g_bSchemaReady) ScheduleClientDatabaseLoad(client, DATABASE_LOAD_START_DELAY);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (client <= 0 || client > MaxClients || IsFakeClient(client)) return;
	if (auth[0] == '\0') return;

	char steamid[32];
	if (GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid), true)) strcopy(g_sAdmiralSteamId[client], sizeof(g_sAdmiralSteamId[]), steamid);
	if (IsClientInGame(client) && g_hDatabase != null && g_bSchemaReady) ScheduleClientDatabaseLoad(client, DATABASE_LOAD_START_DELAY);
}

public void OnClientCookiesCached(int client)
{
	LoadClientPreferences(client);
}

void LoadClientPreferences(int client)
{
	if (!client || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) return;
	if (!AreClientCookiesCached(client)) return;
	if (g_bCookiesLoaded[client]) return;

	LoadPetCookies(client);
	LoadChatColorCookie(client);
	LoadAppearanceCookies(client);
	LoadTrailCookies(client);
	LoadAdmiralTagCookie(client);
	g_bCookiesLoaded[client] = true;
	CreateTimer(0.2, Timer_ResetAppearance, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	if (client <= 0 || client > MaxClients) return;

	// Visual/entity cleanup
	KillTrailEntities(client);

	if (!IsFakeClient(client))
	{
		if (IsClientInGame(client)) RemovePet(client);
		if (g_bDataLoaded[client]) Database_SavePlayerData(client);
		if (g_bChallengeDataLoaded[client]) SaveChallengeProgress(client);
	}

	// Pending actions
	g_bRedeemPending[client] = false;
	g_bRepPending[client] = false;

	// Cookie state
	g_bCookiesLoaded[client] = false;

	// Database load state
	g_iDataRevision[client]++;
	g_bDataLoaded[client] = false;
	g_bDataLoading[client] = false;
	g_bLoadQueued[client] = false;
	g_iLoadRetries[client] = 0;

	// Reputation cache/history
	CPlayers[client].m_iCurrentRep = 0;
	CPlayers[client].m_iTotalRep = 0;
	g_bTotalRepLoaded[client] = false;
	g_bTotalRepLoading[client] = false;
	g_bOpenRepHistoryAfterLoad[client] = false;
	g_bOpenTagMenuAfterRepLoad[client] = false;
	ResetClientReputationHistory(client);

	// Daily Challenge state
	g_bChallengeDataLoaded[client] = false;
	g_bChallengeCompletedToday[client] = false;
	g_iChallengeProgress[client] = 0;
	g_iChallengeDateIndex[client] = 0;
	g_bChallengeHunterPouncing[client] = false;
	g_iChallengePreHealHealth[client] = 0;

	// Admin DB manage state
	g_sManageDbSteamId[client][0] = '\0';
	g_sManageDbName[client][0] = '\0';

	// Identity
	g_sAdmiralSteamId[client][0] = '\0';
}

/* =================================================================================================================== *
 *                                            Config Loading & Validation                                              *
 *==================================================================================================================== */

bool LoadConfig()
{
	delete g_KeyValue;
	g_KeyValue = new KeyValues("Admiral Menu");

	if (!FileExists(g_sData_Path))
	{
		LogError("Missing Admiral config file: %s", g_sData_Path);
		return false;
	}
	
	if (!g_KeyValue.ImportFromFile(g_sData_Path))
	{
		LogError("Could not open Admiral config file: %s", g_sData_Path);
		return false;
	}

	LoadDailyChallengeConfig();
	LoadAdmiralTagConfig();

	return true;
}

int ChallengeDayNameToIndex(const char[] day)
{
	for (int i = 0; i < 7; i++)
		if (StrEqual(day, g_sChallengeDayNames[i], false)) return i;
	
	return -1;
}

bool IsValidChallengeType(const char[] type)
{
	return StrEqual(type, "commons_kill") || StrEqual(type, "charger_level") || StrEqual(type, "hunter_skeet")
		|| StrEqual(type, "kit_heal") || StrEqual(type, "witch_kill") || StrEqual(type, "tank_damage") || StrEqual(type, "infected_kill");
}

bool ParseDailyChallengeAtCurrentKey(char[] chName, int nameLen, char[] type, int typeLen, int &target, int &rewardHours, int &rewardRep)
{
	g_KeyValue.GetString("name", chName, nameLen, "");
	g_KeyValue.GetString("type", type, typeLen, "");
	target = g_KeyValue.GetNum("target", 0);
	rewardHours = g_KeyValue.GetNum("reward_hours", 0);
	rewardRep = g_KeyValue.GetNum("reward_rep", 0);

	return IsValidChallengeType(type) && target > 0;
}

void LoadDailyChallengeConfig()
{
	for (int i = 0; i < 7; i++)
	{
		g_ChallengeOfDay[i].m_sName[0] = '\0';
		g_ChallengeOfDay[i].m_sType[0] = '\0';
		g_ChallengeOfDay[i].m_iTarget = 0;
		g_ChallengeOfDay[i].m_iRewardHours = 0;
		g_ChallengeOfDay[i].m_iRewardRep = 0;
	}

	g_bChallengesConfigured = false;

	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Daily Challenges") && g_KeyValue.GotoFirstSubKey(false))
	{
		do
		{
			char sDay[16];
			if (!g_KeyValue.GetSectionName(sDay, sizeof(sDay))) continue;

			int dayIndex = ChallengeDayNameToIndex(sDay);
			if (dayIndex < 0) continue; // subkey name isn't a recognized day, skip it

			char sName[64], sType[24];
			int target, rewardHours, rewardRep;

			if (!ParseDailyChallengeAtCurrentKey(sName, sizeof(sName), sType, sizeof(sType), target, rewardHours, rewardRep)) continue;

			strcopy(g_ChallengeOfDay[dayIndex].m_sName, sizeof(g_ChallengeOfDay[].m_sName), sName);
			strcopy(g_ChallengeOfDay[dayIndex].m_sType, sizeof(g_ChallengeOfDay[].m_sType), sType);
			g_ChallengeOfDay[dayIndex].m_iTarget = target;
			g_ChallengeOfDay[dayIndex].m_iRewardHours = rewardHours;
			g_ChallengeOfDay[dayIndex].m_iRewardRep = rewardRep;

			g_bChallengesConfigured = true;
		}
		while (g_KeyValue.GotoNextKey(false));
	}

	g_KeyValue.Rewind();
}

void LoadAdmiralTagConfig()
{
	g_iAdmiralTagCount = 0;

	for (int i = 0; i < MAX_ADMIRAL_TAGS; i++)
	{
		g_sAdmiralTagCache[i][0] = '\0';
		g_iAdmiralTagRequirement[i] = 0;
	}

	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Admiral Tags") && g_KeyValue.GotoFirstSubKey(false))
	{
		do
		{
			if (g_iAdmiralTagCount >= MAX_ADMIRAL_TAGS)
			{
				LogError("[Admiral] Admiral tag cache reached MAX_ADMIRAL_TAGS (%d). Extra tags were ignored.", MAX_ADMIRAL_TAGS);
				break;
			}

			char sRawValue[96], sTag[64];
			int requiredReputation;

			g_KeyValue.GetString(NULL_STRING, sRawValue, sizeof(sRawValue));
			TrimString(sRawValue);

			if (!ParseAdmiralTagValue(sRawValue, sTag, sizeof(sTag), requiredReputation))
				GetAdmiralTagNodeData(sTag, sizeof(sTag), requiredReputation);

			if (sTag[0] == '\0' || StrEqual(sTag, "Default", false)) continue;

			strcopy(g_sAdmiralTagCache[g_iAdmiralTagCount], sizeof(g_sAdmiralTagCache[]), sTag);
			g_iAdmiralTagRequirement[g_iAdmiralTagCount] = requiredReputation;
			g_iAdmiralTagCount++;
		}
		while (g_KeyValue.GotoNextKey(false));
	}

	g_KeyValue.Rewind();
}

int ValidateAdmiralConfig(char[] sReport, int maxLen)
{
	sReport[0] = '\0';
	int issues = 0;

	static const char requiredSections[][] =
	{
		"Admiral Rules",
		"Admiral Tags",
		"How to Earn Reputation",
		"Reputation Redeem",
		"Daily Challenges"
	};

	for (int i = 0; i < sizeof(requiredSections); i++)
	{
		g_KeyValue.Rewind();
		if (g_KeyValue.JumpToKey(requiredSections[i])) continue;

		issues++;
		StrCat(sReport, maxLen, "  - WARNING: missing section \"");
		StrCat(sReport, maxLen, requiredSections[i]);
		StrCat(sReport, maxLen, "\" (feature will show empty/default)\n");
	}

	g_KeyValue.Rewind();
	bool bDaySeen[7];
	if (g_KeyValue.JumpToKey("Daily Challenges") && g_KeyValue.GotoFirstSubKey(false))
	{
		char sKey[16];
		do
		{
			if (!g_KeyValue.GetSectionName(sKey, sizeof(sKey))) continue;

			char sType[24];
			g_KeyValue.GetString("type", sType, sizeof(sType), "");
			int target = g_KeyValue.GetNum("target", 0);

			int dayIndex = ChallengeDayNameToIndex(sKey);

			if (dayIndex < 0 || !IsValidChallengeType(sType) || target <= 0)
			{
				issues++;
				StrCat(sReport, maxLen, "  - ERROR: \"Daily Challenges\" -> \"");
				StrCat(sReport, maxLen, sKey);
				StrCat(sReport, maxLen, "\" is not a recognized day, or has an invalid \"type\"/\"target\" (entry will be disabled)\n");
				continue;
			}

			bDaySeen[dayIndex] = true;
		}
		while (g_KeyValue.GotoNextKey(false));
	}
	g_KeyValue.Rewind();

	for (int i = 0; i < 7; i++)
	{
		if (bDaySeen[i]) continue;
		issues++;
		StrCat(sReport, maxLen, "  - WARNING: \"Daily Challenges\" has no entry for \"");
		StrCat(sReport, maxLen, g_sChallengeDayNames[i]);
		StrCat(sReport, maxLen, "\" (that day will have no challenge)\n");
	}

	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Admiral Tags") && g_KeyValue.GotoFirstSubKey(false))
	{
		char key[64], sRawValue[96], sTag[64];
		int required;

		do
		{
			if (!g_KeyValue.GetSectionName(key, sizeof(key))) continue;

			sRawValue[0] = '\0';
			sTag[0] = '\0';
			required = 0;

			g_KeyValue.GetString(NULL_STRING, sRawValue, sizeof(sRawValue));
			TrimString(sRawValue);

			if (!ParseAdmiralTagValue(sRawValue, sTag, sizeof(sTag), required)) GetAdmiralTagNodeData(sTag, sizeof(sTag), required);

			if (sTag[0] == '\0')
			{
				issues++;
				StrCat(sReport, maxLen, "  - ERROR: \"Admiral Tags\" entry \"");
				StrCat(sReport, maxLen, key);
				StrCat(sReport, maxLen, "\" has no usable tag name (check the value/\"name\" field)\n");
			}
		}
		while (g_KeyValue.GotoNextKey(false));
	}

	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Reputation Redeem") && g_KeyValue.GotoFirstSubKey(false))
	{
		char key[64], display[96];
		int cost, hours;

		do
		{
			if (!g_KeyValue.GetSectionName(key, sizeof(key))) continue;
			if (!ParseRedeemTierAtCurrentKey(cost, hours, display, sizeof(display)))
			{
				issues++;
				StrCat(sReport, maxLen, "  - ERROR: \"Reputation Redeem\" tier \"");
				StrCat(sReport, maxLen, key);
				StrCat(sReport, maxLen, "\" has invalid cost/hours (cost must be > 0, hours must be > 0 or -1 for permanent)\n");
			}
		}
		while (g_KeyValue.GotoNextKey(false));
	}

	g_KeyValue.Rewind();
	return issues;
}

Action Command_AdmiralReload(int client, int argc)
{
	if (!g_bPluginEnable) return Plugin_Handled;

	if (LoadConfig())
	{
		CReplyToCommand(client, "{green}[Admiral] {default}Data file has been reloaded successfully.");
		ReportAdmiralConfigValidation(client);
		RefreshPlayersData(); // We need to refresh player info - to avoid sticking with old tags
	}
	else CReplyToCommand(client, "{green}[Admiral] {default}Failed to load data file, please check error logs.");
	return Plugin_Handled;
}

void ReportAdmiralConfigValidation(int client)
{
	char sReport[2048];
	int iError = ValidateAdmiralConfig(sReport, sizeof(sReport));

	if (iError == 0)
	{
		CReplyToCommand(client, "{green}[Admiral] {default}Config validated: no issues found.");
		return;
	}

	CReplyToCommand(client, "{green}[Admiral] {default}Config validated: {lightgreen}%d{default} issue%s found (see console/log for details):", iError, iError == 1 ? "" : "s");
	LogError("[Admiral] Config validation found %d issue(s) in %s:\n%s", iError, g_sData_Path, sReport);

	char sLine[192];
	int iPos = 0;
	while (sReport[iPos] != '\0')
	{
		int iCopied = 0;
		while (sReport[iPos] != '\0' && sReport[iPos] != '\n' && iCopied < sizeof(sLine) - 1)
		{
			sLine[iCopied] = sReport[iPos];
			iCopied++;
			iPos++;
		}
		sLine[iCopied] = '\0';
		if (sReport[iPos] == '\n') iPos++;

		if (sLine[0] != '\0')
		{
			if (client == 0) PrintToServer("%s", sLine);
			else PrintToConsole(client, "%s", sLine);
		}
	}
}

void RefreshPlayersData()
{
	if (!g_hDatabase || !g_bSchemaReady) return;
	LoadDatabaseAdmiralCache(0, false, true);

	int iOrder;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsRealPlayer(i)) continue;
		ScheduleClientDatabaseLoad(i, DATABASE_LOAD_START_DELAY + (DATABASE_LOAD_STEP_DELAY * float(iOrder)));
		iOrder++;
	}
}

/* =================================================================================================================== *
 *                                    Chat: Say Commands, Colors & Tag Formatting                                      *
 *==================================================================================================================== */

public Action Command_Say(int client, const char[] command, int argc)
{
	if (!client || !IsClientInGame(client)) return Plugin_Continue;

	char text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (!text[0]) return Plugin_Continue;

	if (StrEqual(text, "+rep", false))
	{
		Command_ReputationMenu(client, 0);
		return Plugin_Handled;
	}

	if (StrContains(text, "+rep ", false) == 0)
	{
		char targetArg[128];
		strcopy(targetArg, sizeof(targetArg), text[5]);
		TrimString(targetArg);

		if (!targetArg[0])
		{
			Command_ReputationMenu(client, 0);
			return Plugin_Handled;
		}

		int target = FindTarget(client, targetArg, true, false);
		if (target == -1) return Plugin_Handled;

		if (target == client)
		{
			CPrintToChat(client, "{green}[Admiral] {default}You cannot give reputation to yourself.");
			return Plugin_Handled;
		}

		TryGiveReputation(client, target);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_bPluginEnable) return Plugin_Continue;
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Continue;
	if (!StrEqual(command, "say", false) && !StrEqual(command, "say_team", false)) return Plugin_Continue;
	if (sArgs[0] == '/' || sArgs[0] == '@') return Plugin_Continue;
	if (!IsPlayerAdmiral(client)) return Plugin_Continue;

	char sTag[32];
	if (g_bTagMenuEnable) GetAdmiralChatTag(client, sTag, sizeof(sTag));
	else sTag[0] = '\0';

	bool bDefaultColor = !g_bChatColorMenuEnable || IsDefaultChatColor(client);
	bool bNoTag = sTag[0] == '\0';

	if (bDefaultColor && bNoTag) return Plugin_Continue;

	if (StrEqual(command, "say", false)) PrintAdmiralSay(client, sTag, sArgs);
	else PrintAdmiralTeamSay(client, sTag, sArgs);
	
	return Plugin_Stop;
}

bool IsDefaultChatColor(int client)
{
	return g_sChatColor[client][0] == '\0' || StrEqual(g_sChatColor[client], "Default", false);
}

bool IsActiveChatColor(int client, const char[] color)
{
	return g_bChatColorMenuEnable && StrEqual(g_sChatColor[client], color, false);
}

void GetAdmiralChatTag(int client, char[] buffer, int maxLen)
{
	buffer[0] = '\0';

	if (g_sAdmiralTag[client][0] == '\0') return;
	if (StrEqual(g_sAdmiralTag[client], "Default", false)) return;
	if (!IsAdmiralTagAllowed(client, g_sAdmiralTag[client])) return;

	strcopy(buffer, maxLen, g_sAdmiralTag[client]);
}

void GetAdmiralChatColors(int client, char[] nameColor, int nameLen, char[] chatColor, int textLen, bool &bTeamColor)
{
	static const char sChatColorNames[][] = { "Red", "Blue", "Green", "Orange", "Olive" };
	static const char sChatNameTokens[][] = { "{olive}", "{olive}", "{green}", "{teamcolor}", "{teamcolor}" };
	static const char sChatTextTokens[][] = { "{red}", "{blue}", "{lightgreen}", "{green}", "{olive}" };
	static const bool bChatTeamColor[]    = { false, false, false, true, true };

	for (int i = 0; i < sizeof(sChatColorNames); i++)
	{
		if (!IsActiveChatColor(client, sChatColorNames[i])) continue;

		strcopy(nameColor, nameLen, sChatNameTokens[i]);
		strcopy(chatColor, textLen, sChatTextTokens[i]);
		bTeamColor = bChatTeamColor[i];
		return;
	}

	bTeamColor = true;
	strcopy(nameColor, nameLen, "{teamcolor}");
	strcopy(chatColor, textLen, "{default}");
}

void FormatAdmiralChatMessage(int client, const char[] prefix, const char[] sTag, const char[] sArgs, char[] buffer, int maxLen, bool &bTeamColor)
{
	char nameColor[16], chatColor[16], tagText[48];
	GetAdmiralChatColors(client, nameColor, sizeof(nameColor), chatColor, sizeof(chatColor), bTeamColor);

	if (sTag[0] != '\0') FormatEx(tagText, sizeof(tagText), "{green}[%s] ", sTag);
	else tagText[0] = '\0';

	FormatEx(buffer, maxLen, "%s%s%s%N {default}:  %s%s", prefix, tagText, nameColor, client, chatColor, sArgs);
}

void PrintAdmiralSay(int client, const char[] sTag, const char[] sArgs)
{
	char prefix[24], message[512];
	bool bTeamColor;

	if (GetClientTeam(client) == L4D2Team_Spectator) strcopy(prefix, sizeof(prefix), "{default}*SPEC* ");
	else prefix[0] = '\0';

	FormatAdmiralChatMessage(client, prefix, sTag, sArgs, message, sizeof(message), bTeamColor);

	if (bTeamColor) CPrintToChatAllEx(client, "%s", message);
	else CPrintToChatAll("%s", message);
}

void PrintAdmiralTeamSay(int client, const char[] sTag, const char[] sArgs)
{
	char sTeam[16], prefix[32], message[512];
	bool bTeamColor;

	if (GetClientTeam(client) == L4D2Team_Spectator) strcopy(sTeam, sizeof(sTeam), "Spectator");
	else if (GetClientTeam(client) == L4D2Team_Survivor) strcopy(sTeam, sizeof(sTeam), "Survivor");
	else if (GetClientTeam(client) == L4D2Team_Infected) strcopy(sTeam, sizeof(sTeam), "Infected");
	else strcopy(sTeam, sizeof(sTeam), "Team");

	FormatEx(prefix, sizeof(prefix), "{default}(%s) ", sTeam);
	FormatAdmiralChatMessage(client, prefix, sTag, sArgs, message, sizeof(message), bTeamColor);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != GetClientTeam(client)) continue;

		if (bTeamColor) CPrintToChatEx(i, client, "%s", message);
		else CPrintToChat(i, "%s", message);
	}
}

void LoadChatColorCookie(int client)
{
	if (!AreClientCookiesCached(client)) return;

	char sColor[16];
	GetClientCookie(client, g_hTextColorCookie, sColor, sizeof(sColor));

	if (sColor[0] == '\0') strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), "Default");
	else strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), sColor);
}

void SaveChatColorCookie(int client)
{
	if (!AreClientCookiesCached(client)) return;

	if (g_sChatColor[client][0] == '\0') strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), "Default");
	SetClientCookie(client, g_hTextColorCookie, g_sChatColor[client]);
}

void LoadAdmiralTagCookie(int client)
{
	if (!AreClientCookiesCached(client)) return;

	char sTag[32];
	GetClientCookie(client, g_hAdmiralTagCookie, sTag, sizeof(sTag));

	if (sTag[0] == '\0') strcopy(g_sAdmiralTag[client], sizeof(g_sAdmiralTag[]), "Default");
	else strcopy(g_sAdmiralTag[client], sizeof(g_sAdmiralTag[]), sTag);
}

void SaveAdmiralTagCookie(int client)
{
	if (!AreClientCookiesCached(client)) return;

	if (g_sAdmiralTag[client][0] == '\0') strcopy(g_sAdmiralTag[client], sizeof(g_sAdmiralTag[]), "Default");
	SetClientCookie(client, g_hAdmiralTagCookie, g_sAdmiralTag[client]);
}

void Create_TextColorMenu(int client)
{
	if (!CanOpenFeatureMenu(client) || !g_bChatColorMenuEnable) return;

	Menu menu = new Menu(Handle_TextColorMenu);
	menu.SetTitle("Chat Color:\nCurrent: %s\n ", g_sChatColor[client][0] ? g_sChatColor[client] : "Default");

	AddTextColorMenuItem(menu, client, "Default");
	AddTextColorMenuItem(menu, client, "Red");
	AddTextColorMenuItem(menu, client, "Blue");
	AddTextColorMenuItem(menu, client, "Green");
	AddTextColorMenuItem(menu, client, "Orange");
	AddTextColorMenuItem(menu, client, "Olive");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void AddTextColorMenuItem(Menu menu, int client, const char[] color)
{
	char sCurrent[16];
	strcopy(sCurrent, sizeof(sCurrent), g_sChatColor[client][0] ? g_sChatColor[client] : "Default");

	menu.AddItem(color, color, StrEqual(sCurrent, color, false) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
}

int Handle_TextColorMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		if(client <= 0 || !IsClientInGame(client)) return 0;
		if(!g_bChatColorMenuEnable || !HasAdmiralMenuAccess(client)) return 0;

		char item[64];
		menu.GetItem(select, item, sizeof(item));

		strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), item);
		SaveChatColorCookie(client);
		Create_TextColorMenu(client);
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

/* =================================================================================================================== *
 *                                        Main Admiral Menu, Rules & Commands                                          *
 *==================================================================================================================== */

Action Command_AdmiralMenu(int client, int args)
{
	if (!g_bPluginEnable) return Plugin_Handled;
	
	if(client == 0)
	{
		PrintToServer("[Admiral]: This command can not be executed by server.");
		return Plugin_Handled;
	}

	if (!IsRealPlayer(client))
	{
		ReplyToCommand(client, "[Admiral]: This command is only available in-game.");
		return Plugin_Handled;
	}

	if (!g_bDataLoaded[client])
	{
		Database_RetrievePlayerData(client);
		ReplyToCommand(client, "[Admiral]: Your Admiral data is still loading. Try again in a few seconds.");
		return Plugin_Handled;
	}
	
	if(!IsPlayerAdmiral(client) && !IsPlayerAdmin(client))
	{
		ReplyToCommand(client, "[Admiral]: You don't have access to this command.");
		return Plugin_Handled;
	}
	
	Create_AdmiralMenu(client);
	return Plugin_Handled;
}

void Create_AdmiralMenu(int client)
{
	if (client <= 0 || !IsClientInGame(client)) return;

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	SafelyCheckPlayerName(sName, sizeof(sName));

	char sAdmiralPass[64];

	if (!g_bDataLoaded[client]) strcopy(sAdmiralPass, sizeof(sAdmiralPass), "Loading");
	else if (CPlayers[client].m_iTimeDuration == TIME_FOREVER) strcopy(sAdmiralPass, sizeof(sAdmiralPass), "Permanent");
	else
	{
		int iTimeLeft = GetAdmiralTimeLeft(client);
		if (iTimeLeft <= 0) strcopy(sAdmiralPass, sizeof(sAdmiralPass), "Expired");
		else if (iTimeLeft >= 86400)
		{
			int iDays = iTimeLeft / 86400;
			int iHours = (iTimeLeft / 3600) % 24;
			FormatEx(sAdmiralPass, sizeof(sAdmiralPass), "%dd %dh", iDays, iHours);
		}
		else if (iTimeLeft >= 3600)
		{
			int iHours = iTimeLeft / 3600;
			int iMinutes = (iTimeLeft / 60) % 60;
			FormatEx(sAdmiralPass, sizeof(sAdmiralPass), "%dh %dm", iHours, iMinutes);
		}
		else
		{
			int iMinutes = iTimeLeft / 60;
			FormatEx(sAdmiralPass, sizeof(sAdmiralPass), "%dm", iMinutes);
		}
	}
	
	char sTitle[256];
	FormatEx(sTitle, sizeof(sTitle), "Welcome: %s\nAdmiral Pass: %s\n ", sName, sAdmiralPass);

	Menu menu = new Menu(Handle_AdmiralMenu);
	menu.SetTitle(sTitle);

	menu.AddItem("profile", "Profile");
	menu.AddItem("rules", "Rules");

	bool bHasAdmiralAccess = HasAdmiralMenuAccess(client);

	menu.AddItem("pets", "Companion", (bHasAdmiralAccess && g_bPetMenuEnable) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("appearance", "Appearance", (bHasAdmiralAccess && IsAnyAppearanceFeatureEnabled()) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("chatcolor", "Chat Color", (bHasAdmiralAccess && g_bChatColorMenuEnable) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("title", "Title", (bHasAdmiralAccess && g_bTagMenuEnable) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("manage", "Admin Panel", IsPlayerAdmin(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AdmiralMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		if(client <= 0 || !IsClientInGame(client)) return 0;

		char sItem[32];
		menu.GetItem(select, sItem, sizeof(sItem));

		if(StrEqual(sItem, "profile")) Create_AdmiralProfile(client);
		else if(StrEqual(sItem, "rules")) Create_AdmiralRules(client);
		else if(StrEqual(sItem, "pets") && g_bPetMenuEnable && HasAdmiralMenuAccess(client)) Create_AdmiralPetsMenu(client);
		else if(StrEqual(sItem, "appearance") && IsAnyAppearanceFeatureEnabled() && HasAdmiralMenuAccess(client)) Create_AdmiralAppearance(client);
		else if(StrEqual(sItem, "chatcolor") && g_bChatColorMenuEnable && HasAdmiralMenuAccess(client)) Create_TextColorMenu(client);
		else if(StrEqual(sItem, "title") && g_bTagMenuEnable && HasAdmiralMenuAccess(client)) Create_AdmiralTagMenu(client);
		else if(StrEqual(sItem, "manage") && IsPlayerAdmin(client)) Create_AdmiralManagerMenu(client);
	}
	else if(action == MenuAction_End) delete menu;
	return 0;
}

void Create_AdmiralRules(int client)
{
	char sValue[128];
	
	Menu menu = new Menu(Handle_AdmiralRulesMenu);
	menu.SetTitle("Admiral Rules: \n ", ITEMDRAW_DEFAULT);
	g_KeyValue.Rewind();
	
	if (!g_KeyValue.JumpToKey("Admiral Rules"))
	{
		LogError("Missing 'Admiral Rules' section in %s", g_sData_Path);
		menu.AddItem("empty", "No rules configured", ITEMDRAW_DISABLED);
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
		return;
	}
	
	if(g_KeyValue.GotoFirstSubKey(false))
	{
		do
		{
			g_KeyValue.GetString(NULL_STRING, sValue, sizeof(sValue));
			menu.AddItem("", sValue, ITEMDRAW_DISABLED);
			
		}
		while(g_KeyValue.GotoNextKey(false));
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AdmiralRulesMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

bool HasAdmiralMenuAccess(int client)
{
	if (!IsRealPlayer(client)) return false;

	if (!g_bDataLoaded[client])
	{
		Database_RetrievePlayerData(client);
		return false;
	}

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER) return true;
	if (CPlayers[client].m_iTimeDuration <= 0) return false;

	return IsPlayerAdmiral(client);
}

/* =================================================================================================================== *
 *                              Pet System (cookies, menus, spawn, movement, animation)                                *
 *==================================================================================================================== */

void SetDefaultPetSettings(int client)
{
	strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
	strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), "White");
	FormatEx(g_sPet_Size[client], sizeof(g_sPet_Size[]), "%.3f", GetPetBaseSize("Jockey"));
}

void LoadPetCookies(int client)
{
	if (!AreClientCookiesCached(client)) return;

	char sSettings[128];
	GetClientCookie(client, g_hPetSettings, sSettings, sizeof(sSettings));

	SetDefaultPetSettings(client);

	if (sSettings[0] != '\0')
	{
		char sExploded[3][16];
		ExplodeString(sSettings, "|", sExploded, 3, 16);

		if (sExploded[0][0] != '\0') strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), sExploded[0]);
		if (sExploded[1][0] != '\0') strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), sExploded[1]);
		if (sExploded[2][0] != '\0') strcopy(g_sPet_Size[client], sizeof(g_sPet_Size[]), sExploded[2]);

		if (StrEqual(g_sPet_Name[client], "Dango", false)) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Sparky");
		if (StrEqual(g_sPet_Name[client], "Qiqi", false)) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Storm");
	}

	NormalizePetSettings(client);
}

void NormalizePetSettings(int client)
{
	if (!IsValidPetName(g_sPet_Name[client])) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
	EnforcePetCustomAvailability(client, true);
	if (g_sPet_Aura[client][0] == '\0' || StrEqual(g_sPet_Aura[client], "Default", false)) strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), "White");
	if (g_sPet_Size[client][0] == '\0' || StringToFloat(g_sPet_Size[client]) <= 0.0) FormatEx(g_sPet_Size[client], sizeof(g_sPet_Size[]), "%.3f", GetPetBaseSize(g_sPet_Name[client]));
}

void SavePetCookies_Settings(int client)
{
	if (!AreClientCookiesCached(client)) return;

	NormalizePetSettings(client);

	char sSettings[128];
	FormatEx(sSettings, sizeof(sSettings), "%s|%s|%s", g_sPet_Name[client], g_sPet_Aura[client], g_sPet_Size[client]);
	SetClientCookie(client, g_hPetSettings, sSettings);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) RemovePet(i);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) SavePlayerProgressAndTime(i);
}

void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	SavePlayerProgressAndTime(client);
}

void Event_FinaleWin(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) SavePlayerProgressAndTime(i);
}

// Shared checkpoint save used by round_end, map_transition, finale_win, OnMapEnd, and OnPluginEnd.
// Mirrors the same guards OnClientDisconnect already uses for each - safe to call unconditionally,
// it's a no-op for anyone whose data isn't loaded or who has nothing to save.
void SavePlayerProgressAndTime(int client)
{
	if (!IsRealPlayer(client)) return;
	if (g_bChallengeDataLoaded[client]) SaveChallengeProgress(client);
	if (g_bDataLoaded[client]) Database_SavePlayerData(client);
}

void Event_StatusChanged(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || IsFakeClient(client)) return;
	
	RemovePet(client);
	CreateTimer(0.2, Timer_ResetAppearance, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

bool IsValidPetName(const char[] name)
{
	return StrEqual(name, "Jockey") || StrEqual(name, "Melisa") || StrEqual(name, "Sparky") || StrEqual(name, "Storm");
}

bool IsCustomPetName(const char[] name)
{
	return StrEqual(name, "Melisa", false) || StrEqual(name, "Sparky", false) || StrEqual(name, "Storm", false);
}

void EnforcePetCustomAvailability(int client, bool saveCookie)
{
	if (client <= 0 || client > MaxClients) return;

	if (!IsValidPetName(g_sPet_Name[client]))
	{
		strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
		if (saveCookie) SavePetCookies_Settings(client);
		return;
	}

	if (!g_bPetsCustomEnable && IsCustomPetName(g_sPet_Name[client]))
	{
		strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
		if (saveCookie) SavePetCookies_Settings(client);
	}
}

void GetPetModel(int client, char[] model, int maxLen)
{
	if (StrEqual(g_sPet_Name[client], "Melisa")) strcopy(model, maxLen, PET_MELISA_MODEL);
	else if (StrEqual(g_sPet_Name[client], "Sparky")) strcopy(model, maxLen, PET_DANGO_MODEL);
	else if (StrEqual(g_sPet_Name[client], "Storm")) strcopy(model, maxLen, PET_QIQI_MODEL);
	else strcopy(model, maxLen, PET_JOCKEY_MODEL);
}

void CyclePetName(int client)
{
	if (!g_bPetsCustomEnable)
	{
		strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
		SavePetCookies_Settings(client);
		return;
	}

	if (StrEqual(g_sPet_Name[client], "Jockey")) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Melisa");
	else if (StrEqual(g_sPet_Name[client], "Melisa")) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Sparky");
	else if (StrEqual(g_sPet_Name[client], "Sparky")) strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Storm");
	else strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");

	SavePetCookies_Settings(client);
}

void Create_AdmiralPetsMenu(int client)
{
	if (!g_bPluginEnable || !g_bPetMenuEnable || !HasAdmiralMenuAccess(client)) return;
	EnforcePetCustomAvailability(client, true);

	Menu menu = new Menu(Handle_AdmiralPetsMenu);
	char sBuffer[64];
	bool isSpawned = IsPetValid(client);

	menu.SetTitle("Companion Menu: \n ");
	menu.AddItem("TOGGLE", isSpawned ? "Dismiss Companion" : "Summon Companion");

	if (!isSpawned) FormatEx(sBuffer, sizeof(sBuffer), "Companion: (%s)", g_sPet_Name[client]);
	else FormatEx(sBuffer, sizeof(sBuffer), "Companion: %s", g_sPet_Name[client]);
	menu.AddItem("PET", sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "Glow: %s", g_sPet_Aura[client]);
	menu.AddItem("GLOW", sBuffer, isSpawned ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("SIZE", "Body Scale", isSpawned ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("ACTIONS", "Action Moves", isSpawned ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("TRAVEL", "Instant Travel", isSpawned ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AdmiralPetsMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		if (!g_bPluginEnable || !g_bPetMenuEnable || !HasAdmiralMenuAccess(client)) return 0;

		if (GetClientTeam(client) != L4D2Team_Survivor)
		{
			CPrintToChat(client, "{green}[Admiral] {default}Only survivors team can use this.");
			return 0;
		}

		if (!IsPlayerAlive(client))
		{
			CPrintToChat(client, "{green}[Admiral] {default}Only alive survivors can use this command.");
			return 0;
		}

		char item[32];
		menu.GetItem(select, item, sizeof(item));

		bool isSpawned = IsPetValid(client);

		if (StrEqual(item, "TOGGLE"))
		{
			if (isSpawned) ReturnPet(client);
			else
			{
				char model[PLATFORM_MAX_PATH];
				GetPetModel(client, model, sizeof(model));

				if (!g_bPetsCustomEnable && StrContains(model, "jockey", false) == -1)
				{
					strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
					GetPetModel(client, model, sizeof(model));
				}

				SpawnPet(client, model);
			}

			Create_AdmiralPetsMenu(client);
		}
		else if (StrEqual(item, "PET"))
		{
			if (!isSpawned)
			{
				if (!g_bPetsCustomEnable)
				{
					strcopy(g_sPet_Name[client], sizeof(g_sPet_Name[]), "Jockey");
					SavePetCookies_Settings(client);

					CPrintToChat(client, "{green}[Admiral] {default}Custom pets are disabled. Only Jockey pet is available.");
				}
				else CyclePetName(client);
			}
			else PetTalk(client);

			Create_AdmiralPetsMenu(client);
		}
		else if (StrEqual(item, "GLOW"))
		{
			if (isSpawned)
			{
				PetAura_SetOrCycle(client);
				SavePetCookies_Settings(client);
			}

			Create_AdmiralPetsMenu(client);
		}
		else if (StrEqual(item, "SIZE"))
		{
			if (isSpawned) OpenResizePetMenu(client);
			else Create_AdmiralPetsMenu(client);
		}
		else if (StrEqual(item, "ACTIONS"))
		{
			if (isSpawned) OpenPetEmoteMenu(client);
			else Create_AdmiralPetsMenu(client);
		}
		else if (StrEqual(item, "TRAVEL"))
		{
			if (isSpawned) OpenTeleportPetMenu(client);
			else Create_AdmiralPetsMenu(client);
		}
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if (action == MenuAction_End) delete menu;

	return 0;
}

void PetTalk(int client)
{
	char phrases[][] =
	{
		"Hey boss, what's the plan?",
		"I'm right behind you!",
		"Don't worry, I've got your back.",
		"Lead the way, I'll follow.",
		"Stay alert, stay alive.",
		"We move fast, we survive."
	};

	int random = GetRandomInt(0, sizeof(phrases) - 1);
	CPrintToChat(client, "{green}[Pet]{default} %s", phrases[random]);
}

void SpawnPet(int client, char[] model)
{
	if (!g_bPluginEnable || !g_bPetMenuEnable || !HasAdmiralMenuAccess(client) || GetClientTeam(client) != L4D2Team_Survivor || !IsPlayerAlive(client)) return;

	if (g_hTimer_MoveOut[client] != null)
	{
		Create_AdmiralPetsMenu(client);
		return;
	}

	NormalizePetSettings(client);

	g_iFollowTarget[client] = client;
	g_iPet_Entity[client] = CreatePropDynamic(client, model);

	SetPetAnimation(client, "Spawn");
	SetEntProp(g_iPet_Entity[client], Prop_Send, "m_iGlowType", 3);
	PetAura_SetOrCycle(client, g_sPet_Aura[client]);
	AdjustPetSize(client, "DEFAULT");

	g_hTimer_MoveIn[client] = CreateTimer(0.8, Timer_Spawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	g_iPet_Entity[client] = EntIndexToEntRef(g_iPet_Entity[client]);

	CPrintToChat(client, "{green}[Admiral] {blue}%s {default}is at your service!", g_sPet_Name[client]);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client) continue;
		if (!IsClientInGame(i) || !IsPetValid(i)) continue;

		if (g_iFollowTarget[i] == client)
		{
			g_iFollowTarget[i] = i;
			TeleportPet(i);
		}
	}
}

Action Timer_Spawn(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client)) return Plugin_Handled;

	if (!IsPetValid(client))
	{
		g_hTimer_MoveIn[client] = null;
		return Plugin_Handled;
	}

	SetPetAnimation(client, "Idle");
	g_hTimer_MoveIn[client] = null;
	return Plugin_Handled;
}

void OpenPetEmoteMenu(int client)
{
	Menu menu = new Menu(Handle_PetDanceMenu);
	menu.SetTitle("Select A Move: \n ");
	menu.AddItem("MOVE1", "Move 1");
	menu.AddItem("MOVE2", "Move 2");
	menu.AddItem("MOVE3", "Move 3");
	menu.AddItem("MOVE4", "Move 4");
	menu.AddItem("MOVE5", "Move 5");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_PetDanceMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char item[64];
		menu.GetItem(select, item, sizeof(item));

		if (!IsPetValid(client)) return 0;

		if (StrEqual(item, "MOVE1")) SetPetAnimation(client, "Move 1");
		else if (StrEqual(item, "MOVE2")) SetPetAnimation(client, "Move 2");
		else if (StrEqual(item, "MOVE3")) SetPetAnimation(client, "Move 3");
		else if (StrEqual(item, "MOVE4")) SetPetAnimation(client, "Move 4");
		else if (StrEqual(item, "MOVE5")) SetPetAnimation(client, "Move 5");
		OpenPetEmoteMenu(client);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralPetsMenu(client);
	else if (action == MenuAction_End) delete menu;
	return 0;
}

void PetAura_SetOrCycle(int client, const char[] color = "")
{
	if (!IsPetValid(client)) return;

	if (g_sPet_Aura[client][0] == '\0' || StrEqual(g_sPet_Aura[client], "Default", false) || StrEqual(g_sPet_Aura[client], "Disabled", false))
		strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), "White");

	if (color[0] == '\0') GetNextColor(g_sPet_Aura[client], g_sPet_Aura[client], sizeof(g_sPet_Aura[]), false, false);
	else strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), color);

	if (StrEqual(g_sPet_Aura[client], "Black", false) || StrEqual(g_sPet_Aura[client], "Disabled", false))
	{
		SetEntProp(g_iPet_Entity[client], Prop_Send, "m_iGlowType", 0);
		SetEntProp(g_iPet_Entity[client], Prop_Send, "m_glowColorOverride", 0);
		return;
	}

	int rgb[3];
	if (!GetColorRGB(g_sPet_Aura[client], rgb))
	{
		strcopy(g_sPet_Aura[client], sizeof(g_sPet_Aura[]), "White");
		GetColorRGB(g_sPet_Aura[client], rgb);
	}

	SetEntProp(g_iPet_Entity[client], Prop_Send, "m_iGlowType", 3);
	SetEntProp(g_iPet_Entity[client], Prop_Send, "m_glowColorOverride", PackColor(rgb));
}

void OpenResizePetMenu(int client)
{
	Menu menu = new Menu(Handle_ResizePetMenu);
	menu.SetTitle("Scale Your Companion: \n ");
	menu.AddItem("DEFAULT", "Default");
	menu.AddItem("INCREASE", "Increase");
	menu.AddItem("DECREASE", "Decrease");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_ResizePetMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		char item[64];
		menu.GetItem(select, item, sizeof(item));
		
		if (!IsPetValid(client)) return 0;
		else if(StrEqual(item, "DEFAULT") || StrEqual(item, "INCREASE") || StrEqual(item, "DECREASE"))
		{
			AdjustPetSize(client, item);
			OpenResizePetMenu(client);
		}
		
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralPetsMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

float GetPetBaseSize(const char[] petName)
{
	if (StrEqual(petName, "Jockey")) return 0.55;
	if (StrEqual(petName, "Melisa")) return 1.00;
	if (StrEqual(petName, "Sparky")) return 1.00;
	if (StrEqual(petName, "Storm")) return 1.00;
	return 1.00;
}

void AdjustPetSize(int client, const char[] action)
{
	if (!IsPetValid(client)) return;

	float base = GetPetBaseSize(g_sPet_Name[client]);
	float step = 0.10;

	float size = StringToFloat(g_sPet_Size[client]);
	if (size <= 0.0) size = base;

	if (StrEqual(action, "DEFAULT")) size = base;
	else if (StrEqual(action, "INCREASE")) size += step;
	else if (StrEqual(action, "DECREASE")) size -= step;

	float min = base - (step * 4.0);
	float max = base + (step * 4.0);

	if (size < min) size = min;
	if (size > max) size = max;

	FormatEx(g_sPet_Size[client], sizeof(g_sPet_Size[]), "%.3f", size);

	int ent = EntRefToEntIndex(g_iPet_Entity[client]);
	if (ent > 0) SetEntPropFloat(ent, Prop_Send, "m_flModelScale", size);
}

void OpenTeleportPetMenu(int client)
{
	Menu menu = new Menu(Handle_TeleportPetMenu);
	menu.SetTitle("Teleport Companion To: \n ");
	
	char sInfo[255];
	char sPosition[32];
	char sUserID[10];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != L4D2Team_Survivor || !IsPetValid(client)) continue;
		
		if(!IsPlayerAlive(i)) FormatEx(sPosition, sizeof(sPosition), "Dead");
		else if (IsPlayerIncapacitated(i) && !IsPlayerGrabbed(i)) FormatEx(sPosition, sizeof(sPosition), "Incapped");
		else if (IsHandingFromLedge(i)) FormatEx(sPosition, sizeof(sPosition), "Hanging");
		else if (IsPlayerGrabbed(i)) FormatEx(sPosition, sizeof(sPosition), "Held By Infected");
		else FormatEx(sPosition, sizeof(sPosition), "Standing");
		
		FormatEx(sInfo, sizeof(sInfo), "%N - %s", i, sPosition);
		IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
		menu.AddItem(sUserID, sInfo);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_TeleportPetMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char sUserID[12];
		menu.GetItem(select, sUserID, sizeof(sUserID));
		int target = GetClientOfUserId(StringToInt(sUserID));
		
		if(!IsPetValid(client))
		{
			CPrintToChat(client, "{green}[Admiral]{default} You have no pet.");
			Create_AdmiralPetsMenu(client);
			return 0;
		}
		
		if (!target || !IsClientInGame(target) || GetClientTeam(target) != L4D2Team_Survivor) return 0;
		
		if (!IsPlayerAlive(target))
		{
			CPrintToChat(client, "{green}[Admiral]{default} %N is dead.", target);
			OpenTeleportPetMenu(client);
			return 0;
		}
		
		if (target != client && IsPetValid(target))
		{
			CPrintToChat(client, "{green}[Admiral]{blue} %N {default}already has a pet.", target);
			OpenTeleportPetMenu(client);
			return 0;
		}
		
		g_iFollowTarget[client] = target;
		TeleportPet(client);
		OpenTeleportPetMenu(client);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralPetsMenu(client);
	else if (action == MenuAction_End) delete menu;
	return 0;
}

public void OnGameFrame()
{
	if (!g_bPluginEnable) return;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!g_iPet_Entity[client] && g_hTimer_MoveIn[client] == null && g_hTimer_MoveOut[client] == null) continue;
		if (!IsClientInGame(client))
		{
			RemovePet(client);
			continue;
		}
		if (!g_bPetMenuEnable || !HasAdmiralMenuAccess(client))
		{
			RemovePet(client);
			continue;
		}
		if (!IsPlayerAlive(client) || GetClientTeam(client) != L4D2Team_Survivor) continue;
		if (!IsPetValid(client) || g_hTimer_MoveIn[client] != null || g_bIsTeleportPet[client]) continue;
		
		int target = g_iFollowTarget[client];
		if (target <= 0 || target > MaxClients || !IsClientInGame(target) || !IsPlayerAlive(target) || GetClientTeam(target) != L4D2Team_Survivor) g_iFollowTarget[client] = client;
		
		SetTrackingMethod(client);
	}
}

void SetTrackingMethod(int client)
{
	int target = ResolvePetFollowTarget(client);
	
	float vClientPos[3], vPetPos[3];
	GetClientAbsOrigin(target, vClientPos);
	GetEntPropVector(g_iPet_Entity[client], Prop_Data, "m_vecOrigin", vPetPos);
	
	float fDistance = GetVectorDistance(vClientPos, vPetPos);

	if (g_bPetPaused[client] || ShouldFreezeForFatalOrLadder(client))
	{
		g_bPetPaused[client] = true;
		SetPetAnimation(client, "Idle");
		
		if (IsGrounded(client) && !IsOnLadder(client) && (GetTime() - g_iLastTeleportTime[client] >= 3))
		{
			g_bPetPaused[client] = false;
			TeleportPet(client);
		}
		return;
	}
	
	if (fDistance > TELEPORT_DISTANCE)
	{
		TeleportPet(client);
		return;
	}
	
	if (fDistance <= CLIENT_NEAR_DISTANCE)
	{
		if (GetGameTime() < g_fPet_AnimLock[client]) return;
		SetPetAnimation(client, "Idle");
		ResetSteps(client, vClientPos);
		return;
	}
	
	MovePetToNextStep(client, vClientPos, vPetPos);
}

void MovePetToNextStep(int client, float vClientPos[3], float vPetPos[3])
{
	float vPetAngle[3];
	GetEntPropVector(g_iPet_Entity[client], Prop_Data, "m_angRotation", vPetAngle);
	
	// Always record the newest step
	SaveNextStep(client, vClientPos);
	
	float nextX = g_fPlayerSteps[g_iLoadedStep[client]][client][0];
	float nextY = g_fPlayerSteps[g_iLoadedStep[client]][client][1];
	float nextZ = g_fPlayerSteps[g_iLoadedStep[client]][client][2];
	
	float deltaX  = nextX - vPetPos[0];
	float deltaY  = nextY - vPetPos[1];
	float deltaZ  = nextZ - vPetPos[2];
	
	float fDist2D = SquareRoot(deltaX *deltaX  + deltaY * deltaY);
	
	// Compute exact yaw & pitch from step A (pet) to step B (next step)
	float fHoriz = (fDist2D < 0.0001) ? 0.0001 : fDist2D;
	float fTargetYaw   =  (ArcTangent2(deltaY , deltaX ) * 180.0) / FLOAT_PI;
	float fTargetPitch = -(ArcTangent2(deltaZ , fHoriz) * 180.0) / FLOAT_PI;
	
	
	// Spin check fix
	float fCurrYaw = vPetAngle[1];
	float fYawDiff = fTargetYaw - fCurrYaw;
	
	while (fYawDiff > 180.0) fYawDiff -= 360.0;
	while (fYawDiff < -180.0) fYawDiff += 360.0;
	if ((fDist2D < 18.0 && FloatAbs(fYawDiff) > 135.0) || (fDist2D < 16.0 && FloatAbs(fTargetPitch) > 45.0))
	{
		SetPetAnimation(client, "Idle");
		ResetSteps(client, vClientPos);
		return;
	}
	
	// Teleport the pet whenever the required pitch angle is too steep, indicating a sharp change in elevation.
	if (FloatAbs(fTargetPitch) > 75.0)
	{
		TeleportPet(client);
		return;
	}
	
	// Set angles directly (no caps / no smoothing)
	vPetAngle[1] = fTargetYaw;
	vPetAngle[0] = fTargetPitch;
	
	// Face and move forward based on the full 3D angle (no vertical cap)
	float vDirection[3];
	float vNewPos[3];
	GetAngleVectors(vPetAngle, vDirection, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(vDirection, vDirection);
	
	float fSpeed = SetPetSpeed(client, vClientPos, vPetPos);
	
	// Keep your animation logic tied to fSpeed
	float fAbsPitch = FloatAbs(vPetAngle[0]);
	if (fAbsPitch > 10.0) fSpeed *= 0.9;
	if (fAbsPitch > 18.0) fSpeed *= 0.8;
	
	// Move using the exact forward vector
	vNewPos[0] = vPetPos[0] + vDirection[0] * fSpeed;
	vNewPos[1] = vPetPos[1] + vDirection[1] * fSpeed;
	vNewPos[2] = vPetPos[2] + vDirection[2] * fSpeed;
	
	SetAbsOrigin(g_iPet_Entity[client], vNewPos);
	SetAbsAngles(g_iPet_Entity[client], vPetAngle);
	
	LoadNextStep(client, vNewPos);
}

void SaveNextStep(int client, float vPos[3])
{
	float fInterval = PET_MOVE_INTERVAL;
	float fNow = GetGameTime();
	if (fNow - g_fLastStepWriteTime[client] < fInterval) return;
	
	int target = ResolvePetFollowTarget(client);
	
	g_fPlayerSteps[g_iSavedStep[client]][client][0] = vPos[0];
	g_fPlayerSteps[g_iSavedStep[client]][client][1] = vPos[1];
	g_fPlayerSteps[g_iSavedStep[client]][client][2] = IsGrounded(target) ? vPos[2] : (vPos[2] - GroundDistance(target));
	
	g_iSavedStep[client] = (g_iSavedStep[client] > 0) ? (g_iSavedStep[client] - 1) : (MAX_STEPS_MEMORY - 1);
	g_fLastStepWriteTime[client] = fNow;
}

void LoadNextStep(int client, float pos[3])
{
	float fReached = STEP_REACH_DISTANCE + 6.0;
	if (GetVectorDistance(pos, g_fPlayerSteps[g_iLoadedStep[client]][client]) < fReached) g_iLoadedStep[client] = (g_iLoadedStep[client] - 1 + MAX_STEPS_MEMORY) % MAX_STEPS_MEMORY;
}

void ResetSteps(int client, float pos[3])
{
    int target = ResolvePetFollowTarget(client);

    if (IsGrounded(target)) SnapPetToGround(client);

    SetPetAnimation(client, "Idle");

    g_iSavedStep[client]  = MAX_STEPS_MEMORY - 1;
    g_iLoadedStep[client] = MAX_STEPS_MEMORY - 1;

    SaveNextStep(client, pos);
}

void TeleportPet(int client)
{
	int iNow = GetTime();
	if (iNow - g_iLastTeleportTime[client] < 3) return;
	g_iLastTeleportTime[client] = iNow;
	
	if (!IsPetValid(client)) return;
	
	g_bIsTeleportPet[client] = true;
	SetPetAnimation(client, "Return");
	CreateTimer(1.0, Timer_TeleportPetIn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

bool TeleportPetTimerGuard(int client)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client)) return false;

	if (!IsPetValid(client))
	{
		g_bIsTeleportPet[client] = false;
		return false;
	}

	return true;
}

int ResolvePetFollowTarget(int client)
{
	int target = g_iFollowTarget[client];
	if (!target || !IsClientInGame(target) || !IsPlayerAlive(target) || GetClientTeam(target) != L4D2Team_Survivor)
		return client;
	return target;
}

Action Timer_TeleportPetIn(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!TeleportPetTimerGuard(client)) return Plugin_Handled;

	int target = ResolvePetFollowTarget(client);

	float vClientPos[3], vClientAng[3];
	GetClientAbsOrigin(target, vClientPos);
	GetEntPropVector(target, Prop_Data, "m_angRotation", vClientAng);
	
	SetAbsOrigin(g_iPet_Entity[client], vClientPos);
	SetAbsAngles(g_iPet_Entity[client], vClientAng);
	
	SetPetAnimation(client, "Spawn");
	CreateTimer(1.5, Timer_TeleportPetOut, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

Action Timer_TeleportPetOut(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!TeleportPetTimerGuard(client)) return Plugin_Handled;

	int target = ResolvePetFollowTarget(client);
	
	float vPos[3];
	GetClientAbsOrigin(target, vPos);
	
	ResetSteps(client, vPos);    // <- seed for the OWNER
	
	for (int i = 0; i < MAX_STEPS_MEMORY; i++)
	{
		g_fPlayerSteps[i][client][0] = vPos[0];
		g_fPlayerSteps[i][client][1] = vPos[1];
		g_fPlayerSteps[i][client][2] = vPos[2];
	}
	
	g_bIsTeleportPet[client] = false;
	return Plugin_Handled;
}

int CreatePropDynamic(int client, char[] model)
{
	int entity = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(entity, "targetname", "l4d2_admiral_pet");
	DispatchKeyValue(entity, "model", model);
	
	float vecView[3], vDirection[3], vecPos[3];
	GetClientEyePosition(client, vecView);
	GetClientAbsOrigin(client, vecPos);
	GetClientEyeAngles(client, vecView);
	GetAngleVectors(vecView, vDirection, NULL_VECTOR, NULL_VECTOR);
	vecPos[0] += vDirection[0] * 50.0;
	vecPos[1] += vDirection[1] * 50.0;
	
	DispatchKeyValueVector(entity, "origin", vecPos);
	DispatchSpawn(entity);
	SetEntPropFloat(entity, Prop_Data, "m_flPoseParameter", 1.0, 4);
	
	g_iSavedStep[client]  = MAX_STEPS_MEMORY - 1;
	g_iLoadedStep[client] = MAX_STEPS_MEMORY - 1;
	
	float vClientPos[3];
	GetClientAbsOrigin(client, vClientPos);
	SaveNextStep(client, vClientPos);
	
	return entity;
}

void ReturnPet(int client)
{
	if (!IsPetValid(client)) return;

	CPrintToChat(client, "{green}[Admiral] {default}Farewell!");
	SetPetAnimation(client, "Return");
	g_hTimer_MoveOut[client] = CreateTimer(0.8, Timer_ReturnMyPet, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_ReturnMyPet(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client)) return Plugin_Handled;

	g_hTimer_MoveOut[client] = null;
	RemovePet(client);
    
	return Plugin_Handled;
}

void RemovePet(int client)
{
	if (g_iPet_Entity[client] && EntRefToEntIndex(g_iPet_Entity[client]) != INVALID_ENT_REFERENCE)
		AcceptEntityInput(g_iPet_Entity[client], "Kill");
	
	delete g_hTimer_MoveIn[client];
	delete g_hTimer_MoveOut[client];
	
	g_bIsTeleportPet[client]    = false;
	g_bPetPaused[client]        = false;
	
	g_iPet_Entity[client]       = 0;
	g_iPet_MoveType[client]     = 0;
	
	g_fPet_AnimLock[client]      = 0.0;
}

bool IsPetValid(int client)
{
	return g_iPet_Entity[client] && EntRefToEntIndex(g_iPet_Entity[client]) != INVALID_ENT_REFERENCE && g_hTimer_MoveOut[client] == null;
}

float SetPetSpeed(int client, float vClientPos[3], float vPetPos[3])
{
	float fDistance = GetVectorDistance(vClientPos, vPetPos);
	float fSpeed = 0.3 + 0.0055 * fDistance;
	if (fSpeed < 0.3) fSpeed = 0.3;
	if (fSpeed > 3.6) fSpeed = 3.6;
	
	float vVel[3];
	GetEntPropVector(g_iPet_Entity[client], Prop_Data, "m_vecVelocity", vVel);
	float fVel2D = SquareRoot(vVel[0]*vVel[0] + vVel[1] * vVel[1]);
	bool bIsMoving = (fDistance > CLIENT_NEAR_DISTANCE) || (fVel2D > 20.0);
	
	if (bIsMoving)
	{
		if (fDistance < 500.0) SetPetAnimation(client, "Walk");
		else SetPetAnimation(client, "Run");
		return fSpeed;
	}
	
	if (g_iPet_MoveType[client] >= 6 && GetGameTime() < g_fPet_AnimLock[client]) return fSpeed;
	
	static float fLastAnimDist[MAXPLAYERS+1];
	float fThreshold = (fLastAnimDist[client] >= 500.0) ? 480.0 : 520.0;
	
	if (fDistance < fThreshold) SetPetAnimation(client, "Walk");
	else SetPetAnimation(client, "Run");
	
	fLastAnimDist[client] = fDistance;
	return fSpeed;
}

void SetPetAnimation(int client, const char[] sAnimName)
{
	if (!IsPetValid(client)) return;
	
	static const char sAnimKeys[][] =
	{
		"Idle",
		"Walk",
		"Run",
		"Spawn",
		"Return",
		"Move 1",
		"Move 2",
		"Move 3",
		"Move 4",
		"Move 5",
		"Move 6",
		"Move 7"
	};
	
	static const int iMoveTypes[] =
	{
		1, // Idle
		2, // Walk
		3, // Run
		4, // Spawn
		5, // Return
		6, // Move 1
		7, // Move 2
		8, // Move 3
		9, // Move 4
		10, // Move 5
		11, // Move 6
		12  // Move 7
	};
	
	static const char sAnimSeqs_Jockey[][] =
	{
		"Standing_Idle",   // Idle
		"Run",            // Walk
		"Run",             // Run
		"Jump",            // Spawn
		"Jump",   		  // Return
		"Crouch_Idle",    // Move 1
		"Shoved_Backward", // Move 2
		"Shoved_Forward",  // Move 3
		"Shoved_Leftward", // Move 4
		"Shoved_Rightward",// Move 5
		"Jump",            // Move 6
		"Crouch_Idle"      // Move 7
	};
	
	static const float fLockDurations_Jockey[] =
	{
		0.0, // Idle
		0.0, // Walk
		0.0, // Run
		0.8, // Spawn
		0.8, // Return
		4.0, // Move 1
		0.8, // Move 2
		0.8, // Move 3
		0.8, // Move 4
		0.8, // Move 5
		0.8, // Move 6
		1.0  // Move 7
	};
	
	static const char sAnimSeqs_Melisa[][] =
	{
		"idle",      // Idle
		"run",       // Walk
		"run2",      // Run
		"go_in",     // Spawn
		"go_out",    // Return
		"dance",     // Move 1
		"dance2",    // Move 2
		"celebrate", // Move 3
		"dance3",    // Move 4
		"dance4",    // Move 5
		"interact",  // Move 6
		"idle2"      // Move 7
	};
	
	static const float fLockDurations_Melisa[] =
	{
		0.0,  // Idle, loop
		0.0,  // Walk, run loop
		0.0,  // Run, run2 loop
		3.0,  // Spawn, go_in: 90 frames / 30 fps
		1.5,  // Return, go_out: 45 frames / 30 fps
		7.5,  // Move 1, dance: 225 frames / 30 fps
		2.67, // Move 2, dance2: 80 frames / 30 fps, loop
		1.47, // Move 3, celebrate: 44 frames / 30 fps
		1.67, // Move 4, dance3: 50 frames / 30 fps, loop
		1.67, // Move 5, dance4: 50 frames / 30 fps, loop
		3.7,  // Move 6, interact: 111 frames / 30 fps
		2.0   // Move 7, idle2, estimated
	};
	
	static const char sAnimSeqs_Dango[][] =
	{
		"idle",     // Idle
		"run",      // Walk
		"run2",     // Run
		"go_in",    // Spawn
		"go_out",   // Return
		"dance",    // Move 1
		"dance2",   // Move 2
		"taunt",    // Move 3
		"celebrate",// Move 4
		"eatfish",  // Move 5
		"taunt_in", // Move 6
		"interact"  // Move 7
	};
	
	static const float fLockDurations_Dango[] =
	{
		0.0,  // Idle, loop
		0.0,  // Walk, run loop
		0.0,  // Run, run2 loop
		2.4,  // Spawn, go_in: 72 / 30
		1.27, // Return, go_out: 38 / 30
		0.67, // Move 1, dance: 20 / 30, loop
		1.0,  // Move 2, dance2: 30 / 30, loop
		2.77, // Move 3, taunt: 83 / 30, loop
		1.53, // Move 4, celebrate: 46 / 30
		5.67, // Move 5, eatfish: 170 / 30
		1.23, // Move 6, taunt_in: 37 / 30
		4.0   // Move 7, interact: 120 / 30
	};
	
	static const char sAnimSeqs_Qiqi[][] =
	{
		"idle",      // Idle
		"run",       // Walk
		"run2",      // Run
		"go_in",     // Spawn
		"go_out",    // Return
		"dance",     // Move 1
		"celebrate", // Move 2
		"chanhcho",  // Move 3
		"nhay",      // Move 4
		"what",      // Move 5
		"idle2",     // Move 6
		"lacvong"    // Move 7
	};
	
	static const float fLockDurations_Qiqi[] =
	{
		0.0,   // Idle, loop
		0.0,   // Walk, run loop
		0.0,   // Run, run2 loop
		2.4,   // Spawn, go_in: 72 / 30
		2.37,  // Return, go_out: 71 / 30
		15.93, // Move 1, dance: 478 / 30
		1.37,  // Move 2, celebrate: 41 / 30
		6.67,  // Move 3, chanhcho: 200 / 30
		1.93,  // Move 4, nhay: 58 / 30, loop
		4.33,  // Move 5, what: 130 / 30
		2.0,   // Move 6, idle2, estimated
		0.43   // Move 7, lacvong: 13 / 30, loop
	};
	
	int iAnimIndex = -1;
	for (int i = 0; i < sizeof(sAnimKeys); i++)
	{
		if (StrEqual(sAnimName, sAnimKeys[i], false))
		{
			iAnimIndex = i;
			break;
		}
	}
	
	if (iAnimIndex == -1) return;
	
	int iReqType = iMoveTypes[iAnimIndex];
	float fNow = GetGameTime();
	
	if (iReqType <= 5 && g_iPet_MoveType[client] >= 6 && fNow < g_fPet_AnimLock[client]) g_fPet_AnimLock[client] = 0.0;
	if (iReqType <= 5 && g_iPet_MoveType[client] == iReqType) return;
	if (iReqType >= 6 && fNow < g_fPet_AnimLock[client]) return;
	
	float fLockTime = 0.0;
	char sSeq[64];
	
	if (StrEqual(g_sPet_Name[client], "Jockey", false))
	{
		fLockTime = fLockDurations_Jockey[iAnimIndex];
		strcopy(sSeq, sizeof(sSeq), sAnimSeqs_Jockey[iAnimIndex]);
	}
	else if (StrEqual(g_sPet_Name[client], "Melisa", false))
	{
		fLockTime = fLockDurations_Melisa[iAnimIndex];
		strcopy(sSeq, sizeof(sSeq), sAnimSeqs_Melisa[iAnimIndex]);
	}
	else if (StrEqual(g_sPet_Name[client], "Sparky", false))
	{
		fLockTime = fLockDurations_Dango[iAnimIndex];
		strcopy(sSeq, sizeof(sSeq), sAnimSeqs_Dango[iAnimIndex]);
	}
	else if (StrEqual(g_sPet_Name[client], "Storm", false))
	{
		fLockTime = fLockDurations_Qiqi[iAnimIndex];
		strcopy(sSeq, sizeof(sSeq), sAnimSeqs_Qiqi[iAnimIndex]);
	}
	else
	{
		fLockTime = fLockDurations_Jockey[iAnimIndex];
		strcopy(sSeq, sizeof(sSeq), sAnimSeqs_Jockey[iAnimIndex]);
	}
	
	if (sSeq[0] == '\0') return;
	
	if (fLockTime > 0.0) g_fPet_AnimLock[client] = fNow + fLockTime;
	
	int entity = EntRefToEntIndex(g_iPet_Entity[client]);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity)) return;
	
	SetVariantString(sSeq);
	AcceptEntityInput(entity, "SetAnimation");
	
	g_iPet_MoveType[client] = iReqType;
}

float GroundDistance(int client)
{
	float fStart[3], fDistance = 0.0;
	if(IsGrounded(client)) return 0.0;
	
	GetClientAbsOrigin(client, fStart);
	fStart[2] += 10.0;
	
	Handle hTrace = TR_TraceRayFilterEx(fStart, view_as<float>({90.0, 0.0, 0.0}), MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client); 
	if (TR_DidHit(hTrace))
	{
		float fEndPos[3];
		TR_GetEndPosition(fEndPos, hTrace);
		fStart[2] -= 10.0;
		fDistance = GetVectorDistance(fStart, fEndPos);
	}
	
	if (hTrace != null) CloseHandle(hTrace);
	return fDistance;
}

void SnapPetToGround(int client)
{
	if (!IsPetValid(client)) return;
	
	float vOrigin[3];
	GetEntPropVector(g_iPet_Entity[client], Prop_Data, "m_vecOrigin", vOrigin);
	
	float vStart[3];
	vStart[0] = vOrigin[0];
	vStart[1] = vOrigin[1];
	vStart[2] = vOrigin[2] + 50.0;

	float vEnd[3];
	vEnd[0] = vStart[0];
	vEnd[1] = vStart[1];
	vEnd[2] = vStart[2] - 2048.0;
	
	Handle hTrace = TR_TraceRayFilterEx(vStart, vEnd, MASK_PLAYERSOLID, RayType_EndPoint, TraceRayDontHitSelf, g_iPet_Entity[client]);
	
	if (hTrace != null && TR_DidHit(hTrace))
	{
		float vHit[3];
		TR_GetEndPosition(vHit, hTrace);
		
		float vFixedPos[3];
		vFixedPos[0] = vOrigin[0];
		vFixedPos[1] = vOrigin[1];
		vFixedPos[2] = vHit[2];
		
		SetAbsOrigin(g_iPet_Entity[client], vFixedPos);
	}
	
	if (hTrace != null) CloseHandle(hTrace);
}

bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	if (entity == data) return false;
	if (entity >= 1 && entity <= MaxClients && IsClientInGame(entity)) return false;
	return true; 
}

bool NextStepIsLadder(int client)
{
	float vNextStep[3];
	vNextStep[0] = g_fPlayerSteps[g_iLoadedStep[client]][client][0];
	vNextStep[1] = g_fPlayerSteps[g_iLoadedStep[client]][client][1];
	vNextStep[2] = g_fPlayerSteps[g_iLoadedStep[client]][client][2] + 16.0;
	
	int iContents  = TR_GetPointContents(vNextStep);
	return (iContents & CONTENTS_LADDER) != 0;
}

bool IsFatalDrop(int client)
{
	if (!IsClientInGame(client)) return false;
	if (IsPlayerIncapacitated(client) || IsGrounded(client) || IsOnLadder(client)) return false;
	
	float fGap = GroundDistance(client);
	if (fGap >= 720.0) return true;
	if (fGap >= 520.0)
	{
		float vVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
		if (vVelocity[2] <= -240.0) return true;
	}
	
	return false;
}

bool ShouldFreezeForFatalOrLadder(int client)
{
	int target = ResolvePetFollowTarget(client);
	if (IsOnLadder(target) || IsFatalDrop(target) || NextStepIsLadder(client)) return true;
	return false;
}

/* =================================================================================================================== *
 *                                           Cosmetics: Skin & Aura Colors                                          *
 *==================================================================================================================== */

static const char g_sColorPaletteNames[][] =
{
	"White", "Gray", "Red", "Crimson", "Coral", "Peach", "Orange", "Gold",
	"Yellow", "Lime", "Green", "Mint", "Cyan", "Sky", "Blue", "Navy",
	"Purple", "Violet", "Lavender", "Pink", "Rose", "Midnight", "Rainbow", "Black"
};

static const int g_iColorPaletteRGB[][3] =
{
	{255, 255, 255}, {80, 80, 80}, {255, 0, 0}, {139, 0, 0},
	{255, 60, 20}, {255, 180, 140}, {255, 128, 0}, {255, 215, 0},
	{255, 255, 0}, {128, 255, 0}, {0, 255, 0}, {0, 255, 150},
	{0, 255, 255}, {135, 206, 250}, {0, 0, 255}, {0, 0, 100},
	{128, 0, 128}, {249, 19, 255}, {180, 150, 255}, {255, 105, 180},
	{255, 0, 100}, {0, 51, 51}, {-1, -1, -1}, {0, 0, 0}
};

void GetNextColor(const char[] current, char[] sNext, int maxLen, bool skin, bool rainbow = true)
{
	if (current[0] == '\0' || StrEqual(current, "Default", false) || StrEqual(current, "Disabled", false))
	{
		strcopy(sNext, maxLen, skin ? "Gray" : "White");
		return;
	}

	for (int i = 0; i < sizeof(g_sColorPaletteNames); i++)
	{
		if (!StrEqual(current, g_sColorPaletteNames[i], false)) continue;

		for (int j = i + 1; j < sizeof(g_sColorPaletteNames); j++)
		{
			if (!rainbow && StrEqual(g_sColorPaletteNames[j], "Rainbow", false)) continue;
			strcopy(sNext, maxLen, g_sColorPaletteNames[j]);
			return;
		}

		strcopy(sNext, maxLen, "White");
		return;
	}
	
	strcopy(sNext, maxLen, "White");
}

bool GetColorRGB(const char[] color, int rgb[3])
{
	for (int i = 0; i < sizeof(g_sColorPaletteNames); i++)
	{
		if (!StrEqual(color, g_sColorPaletteNames[i], false)) continue;
		if (g_iColorPaletteRGB[i][0] < 0) return false;

		rgb[0] = g_iColorPaletteRGB[i][0];
		rgb[1] = g_iColorPaletteRGB[i][1];
		rgb[2] = g_iColorPaletteRGB[i][2];
		return true;
	}
	return false;
}

int PackColor(int rgb[3])
{
	return rgb[0] + (rgb[1] * 256) + (rgb[2] * 65536);
}

void CycleColor(int client, bool skin)
{
	char sNext[16];

	if (skin)
	{
		GetNextColor(g_sSkinColor[client], sNext, sizeof(sNext), true);
		if (StrEqual(sNext, "White", false)) strcopy(sNext, sizeof(sNext), "Default");
		SetSkinColor(client, sNext, true);
	}
	else
	{
		GetNextColor(g_sAuraColor[client], sNext, sizeof(sNext), false);
		SetAuraColor(client, sNext, true);
	}
}

void Create_AdmiralAppearance(int client)
{
	if (!CanOpenFeatureMenu(client) || !IsAnyAppearanceFeatureEnabled()) return;

	Menu menu = new Menu(Handle_AppearanceMenu);
	menu.SetTitle("Appearance Menu: \n ");

	char sBuffer[64];
	if (StrEqual(g_sSkinColor[client], "White", false)) strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");
	FormatEx(sBuffer, sizeof(sBuffer), "Skin: %s", g_sSkinColor[client][0] ? g_sSkinColor[client] : "Default");
	menu.AddItem("SKIN_COLOR", sBuffer, g_bSkinColorMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "Aura: %s \n ", g_sAuraColor[client][0] ? g_sAuraColor[client] : "Default");
	menu.AddItem("AURA_COLOR", sBuffer, g_bAuraColorMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	NormalizeTrailSettings(client);

	FormatEx(sBuffer, sizeof(sBuffer), "Trail I: %s", g_sTrailColor[client][0]);
	menu.AddItem("TRAIL_A", sBuffer, g_bTrailsMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "Trail II: %s", g_sTrailColor[client][1]);
	menu.AddItem("TRAIL_B", sBuffer, g_bTrailsMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "Trail III: %s", g_sTrailColor[client][2]);
	menu.AddItem("TRAIL_C", sBuffer, g_bTrailsMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	FormatEx(sBuffer, sizeof(sBuffer), "Style: %s", g_sTrailStyle[client]);
	menu.AddItem("TRAIL_STYLE", sBuffer, g_bTrailsMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "Length: %s", g_sTrailLength[client]);
	menu.AddItem("TRAIL_LENGTH", sBuffer, g_bTrailsMenuEnable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AppearanceMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		if (!CanOpenFeatureMenu(client)) return 0;

		char item[64];
		menu.GetItem(select, item, sizeof(item));

		if (StrEqual(item, "SKIN_COLOR") && g_bSkinColorMenuEnable) CycleColor(client, true);
		else if (StrEqual(item, "AURA_COLOR") && g_bAuraColorMenuEnable) CycleColor(client, false);
		else if (StrEqual(item, "TRAIL_A") && g_bTrailsMenuEnable) CycleTrailSlotColor(client, 0);
		else if (StrEqual(item, "TRAIL_B") && g_bTrailsMenuEnable) CycleTrailSlotColor(client, 1);
		else if (StrEqual(item, "TRAIL_C") && g_bTrailsMenuEnable) CycleTrailSlotColor(client, 2);
		else if (StrEqual(item, "TRAIL_STYLE") && g_bTrailsMenuEnable) ToggleTrailStyle(client);
		else if (StrEqual(item, "TRAIL_LENGTH") && g_bTrailsMenuEnable) ToggleTrailLength(client);
		Create_AdmiralAppearance(client);
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

bool IsAnyAppearanceFeatureEnabled()
{
	return g_bSkinColorMenuEnable || g_bAuraColorMenuEnable || g_bTrailsMenuEnable;
}

bool CanOpenFeatureMenu(int client)
{
	return g_bPluginEnable && HasAdmiralMenuAccess(client) && AreClientCookiesCached(client) && g_bCookiesLoaded[client];
}

bool CanUseSurvivorAppearance(int client)
{
	return g_bPluginEnable && IsRealPlayer(client) && GetClientTeam(client) == L4D2Team_Survivor && IsPlayerAlive(client) && HasAdmiralMenuAccess(client);
}

void ResetSurvivorAppearance(int client)
{
	ResetSkinColor(client);
	ResetAuraColor(client);
	KillTrailEntities(client);
}

void ResetSkinColor(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
	SDKUnhook(client, SDKHook_PreThink, Rainbow_Color);
	SetEntityRenderColor(client, 255, 255, 255, 255);
}

void ResetAuraColor(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
	SDKUnhook(client, SDKHook_PreThink, Rainbow_Aura);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", 0);
	SetEntProp(client, Prop_Send, "m_iGlowType", 0);
	SetEntProp(client, Prop_Send, "m_nGlowRange", 0);
	SetEntProp(client, Prop_Send, "m_nGlowRangeMin", 0);
}

void SetSkinColor(int client, char [] color, bool remember)
{
	if (!g_bSkinColorMenuEnable)
	{
		ResetSkinColor(client);
		return;
	}

	if (remember)
	{
		strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), color);
		SaveAppearanceCookies(client);
	}

	SDKUnhook(client, SDKHook_PreThink, Rainbow_Color);

	if (!CanUseSurvivorAppearance(client))
	{
		SetEntityRenderColor(client, 255, 255, 255, 255);
		return;
	}

	if (StrEqual("Rainbow", color))
	{
		SDKHook(client, SDKHook_PreThink, Rainbow_Color);
		return;
	}

	int rgb[3];
	if (StrEqual(color, "Default", false) || StrEqual(color, "White", false) || !GetColorRGB(color, rgb))
	{
		SetEntityRenderColor(client, 255, 255, 255, 255);
		return;
	}

	SetEntityRenderColor(client, rgb[0], rgb[1], rgb[2], 255);
}

Action Rainbow_Color(int client)
{
	if (client <= 0 || client > MaxClients || !CanUseSurvivorAppearance(client))
	{
		SDKUnhook(client, SDKHook_PreThink, Rainbow_Color);
		SetEntityRenderColor(client, 255, 255, 255, 255);
		return Plugin_Stop;
	}

	int rgb[3];
	GetRainbowRGB(client, rgb);
	SetEntityRenderColor(client, rgb[0], rgb[1], rgb[2], 255);
	return Plugin_Handled;
}

void SetAuraColor(int client, char [] color, bool remember)
{
	if (!g_bAuraColorMenuEnable)
	{
		ResetAuraColor(client);
		return;
	}

	if (remember)
	{
		strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), color);
		SaveAppearanceCookies(client);
	}

	SDKUnhook(client, SDKHook_PreThink, Rainbow_Aura);

	if (!CanUseSurvivorAppearance(client) || StrEqual(color, "Default", false) || StrEqual(color, "Black", false))
	{
		ResetAuraColor(client);
		return;
	}

	if (StrEqual(color, "Rainbow", false))
	{
		SDKHook(client, SDKHook_PreThink, Rainbow_Aura);
		return;
	}

	int rgb[3];
	if (!GetColorRGB(color, rgb))
	{
		ResetAuraColor(client);
		return;
	}

	SetEntProp(client, Prop_Send, "m_glowColorOverride", PackColor(rgb));
	SetEntProp(client, Prop_Send, "m_iGlowType", 3);
	SetEntProp(client, Prop_Send, "m_nGlowRange", 99999);
	SetEntProp(client, Prop_Send, "m_nGlowRangeMin", 0);
}

Action Rainbow_Aura(int client)
{
	if (client <= 0 || client > MaxClients || !CanUseSurvivorAppearance(client))
	{
		SDKUnhook(client, SDKHook_PreThink, Rainbow_Aura);
		ResetAuraColor(client);
		return Plugin_Stop;
	}

	int rgb[3];
	GetRainbowRGB(client, rgb);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", PackColor(rgb));
	SetEntProp(client, Prop_Send, "m_iGlowType", 3);
	SetEntProp(client, Prop_Send, "m_nGlowRange", 99999);
	SetEntProp(client, Prop_Send, "m_nGlowRangeMin", 0);
	return Plugin_Handled;
}

void LoadAppearanceCookies(int client)
{
	if (!AreClientCookiesCached(client)) return;

	char sSettings[64];
	GetClientCookie(client, g_hAppearanceSettingsCookie, sSettings, sizeof(sSettings));

	if (sSettings[0] == '\0')
	{
		strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");
		strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), "Default");
		return;
	}

	char sExploded[2][16];
	ExplodeString(sSettings, "|", sExploded, 2, 16);

	if (sExploded[0][0] != '\0') strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), sExploded[0]);
	else strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");
	if (StrEqual(g_sSkinColor[client], "White", false)) strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");

	if (sExploded[1][0] != '\0') strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), sExploded[1]);
	else strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), "Default");
}

void SaveAppearanceCookies(int client)
{
	if (!AreClientCookiesCached(client)) return;

	if (g_sSkinColor[client][0] == '\0' || StrEqual(g_sSkinColor[client], "White", false)) strcopy(g_sSkinColor[client], sizeof(g_sSkinColor[]), "Default");
	if (g_sAuraColor[client][0] == '\0') strcopy(g_sAuraColor[client], sizeof(g_sAuraColor[]), "Default");

	char sSettings[64];
	FormatEx(sSettings, sizeof(sSettings), "%s|%s", g_sSkinColor[client], g_sAuraColor[client]);
	SetClientCookie(client, g_hAppearanceSettingsCookie, sSettings);
}

Action Timer_ResetAppearance(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
	
	if (!CanUseSurvivorAppearance(client))
	{
		ResetSurvivorAppearance(client);
		return Plugin_Handled;
	}
	
	if (g_bSkinColorMenuEnable)
	{
		if (g_sSkinColor[client][0]) SetSkinColor(client, g_sSkinColor[client], false);
		else SetSkinColor(client, "Default", false);
	}
	else ResetSkinColor(client);

	if (g_bAuraColorMenuEnable)
	{
		if (g_sAuraColor[client][0]) SetAuraColor(client, g_sAuraColor[client], false);
		else SetAuraColor(client, "Default", false);
	}
	else ResetAuraColor(client);

	if (g_bTrailsMenuEnable)
	{
		if (g_sTrailColor[client][0][0]) SetPlayerTrails(client, g_sTrailColor[client][0], false);
		else SetPlayerTrails(client, "Default", false);
	}
	else KillTrailEntities(client);
	return Plugin_Handled;
}

/* =================================================================================================================== *
 *                                                 Cosmetics: Trails                                                   *
 *==================================================================================================================== */

void CycleTrailSlotColor(int client, int slot)
{
	char sNext[16];

	switch (slot)
	{
		case 0:
		{
			GetNextColor(g_sTrailColor[client][0], sNext, sizeof(sNext), false);
			strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), sNext);
		}
		case 1:
		{
			GetNextColor(g_sTrailColor[client][1], sNext, sizeof(sNext), false);
			strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), sNext);
		}
		case 2:
		{
			GetNextColor(g_sTrailColor[client][2], sNext, sizeof(sNext), false);
			strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), sNext);
		}
	}

	NormalizeTrailSettings(client);
	SaveTrailCookies(client);
	RefreshPlayerTrails(client);
}

void ToggleTrailLength(int client)
{
	if (StrEqual(g_sTrailLength[client], "Short", false)) strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");
	else if (StrEqual(g_sTrailLength[client], "Normal", false)) strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Long");
	else strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Short");

	SaveTrailCookies(client);
	RefreshPlayerTrails(client);
}

void ToggleTrailStyle(int client)
{
	if (StrEqual(g_sTrailStyle[client], "Linear", false)) strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Spiral");
	else if (StrEqual(g_sTrailStyle[client], "Spiral", false)) strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Arrow");
	else if (StrEqual(g_sTrailStyle[client], "Arrow", false)) strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Ribbon");
	else if (StrEqual(g_sTrailStyle[client], "Ribbon", false)) strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Disabled");
	else strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Linear");

	SaveTrailCookies(client);
	RefreshPlayerTrails(client);
}

void NormalizeTrailSettings(int client)
{
	if (g_sTrailColor[client][0][0] == '\0' || StrEqual(g_sTrailColor[client][0], "Default", false)) strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), "White");
	if (g_sTrailColor[client][1][0] == '\0' || StrEqual(g_sTrailColor[client][1], "Default", false)) strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), "Disabled");
	if (g_sTrailColor[client][2][0] == '\0' || StrEqual(g_sTrailColor[client][2], "Default", false)) strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), "Disabled");

	if (StrEqual(g_sTrailColor[client][0], "Black", false)) strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), "Disabled");
	if (StrEqual(g_sTrailColor[client][1], "Black", false)) strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), "Disabled");
	if (StrEqual(g_sTrailColor[client][2], "Black", false)) strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), "Disabled");

	if (g_sTrailStyle[client][0] == '\0') strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Disabled");
	if (!StrEqual(g_sTrailStyle[client], "Disabled", false)
		&& !StrEqual(g_sTrailStyle[client], "Linear", false)
		&& !StrEqual(g_sTrailStyle[client], "Spiral", false)
		&& !StrEqual(g_sTrailStyle[client], "Arrow", false)
		&& !StrEqual(g_sTrailStyle[client], "Ribbon", false))
		strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Disabled");

	if (g_sTrailLength[client][0] == '\0') strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");
	if (!StrEqual(g_sTrailLength[client], "Short", false) && !StrEqual(g_sTrailLength[client], "Normal", false) && !StrEqual(g_sTrailLength[client], "Long", false)) strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");
}

void RefreshPlayerTrails(int client)
{
	NormalizeTrailSettings(client);
	SetPlayerTrails(client, g_sTrailColor[client][0], false);
}

int GetTrailLineCount(int client)
{
	int count = 0;
	if (!StrEqual(g_sTrailColor[client][0], "Disabled", false)) count++;
	if (!StrEqual(g_sTrailColor[client][1], "Disabled", false)) count++;
	if (!StrEqual(g_sTrailColor[client][2], "Disabled", false)) count++;
	return count;
}

float GetTrailLifetime(int client)
{
	if (StrEqual(g_sTrailLength[client], "Short", false)) return 0.45;
	if (StrEqual(g_sTrailLength[client], "Long", false)) return 1.25;
	return 0.75;
}

void FormatFloatSetting(float value, char[] output, int maxLen)
{
	FormatEx(output, maxLen, "%.2f", value);
}

bool IsAnyTrailRainbow(int client)
{
	return StrEqual(g_sTrailColor[client][0], "Rainbow", false) || StrEqual(g_sTrailColor[client][1], "Rainbow", false) || StrEqual(g_sTrailColor[client][2], "Rainbow", false);
}

void SetPlayerTrails(int client, const char[] color, bool remember)
{
	if (!g_bTrailsMenuEnable)
	{
		KillTrailEntities(client);
		return;
	}

	if(remember)
	{
		strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), color);
		NormalizeTrailSettings(client);
		SaveTrailCookies(client);
	}

	NormalizeTrailSettings(client);
	KillTrailEntities(client);

	if (!CanUseSurvivorAppearance(client)) return;
	if (StrEqual(g_sTrailStyle[client], "Disabled", false)) return;
	if (GetTrailLineCount(client) <= 0) return;

	if (StrEqual(g_sTrailStyle[client], "Spiral", false)) CreateSpiralTrail(client);
	else if (StrEqual(g_sTrailStyle[client], "Arrow", false)) CreateArrowTrail(client);
	else if (StrEqual(g_sTrailStyle[client], "Ribbon", false)) CreateRibbonTrail(client);
	else CreateLinearTrail(client);

	if (IsAnyTrailRainbow(client)) SDKHook(client, SDKHook_PreThink, Rainbow_Trail);
}

void KillTrailEntities(int client)
{
	if (client > 0 && client <= MaxClients) SDKUnhook(client, SDKHook_PreThink, Rainbow_Trail);

	for (int i = 0; i < sizeof(g_iEntTrails[]); i++)
	{
		if (g_iEntTrails[client][i] != 0)
		{
			int entity = EntRefToEntIndex(g_iEntTrails[client][i]);
			if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
			{
				AcceptEntityInput(entity, "HideSprite");
				AcceptEntityInput(entity, "Kill");
			}
			g_iEntTrails[client][i] = 0;
		}
	}
}

void GetTrailColorString(const char[] color, char[] sColor, int maxLen)
{
	int rgb[3];

	if (StrEqual(color, "Rainbow", false)) GetRainbowRGB(0, rgb);
	else if (!GetColorRGB(color, rgb))
	{
		rgb[0] = 255;
		rgb[1] = 255;
		rgb[2] = 255;
	}

	FormatEx(sColor, maxLen, "%d %d %d", rgb[0], rgb[1], rgb[2]);
}

void GetRainbowRGB(int seed, int color[3])
{
	color[0] = RoundToNearest(Cosine((GetGameTime() * 3.0) + seed + 1) * 127.5 + 127.5);
	color[1] = RoundToNearest(Cosine((GetGameTime() * 3.0) + seed + 3) * 127.5 + 127.5);
	color[2] = RoundToNearest(Cosine((GetGameTime() * 3.0) + seed + 5) * 127.5 + 127.5);
}

Action Rainbow_Trail(int client)
{
	if (client <= 0 || client > MaxClients || !CanUseSurvivorAppearance(client) || !IsAnyTrailRainbow(client))
	{
		SDKUnhook(client, SDKHook_PreThink, Rainbow_Trail);
		return Plugin_Stop;
	}

	int colorRGB[3];

	for (int i = 0; i < sizeof(g_iEntTrails[]); i++)
	{
		int entity = EntRefToEntIndex(g_iEntTrails[client][i]);
		if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity)) continue;

		bool rainbowSlot = false;
		if (StrEqual(g_sTrailStyle[client], "Spiral", false) || StrEqual(g_sTrailStyle[client], "Ribbon", false))
		{
			if (i == 1 && StrEqual(g_sTrailColor[client][0], "Rainbow", false)) rainbowSlot = true;
			else if (i == 2 && StrEqual(g_sTrailColor[client][1], "Rainbow", false)) rainbowSlot = true;
			else if (i == 3 && StrEqual(g_sTrailColor[client][2], "Rainbow", false)) rainbowSlot = true;
		}
		else
		{
			if (i == 0 && StrEqual(g_sTrailColor[client][0], "Rainbow", false)) rainbowSlot = true;
			else if (i == 1 && StrEqual(g_sTrailColor[client][1], "Rainbow", false)) rainbowSlot = true;
			else if (i == 2 && StrEqual(g_sTrailColor[client][2], "Rainbow", false)) rainbowSlot = true;
		}

		if (!rainbowSlot) continue;

		GetRainbowRGB(client + i, colorRGB);
		SetEntityRenderColor(entity, colorRGB[0], colorRGB[1], colorRGB[2], 255);
	}

	return Plugin_Handled;
}

void CreateLinearTrail(int client)
{
	float vBase[3];
	GetClientAbsOrigin(client, vBase);

	float vAngles[3], vForward[3];
	GetClientEyeAngles(client, vAngles);
	GetAngleVectors(vAngles, vForward, NULL_VECTOR, NULL_VECTOR);

	float lifetime = GetTrailLifetime(client);
	char sLifetime[16];
	FormatFloatSetting(lifetime, sLifetime, sizeof(sLifetime));

	float heights[3] = { 24.0, 42.0, 60.0 };
	char colors[3][16];
	strcopy(colors[0], sizeof(colors[]), g_sTrailColor[client][0]);
	strcopy(colors[1], sizeof(colors[]), g_sTrailColor[client][1]);
	strcopy(colors[2], sizeof(colors[]), g_sTrailColor[client][2]);

	for (int i = 0; i < 3; i++)
	{
		if (StrEqual(colors[i], "Disabled", false)) continue;

		float vTrail[3];
		vTrail[0] = vBase[0] - (vForward[0] * TRAIL_LINEAR_BACK_OFFSET);
		vTrail[1] = vBase[1] - (vForward[1] * TRAIL_LINEAR_BACK_OFFSET);
		vTrail[2] = vBase[2] + heights[i] - TRAIL_HEIGHT_TRIM;

		char sColor[32];
		GetTrailColorString(colors[i], sColor, sizeof(sColor));

		int trail = CreateSpriteTrail(vTrail, sColor, sLifetime, "5.0", "1.0", "255");
		if (trail <= MaxClients || !IsValidEntity(trail)) continue;

		SetVariantString("!activator");
		AcceptEntityInput(trail, "SetParent", client);
		AcceptEntityInput(trail, "ShowSprite");

		g_iEntTrails[client][i] = EntIndexToEntRef(trail);
	}
}

void CreateArrowTrail(int client)
{
	float vBase[3];
	GetClientAbsOrigin(client, vBase);

	float lifetime = GetTrailLifetime(client) + 0.05;
	char sLifetime[16];
	FormatFloatSetting(lifetime, sLifetime, sizeof(sLifetime));

	float offsets[3][3] =
	{
	    { 0.0, -4.0, 42.0 },
	    { 0.0,  0.0, 42.0 },
	    { 0.0,  4.0, 42.0 }
	};
	for (int k = 0; k < 3; k++) offsets[k][2] -= TRAIL_HEIGHT_TRIM;

	char colors[3][16];
	strcopy(colors[0], sizeof(colors[]), g_sTrailColor[client][0]);
	strcopy(colors[1], sizeof(colors[]), g_sTrailColor[client][1]);
	strcopy(colors[2], sizeof(colors[]), g_sTrailColor[client][2]);

	for (int i = 0; i < 3; i++)
	{
		if (StrEqual(colors[i], "Disabled", false)) continue;

		float vTrail[3];
		vTrail[0] = vBase[0] + offsets[i][0];
		vTrail[1] = vBase[1] + offsets[i][1];
		vTrail[2] = vBase[2] + offsets[i][2];

		char sColor[32];
		GetTrailColorString(colors[i], sColor, sizeof(sColor));

		int trail = CreateSpriteTrail(vTrail, sColor, sLifetime, "9.5", "1.6", "255");
		if (trail <= MaxClients || !IsValidEntity(trail)) continue;

		SetVariantString("!activator");
		AcceptEntityInput(trail, "SetParent", client);
		AcceptEntityInput(trail, "ShowSprite");

		g_iEntTrails[client][i] = EntIndexToEntRef(trail);
	}
}

void CreateRibbonTrail(int client)
{
	float vCenter[3];
	GetClientAbsOrigin(client, vCenter);
	vCenter[2] += 38.0 - TRAIL_HEIGHT_TRIM;

	int rotator = CreateEntityByName("func_rotating");
	if (rotator <= MaxClients || !IsValidEntity(rotator)) return;

	DispatchKeyValue(rotator, "targetname", "l4d2_admiral_trail_rotator");
	DispatchKeyValue(rotator, "renderfx", "5");
	DispatchKeyValue(rotator, "rendermode", "5");
	DispatchKeyValue(rotator, "renderamt", "0");
	DispatchKeyValue(rotator, "rendercolor", "255 255 255");
	DispatchKeyValue(rotator, "maxspeed", "180");
	DispatchKeyValue(rotator, "friction", "20");
	DispatchKeyValue(rotator, "dmg", "0");
	DispatchKeyValue(rotator, "solid", "0");
	DispatchKeyValue(rotator, "spawnflags", "64");
	DispatchSpawn(rotator);
	TeleportEntity(rotator, vCenter, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(rotator, "SetParent", client);

	float lifetime = GetTrailLifetime(client) + 0.15;
	char sLifetime[16];
	FormatFloatSetting(lifetime, sLifetime, sizeof(sLifetime));

	float radius[3] = { -28.0, 0.0, 28.0 };
	char colors[3][16];
	strcopy(colors[0], sizeof(colors[]), g_sTrailColor[client][0]);
	strcopy(colors[1], sizeof(colors[]), g_sTrailColor[client][1]);
	strcopy(colors[2], sizeof(colors[]), g_sTrailColor[client][2]);

	for (int i = 0; i < 3; i++)
	{
		if (StrEqual(colors[i], "Disabled", false)) continue;

		float vTrail[3];
		vTrail[0] = vCenter[0];
		vTrail[1] = vCenter[1] + radius[i];
		vTrail[2] = vCenter[2];

		char sColor[32];
		GetTrailColorString(colors[i], sColor, sizeof(sColor));

		int trail = CreateSpriteTrail(vTrail, sColor, sLifetime, "6.5", "0.9", "255");
		if (trail <= MaxClients || !IsValidEntity(trail)) continue;

		SetVariantString("!activator");
		AcceptEntityInput(trail, "SetParent", rotator);
		AcceptEntityInput(trail, "ShowSprite");

		g_iEntTrails[client][i + 1] = EntIndexToEntRef(trail);
	}

	AcceptEntityInput(rotator, "Start");
	g_iEntTrails[client][0] = EntIndexToEntRef(rotator);
}

void CreateSpiralTrail(int client)
{
	float vCenter[3];
	GetClientAbsOrigin(client, vCenter);
	vCenter[2] += 40.0 - TRAIL_HEIGHT_TRIM;

	int rotator = CreateEntityByName("func_rotating");
	if (rotator <= MaxClients || !IsValidEntity(rotator)) return;

	DispatchKeyValue(rotator, "targetname", "l4d2_admiral_trail_rotator");
	DispatchKeyValue(rotator, "renderfx", "5");
	DispatchKeyValue(rotator, "rendermode", "5");
	DispatchKeyValue(rotator, "renderamt", "0");
	DispatchKeyValue(rotator, "rendercolor", "255 255 255");
	DispatchKeyValue(rotator, "maxspeed", "360");
	DispatchKeyValue(rotator, "friction", "20");
	DispatchKeyValue(rotator, "dmg", "0");
	DispatchKeyValue(rotator, "solid", "0");
	DispatchKeyValue(rotator, "spawnflags", "64");
	DispatchSpawn(rotator);
	TeleportEntity(rotator, vCenter, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(rotator, "SetParent", client);

	float lifetime = GetTrailLifetime(client) + 0.10;
	char sLifetime[16];
	FormatFloatSetting(lifetime, sLifetime, sizeof(sLifetime));

	float radius[3] = { 24.0, -28.0, 32.0 };
	float height[3] = { -18.0, 0.0, 18.0 };
	char colors[3][16];
	strcopy(colors[0], sizeof(colors[]), g_sTrailColor[client][0]);
	strcopy(colors[1], sizeof(colors[]), g_sTrailColor[client][1]);
	strcopy(colors[2], sizeof(colors[]), g_sTrailColor[client][2]);

	for (int i = 0; i < 3; i++)
	{
		if (StrEqual(colors[i], "Disabled", false)) continue;

		float vTrail[3];
		vTrail[0] = vCenter[0] + radius[i];
		vTrail[1] = vCenter[1];
		vTrail[2] = vCenter[2] + height[i];

		char sColor[32];
		GetTrailColorString(colors[i], sColor, sizeof(sColor));

		int trail = CreateSpriteTrail(vTrail, sColor, sLifetime, "4.5", "0.7", "255");
		if (trail <= MaxClients || !IsValidEntity(trail)) continue;

		SetVariantString("!activator");
		AcceptEntityInput(trail, "SetParent", rotator);
		AcceptEntityInput(trail, "ShowSprite");

		g_iEntTrails[client][i + 1] = EntIndexToEntRef(trail);
	}

	AcceptEntityInput(rotator, "Start");
	g_iEntTrails[client][0] = EntIndexToEntRef(rotator);
}

int CreateSpriteTrail(float vPos[3], const char[] sColor, const char[] sLifetime, const char[] sStartWidth, const char[] sEndWidth, const char[] sRenderAmt)
{
	int entity = CreateEntityByName("env_spritetrail");
	if(entity > MaxClients && IsValidEntity(entity))
	{
		DispatchKeyValue(entity, "targetname", "l4d2_admiral_trail");
		DispatchKeyValue(entity, "lifetime", sLifetime);
		DispatchKeyValue(entity, "startwidth", sStartWidth);
		DispatchKeyValue(entity, "endwidth", sEndWidth);
		DispatchKeyValue(entity, "spritename", "materials/sprites/laserbeam.vmt");
		DispatchKeyValue(entity, "rendermode", "5");
		DispatchKeyValue(entity, "rendercolor", sColor);
		DispatchKeyValue(entity, "renderamt", sRenderAmt);
		DispatchSpawn(entity);

		char sPart[3][8];
		ExplodeString(sColor, " ", sPart, sizeof(sPart), sizeof(sPart[]));
		SetEntityRenderColor(entity, StringToInt(sPart[0]), StringToInt(sPart[1]), StringToInt(sPart[2]), StringToInt(sRenderAmt));

		TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
		return entity;
	}
	return 0;
}

public void OnEntityCreated(int entity, const char[] sClassName)
{
	if (strcmp(sClassName, "env_spritetrail", false) == 0)
		RequestFrame(Frame_FixSpriteTrail, EntIndexToEntRef(entity));
}

void Frame_FixSpriteTrail(any ref)
{
	int entity = EntRefToEntIndex(ref);
	if (entity != INVALID_ENT_REFERENCE && IsValidEdict(entity)) FixSpriteTrail(entity);
}

void FixSpriteTrail(int entity)
{
	SetVariantString("OnUser1 !self:SetScale:2:0.5:1");
	AcceptEntityInput(entity, "AddOutput");
	AcceptEntityInput(entity, "FireUser1");
}

void LoadTrailCookies(int client)
{
	if (!AreClientCookiesCached(client)) return;

	char sSettings[128];
	GetClientCookie(client, g_hTrailSettingsCookie, sSettings, sizeof(sSettings));

	if (sSettings[0] == '\0')
	{
		strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), "White");
		strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), "Disabled");
		strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), "Disabled");
		strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), "Disabled");
		strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");
		return;
	}

	char sExploded[6][24];
	ExplodeString(sSettings, "|", sExploded, sizeof(sExploded), sizeof(sExploded[]));

	if (StrEqual(sExploded[0], "v2", false))
	{
		strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), sExploded[1]);
		strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), sExploded[2]);
		strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), sExploded[3]);
		strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), sExploded[4]);
		strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), sExploded[5]);
	}
	else
	{
		strcopy(g_sTrailColor[client][0], sizeof(g_sTrailColor[][]), sExploded[0]);
		strcopy(g_sTrailStyle[client], sizeof(g_sTrailStyle[]), sExploded[1]);
		char sLegacyMode[16];
		strcopy(sLegacyMode, sizeof(sLegacyMode), sExploded[2]);
		strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), "Disabled");
		strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), "Disabled");
		strcopy(g_sTrailLength[client], sizeof(g_sTrailLength[]), "Normal");

		if (StrEqual(sLegacyMode, "2 Lines", false) || StrEqual(sLegacyMode, "Double", false) || StrEqual(sLegacyMode, "Doubled", false)) strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), g_sTrailColor[client][0]);
		else if (StrEqual(sLegacyMode, "3 Lines", false))
		{
			strcopy(g_sTrailColor[client][1], sizeof(g_sTrailColor[][]), g_sTrailColor[client][0]);
			strcopy(g_sTrailColor[client][2], sizeof(g_sTrailColor[][]), g_sTrailColor[client][0]);
		}
	}

	NormalizeTrailSettings(client);
}

void SaveTrailCookies(int client)
{
	if (!AreClientCookiesCached(client)) return;

	NormalizeTrailSettings(client);

	char sSettings[128];
	FormatEx(sSettings, sizeof(sSettings), "v2|%s|%s|%s|%s|%s", g_sTrailStyle[client], g_sTrailColor[client][0], g_sTrailColor[client][1], g_sTrailColor[client][2], g_sTrailLength[client]);
	SetClientCookie(client, g_hTrailSettingsCookie, sSettings);
}

/* =================================================================================================================== *
 *                                          Admiral Tags & Reputation Gating                                           *
 *==================================================================================================================== */

int ParseAdmiralTagRequiredReputation(const char[] sReputation)
{
	char sValue[32];
	strcopy(sValue, sizeof(sValue), sReputation);
	TrimString(sValue);

	if (sValue[0] == '\0') return 0;

	int reputation = StringToInt(sValue);
	if (reputation < 0) reputation = 0;

	return reputation;
}

void GetAdmiralTagNodeData(char[] sTag, int maxLen, int &requiredReputation)
{
	char sReputation[32];

	g_KeyValue.GetString("name", sTag, maxLen);
	TrimString(sTag);

	// Backward compatibility for older nested configs that used "tag" instead of "name".
	if (sTag[0] == '\0')
	{
		g_KeyValue.GetString("tag", sTag, maxLen);
		TrimString(sTag);
	}

	g_KeyValue.GetString("reputation", sReputation, sizeof(sReputation), "0");
	TrimString(sReputation);

	requiredReputation = ParseAdmiralTagRequiredReputation(sReputation);
}

bool ParseAdmiralTagValue(const char[] sRawValue, char[] sTag, int maxLen, int &requiredReputation)
{
	sTag[0] = '\0';
	requiredReputation = 0;

	char sValue[96];
	strcopy(sValue, sizeof(sValue), sRawValue);
	TrimString(sValue);

	if (sValue[0] == '\0') return false;

	char sExploded[2][64];
	int pieces = ExplodeString(sValue, "|", sExploded, 2, 64);

	if (pieces >= 1)
	{
		TrimString(sExploded[0]);
		strcopy(sTag, maxLen, sExploded[0]);
	}

	if (pieces >= 2)
	{
		TrimString(sExploded[1]);
		requiredReputation = ParseAdmiralTagRequiredReputation(sExploded[1]);
	}

	return sTag[0] != '\0';
}

bool IsAdmiralTagReputationAllowed(int client, int requiredReputation)
{
	if (requiredReputation <= 0) return true;

	if (!g_bTotalRepLoaded[client])
	{
		LoadClientTotalReputation(client);
		return false;
	}

	return CPlayers[client].m_iTotalRep >= requiredReputation;
}

bool FindAdmiralTagRequirement(const char[] sWantedTag, int &requiredReputation)
{
	requiredReputation = 0;

	if (sWantedTag[0] == '\0') return false;
	if (StrEqual(sWantedTag, "Default", false)) return true;

	for (int i = 0; i < g_iAdmiralTagCount; i++)
	{
		if (!StrEqual(g_sAdmiralTagCache[i], sWantedTag, false)) continue;

		requiredReputation = g_iAdmiralTagRequirement[i];
		return true;
	}

	return false;
}

bool IsAdmiralTagAllowed(int client, const char[] sTag)
{
	if (sTag[0] == '\0') return false;
	if (StrEqual(sTag, "Default", false)) return true;

	int requiredReputation;
	if (!FindAdmiralTagRequirement(sTag, requiredReputation)) return false;

	return IsAdmiralTagReputationAllowed(client, requiredReputation);
}

bool AddTagToMenu(Menu menu, int client, const char[] sTag, int requiredReputation)
{
	if (sTag[0] == '\0') return false;
	if (StrEqual(sTag, "Default", false)) return false;

	char sDisplay[96];
	bool allowed = IsAdmiralTagReputationAllowed(client, requiredReputation);
	bool selected = StrEqual(g_sAdmiralTag[client], sTag, false);

	if (requiredReputation > 0) FormatEx(sDisplay, sizeof(sDisplay), "%s - Requires %d Rep", sTag, requiredReputation);
	else strcopy(sDisplay, sizeof(sDisplay), sTag);

	menu.AddItem(sTag, sDisplay, (selected || !allowed) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	return true;
}

int AddTagsFromKeyValues(Menu menu, int client)
{
	int count;

	for (int i = 0; i < g_iAdmiralTagCount; i++)
	{
		if (AddTagToMenu(menu, client, g_sAdmiralTagCache[i], g_iAdmiralTagRequirement[i])) count++;
	}

	return count;
}

void Create_AdmiralTagMenu(int client)
{
	if (!CanOpenFeatureMenu(client) || !g_bTagMenuEnable) return;

	if (!g_bTotalRepLoaded[client])
	{
		g_bOpenTagMenuAfterRepLoad[client] = true;
		LoadClientTotalReputation(client);
		CPrintToChat(client, "{green}[Admiral] {default}Loading your total reputation. Open the tag menu again if it does not appear.");
		return;
	}

	Menu menu = new Menu(Handle_AdmiralTagMenu);
	menu.SetTitle("Select Admiral Tag:\nLifetime Reputation: %d\n ", CPlayers[client].m_iTotalRep);

	// Default is always first and means no tag.
	menu.AddItem("Default", "Default", StrEqual(g_sAdmiralTag[client], "Default", false) || !g_sAdmiralTag[client][0] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	AddTagsFromKeyValues(menu, client);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AdmiralTagMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char item[64];
		menu.GetItem(select, item, sizeof(item));

		if (!g_bTagMenuEnable) return 0;

		if (!IsAdmiralTagAllowed(client, item))
		{
			CPrintToChat(client, "{green}[Admiral] {default}This tag is locked by your total reputation.");
			Create_AdmiralTagMenu(client);
			return 0;
		}

		strcopy(g_sAdmiralTag[client], sizeof(g_sAdmiralTag[]), item);
		SaveAdmiralTagCookie(client);
		Create_AdmiralTagMenu(client);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if (action == MenuAction_End) delete menu;
	return 0;
}

/* =================================================================================================================== *
 *                                               Admiral Profile Panel                                                 *
 *==================================================================================================================== */

void Create_AdmiralProfile(int client)
{
	if (client <= 0 || !IsClientInGame(client))
		return;

	char steamid[32], steamEsc[64];
	if (!g_hDatabase || !Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		ShowAdmiralProfilePanel(client, 0, CPlayers[client].m_iTotalRep);
		return;
	}

	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	DataPack pack = Client_CreatePack(client, steamid);
	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
		"SELECT COALESCE(current_rep, 0), COALESCE(lifetime_rep, current_rep, 0) FROM Admiral_Rep_Total WHERE steamid = '%s' LIMIT 1;",
		steamEsc);

	g_hDatabase.Query(OnAdmiralProfileReputationLoaded, g_SQLBuffer, pack);
}

void OnAdmiralProfileReputationLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client))
		return;

	int currentReputation;
	int totalReputation = CPlayers[client].m_iTotalRep;

	if (results == null || error[0] != '\0')
	{
		LogError("Admiral profile reputation query failed (%s)", error);
		ShowAdmiralProfilePanel(client, currentReputation, totalReputation);
		return;
	}

	if (results.FetchRow())
	{
		currentReputation = results.FetchInt(0);
		totalReputation = results.FetchInt(1);
		CPlayers[client].m_iTotalRep = totalReputation;
		g_bTotalRepLoaded[client] = true;
	}

	ShowAdmiralProfilePanel(client, currentReputation, totalReputation);
}

void ShowAdmiralProfilePanel(int client, int currentReputation, int totalReputation)
{
	if (client <= 0 || !IsClientInGame(client))
		return;

	char sAccess[32];
	char sAdmiralPass[32];
	char sLine[256];

	if (IsPlayerAdmiral(client))
	{
		if (IsPlayerAdmin(client)) strcopy(sAccess, sizeof(sAccess), "Admiral (Admin)");
		else strcopy(sAccess, sizeof(sAccess), "Admiral");
	}
	else if (IsPlayerAdmin(client)) strcopy(sAccess, sizeof(sAccess), "Admin");
	else strcopy(sAccess, sizeof(sAccess), "None");

	int timeLeft = GetAdmiralTimeLeft(client);
	if (timeLeft == TIME_FOREVER)
	{
		strcopy(sAdmiralPass, sizeof(sAdmiralPass), "Permanent");
	}
	else
	{
		int days = timeLeft / 86400;
		int hours = (timeLeft % 86400) / 3600;
		int minutes = (timeLeft % 3600) / 60;

		if (days > 0) FormatEx(sAdmiralPass, sizeof(sAdmiralPass), "%dd %dh %dm", days, hours, minutes);
		else FormatEx(sAdmiralPass, sizeof(sAdmiralPass), "%dh %dm", hours, minutes);
	}

	Panel panel = new Panel();
	panel.SetTitle("Admiral Profile");
	panel.DrawText(" ");

	FormatEx(sLine, sizeof(sLine), "Name: %N", client);
	panel.DrawText(sLine);

	FormatEx(sLine, sizeof(sLine), "Access: %s", sAccess);
	panel.DrawText(sLine);

	FormatEx(sLine, sizeof(sLine), "Admiral Pass: %s", sAdmiralPass);
	panel.DrawText(sLine);
	panel.DrawText(" ");

	FormatEx(sLine, sizeof(sLine), "Available Reputation: %d", currentReputation);
	panel.DrawText(sLine);

	FormatEx(sLine, sizeof(sLine), "Lifetime Reputation: %d", totalReputation);
	panel.DrawText(sLine);
	panel.DrawText(" ");

	FormatEx(sLine, sizeof(sLine), "Title: %s", g_sAdmiralTag[client][0] && !StrEqual(g_sAdmiralTag[client], "Default", false) ? g_sAdmiralTag[client] : "Default");
	panel.DrawText(sLine);

	FormatEx(sLine, sizeof(sLine), "Pet: %s", g_sPet_Name[client][0] ? g_sPet_Name[client] : "Jockey");
	panel.DrawText(sLine);
	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.CurrentKey = 8;
	panel.DrawItem("Back", ITEMDRAW_CONTROL);

	panel.DrawText(" ");
	panel.CurrentKey = 10;
	panel.DrawItem("Exit", ITEMDRAW_CONTROL);

	panel.Send(client, Handle_AdmiralProfile, MENU_TIME_FOREVER);
	delete panel;
}

int Handle_AdmiralProfile(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		if(client <= 0 || !IsClientInGame(client)) return 0;
		if(select == 8) Create_AdmiralMenu(client);
	}
	return 0;
}

/* =================================================================================================================== *
 *                                  Admin: Admiral Management Menus & Database Cache                                *
 *==================================================================================================================== */

void Create_AdmiralManagerMenu(int client)
{
	Menu menu = new Menu(Handle_AdmiralManagerMenu);
	menu.SetTitle("Admiral Management\n ");

	menu.AddItem("online", "Online Players");
	menu.AddItem("database", "Database Admirals", g_hDatabase != null ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_AdmiralManagerMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		char item[32];
		menu.GetItem(select, item, sizeof(item));

		if (StrEqual(item, "online")) ShowOnlineAdmiralManagerMenu(client);
		else if (StrEqual(item, "database")) LoadDatabaseAdmiralList(client);
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

void ShowOnlineAdmiralManagerMenu(int client)
{
	Menu menu = new Menu(Handle_OnlineAdmiralManagerMenu);
	
	char sBuffer[128];
	int iCount;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		
		FormatEx(sBuffer, sizeof(sBuffer), "%N", i);
		if(IsPlayerAdmiral(i)) StrCat(sBuffer, sizeof(sBuffer), " (Admiral)");
		if(IsPlayerAdmin(i)) StrCat(sBuffer, sizeof(sBuffer), " (Root)");
		
		++iCount;
		char sUserID[10];
		IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
		menu.AddItem(sUserID, sBuffer);
	}
	
	menu.SetTitle("Online Players: (%d) \n ", iCount);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_OnlineAdmiralManagerMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		char item[32];
		menu.GetItem(select, item, sizeof(item));
		int target = GetClientOfUserId(StringToInt(item));
		
		if(target && IsClientInGame(target)) ShowAdmiralManageMenu(client, target);
		else 
		{
			CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {default}Player left the game.");
			ShowOnlineAdmiralManagerMenu(client);
		}
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralManagerMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

void ResetDatabaseAdmiralCache()
{
	g_bCacheLoaded = false;
	g_bCacheLoading = false;
	g_iCacheCount = 0;
	for (int i = 0; i < DATABASE_CACHE_LIMIT; i++)
	{
		g_DbAdmirals[i].m_sSteam[0] = '\0';
		g_DbAdmirals[i].m_sName[0] = '\0';
		g_DbAdmirals[i].m_iJoinTime = 0;
		g_DbAdmirals[i].m_iTimeDuration = 0;
		g_DbAdmirals[i].m_iTimeLeft = 0;
	}
}

void LoadDatabaseAdmiralList(int client)
{
	if (!Admiral_CheckDatabaseReady(client))
	{
		Create_AdmiralManagerMenu(client);
		return;
	}

	if (g_bCacheLoaded)
	{
		ShowCachedDatabaseAdmiralList(client);
		LoadDatabaseAdmiralCache(0, false, false);
		return;
	}

	LoadDatabaseAdmiralCache(client, true, false);
}

void LoadDatabaseAdmiralCache(int client = 0, bool displayAfterLoad = false, bool force = false)
{
	if (g_hDatabase == null || !g_bSchemaReady) return;
	if (g_bCacheLoading)
	{
		if (force) g_bCacheRefreshQueued = true;
		return;
	}

	g_bCacheLoading = true;

	DataPack pack = new DataPack();
	pack.WriteCell(client > 0 ? GetClientUserId(client) : 0);
	pack.WriteCell(displayAfterLoad);

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
		"SELECT steamid, name, jointime, duration, timeleft FROM Admiral_DataBase WHERE duration = -1 OR (duration > 0 AND (jointime + duration) > %d) ORDER BY name ASC LIMIT %d;",
		GetTime(), DATABASE_CACHE_LIMIT);

	g_hDatabase.Query(OnDatabaseAdmiralCacheLoaded, g_SQLBuffer, pack);
}

void OnDatabaseAdmiralCacheLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int userid = pack.ReadCell();
	bool displayAfterLoad = view_as<bool>(pack.ReadCell());
	delete pack;

	g_bCacheLoading = false;

	int client = userid ? GetClientOfUserId(userid) : 0;

	if (results == null || error[0] != '\0')
	{
		LogError("Database Admiral cache query failed (%s)", error);
		if (displayAfterLoad && IsRealPlayer(client))
		{
			CPrintToChat(client, "{green}[Admiral] {default}Could not load database Admirals.");
			Create_AdmiralManagerMenu(client);
		}
		if (g_bCacheRefreshQueued)
		{
			g_bCacheRefreshQueued = false;
			LoadDatabaseAdmiralCache(0, false, true);
		}
		return;
	}

	ResetDatabaseAdmiralCache();
	g_bCacheLoaded = true;
	g_bCacheLoading = false;

	while (results.FetchRow() && g_iCacheCount < DATABASE_CACHE_LIMIT)
	{
		int index = g_iCacheCount;
		results.FetchString(0, g_DbAdmirals[index].m_sSteam, sizeof(CDbAdmiral::m_sSteam));
		results.FetchString(1, g_DbAdmirals[index].m_sName, sizeof(CDbAdmiral::m_sName));
		g_DbAdmirals[index].m_iJoinTime = results.FetchInt(2);
		g_DbAdmirals[index].m_iTimeDuration = results.FetchInt(3);
		g_DbAdmirals[index].m_iTimeLeft = results.FetchInt(4);
		NormalizeAdmiralAccessData(g_DbAdmirals[index].m_iJoinTime, g_DbAdmirals[index].m_iTimeDuration, g_DbAdmirals[index].m_iTimeLeft);
		g_iCacheCount++;
	}

	if (displayAfterLoad && IsRealPlayer(client)) ShowCachedDatabaseAdmiralList(client);

	if (g_bCacheRefreshQueued)
	{
		g_bCacheRefreshQueued = false;
		LoadDatabaseAdmiralCache(0, false, true);
	}
}

void ShowCachedDatabaseAdmiralList(int client)
{
	if (!IsRealPlayer(client)) return;

	Menu menu = new Menu(Handle_DatabaseAdmiralListMenu);
	menu.SetTitle("Database Admirals\n ");

	char sBuffer[128], sTime[64];
	int iNow = GetTime();
	int iCount;

	for (int i = 0; i < g_iCacheCount; i++)
	{
		int iTimeleft;
		if (g_DbAdmirals[i].m_iTimeDuration == TIME_FOREVER) iTimeleft = TIME_FOREVER;
		else iTimeleft = g_DbAdmirals[i].m_iJoinTime + g_DbAdmirals[i].m_iTimeDuration - iNow;

		if (g_DbAdmirals[i].m_iTimeDuration != TIME_FOREVER && iTimeleft <= 0) continue;

		FormatAdmiralTimeShort(iTimeleft, sTime, sizeof(sTime));
		FormatEx(sBuffer, sizeof(sBuffer), "%s - %s", g_DbAdmirals[i].m_sName[0] ? g_DbAdmirals[i].m_sName : g_DbAdmirals[i].m_sSteam, sTime);
		menu.AddItem(g_DbAdmirals[i].m_sSteam, sBuffer);
		iCount++;
	}

	if (!iCount) menu.AddItem("empty", "No players inside the database", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handle_DatabaseAdmiralListMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		if (!IsRealPlayer(client)) return 0;

		char steamid[32];
		menu.GetItem(select, steamid, sizeof(steamid));

		if (StrEqual(steamid, "empty", false))
		{
			ShowCachedDatabaseAdmiralList(client);
			return 0;
		}

		ShowCachedDatabaseAdmiralDetails(client, steamid);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) Create_AdmiralManagerMenu(client);
	else if (action == MenuAction_End) delete menu;

	return 0;
}

int FindCachedDatabaseAdmiralIndex(const char[] steamid)
{
	for (int i = 0; i < g_iCacheCount; i++)
		if (StrEqual(g_DbAdmirals[i].m_sSteam, steamid, false)) return i;
	
	return -1;
}

int GetCachedDatabaseAdmiralTimeLeft(int index)
{
	if (index < 0 || index >= g_iCacheCount) return 0;
	if (g_DbAdmirals[index].m_iTimeDuration == TIME_FOREVER) return TIME_FOREVER;
	return g_DbAdmirals[index].m_iJoinTime + g_DbAdmirals[index].m_iTimeDuration - GetTime();
}

bool IsCachedDatabaseAdmiralActive(int index)
{
	if (index < 0 || index >= g_iCacheCount) return false;
	return g_DbAdmirals[index].m_iTimeDuration == TIME_FOREVER || GetCachedDatabaseAdmiralTimeLeft(index) > 0;
}

void CacheAdmiralUpsert(const char[] steamid, const char[] name, int joinTime, int duration, int timeLeft)
{
	if (steamid[0] == '\0') return;

	int index = FindCachedDatabaseAdmiralIndex(steamid);
	if (index == -1)
	{
		if (g_iCacheCount >= DATABASE_CACHE_LIMIT) return;
		index = g_iCacheCount++;
	}

	strcopy(g_DbAdmirals[index].m_sSteam, sizeof(CDbAdmiral::m_sSteam), steamid);
	strcopy(g_DbAdmirals[index].m_sName, sizeof(CDbAdmiral::m_sName), name);
	g_DbAdmirals[index].m_iJoinTime = joinTime;
	g_DbAdmirals[index].m_iTimeDuration = duration;
	g_DbAdmirals[index].m_iTimeLeft = timeLeft;
	g_bCacheLoaded = true;
}

void CacheAdmiralRemove(const char[] steamid)
{
	int index = FindCachedDatabaseAdmiralIndex(steamid);
	if (index == -1) return;

	for (int i = index; i < g_iCacheCount - 1; i++)
	{
		strcopy(g_DbAdmirals[i].m_sSteam, sizeof(CDbAdmiral::m_sSteam), g_DbAdmirals[i + 1].m_sSteam);
		strcopy(g_DbAdmirals[i].m_sName, sizeof(CDbAdmiral::m_sName), g_DbAdmirals[i + 1].m_sName);
		g_DbAdmirals[i].m_iJoinTime = g_DbAdmirals[i + 1].m_iJoinTime;
		g_DbAdmirals[i].m_iTimeDuration = g_DbAdmirals[i + 1].m_iTimeDuration;
		g_DbAdmirals[i].m_iTimeLeft = g_DbAdmirals[i + 1].m_iTimeLeft;
	}

	g_iCacheCount--;
	if (g_iCacheCount < 0) g_iCacheCount = 0;

	g_DbAdmirals[g_iCacheCount].m_sSteam[0] = '\0';
	g_DbAdmirals[g_iCacheCount].m_sName[0] = '\0';
	g_DbAdmirals[g_iCacheCount].m_iJoinTime = 0;
	g_DbAdmirals[g_iCacheCount].m_iTimeDuration = 0;
	g_DbAdmirals[g_iCacheCount].m_iTimeLeft = 0;
	g_bCacheLoaded = true;
}

void ShowCachedDatabaseAdmiralDetails(int client, const char[] steamid)
{
	if (!IsRealPlayer(client)) return;

	int index = FindCachedDatabaseAdmiralIndex(steamid);
	if (index == -1 || !IsCachedDatabaseAdmiralActive(index))
	{
		CPrintToChat(client, "{green}[Admiral] {default}That database Admiral is no longer active. Refreshing list...");
		CacheAdmiralRemove(steamid);
		LoadDatabaseAdmiralCache(0, false, true);
		ShowCachedDatabaseAdmiralList(client);
		return;
	}

	int timeLeft = GetCachedDatabaseAdmiralTimeLeft(index);

	strcopy(g_sManageDbSteamId[client], sizeof(g_sManageDbSteamId[]), g_DbAdmirals[index].m_sSteam);
	strcopy(g_sManageDbName[client], sizeof(g_sManageDbName[]), g_DbAdmirals[index].m_sName);

	ShowDatabaseAdmiralManageMenu(client, g_DbAdmirals[index].m_sName, timeLeft);
}

void LoadDatabaseAdmiralDetails(int client, const char[] steamid)
{
	if (!Admiral_CheckDatabaseReady(client))
	{
		Create_AdmiralManagerMenu(client);
		return;
	}

	if (g_bCacheLoaded)
	{
		ShowCachedDatabaseAdmiralDetails(client, steamid);
		return;
	}

	LoadDatabaseAdmiralCache(client, true, true);
}

void ShowDatabaseAdmiralManageMenu(int client, const char[] name, int timeleft)
{
	if (client <= 0 || !IsClientInGame(client)) return;

	Menu menu = new Menu(Handle_DatabaseAdmiralManageMenu);

	char sTime[64];
	FormatAdmiralTimeShort(timeleft, sTime, sizeof(sTime));

	if (!g_hDatabase && !g_bDbConnecting) Database_OnConfigExecuted();

	bool bDatabaseReady = (g_hDatabase != null);

	menu.SetTitle(
		"Manage: %s\n \nState: Admiral (Database)\nTime Left: %s\nDatabase: %s\n ",
		name[0] ? name : "Unknown",
		sTime,
		bDatabaseReady ? "Connected" : (g_bDbConnecting ? "Connecting" : "Not connected")
	);

	menu.AddItem("addtime", "Update Admiral Time");
	menu.AddItem("remove", "Remove Admiral");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_DatabaseAdmiralManageMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		if (!IsRealPlayer(client)) return 0;

		char item[32];
		menu.GetItem(select, item, sizeof(item));

		if (g_sManageDbSteamId[client][0] == '\0')
		{
			LoadDatabaseAdmiralList(client);
			return 0;
		}

		if (StrEqual(item, "addtime", false))
		{
			g_eMenuAction[client] = MENU_ADD_DB_TIME;
			ShowMenuTimeCount(client);
		}
		else if (StrEqual(item, "remove", false)) RemoveDatabaseAdmiral(client, g_sManageDbSteamId[client]);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) LoadDatabaseAdmiralList(client);
	else if (action == MenuAction_End) delete menu;

	return 0;
}

void ShowAdmiralManageMenu(int client, int target)
{
	Menu menu = new Menu(Handle_AdmiralManageMenu);

	char sBuffer[64];
	char sTime[64];
	if (!g_hDatabase && !g_bDbConnecting) Database_OnConfigExecuted();
	bool bDatabaseReady = (g_hDatabase != null);
	
	FormatAdmiralTimeShort(GetAdmiralTimeLeft(target), sTime, sizeof(sTime));
	FormatEx(sBuffer, sizeof(sBuffer), "%s%s", IsPlayerAdmiral(target) ? "Admiral" : "None", IsPlayerAdmin(target) ? " (Root)" : " (User)");
	menu.SetTitle("Manage: (%N)\n \nState: %s\nTime Left: %s\nDatabase: %s \n ", target, sBuffer, sTime, bDatabaseReady ? "Connected" : (g_bDbConnecting ? "Connecting" : "Not connected"));
	
	menu.AddItem("1", "Add New Admiral", (!bDatabaseReady || IsPlayerAdmiral(target)) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("2", "Update Admiral Time", (bDatabaseReady && IsPlayerAdmiral(target)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("3", "Remove Admiral", (bDatabaseReady && IsPlayerAdmiral(target)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	
	g_iMenusTarget[client] = GetClientUserId(target);
}

int Handle_AdmiralManageMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		char item[32];
		menu.GetItem(select, item, sizeof(item));
		
		int task = StringToInt(item);
		int target = GetClientOfUserId(g_iMenusTarget[client]);
		
		if(!target || !IsClientInGame(target))
		{
			CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {default}Player left the game.");
			ShowOnlineAdmiralManagerMenu(client);
		}
		else switch(task)
		{
			case 1:
			{
				if (!Admiral_CheckDatabaseReady(client))
				{
					ShowAdmiralManageMenu(client, target);
					return 0;
				}
				g_eMenuAction[client] = MENU_ADD_ADMIRAL;
				ShowMenuTimeCount(client);
			}
			case 2:
			{
				if (!Admiral_CheckDatabaseReady(client))
				{
					ShowAdmiralManageMenu(client, target);
					return 0;
				}
				g_eMenuAction[client] = MENU_ADD_TIME;
				ShowMenuTimeCount(client);
			}
			case 3:
			{
				if (!Admiral_CheckDatabaseReady(client))
				{
					ShowAdmiralManageMenu(client, target);
					return 0;
				}
				RemoveAdmiral(target);
				CPrintToChatAll("{green}[Admiral] {olive}%N {default}removed Admiral access from {olive}%N{default}.", client, target);
				LogAction(client, target, "[Admiral] %N removed Admiral access from %N.", client, target);
				ShowOnlineAdmiralManagerMenu(client);
			}
		}
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack) ShowOnlineAdmiralManagerMenu(client);
	else if(action == MenuAction_End) delete menu;
	return 0;
}

void ShowMenuTimeCount(int client)
{
	Menu menu = new Menu(Handle_TimeCountMenu);
	
	if(g_eMenuAction[client] == MENU_ADD_DB_TIME) menu.SetTitle("Adding time for: (%s)\n ", g_sManageDbName[client][0] ? g_sManageDbName[client] : "Database Admiral");
	else
	{
		int target = GetClientOfUserId(g_iMenusTarget[client]);
		if(!target || !IsClientInGame(target))
		{
			CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {default}Player left the game.");
			ShowOnlineAdmiralManagerMenu(client);
			delete menu;
			return;
		}

		if(g_eMenuAction[client] == MENU_ADD_ADMIRAL) menu.SetTitle("Set time for: (%N) \n ", target);
		else if (g_eMenuAction[client] == MENU_ADD_TIME) menu.SetTitle("Adding time for: (%N) \n ", target);
	}
	
	menu.AddItem("3600", "60 Minutes");
	menu.AddItem("86400", "24 Hours");
	menu.AddItem("2592000", "30 Days");
	menu.AddItem("-1", "Permanent");
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_TimeCountMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select)
	{
		char item[32];
		menu.GetItem(select, item, sizeof(item));
		int duration = StringToInt(item);
		
		if (g_eMenuAction[client] == MENU_ADD_DB_TIME)
		{
		    int dbIndex = FindCachedDatabaseAdmiralIndex(g_sManageDbSteamId[client]);
		    if (duration == TIME_FOREVER && dbIndex != -1 && g_DbAdmirals[dbIndex].m_iTimeDuration == TIME_FOREVER)
		    {
		        CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {olive}%s {default}already has permanent access.", g_sManageDbName[client]);
		        return 0;
		    }
		
		    AddTimeToDatabaseAdmiral(client, g_sManageDbSteamId[client], duration);
		    return 0;
		}

		int target = GetClientOfUserId(g_iMenusTarget[client]);
		
		if(!target || !IsClientInGame(target))
		{
			ShowOnlineAdmiralManagerMenu(client);
			CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {default}Player left the game.");
			return 0;
		}

		if (!Admiral_CheckDatabaseReady(client))
		{
			ShowAdmiralManageMenu(client, target);
			return 0;
		}
		
		if(g_eMenuAction[client] == MENU_ADD_ADMIRAL)
		{
			if (!AddAdmiral(target, duration))
			{
				CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {default}Admiral access was not saved because the database is not connected.");
				ShowOnlineAdmiralManagerMenu(client);
				return 0;
			}

			if(duration > 0)
			{
				CPrintToChatAll("{green}[Admiral] {olive}%N {default}gave {lightgreen}%i hours {default}of Admiral access to {olive}%N{default}.", client, duration / 3600, target);
				LogAction(client, target, "[Admiral] %N gave %i hours of Admiral access to %N.", client, duration / 3600, target);
			}
			else
			{
				CPrintToChatAll("{green}[Admiral] {olive}%N {default}gave {olive}permanent {default}Admiral access to {olive}%N{default}.", client, target);
				LogAction(client, target, "[Admiral] %N gave permanent Admiral access to %N.", client, target);
			}
		}
		else if (g_eMenuAction[client] == MENU_ADD_TIME)
		{
			if(IsPlayerAdmiral(target) && CPlayers[target].m_iTimeDuration == TIME_FOREVER) CPrintToChat(client, "{green}[Admiral] {lightgreen}Error: {olive}%N {default}already has permanent access.", target);
			else
			{
				if (!UpdateAdmiral(target, duration))
				{
					CPrintToChat(client, "{green}[Admiral] {red}Error: {default}Admiral time was not saved because the database is not connected.");
					ShowOnlineAdmiralManagerMenu(client);
					return 0;
				}

				if(duration > 0)
				{
					CPrintToChatAll("{green}[Admiral] {olive}%N {default}added {lightgreen}%i hours {default}to {olive}%N{default}.", client, duration / 3600, target);
					LogAction(client, target, "[Admiral] %N added %i hours to %N.", client, duration / 3600, target);
				}
				else
				{
					CPrintToChatAll("{green}[Admiral] {olive}%N {default}gave {olive}permanent {default}Admiral access to {olive}%N{default}.", client, target);
					LogAction(client, target, "[Admiral] %N gave permanent Admiral access to %N.", client, target);
				}
			}
		}
		ShowOnlineAdmiralManagerMenu(client);
	}
	else if(action == MenuAction_Cancel && select == MenuCancel_ExitBack)
	{
		if (g_eMenuAction[client] == MENU_ADD_DB_TIME && g_sManageDbSteamId[client][0]) LoadDatabaseAdmiralDetails(client, g_sManageDbSteamId[client]);
		else ShowOnlineAdmiralManagerMenu(client);
	}
	else if(action == MenuAction_End) delete menu;
	return 0;
}

void GetAdmiralDatabaseActionNames(int client, const char[] steamid, char[] adminName, int adminLen, char[] targetName, int targetLen)
{
	if (IsRealPlayer(client)) GetClientName(client, adminName, adminLen);
	else strcopy(adminName, adminLen, "Console");

	int target = FindClientBySteamID(steamid);
	if (target) GetClientName(target, targetName, targetLen);
	else if (client > 0 && client <= MaxClients && g_sManageDbName[client][0]) strcopy(targetName, targetLen, g_sManageDbName[client]);
	else if (steamid[0]) strcopy(targetName, targetLen, steamid);
	else strcopy(targetName, targetLen, "Unknown");
}

void RemoveDatabaseAdmiral(int client, const char[] steamid)
{
	if (!Admiral_CheckDatabaseReady(client) || steamid[0] == '\0')
	{
		Create_AdmiralManagerMenu(client);
		return;
	}

	if (g_bWriteBusy)
	{
		DataPack retryPack = new DataPack();
		retryPack.WriteCell(GetClientUserId(client));
		retryPack.WriteString(steamid);
		CreateTimer(0.25, Timer_RetryRemoveDatabaseAdmiral, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
		return;
	}

	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(steamid);

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_DataBase SET jointime = 0, duration = 0, timeleft = 0 WHERE steamid = '%s';", steamEsc);
	g_hDatabase.Query(OnDatabaseAdmiralRemoved, g_SQLBuffer, pack);
}

Action Timer_RetryRemoveDatabaseAdmiral(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());

	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));

	if (IsRealPlayer(client)) RemoveDatabaseAdmiral(client, steamid);
	return Plugin_Handled;
}

void OnDatabaseAdmiralRemoved(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int userid = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return;

	char sAdminName[MAX_NAME_LENGTH], sTargetName[MAX_NAME_LENGTH];
	GetAdmiralDatabaseActionNames(client, steamid, sAdminName, sizeof(sAdminName), sTargetName, sizeof(sTargetName));

	if (results == null || error[0] != '\0')
	{
		LogError("Remove database Admiral failed: %s tried to remove %s (%s): %s", sAdminName, sTargetName, steamid, error);
		CPrintToChat(client, "{green}[Admiral] {default}Could not remove Admiral access from {olive}%s{default}.", sTargetName);
		LoadDatabaseAdmiralDetails(client, steamid);
		return;
	}

	int target = FindClientBySteamID(steamid);
	if (target)
	{
		CPlayers[target].m_iJoinTime = 0;
		CPlayers[target].m_iTimeDuration = 0;
		CPlayers[target].m_iTimeLeft = 0;
		g_bDataLoading[target] = false;
		g_bDataLoaded[target] = true;
		ClearActiveAdmiralPrivileges(target);
	}

	CacheAdmiralRemove(steamid);
	CPrintToChat(client, "{green}[Admiral] {olive}%s {default}removed Admiral access from {olive}%s{default}.", sAdminName, sTargetName);
	LogAction(client, -1, "[Admiral] %s removed Admiral access from %s (%s).", sAdminName, sTargetName, steamid);
	ShowCachedDatabaseAdmiralList(client);
}

void AddTimeToDatabaseAdmiral(int client, const char[] steamid, int duration)
{
	if (!Admiral_CheckDatabaseReady(client) || steamid[0] == '\0')
	{
		Create_AdmiralManagerMenu(client);
		return;
	}

	if (g_bWriteBusy)
	{
		DataPack retryPack = new DataPack();
		retryPack.WriteCell(GetClientUserId(client));
		retryPack.WriteString(steamid);
		retryPack.WriteCell(duration);
		CreateTimer(0.25, Timer_RetryAddTimeToDatabaseAdmiral, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
		return;
	}

	char steamEsc[64], nameEsc[256];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));
	EscapeSQLStringSafe(g_sManageDbName[client], nameEsc, sizeof(nameEsc));

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(steamid);
	pack.WriteCell(duration);

	int now = GetTime();

	if (duration == TIME_FOREVER)
	{
		if (StrEqual(g_SQLDriver, MYSQL, false))
		{
			FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
				"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, -1, -1) ON DUPLICATE KEY UPDATE name = VALUES(name), jointime = VALUES(jointime), duration = -1, timeleft = -1;",
				steamEsc, nameEsc, now);
		}
		else
		{
			FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
				"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, -1, -1) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, jointime = excluded.jointime, duration = -1, timeleft = -1;",
				steamEsc, nameEsc, now);
		}
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"UPDATE Admiral_DataBase SET name = '%s', jointime = CASE WHEN duration <= 0 OR (jointime + duration) <= %d THEN %d ELSE jointime END, duration = CASE WHEN duration <= 0 OR (jointime + duration) <= %d THEN %d ELSE duration + %d END, timeleft = CASE WHEN duration <= 0 OR (jointime + duration) <= %d THEN %d ELSE (jointime + duration + %d - %d) END WHERE steamid = '%s' AND duration != -1 AND timeleft != -1;",
			nameEsc, now, now, now, duration, duration, now, duration, duration, now, steamEsc);
	}

	g_hDatabase.Query(OnDatabaseAdmiralTimeAdded, g_SQLBuffer, pack);
}

Action Timer_RetryAddTimeToDatabaseAdmiral(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());

	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	int duration = pack.ReadCell();

	if (IsRealPlayer(client)) AddTimeToDatabaseAdmiral(client, steamid, duration);
	return Plugin_Handled;
}

void OnDatabaseAdmiralTimeAdded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int userid = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	int duration = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return;

	char sAdminName[MAX_NAME_LENGTH], sTargetName[MAX_NAME_LENGTH];
	GetAdmiralDatabaseActionNames(client, steamid, sAdminName, sizeof(sAdminName), sTargetName, sizeof(sTargetName));

	if (results == null || error[0] != '\0')
	{
		LogError("Add database Admiral time failed: %s tried to update %s (%s): %s", sAdminName, sTargetName, steamid, error);
		CPrintToChat(client, "{green}[Admiral] {default}Could not update Admiral time for {olive}%s{default}.", sTargetName);
		LoadDatabaseAdmiralDetails(client, steamid);
		return;
	}

	if (duration != TIME_FOREVER && results.AffectedRows <= 0)
	{
		CPrintToChat(client, "{green}[Admiral] {olive}%s {default}already has permanent Admiral access or no active database row was found.", sTargetName);
		LoadDatabaseAdmiralDetails(client, steamid);
		return;
	}

	int target = FindClientBySteamID(steamid);
	if (target)
	{
		if (duration == TIME_FOREVER)
		{
			CPlayers[target].m_iJoinTime = GetTime();
			CPlayers[target].m_iTimeDuration = TIME_FOREVER;
			CPlayers[target].m_iTimeLeft = TIME_FOREVER;
			g_bDataLoading[target] = false;
			g_bDataLoaded[target] = true;
			g_bPrivCleared[target] = false;
			RestoreActiveAdmiralPrivileges(target);
		}
		else if (CPlayers[target].m_iTimeDuration <= 0 || GetAdmiralTimeLeft(target) <= 0)
		{
			CPlayers[target].m_iJoinTime = GetTime();
			CPlayers[target].m_iTimeDuration = duration;
			CPlayers[target].m_iTimeLeft = duration;
		}
		else if (CPlayers[target].m_iTimeDuration != TIME_FOREVER)
		{
			CPlayers[target].m_iTimeDuration += duration;
			GetAdmiralTimeLeft(target);
		}
	}

	int now = GetTime();
	int index = FindCachedDatabaseAdmiralIndex(steamid);
	int newJoinTime = now;
	int newDuration = duration;
	int newTimeLeft = duration;

	if (duration == TIME_FOREVER)
	{
		newDuration = TIME_FOREVER;
		newTimeLeft = TIME_FOREVER;
	}
	else if (index != -1 && IsCachedDatabaseAdmiralActive(index) && g_DbAdmirals[index].m_iTimeDuration != TIME_FOREVER)
	{
		newJoinTime = g_DbAdmirals[index].m_iJoinTime;
		newDuration = g_DbAdmirals[index].m_iTimeDuration + duration;
		newTimeLeft = newJoinTime + newDuration - now;
	}

	CacheAdmiralUpsert(steamid, sTargetName, newJoinTime, newDuration, newTimeLeft);

	if (duration == TIME_FOREVER)
	{
		CPrintToChat(client, "{green}[Admiral] {olive}%s {default}gave {olive}permanent {default}Admiral access to {olive}%s{default}.", sAdminName, sTargetName);
		LogAction(client, -1, "[Admiral] %s gave permanent Admiral access to %s (%s).", sAdminName, sTargetName, steamid);
	}
	else
	{
		CPrintToChat(client, "{green}[Admiral] {olive}%s {default}added {lightgreen}%i hours {default}to {olive}%s{default}.", sAdminName, duration / 3600, sTargetName);
		LogAction(client, -1, "[Admiral] %s added %i hours to %s (%s).", sAdminName, duration / 3600, sTargetName, steamid);
	}

	ShowCachedDatabaseAdmiralDetails(client, steamid);
}

void RemoveAdmiral(int client)
{
	if (client <= 0 || client > MaxClients) return;

	CPlayers[client].m_iJoinTime = 0;
	CPlayers[client].m_iTimeDuration = 0;
	CPlayers[client].m_iTimeLeft = 0;
	g_iDataRevision[client]++;
	g_bDataLoading[client] = false;
	g_bDataLoaded[client] = true;
	ClearActiveAdmiralPrivileges(client);
	Database_SavePlayerData(client);
	char steamid[32];
	if (Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) CacheAdmiralRemove(steamid);
}

bool AddAdmiral(int client, int duration)
{
	if (!g_hDatabase || !IsRealPlayer(client)) return false;

	CPlayers[client].m_iJoinTime = GetTime();
	CPlayers[client].m_iTimeDuration = duration;
	CPlayers[client].m_iTimeLeft = (duration == TIME_FOREVER) ? TIME_FOREVER : duration;
	g_iDataRevision[client]++;
	g_bDataLoading[client] = false;
	g_bDataLoaded[client] = true;
	g_bPrivCleared[client] = false;
	char steamid[32], name[MAX_NAME_LENGTH];
	if (Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		GetClientName(client, name, sizeof(name));
		SafelyCheckPlayerName(name, sizeof(name));
		strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), name);
		CacheAdmiralUpsert(steamid, name, CPlayers[client].m_iJoinTime, CPlayers[client].m_iTimeDuration, CPlayers[client].m_iTimeLeft);
	}
	Database_SavePlayerData(client);
	RestoreActiveAdmiralPrivileges(client);
	return true;
}

bool UpdateAdmiral(int client, int duration)
{
	if (!g_hDatabase || !IsRealPlayer(client)) return false;

	int now = GetTime();

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER) return false;
	
	if (duration == TIME_FOREVER)
	{
		CPlayers[client].m_iJoinTime = now;
		CPlayers[client].m_iTimeDuration = TIME_FOREVER;
		CPlayers[client].m_iTimeLeft = TIME_FOREVER;
	}
	else if (CPlayers[client].m_iTimeDuration <= 0 || GetAdmiralTimeLeft(client) <= 0)
	{
		CPlayers[client].m_iJoinTime = now;
		CPlayers[client].m_iTimeDuration = duration;
		CPlayers[client].m_iTimeLeft = duration;
	}
	else
	{
		CPlayers[client].m_iTimeDuration += duration;
		CPlayers[client].m_iTimeLeft = CPlayers[client].m_iJoinTime + CPlayers[client].m_iTimeDuration - now;
	}
	
	g_iDataRevision[client]++;
	g_bDataLoading[client] = false;
	g_bDataLoaded[client] = true;
	g_bPrivCleared[client] = false;
	char steamid[32], name[MAX_NAME_LENGTH];
	if (Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		GetClientName(client, name, sizeof(name));
		SafelyCheckPlayerName(name, sizeof(name));
		strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), name);
		CacheAdmiralUpsert(steamid, name, CPlayers[client].m_iJoinTime, CPlayers[client].m_iTimeDuration, CPlayers[client].m_iTimeLeft);
	}
	Database_SavePlayerData(client);
	RestoreActiveAdmiralPrivileges(client);
	return true;
}

Action Command_AdmiralsMenu(int client, int args)
{
	if (!g_bPluginEnable) return Plugin_Handled;

	Menu menu = new Menu(Handle_OnlineAdminsMenu);
	menu.ExitBackButton = (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && (IsPlayerAdmin(client) || IsPlayerAdmiral(client)));

	char buffer[128];
	int count;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;

		bool flag = false;
		Format(buffer, sizeof(buffer), "%N", i);

		if(IsPlayerAdmiral(i))
		{
			StrCat(buffer, sizeof(buffer), " (Admiral)");
			flag = true;
		}

		if(IsPlayerAdmin(i))
		{
			StrCat(buffer, sizeof(buffer), " (Admin)");
			flag = true;
		}

		if(flag)
		{
			++count;
			char sUserID[10];
			int UserID = GetClientUserId(i);
			IntToString(UserID, sUserID, sizeof(sUserID));
			menu.AddItem(sUserID, buffer, ITEMDRAW_DISABLED);
		}
	}

	if (!count) menu.AddItem("", "No Admirals/Admins", ITEMDRAW_DISABLED);
	menu.SetTitle("Online Admirals: (%d) \n ", count);
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

int Handle_OnlineAdminsMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Cancel && select == MenuCancel_ExitBack)
	{
		if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && (IsPlayerAdmin(client) || IsPlayerAdmiral(client)))
			Create_AdmiralMenu(client);
	}
	else if(action == MenuAction_End) delete menu;
	return 0;
}

/* =================================================================================================================== *
 *                                            Reputation: Give Transaction                                             *
 *==================================================================================================================== */

void ClearReputationPending(int client)
{
	if (client > 0 && client <= MaxClients) g_bRepPending[client] = false;
}

void ReputationRollback(Database db)
{
	g_bWriteBusy = false;
	if (db != null) db.Query(OnDatabaseAlterIgnore, "ROLLBACK;");
}

DataPack Reputation_CreatePack(int client, int target, const char[] senderSteam, const char[] receiverSteam)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(GetClientUserId(target));
	pack.WriteString(senderSteam);
	pack.WriteString(receiverSteam);
	return pack;
}

bool Reputation_ReadPack(any data, int &client, int &target, char[] senderSteam, int senderLen, char[] receiverSteam, int receiverLen)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int senderUserid = pack.ReadCell();
	int receiverUserid = pack.ReadCell();
	pack.ReadString(senderSteam, senderLen);
	pack.ReadString(receiverSteam, receiverLen);
	delete pack;

	client = GetClientOfUserId(senderUserid);
	target = GetClientOfUserId(receiverUserid);

	if (!IsRealPlayer(client) || !IsRealPlayer(target))
	{
		ClearReputationPending(client);
		return false;
	}

	char currentSenderSteam[32], currentReceiverSteam[32];
	if (!Admiral_GetClientSteamID(client, currentSenderSteam, sizeof(currentSenderSteam)) || !Admiral_GetClientSteamID(target, currentReceiverSteam, sizeof(currentReceiverSteam)) || !StrEqual(currentSenderSteam, senderSteam) || !StrEqual(currentReceiverSteam, receiverSteam))
	{
		ClearReputationPending(client);
		return false;
	}

	return true;
}

void TryGiveReputation(int client, int target)
{
	if (!IsRealPlayer(client) || !IsRealPlayer(target)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	if (client == target)
	{
		CPrintToChat(client, "{green}[Admiral] {default}You cannot give reputation to yourself.");
		return;
	}

	if (g_bRepPending[client])
	{
		CPrintToChat(client, "{green}[Admiral] {default}Your previous reputation request is still being processed.");
		return;
	}

	char senderSteam[32], receiverSteam[32];
	if (!Admiral_GetClientSteamID(client, senderSteam, sizeof(senderSteam)) || !Admiral_GetClientSteamID(target, receiverSteam, sizeof(receiverSteam)))
	{
		CPrintToChat(client, "{green}[Admiral] {default}Could not verify Steam IDs. Try again later.");
		return;
	}

	g_bRepPending[client] = true;
	CheckReputationEligibility(client, target, senderSteam, receiverSteam);
}

void CheckReputationEligibility(int client, int target, const char[] senderSteam, const char[] receiverSteam)
{
	if (!TryBeginDatabaseWrite(client, "+rep request"))
	{
		ClearReputationPending(client);
		return;
	}

	char query[64];
	strcopy(query, sizeof(query), StrEqual(g_SQLDriver, MYSQL, false) ? "START TRANSACTION;" : "BEGIN IMMEDIATE TRANSACTION;");

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);
	g_hDatabase.Query(OnReputationTransactionStarted, query, pack);
}

void OnReputationTransactionStarted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam)))
	{
		ReputationRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		FinishDatabaseWrite();
		LogError("Reputation transaction start failed (%s)", error);
		CPrintToChat(client, "{green}[Admiral] {default}Could not send reputation right now.");
		ClearReputationPending(client);
		return;
	}

	char senderEsc[64], receiverEsc[64];
	EscapeSQLStringSafe(senderSteam, senderEsc, sizeof(senderEsc));
	EscapeSQLStringSafe(receiverSteam, receiverEsc, sizeof(receiverEsc));

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);
	int dayStart = GetTime() - 86400;

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
		"SELECT COALESCE(MAX(CASE WHEN receiver = '%s' THEN timestamp ELSE 0 END), 0), COALESCE(SUM(CASE WHEN timestamp >= %d THEN 1 ELSE 0 END), 0) FROM Admiral_Rep_Log WHERE sender = '%s';",
		receiverEsc, dayStart, senderEsc);

	g_hDatabase.Query(OnReputationEligibilityLoaded, g_SQLBuffer, pack);
}

void OnReputationEligibilityLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam)))
	{
		ReputationRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation eligibility query failed (%s)", error);
		ReputationRollback(db);
		CPrintToChat(client, "{green}[Admiral] {default}Could not send reputation right now.");
		ClearReputationPending(client);
		return;
	}

	int lastSameTargetTime;
	int sentLast24Hours;
	if (results.FetchRow())
	{
		lastSameTargetTime = results.FetchInt(0);
		sentLast24Hours = results.FetchInt(1);
	}

	if (g_iRepDailyLimit > 0 && sentLast24Hours >= g_iRepDailyLimit)
	{
		ReputationRollback(db);
		CPrintToChat(client, "{green}[Admiral] {default}You reached your daily +rep limit ({lightgreen}%d{default} per 24 hours).", g_iRepDailyLimit);
		ClearReputationPending(client);
		return;
	}

	if (g_iRepCooldown > 0 && lastSameTargetTime > 0)
	{
		int cooldownSeconds = g_iRepCooldown * 86400;
		int elapsed = GetTime() - lastSameTargetTime;

		if (elapsed < cooldownSeconds)
		{
			int remaining = cooldownSeconds - elapsed;
			int days = RoundToCeil(float(remaining) / 86400.0);
			ReputationRollback(db);
			CPrintToChat(client, "{green}[Admiral] {default}You already gave +rep to {olive}%N{default}. Try again in {lightgreen}%d day%s{default}.", target, days, days == 1 ? "" : "s");
			ClearReputationPending(client);
			return;
		}
	}

	InsertReputationLog(client, target, senderSteam, receiverSteam);
}

void InsertReputationLog(int client, int target, const char[] senderSteam, const char[] receiverSteam)
{
	char senderNameEsc[256], receiverNameEsc[256], senderEsc[64], receiverEsc[64];

	GetSafeEscapedClientName(client, senderNameEsc, sizeof(senderNameEsc));
	GetSafeEscapedClientName(target, receiverNameEsc, sizeof(receiverNameEsc));
	EscapeSQLStringSafe(senderSteam, senderEsc, sizeof(senderEsc));
	EscapeSQLStringSafe(receiverSteam, receiverEsc, sizeof(receiverEsc));

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
		"INSERT INTO Admiral_Rep_Log(sender, receiver, sender_name, receiver_name, timestamp) VALUES('%s', '%s', '%s', '%s', %d);",
		senderEsc, receiverEsc, senderNameEsc, receiverNameEsc, GetTime());

	g_hDatabase.Query(OnReputationLogInserted, g_SQLBuffer, pack);
}

void OnReputationLogInserted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam)))
	{
		ReputationRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation log insert failed (%s)", error);
		ReputationRollback(db);
		CPrintToChat(client, "{green}[Admiral] {default}Could not save your reputation right now.");
		ClearReputationPending(client);
		return;
	}

	IncrementReputationTotal(client, target, senderSteam, receiverSteam);
}

void IncrementReputationTotal(int client, int target, const char[] senderSteam, const char[] receiverSteam)
{
	char receiverNameEsc[256], receiverEsc[64];

	GetSafeEscapedClientName(target, receiverNameEsc, sizeof(receiverNameEsc));
	EscapeSQLStringSafe(receiverSteam, receiverEsc, sizeof(receiverEsc));

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Rep_Total(steamid, name, current_rep, lifetime_rep) VALUES('%s', '%s', 1, 1) ON DUPLICATE KEY UPDATE name = VALUES(name), current_rep = current_rep + 1, lifetime_rep = lifetime_rep + 1;",
			receiverEsc, receiverNameEsc);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Rep_Total(steamid, name, current_rep, lifetime_rep) VALUES('%s', '%s', 1, 1) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, current_rep = current_rep + 1, lifetime_rep = lifetime_rep + 1;",
			receiverEsc, receiverNameEsc);
	}

	g_hDatabase.Query(OnReputationTotalIncremented, g_SQLBuffer, pack);
}

void OnReputationTotalIncremented(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam)))
	{
		ReputationRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation total increment failed (%s)", error);
		ReputationRollback(db);
		CPrintToChat(client, "{green}[Admiral] {default}Could not send reputation right now.");
		ClearReputationPending(client);
		return;
	}

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);
	g_hDatabase.Query(OnReputationCommitted, "COMMIT;", pack);
}

void OnReputationCommitted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam)))
	{
		ReputationRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation commit failed (%s)", error);
		ReputationRollback(db);
		CPrintToChat(client, "{green}[Admiral] {default}Could not send reputation right now.");
		ClearReputationPending(client);
		return;
	}

	FinishDatabaseWrite();

	if (g_bTotalRepLoaded[target])
	{
		CPlayers[target].m_iCurrentRep++;
		CPlayers[target].m_iTotalRep++;
		AnnounceReputationGiven(client, target, CPlayers[target].m_iTotalRep);
		ClearReputationPending(client);
		return;
	}

	char receiverEsc[64];
	EscapeSQLStringSafe(receiverSteam, receiverEsc, sizeof(receiverEsc));

	DataPack pack = Reputation_CreatePack(client, target, senderSteam, receiverSteam);
	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT COALESCE(current_rep, 0), COALESCE(lifetime_rep, current_rep, 0) FROM Admiral_Rep_Total WHERE steamid = '%s' LIMIT 1;", receiverEsc);
	g_hDatabase.Query(OnReputationTotalNotifyAll, g_SQLBuffer, pack);
}

void AnnounceReputationGiven(int client, int target, int total)
{
	g_bTotalRepLoaded[target] = true;
	PrintHintText(client, "+Rep Submitted");
	CPrintToChatAll("{green}[Admiral] {olive}%N {default}received {lightgreen}+rep{default}. Total reputation: {lightgreen}%d{default}.", target, total);
}

void OnReputationTotalNotifyAll(Database db, DBResultSet results, const char[] error, any data)
{
	int client, target;
	char senderSteam[32], receiverSteam[32];
	if (!Reputation_ReadPack(data, client, target, senderSteam, sizeof(senderSteam), receiverSteam, sizeof(receiverSteam))) return;

	int current = 0;
	int total = 0;
	if (results != null && error[0] == '\0' && results.FetchRow())
	{
		current = results.FetchInt(0);
		total = results.FetchInt(1);
	}

	CPlayers[target].m_iCurrentRep = current;
	CPlayers[target].m_iTotalRep = total;
	AnnounceReputationGiven(client, target, total);
	ClearReputationPending(client);
}

/* =================================================================================================================== *
 *                                      Reputation: Menus, History & Leaderboard                               	       *
 *==================================================================================================================== */

void LoadClientTotalReputation(int client)
{
	if (!g_hDatabase || !g_bSchemaReady || !IsRealPlayer(client)) return;
	if (g_bTotalRepLoading[client]) return;

	char steamid[32], steamEsc[64];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	g_bTotalRepLoading[client] = true;

	DataPack pack = Client_CreatePack(client, steamid);
	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT COALESCE(current_rep, 0), COALESCE(lifetime_rep, current_rep, 0) FROM Admiral_Rep_Total WHERE steamid = '%s' LIMIT 1;", steamEsc);
	g_hDatabase.Query(OnClientTotalReputationLoaded, g_SQLBuffer, pack);
}

void OnClientTotalReputationLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;
	g_bTotalRepLoading[client] = false;

	if (results == null || error[0] != '\0')
	{
		LogError("Total reputation query failed (%s)", error);
		return;
	}

	CPlayers[client].m_iCurrentRep = 0;
	CPlayers[client].m_iTotalRep = 0;
	if (results.FetchRow())
	{
		CPlayers[client].m_iCurrentRep = results.FetchInt(0);
		CPlayers[client].m_iTotalRep = results.FetchInt(1);
	}
	g_bTotalRepLoaded[client] = true;

	if (g_bOpenTagMenuAfterRepLoad[client])
	{
		g_bOpenTagMenuAfterRepLoad[client] = false;
		Create_AdmiralTagMenu(client);
	}
}

void ShowReputationEarnMenu(int client)
{
	char sValue[128];
	
	Menu menu = new Menu(Handle_ReputationInfoMenu);
	menu.SetTitle("How to Earn Reputation: \n ", ITEMDRAW_DEFAULT);
	g_KeyValue.Rewind();
	
	if (!g_KeyValue.JumpToKey("How to Earn Reputation"))
	{
		LogError("Missing 'How to Earn Reputation' section in %s", g_sData_Path);
		menu.AddItem("empty", "No information provided", ITEMDRAW_DISABLED);
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
		return;
	}
	
	if(g_KeyValue.GotoFirstSubKey(false))
	{
		do
		{
			g_KeyValue.GetString(NULL_STRING, sValue, sizeof(sValue));
			menu.AddItem("", sValue, ITEMDRAW_DISABLED);
			
		}
		while(g_KeyValue.GotoNextKey(false));
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_ReputationInfoMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) LoadMyReputationMenu(client);
	else if (action == MenuAction_End) delete menu;
	return 0;
}

Action Command_ReputationMenu(int client, int args)
{
	if (!g_bPluginEnable) return Plugin_Handled;
	if (!IsRealPlayer(client)) return Plugin_Handled;

	if (args == 0)
	{
		ShowReputationMenu(client);
		return Plugin_Handled;
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	int target = FindTarget(client, arg, true, false);

	if (target == -1) return Plugin_Handled;
	else TryGiveReputation(client, target);

	return Plugin_Handled;
}

void ShowReputationMenu(int client)
{
	Menu menu = new Menu(Handle_ReputationMenu);
	menu.SetTitle("Give +Rep To:\n ");

	char info[16], text[96];
	bool hasPlayers = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsRealPlayer(i)) continue;

		hasPlayers = true;

		IntToString(GetClientUserId(i), info, sizeof(info));
		FormatEx(text, sizeof(text), "%N", i);
		menu.AddItem(info, text);
	}

	if (!hasPlayers) menu.AddItem("", "No players available", ITEMDRAW_DISABLED);

	menu.ExitBackButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_ReputationMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char item[16];
		menu.GetItem(select, item, sizeof(item));
		TryGiveReputation(client, GetClientOfUserId(StringToInt(item)));
	}
	else if (action == MenuAction_End) delete menu;
	return 0;
}

Action Command_MyReputation(int client, int args)
{
	if (!g_bPluginEnable) return Plugin_Handled;
	if (!IsRealPlayer(client)) return Plugin_Handled;
	if (!Admiral_CheckDatabaseReady(client)) return Plugin_Handled;

	LoadMyReputationMenu(client);
	return Plugin_Handled;
}

void LoadMyReputationMenu(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	if (!g_bTotalRepLoaded[client] && !g_bTotalRepLoading[client]) LoadClientTotalReputation(client);
	ShowMyReputationMenu(client, CPlayers[client].m_iCurrentRep, CPlayers[client].m_iTotalRep);
}

void ShowMyReputationMenu(int client, int balance, int totalReceived)
{
	char sTimeleft[64], sChallenege[32], sTitle[256];

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER) strcopy(sTimeleft, sizeof(sTimeleft), "Permanent Access");
	else if (IsPlayerAdmiral(client)) FormatAdmiralTimeShort(GetAdmiralTimeLeft(client), sTimeleft, sizeof(sTimeleft));
	else strcopy(sTimeleft, sizeof(sTimeleft), "Expired Access");
	
	if (g_bChallengeCompletedToday[client]) strcopy(sChallenege, sizeof(sChallenege), "Complete");
	else strcopy(sChallenege, sizeof(sChallenege), "In Progress");

	FormatEx(sTitle, sizeof(sTitle), "%N | %s\nReputation: %d (Lifetime: %d)\nDaily Challenge: %s\n ", client, sTimeleft, balance, totalReceived, sChallenege);

	Menu menu = new Menu(Handle_MyReputationMenu);
	menu.SetTitle(sTitle);

	menu.AddItem("challenge", "Daily Challenge");
	menu.AddItem("redeem", "Redeem Admiral Time");
	menu.AddItem("earn", "How to Earn Reputation");
	menu.AddItem("history", "My Redeem History");
	menu.AddItem("players", "Online Reputation");
	menu.AddItem("leaderboard", "Leaderboard");

	menu.ExitBackButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_MyReputationMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char item[32];
		menu.GetItem(select, item, sizeof(item));
		
		if (StrEqual(item, "challenge")) LoadDailyChallengeMenu(client);
		else if (StrEqual(item, "redeem")) LoadReputationRedeemMenu(client);
		else if (StrEqual(item, "earn")) ShowReputationEarnMenu(client);
		else if (StrEqual(item, "history")) LoadReputationRedeemHistory(client);
		else if (StrEqual(item, "players")) LoadPlayersReputationMenu(client);
		else if (StrEqual(item, "leaderboard")) LoadReputationLeaderboardMenu(client);
	}
	else if (action == MenuAction_End) delete menu;
	return 0;
}

void LoadPlayersReputationMenu(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsRealPlayer(i)) continue;
		if (!g_bTotalRepLoaded[i] && !g_bTotalRepLoading[i]) LoadClientTotalReputation(i);
	}

	ShowPlayersReputationMenu(client);
}

void ShowPlayersReputationMenu(int client)
{
	Menu menu = new Menu(Handle_ReputationInfoMenu);
	menu.SetTitle("Online Reputation:\n ");

	char text[128];
	bool hasPlayers;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsRealPlayer(i)) continue;

		hasPlayers = true;
		if (g_bTotalRepLoaded[i]) FormatEx(text, sizeof(text), "%N: %d", i, CPlayers[i].m_iTotalRep);
		else FormatEx(text, sizeof(text), "%N: Loading...", i);

		menu.AddItem("player", text, ITEMDRAW_DISABLED);
	}

	if (!hasPlayers) menu.AddItem("empty", "No players online", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void LoadReputationLeaderboardMenu(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;

	DataPack pack = Client_CreatePack(client, steamid);
	strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT name, steamid, COALESCE(lifetime_rep, current_rep, 0) AS total_rep FROM Admiral_Rep_Total WHERE COALESCE(lifetime_rep, current_rep, 0) >= 1 ORDER BY total_rep DESC, name ASC LIMIT 100;");
	g_hDatabase.Query(OnReputationLeaderboardLoaded, g_SQLBuffer, pack);
}

void OnReputationLeaderboardLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();

	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));

	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;

	Menu menu = new Menu(Handle_ReputationInfoMenu);
	menu.SetTitle("Reputation Leaderboard:\n ");

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation leaderboard query failed (%s)", error);
		menu.AddItem("empty", "No players found", ITEMDRAW_DISABLED);
	}
	else
	{
		char name[MAX_NAME_LENGTH], playerSteam[32], text[160];

		int count = 0;

		while (results.FetchRow())
		{
			results.FetchString(0, name, sizeof(name));
			results.FetchString(1, playerSteam, sizeof(playerSteam));

			int total = results.FetchInt(2);
			if (total < 1) continue;

			if (name[0] == '\0') strcopy(name, sizeof(name), playerSteam);

			count++;
			FormatEx(text, sizeof(text), "%s - %d Rep", name, total);
			menu.AddItem("player", text, ITEMDRAW_DISABLED);
		}

		if (count <= 0) menu.AddItem("empty", "No players found", ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void ResetClientReputationHistory(int client)
{
	if (client <= 0 || client > MaxClients) return;

	CPlayers[client].m_iRepHistCount = 0;
	g_bRepHistoryLoaded[client] = false;
	g_bRepHistoryLoading[client] = false;
	g_bOpenRepHistoryAfterLoad[client] = false;

	for (int i = 0; i < HISTORY_LIMIT; i++)
	{
		CPlayers[client].m_iRepHistCost[i] = 0;
		CPlayers[client].m_iRepHistHours[i] = 0;
		CPlayers[client].m_iRepHistTime[i] = 0;
	}
}

void AddClientReputationHistoryCache(int client, int cost, int hours, int timestamp)
{
	if (client <= 0 || client > MaxClients) return;

	int limit = CPlayers[client].m_iRepHistCount;
	if (limit >= HISTORY_LIMIT) limit = HISTORY_LIMIT - 1;

	for (int i = limit; i > 0; i--)
	{
		CPlayers[client].m_iRepHistCost[i] = CPlayers[client].m_iRepHistCost[i - 1];
		CPlayers[client].m_iRepHistHours[i] = CPlayers[client].m_iRepHistHours[i - 1];
		CPlayers[client].m_iRepHistTime[i] = CPlayers[client].m_iRepHistTime[i - 1];
	}

	CPlayers[client].m_iRepHistCost[0] = cost;
	CPlayers[client].m_iRepHistHours[0] = hours;
	CPlayers[client].m_iRepHistTime[0] = timestamp;

	if (CPlayers[client].m_iRepHistCount < HISTORY_LIMIT) CPlayers[client].m_iRepHistCount++;
	g_bRepHistoryLoaded[client] = true;
}

void LoadClientReputationRedeemHistory(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!g_hDatabase || !g_bSchemaReady) return;
	if (g_bRepHistoryLoaded[client]) return;
	if (g_bRepHistoryLoading[client]) return;

	char steamid[32], steamEsc[64];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	g_bRepHistoryLoading[client] = true;

	DataPack pack = Client_CreatePack(client, steamid);
	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT cost, hours, timestamp FROM Admiral_Rep_Redeem_Log WHERE steamid = '%s' ORDER BY timestamp DESC LIMIT %d;", steamEsc, HISTORY_LIMIT);
	g_hDatabase.Query(OnReputationRedeemHistoryLoaded, g_SQLBuffer, pack);
}

void LoadReputationRedeemHistory(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	if (g_bRepHistoryLoaded[client])
	{
		ShowCachedReputationRedeemHistory(client);
		return;
	}

	g_bOpenRepHistoryAfterLoad[client] = true;
	LoadClientReputationRedeemHistory(client);
}

void OnReputationRedeemHistoryLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;

	g_bRepHistoryLoading[client] = false;
	CPlayers[client].m_iRepHistCount = 0;

	if (results == null || error[0] != '\0')
	{
		LogError("Reputation redeem history query failed (%s)", error);
		g_bRepHistoryLoaded[client] = true;

		if (g_bOpenRepHistoryAfterLoad[client])
		{
			g_bOpenRepHistoryAfterLoad[client] = false;
			ShowCachedReputationRedeemHistory(client);
		}
		return;
	}

	while (results.FetchRow() && CPlayers[client].m_iRepHistCount < HISTORY_LIMIT)
	{
		int index = CPlayers[client].m_iRepHistCount;
		CPlayers[client].m_iRepHistCost[index] = results.FetchInt(0);
		CPlayers[client].m_iRepHistHours[index] = results.FetchInt(1);
		CPlayers[client].m_iRepHistTime[index] = results.FetchInt(2);
		CPlayers[client].m_iRepHistCount++;
	}

	g_bRepHistoryLoaded[client] = true;

	if (g_bOpenRepHistoryAfterLoad[client])
	{
		g_bOpenRepHistoryAfterLoad[client] = false;
		ShowCachedReputationRedeemHistory(client);
	}
}

void ShowCachedReputationRedeemHistory(int client)
{
	if (!g_bRepHistoryLoaded[client])
	{
		g_bOpenRepHistoryAfterLoad[client] = true;
		LoadClientReputationRedeemHistory(client);
		return;
	}

	Menu menu = new Menu(Handle_ReputationInfoMenu);
	menu.SetTitle("My Redeem History:\n ");

	if (CPlayers[client].m_iRepHistCount <= 0) menu.AddItem("empty", "No redeem history yet", ITEMDRAW_DISABLED);
	else
	{
		char date[64], text[128];

		for (int i = 0; i < CPlayers[client].m_iRepHistCount; i++)
		{
			int cost = CPlayers[client].m_iRepHistCost[i];
			int hours = CPlayers[client].m_iRepHistHours[i];
			int timestamp = CPlayers[client].m_iRepHistTime[i];

			FormatTime(date, sizeof(date), "%d/%m/%Y - %H:%M", timestamp);
			if (hours == TIME_FOREVER) FormatEx(text, sizeof(text), "%d Lifetime Reputation: Permanent Admiral - %s", cost, date);
			else FormatEx(text, sizeof(text), "%d Reputation: %d Day%s - %s", cost, hours / 24, (hours / 24) == 1 ? "" : "s", date);
			menu.AddItem("history", text, ITEMDRAW_DISABLED);
		}
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

/* =================================================================================================================== *
 *                                           Reputation Redeem Transaction                                        	   *
 *==================================================================================================================== */

bool ParseRedeemTierAtCurrentKey(int &cost, int &hours, char[] display, int displayLen)
{
	cost = g_KeyValue.GetNum("cost", 0);
	hours = g_KeyValue.GetNum("hours", 0);

	display[0] = '\0';
	g_KeyValue.GetString("display", display, displayLen, "");

	if (cost <= 0 || (hours <= 0 && hours != TIME_FOREVER)) return false;

	if (display[0] == '\0')
	{
		if (hours == TIME_FOREVER) strcopy(display, displayLen, "Permanent Admiral");
		else
		{
			int days = hours / 24;
			if (days > 0 && hours % 24 == 0) FormatEx(display, displayLen, "%d Day%s Admiral", days, days == 1 ? "" : "s");
			else FormatEx(display, displayLen, "%d Hour%s Admiral", hours, hours == 1 ? "" : "s");
		}
	}

	return true;
}

bool ResolveRedeemTierFromItem(const char[] item, int &cost, int &hours)
{
	char display[96];

	if (strncmp(item, "cfg:", 4) != 0) return false;

	bool found = false;
	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Reputation Redeem") && g_KeyValue.JumpToKey(item[4]))
	{
		found = ParseRedeemTierAtCurrentKey(cost, hours, display, sizeof(display));
	}
	g_KeyValue.Rewind();

	return found;
}

void LoadReputationRedeemMenu(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	if (!g_bTotalRepLoaded[client] && !g_bTotalRepLoading[client]) LoadClientTotalReputation(client);
	ShowReputationRedeemMenu(client, CPlayers[client].m_iCurrentRep, CPlayers[client].m_iTotalRep);
}

void AddRedeemTierMenuItem(Menu menu, const char[] item, int cost, int hours, const char[] display, int balance, int totalReceived)
{
	char text[128];

	if (hours == TIME_FOREVER)
	{
		FormatEx(text, sizeof(text), "%d Lifetime: %s", cost, display);
		menu.AddItem(item, text, totalReceived >= cost ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	else
	{
		FormatEx(text, sizeof(text), "%d Reputation: %s", cost, display);
		menu.AddItem(item, text, balance >= cost ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
}

void ShowReputationRedeemMenu(int client, int balance, int totalReceived)
{
	Menu menu = new Menu(Handle_ReputationRedeemMenu);
	menu.SetTitle("Available Reputation: %d\nLifetime Reputation: %d\n ", balance, totalReceived);

	char key[64], item[72], display[96];
	int cost, hours, count = 0;

	g_KeyValue.Rewind();
	if (g_KeyValue.JumpToKey("Reputation Redeem") && g_KeyValue.GotoFirstSubKey(false))
	{
		do
		{
			if (!g_KeyValue.GetSectionName(key, sizeof(key))) continue;
			if (!ParseRedeemTierAtCurrentKey(cost, hours, display, sizeof(display))) continue;

			FormatEx(item, sizeof(item), "cfg:%s", key);
			AddRedeemTierMenuItem(menu, item, cost, hours, display, balance, totalReceived);
			count++;
		}
		while (g_KeyValue.GotoNextKey(false));
	}
	g_KeyValue.Rewind();

	if (count <= 0) menu.AddItem("empty", "No reputation rewards configured", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handle_ReputationRedeemMenu(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select)
	{
		char item[72];
		menu.GetItem(select, item, sizeof(item));

		if (!StrEqual(item, "empty"))
			TryRedeemReputation(client, item);
	}
	else if (action == MenuAction_Cancel && select == MenuCancel_ExitBack) LoadMyReputationMenu(client);
	else if (action == MenuAction_End) delete menu;
	return 0;
}

void TryRedeemReputation(int client, const char[] item)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	int cost, hours;
	if (!ResolveRedeemTierFromItem(item, cost, hours)) return;

	if (g_bRedeemPending[client])
	{
		CPrintToChat(client, "{green}[Admiral] {default}Your previous redeem request is still being processed.");
		return;
	}

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER)
	{
		CPrintToChat(client, "{green}[Admiral] {default}You already have permanent Admiral access. Your reputation was not deducted.");
		return;
	}

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		CPrintToChat(client, "{green}[Admiral] {default}Could not verify your Steam ID. Try again later.");
		return;
	}

	if (!g_bTotalRepLoaded[client] && !g_bTotalRepLoading[client])
		LoadClientTotalReputation(client);

	if (hours == TIME_FOREVER)
	{
		if (CPlayers[client].m_iTotalRep < cost)
		{
			CPrintToChat(client, "{green}[Admiral] {default}You need {lightgreen}%d{default} lifetime reputation for permanent Admiral. You currently have {olive}%d{default}.", cost, CPlayers[client].m_iTotalRep);
			return;
		}
	}
	else if (CPlayers[client].m_iCurrentRep < cost)
	{
		CPrintToChat(client, "{green}[Admiral] {default}You need {lightgreen}%d{default} available reputation for this reward. You currently have {olive}%d{default}.", cost, CPlayers[client].m_iCurrentRep);
		return;
	}

	g_bRedeemPending[client] = true;
	StartRedeemTransaction(client, steamid, cost, hours);
}

DataPack Redeem_CreatePack(int client, const char[] steamid, int cost, int hours, int balance = 0, int lifetime = 0, bool hasRow = false, int joinTime = 0, int duration = 0, int newJoinTime = 0, int newDuration = 0, int newTimeLeft = 0, int newTotal = 0)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(steamid);
	pack.WriteCell(cost);
	pack.WriteCell(hours);
	pack.WriteCell(balance);
	pack.WriteCell(lifetime);
	pack.WriteCell(hasRow ? 1 : 0);
	pack.WriteCell(joinTime);
	pack.WriteCell(duration);
	pack.WriteCell(newJoinTime);
	pack.WriteCell(newDuration);
	pack.WriteCell(newTimeLeft);
	pack.WriteCell(newTotal);
	return pack;
}

bool Redeem_ReadPack(any data, int &client, char[] steamid, int steamLen, int &cost, int &hours, int &balance, int &lifetime, bool &hasRow, int &joinTime, int &duration, int &newJoinTime, int &newDuration, int &newTimeLeft, int &newTotal)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	pack.ReadString(steamid, steamLen);
	cost = pack.ReadCell();
	hours = pack.ReadCell();
	balance = pack.ReadCell();
	lifetime = pack.ReadCell();
	hasRow = pack.ReadCell() != 0;
	joinTime = pack.ReadCell();
	duration = pack.ReadCell();
	newJoinTime = pack.ReadCell();
	newDuration = pack.ReadCell();
	newTimeLeft = pack.ReadCell();
	newTotal = pack.ReadCell();
	delete pack;

	return Admiral_ValidateCallbackClient(userid, steamid, client);
}

void StartRedeemTransaction(int client, const char[] steamid, int cost, int hours)
{
	if (!TryBeginDatabaseWrite(client, "redeem request"))
	{
		ClearRedeemPending(client);
		return;
	}

	char query[64];
	strcopy(query, sizeof(query), StrEqual(g_SQLDriver, MYSQL, false) ? "START TRANSACTION;" : "BEGIN IMMEDIATE TRANSACTION;");

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours);
	g_hDatabase.Query(OnRedeemTransactionStarted, query, pack);
}

void RedeemRollback(Database db)
{
	FinishDatabaseWrite();
	if (db != null) db.Query(OnDatabaseAlterIgnore, "ROLLBACK;");
}

void FinishRedeemFailure(int client, int result)
{
	switch (result)
	{
		case REDEEM_RESULT_NO_BALANCE:
		{
			CPrintToChat(client, "{green}[Admiral] {default}Your reputation balance changed before redeeming. Nothing was deducted. Please try again.");
			LoadClientTotalReputation(client);
		}
		case REDEEM_RESULT_PERMANENT:
		{
			CPrintToChat(client, "{green}[Admiral] {default}You already have permanent Admiral access. Your reputation was not deducted.");
		}
		default:
		{
			CPrintToChat(client, "{green}[Admiral] {default}Redeem failed safely. Nothing was deducted. Please try again later.");
			LoadClientTotalReputation(client);
		}
	}

	ClearRedeemPending(client);
}

void OnRedeemTransactionStarted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		FinishDatabaseWrite();
		LogError("Redeem transaction start failed (%s)", error);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	if (StrEqual(g_SQLDriver, MYSQL, false)) FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT current_rep, lifetime_rep FROM Admiral_Rep_Total WHERE steamid = '%s' LIMIT 1 FOR UPDATE;", steamEsc);
	else FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT current_rep, lifetime_rep FROM Admiral_Rep_Total WHERE steamid = '%s' LIMIT 1;", steamEsc);

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours);
	g_hDatabase.Query(OnRedeemBalanceLoaded, g_SQLBuffer, pack);
}

void OnRedeemBalanceLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Redeem balance query failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	if (results.FetchRow())
	{
		balance = results.FetchInt(0);
		lifetime = results.FetchInt(1);
	}

	if ((hours == TIME_FOREVER && lifetime < cost) || (hours != TIME_FOREVER && balance < cost))
	{
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_NO_BALANCE);
		return;
	}

	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	if (StrEqual(g_SQLDriver, MYSQL, false)) FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT jointime, duration, timeleft FROM Admiral_DataBase WHERE steamid = '%s' LIMIT 1 FOR UPDATE;", steamEsc);
	else FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT jointime, duration, timeleft FROM Admiral_DataBase WHERE steamid = '%s' LIMIT 1;", steamEsc);

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours, balance, lifetime);
	g_hDatabase.Query(OnRedeemAdmiralLoaded, g_SQLBuffer, pack);
}

void OnRedeemAdmiralLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, timeLeft, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Redeem Admiral query failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	hasRow = results.FetchRow();
	if (hasRow)
	{
		joinTime = results.FetchInt(0);
		duration = results.FetchInt(1);
		timeLeft = results.FetchInt(2);
		NormalizeAdmiralAccessData(joinTime, duration, timeLeft);
	}

	int now = GetTime();
	if (g_bDataLoaded[client])
	{
		if (CPlayers[client].m_iTimeDuration == TIME_FOREVER)
		{
			RedeemRollback(db);
			FinishRedeemFailure(client, REDEEM_RESULT_PERMANENT);
			return;
		}

		int dbRemaining = (hasRow && duration > 0) ? (joinTime + duration - now) : 0;
		int liveRemaining = (CPlayers[client].m_iTimeDuration > 0) ? (CPlayers[client].m_iJoinTime + CPlayers[client].m_iTimeDuration - now) : 0;
		if (liveRemaining > dbRemaining)
		{
			hasRow = true;
			joinTime = CPlayers[client].m_iJoinTime;
			duration = CPlayers[client].m_iTimeDuration;
		}
	}

	if (duration == TIME_FOREVER)
	{
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_PERMANENT);
		return;
	}

	if (hours == TIME_FOREVER)
	{
		newJoinTime = now;
		newDuration = TIME_FOREVER;
		newTimeLeft = TIME_FOREVER;
	}
	else
	{
		int addSeconds = hours * 3600;
		if (!hasRow || duration <= 0 || (joinTime + duration) <= now)
		{
			newJoinTime = now;
			newDuration = addSeconds;
			newTimeLeft = addSeconds;
		}
		else
		{
			newJoinTime = joinTime;
			newDuration = duration + addSeconds;
			newTimeLeft = joinTime + newDuration - now;
		}
	}

	newTotal = (hours == TIME_FOREVER) ? balance : balance - cost;

	char steamEsc[64], nameEsc[256];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));
	GetSafeEscapedClientName(client, nameEsc, sizeof(nameEsc));

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name = VALUES(name), jointime = VALUES(jointime), duration = VALUES(duration), timeleft = VALUES(timeleft);",
			steamEsc, nameEsc, newJoinTime, newDuration, newTimeLeft);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, jointime = excluded.jointime, duration = excluded.duration, timeleft = excluded.timeleft;",
			steamEsc, nameEsc, newJoinTime, newDuration, newTimeLeft);
	}

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
	g_hDatabase.Query(OnRedeemAdmiralUpdated, g_SQLBuffer, pack);
}

void OnRedeemAdmiralUpdated(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Redeem Admiral update failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	if (hours == TIME_FOREVER)
	{
		InsertRedeemLog(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
		return;
	}

	char steamEsc[64], nameEsc[256];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));
	GetSafeEscapedClientName(client, nameEsc, sizeof(nameEsc));

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_Rep_Total SET name = '%s', current_rep = current_rep - %d WHERE steamid = '%s' AND current_rep >= %d;", nameEsc, cost, steamEsc, cost);

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
	g_hDatabase.Query(OnRedeemReputationDeducted, g_SQLBuffer, pack);
}

void OnRedeemReputationDeducted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0' || results.AffectedRows <= 0)
	{
		if (error[0] != '\0') LogError("Redeem reputation deduct failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_NO_BALANCE);
		return;
	}

	InsertRedeemLog(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
}

void InsertRedeemLog(int client, const char[] steamid, int cost, int hours, int balance, int lifetime, bool hasRow, int joinTime, int duration, int newJoinTime, int newDuration, int newTimeLeft, int newTotal)
{
	char steamEsc[64], nameEsc[256];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));
	GetSafeEscapedClientName(client, nameEsc, sizeof(nameEsc));

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "INSERT INTO Admiral_Rep_Redeem_Log(steamid, name, cost, hours, timestamp) VALUES('%s', '%s', %d, %d, %d);", steamEsc, nameEsc, cost, hours, GetTime());

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
	g_hDatabase.Query(OnRedeemLogInserted, g_SQLBuffer, pack);
}

void OnRedeemLogInserted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		RedeemRollback(db);
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Redeem log insert failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	DataPack pack = Redeem_CreatePack(client, steamid, cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal);
	g_hDatabase.Query(OnRedeemCommitted, "COMMIT;", pack);
}

void OnRedeemCommitted(Database db, DBResultSet results, const char[] error, any data)
{
	int client, cost, hours, balance, lifetime, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal;
	bool hasRow;
	char steamid[32];
	if (!Redeem_ReadPack(data, client, steamid, sizeof(steamid), cost, hours, balance, lifetime, hasRow, joinTime, duration, newJoinTime, newDuration, newTimeLeft, newTotal))
	{
		FinishDatabaseWrite();
		return;
	}

	if (results == null || error[0] != '\0')
	{
		LogError("Redeem commit failed (%s)", error);
		RedeemRollback(db);
		FinishRedeemFailure(client, REDEEM_RESULT_DB_ERROR);
		return;
	}

	FinishDatabaseWrite();

	char name[MAX_NAME_LENGTH];
	GetSafeClientName(client, name, sizeof(name));

	CPlayers[client].m_iJoinTime = newJoinTime;
	CPlayers[client].m_iTimeDuration = newDuration;
	CPlayers[client].m_iTimeLeft = newTimeLeft;
	strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), name);
	g_bDataLoading[client] = false;
	g_bDataLoaded[client] = true;
	g_iDataRevision[client]++;
	RestoreActiveAdmiralPrivileges(client);

	AddClientReputationHistoryCache(client, cost, hours, GetTime());

	if (hours == TIME_FOREVER) CPrintToChat(client, "{green}[Admiral] {default}You unlocked {olive}Permanent Admiral{default} using {lightgreen}%d{default} lifetime reputation. Your available reputation was not deducted.", cost);
	else
	{
		CPlayers[client].m_iCurrentRep = newTotal;
		g_bTotalRepLoaded[client] = true;
		CPrintToChat(client, "{green}[Admiral] {default}You redeemed {lightgreen}%d{default} reputation for {olive}%d day%s{default} Admiral time. Remaining reputation: {lightgreen}%d{default}.", cost, hours / 24, (hours / 24) == 1 ? "" : "s", newTotal);
	}

	CacheAdmiralUpsert(steamid, name, newJoinTime, newDuration, newTimeLeft);
	ClearRedeemPending(client);
}

void ClearRedeemPending(int client)
{
	if (client > 0 && client <= MaxClients) g_bRedeemPending[client] = false;
}

/* =================================================================================================================== *
 *                                           Admiral Privilege Enforcement                                          *
 *==================================================================================================================== */

void ClearActiveAdmiralPrivileges(int client)
{
	if (client <= 0 || client > MaxClients) return;

	RemovePet(client);
	KillTrailEntities(client);

	if (IsClientInGame(client))
	{
		ResetSkinColor(client);
		ResetAuraColor(client);
	}

	g_bPrivCleared[client] = true;
}

void RestoreActiveAdmiralPrivileges(int client)
{
	if (!IsRealPlayer(client)) return;

	g_bPrivCleared[client] = false;

	if (AreClientCookiesCached(client))
	{
		g_bCookiesLoaded[client] = false;
		LoadClientPreferences(client);
	}
	else g_bCookiesLoaded[client] = false;
	
	CreateTimer(0.2, Timer_ResetAppearance, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void ExpireAdmiralAccess(int client)
{
	if (!IsRealPlayer(client)) return;

	CPlayers[client].m_iJoinTime = 0;
	CPlayers[client].m_iTimeDuration = 0;
	CPlayers[client].m_iTimeLeft = 0;
	g_bDataLoading[client] = false;
	g_bDataLoaded[client] = true;

	ClearActiveAdmiralPrivileges(client);
	Database_SavePlayerData(client);

	char steamid[32];
	if (Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) CacheAdmiralRemove(steamid);
}

Action Timer_EnforceAdmiralPrivileges(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsRealPlayer(client)) continue;

		if (!g_bPluginEnable)
		{
			if (!g_bPrivCleared[client]) ClearActiveAdmiralPrivileges(client);
			continue;
		}

		if (!g_bDataLoaded[client]) continue;
		if (!IsPlayerAdmiral(client) && !g_bPrivCleared[client]) ClearActiveAdmiralPrivileges(client);
	}

	return Plugin_Continue;
}

/* =================================================================================================================== *
 *                                                Daily Challenges                                                     *
 *==================================================================================================================== */

int GetChallengeDateIndex()
{
	return GetTime() / 86400;
}

int GetChallengeDayOfWeek()
{
	int result = (GetChallengeDateIndex() + 4) % 7;
	if (result < 0) result += 7;
	return result;
}

int GetChallengeResetSecondsLeft()
{
	int secondsToday = GetTime() % 86400;
	return 86400 - secondsToday;
}

void EnsureChallengeDateCurrent(int client)
{
	int today = GetChallengeDateIndex();
	if (g_iChallengeDateIndex[client] == today) return;

	g_iChallengeDateIndex[client] = today;
	g_iChallengeProgress[client] = 0;
	g_bChallengeCompletedToday[client] = false;
}

void AdvanceChallengeProgress(int client, const char[] type, int amount)
{
	if (!g_bPluginEnable || !g_bChallengesConfigured) return;
	if (!IsRealPlayer(client) || !g_bChallengeDataLoaded[client]) return;

	int dayIndex = GetChallengeDayOfWeek();
	if (g_ChallengeOfDay[dayIndex].m_sType[0] == '\0') return;
	if (!StrEqual(g_ChallengeOfDay[dayIndex].m_sType, type)) return;

	EnsureChallengeDateCurrent(client);
	if (g_bChallengeCompletedToday[client]) return;

	g_iChallengeProgress[client] += amount;

	if (g_iChallengeProgress[client] >= g_ChallengeOfDay[dayIndex].m_iTarget)
	{
		g_iChallengeProgress[client] = g_ChallengeOfDay[dayIndex].m_iTarget;
		g_bChallengeCompletedToday[client] = true;
		GrantChallengeReward(client, dayIndex);
		SaveChallengeProgress(client);
	}
}

void GrantChallengeReward(int client, int dayIndex)
{
	int hours = g_ChallengeOfDay[dayIndex].m_iRewardHours;
	int rep = g_ChallengeOfDay[dayIndex].m_iRewardRep;

	if (hours > 0) UpdateAdmiral(client, hours * 3600);
	if (rep > 0) GrantChallengeReputation(client, rep);

	char sReward[64];
	FormatChallengeRewardText(hours, rep, sReward, sizeof(sReward));

	CPrintToChatAll("{green}[Admiral] {olive}%N {default} completed Daily Challenge: {lightgreen}%s{default}!", client, g_ChallengeOfDay[dayIndex].m_sName);
	PrintHintText(client, "Congrats: %s ", sReward);
}

void FormatChallengeRewardText(int hours, int rep, char[] buffer, int maxLen)
{
	if (rep > 0) FormatEx(buffer, maxLen, "%dh Admiral Time + %d Rep", hours, rep);
	else FormatEx(buffer, maxLen, "%dh Admiral Time", hours);
}

void GrantChallengeReputation(int client, int amount)
{
	if (!g_hDatabase || !IsRealPlayer(client) || amount <= 0) return;

	if (!TryBeginDatabaseWrite(0, "challenge reward"))
	{
		ScheduleChallengeReputationRetry(client, amount, 1);
		return;
	}

	PerformChallengeReputationGrant(client, amount);
}

void ScheduleChallengeReputationRetry(int client, int amount, int retry)
{
	if (retry > 3)
	{
		LogError("[Admiral] Gave up granting %d challenge reputation - database stayed busy after 3 retries.", amount);
		return;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(amount);
	pack.WriteCell(retry);
	CreateTimer(1.5, Timer_RetryChallengeReputationGrant, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

Action Timer_RetryChallengeReputationGrant(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int amount = pack.ReadCell();
	int retry = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return Plugin_Handled;

	if (!TryBeginDatabaseWrite(0, "challenge reward"))
	{
		ScheduleChallengeReputationRetry(client, amount, retry + 1);
		return Plugin_Handled;
	}

	PerformChallengeReputationGrant(client, amount);
	return Plugin_Handled;
}

void PerformChallengeReputationGrant(int client, int amount)
{
	CPlayers[client].m_iCurrentRep += amount;
	CPlayers[client].m_iTotalRep += amount;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		FinishDatabaseWrite();
		return;
	}

	char nameEsc[256], steamEsc[64];
	GetSafeEscapedClientName(client, nameEsc, sizeof(nameEsc));
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Rep_Total(steamid, name, current_rep, lifetime_rep) VALUES('%s', '%s', %d, %d) ON DUPLICATE KEY UPDATE name = VALUES(name), current_rep = current_rep + %d, lifetime_rep = lifetime_rep + %d;",
			steamEsc, nameEsc, amount, amount, amount, amount);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Rep_Total(steamid, name, current_rep, lifetime_rep) VALUES('%s', '%s', %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, current_rep = current_rep + %d, lifetime_rep = lifetime_rep + %d;",
			steamEsc, nameEsc, amount, amount, amount, amount);
	}

	g_hDatabase.Query(OnChallengeReputationGranted, g_SQLBuffer);
}

void OnChallengeReputationGranted(Database db, DBResultSet results, const char[] error, any data)
{
	FinishDatabaseWrite();
	if (results == null || error[0] != '\0') LogError("[Admiral] Challenge reputation grant query failed: %s", error);
}

void LoadClientChallengeData(int client)
{
	if (!g_hDatabase || !IsRealPlayer(client)) return;
	if (g_bChallengeDataLoaded[client]) return;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;

	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT date_index, progress, completed FROM Admiral_Challenges WHERE steamid = '%s';", steamEsc);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	g_hDatabase.Query(OnChallengeDataLoaded, g_SQLBuffer, pack);
}

void OnChallengeDataLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return;

	if (results == null || error[0] != '\0') LogError("[Admiral] Failed to load challenge progress for userid=%d: %s", userid, error);

	int today = GetChallengeDateIndex();
	g_iChallengeDateIndex[client] = today;
	g_iChallengeProgress[client] = 0;
	g_bChallengeCompletedToday[client] = false;

	if (results != null && error[0] == '\0' && results.FetchRow())
	{
		int storedDate = results.FetchInt(0);
		if (storedDate == today)
		{
			g_iChallengeProgress[client] = results.FetchInt(1);
			g_bChallengeCompletedToday[client] = results.FetchInt(2) != 0;
		}
	}

	g_bChallengeDataLoaded[client] = true;
}

void SaveChallengeProgress(int client)
{
	if (!g_hDatabase || !IsRealPlayer(client) || !g_bChallengeDataLoaded[client]) return;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;

	char name[MAX_NAME_LENGTH];
	GetSafeClientName(client, name, sizeof(name));

	Database_SaveChallengeSnapshot(GetClientUserId(client), steamid, name, g_iChallengeDateIndex[client], g_iChallengeProgress[client], g_bChallengeCompletedToday[client]);
}

void Database_SaveChallengeSnapshot(int userid, const char[] steamid, const char[] name, int dateIndex, int progress, bool completed)
{
	if (!g_hDatabase || steamid[0] == '\0') return;

	int client = GetClientOfUserId(userid);

	if (g_bWriteBusy || (client && g_bChallengeSaveBusy[client]))
	{
		DataPack retryPack = new DataPack();
		retryPack.WriteCell(userid);
		retryPack.WriteString(steamid);
		retryPack.WriteString(name);
		retryPack.WriteCell(dateIndex);
		retryPack.WriteCell(progress);
		retryPack.WriteCell(completed ? 1 : 0);
		CreateTimer(CHALLENGE_SAVE_RETRY_DELAY, Timer_RetryChallengeSave, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
		return;
	}

	char nameEsc[256], steamEsc[64];
	EscapeSQLStringSafe(name, nameEsc, sizeof(nameEsc));
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	if (client) g_bChallengeSaveBusy[client] = true;

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Challenges(steamid, name, date_index, progress, completed) VALUES('%s', '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name = VALUES(name), date_index = VALUES(date_index), progress = VALUES(progress), completed = VALUES(completed);",
			steamEsc, nameEsc, dateIndex, progress, completed ? 1 : 0);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_Challenges(steamid, name, date_index, progress, completed) VALUES('%s', '%s', %d, %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, date_index = excluded.date_index, progress = excluded.progress, completed = excluded.completed;",
			steamEsc, nameEsc, dateIndex, progress, completed ? 1 : 0);
	}

	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	g_hDatabase.Query(OnChallengeProgressSaved, g_SQLBuffer, pack);
}

Action Timer_RetryChallengeSave(Handle timer, DataPack pack)
{
	pack.Reset();

	int userid = pack.ReadCell();
	char steamid[32], name[MAX_NAME_LENGTH];
	pack.ReadString(steamid, sizeof(steamid));
	pack.ReadString(name, sizeof(name));
	int dateIndex = pack.ReadCell();
	int progress = pack.ReadCell();
	bool completed = pack.ReadCell() != 0;

	Database_SaveChallengeSnapshot(userid, steamid, name, dateIndex, progress, completed);
	return Plugin_Handled;
}

void OnChallengeProgressSaved(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(userid);
	if (IsRealPlayer(client)) g_bChallengeSaveBusy[client] = false;

	if (results == null || error[0] != '\0') LogError("[Admiral] Failed to save challenge progress: %s", error);
}

void Event_ChallengeAbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client)) return;

	char sAbility[32];
	event.GetString("ability", sAbility, sizeof(sAbility));
	if (!StrEqual(sAbility, "ability_lunge")) return;

	g_bChallengeHunterPouncing[client] = true;
	CreateTimer(0.1, Timer_ChallengeHunterGroundCheck, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

Action Timer_ChallengeHunterGroundCheck(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Stop;
	if (!g_bChallengeHunterPouncing[client]) return Plugin_Stop;

	if (IsGrounded(client) || IsOnLadder(client))
	{
		g_bChallengeHunterPouncing[client] = false;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void Event_ChallengePlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsValidClient(victim) || !IsRealPlayer(attacker)) return;
	if (GetClientTeam(attacker) != L4D2Team_Survivor || GetClientTeam(victim) != L4D2Team_Infected) return;

	bool wasPouncing = g_bChallengeHunterPouncing[victim];
	g_bChallengeHunterPouncing[victim] = false;

	if (wasPouncing && IsPlayerHunter(victim))
	{
		AdvanceChallengeProgress(attacker, "hunter_skeet", 1);
		return;
	}

	if (!IsPlayerTank(victim)) AdvanceChallengeProgress(attacker, "infected_kill", 1);
}

void Event_ChallengeInfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsRealPlayer(attacker) || GetClientTeam(attacker) != L4D2Team_Survivor) return;

	AdvanceChallengeProgress(attacker, "commons_kill", 1);
}

void Event_ChallengeChargerKilled(Event event, const char[] name, bool dontBroadcast)
{
	if (!event.GetBool("charging") || !event.GetBool("melee")) return;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsRealPlayer(attacker) || GetClientTeam(attacker) != L4D2Team_Survivor) return;

	AdvanceChallengeProgress(attacker, "charger_level", 1);
}


void Event_ChallengeWitchKilled(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!IsRealPlayer(attacker) || GetClientTeam(attacker) != L4D2Team_Survivor) return;

	AdvanceChallengeProgress(attacker, "witch_kill", 1);
}

void Event_ChallengeTankDamage(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsValidClient(victim) || !IsRealPlayer(attacker) || victim == attacker) return;
	if (GetClientTeam(attacker) != L4D2Team_Survivor) return;

	int damage = event.GetInt("dmg_health");
	if (damage <= 0) return;
	if (!IsPlayerTank(victim)) return;

	AdvanceChallengeProgress(attacker, "tank_damage", damage);
}

void Event_ChallengeHealBegin(Event event, const char[] name, bool dontBroadcast)
{
	int subject = GetClientOfUserId(event.GetInt("subject"));
	if (!IsValidClient(subject) || !IsPlayerAlive(subject)) return;

	g_iChallengePreHealHealth[subject] = GetClientHealth(subject);
}

void Event_ChallengeHealSuccess(Event event, const char[] name, bool dontBroadcast)
{
	int healer = GetClientOfUserId(event.GetInt("userid"));
	int target = GetClientOfUserId(event.GetInt("subject"));
	if (!IsRealPlayer(healer) || !IsValidClient(target) || healer == target) return;

	int maxHealth = GetEntProp(target, Prop_Send, "m_iMaxHealth");
	int criticalThreshold = (maxHealth * 40) / 100;

	if (g_iChallengePreHealHealth[target] >= criticalThreshold) return;
	AdvanceChallengeProgress(healer, "kit_heal", 1);
}

void LoadDailyChallengeMenu(int client)
{
	if (!IsRealPlayer(client)) return;
	if (!Admiral_CheckDatabaseReady(client)) return;

	if (!g_bChallengeDataLoaded[client]) LoadClientChallengeData(client);

	ShowDailyChallengeMenu(client);
}

void ShowDailyChallengeMenu(int client)
{
	int dayIndex = GetChallengeDayOfWeek();
	Panel panel = new Panel();

	if (!g_bChallengesConfigured || g_ChallengeOfDay[dayIndex].m_sType[0] == '\0')
	{
		panel.SetTitle("Daily Challenge");
		panel.DrawText(" ");
		panel.DrawText("No challenge is configured for today.");
		panel.DrawText(" ");
		panel.DrawText(" ");
		panel.CurrentKey = 8;
		panel.DrawItem("Back", ITEMDRAW_CONTROL);

		panel.DrawText(" ");
		panel.CurrentKey = 10;
		panel.DrawItem("Exit", ITEMDRAW_CONTROL);
		panel.Send(client, Handle_DailyChallengePanel, MENU_TIME_FOREVER);
		delete panel;
		return;
	}

	if (!g_bChallengeDataLoaded[client])
	{
		panel.SetTitle("Daily Challenge");
		panel.DrawText(" ");
		panel.DrawText("Still loading your progress - try again in a moment.");
		panel.DrawText(" ");
		panel.DrawText(" ");
		panel.CurrentKey = 8;
		panel.DrawItem("Back", ITEMDRAW_CONTROL);
	
		panel.DrawText(" ");
		panel.CurrentKey = 10;
		panel.DrawItem("Exit", ITEMDRAW_CONTROL);
		panel.Send(client, Handle_DailyChallengePanel, MENU_TIME_FOREVER);
		delete panel;
		return;
	}

	EnsureChallengeDateCurrent(client);

	char sDate[32];
	FormatTime(sDate, sizeof(sDate), "%Y-%m-%d", GetTime());

	char sReward[64];
	FormatChallengeRewardText(g_ChallengeOfDay[dayIndex].m_iRewardHours, g_ChallengeOfDay[dayIndex].m_iRewardRep, sReward, sizeof(sReward));

	int secondsLeft = GetChallengeResetSecondsLeft();
	char sCountdown[16];
	FormatEx(sCountdown, sizeof(sCountdown), "%02dh %02dm", secondsLeft / 3600, (secondsLeft % 3600) / 60);

	char sLine[128];

	FormatEx(sLine, sizeof(sLine), "Daily Challenge - %s", g_sChallengeDayNames[dayIndex]);
	panel.SetTitle(sLine);

	panel.DrawText(sDate);
	panel.DrawText(" ");
	panel.DrawText(g_ChallengeOfDay[dayIndex].m_sName);

	FormatEx(sLine, sizeof(sLine), "Progress: %d / %d", g_iChallengeProgress[client], g_ChallengeOfDay[dayIndex].m_iTarget);
	panel.DrawText(sLine);
	panel.DrawText(" ");

	if (g_bChallengeCompletedToday[client]) panel.DrawText("Status: Complete");
	else panel.DrawText("Status: In Progress");
	
	FormatEx(sLine, sizeof(sLine), "Reward: %s", sReward);
	panel.DrawText(sLine);

	panel.DrawText(" ");
	FormatEx(sLine, sizeof(sLine), "Resets in: %s", sCountdown);
	panel.DrawText(sLine);
	
	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.CurrentKey = 8;
	panel.DrawItem("Back", ITEMDRAW_CONTROL);

	panel.DrawText(" ");
	panel.CurrentKey = 10;
	panel.DrawItem("Exit", ITEMDRAW_CONTROL);

	panel.Send(client, Handle_DailyChallengePanel, MENU_TIME_FOREVER);
	delete panel;
}

int Handle_DailyChallengePanel(Menu menu, MenuAction action, int client, int select)
{
	if (action == MenuAction_Select && select == 8) LoadMyReputationMenu(client);
	return 0;
}

/* =================================================================================================================== *
 *                                         Entity Cleanup & Orphan Detection                                           *
 *==================================================================================================================== */

void CleanupAdmiralEffectsOnUnload()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			RemovePet(client);
			KillTrailEntities(client);

			if (IsClientInGame(client))
			{
				ResetSkinColor(client);
				ResetAuraColor(client);
			}
		}

		g_bPrivCleared[client] = true;
	}

	CleanupAdmiralOrphanEntities();
}

void CleanupAdmiralOrphanEntities()
{
	int maxEntities = GetMaxEntities();
	char sClass[64];

	for (int entity = MaxClients + 1; entity < maxEntities; entity++)
	{
		if (!IsValidEntity(entity)) continue;
		if (!GetEntityClassname(entity, sClass, sizeof(sClass))) continue;

		if (IsAdmiralTaggedEntity(entity) || IsLegacyAdmiralTrailEntity(entity, sClass) || IsLegacyAdmiralPetEntity(entity, sClass))
			AcceptEntityInput(entity, "Kill");
	}
}

bool IsAdmiralTaggedEntity(int entity)
{
	if (!HasEntProp(entity, Prop_Data, "m_iName")) return false;

	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));
	return StrContains(sName, "l4d2_admiral_", false) == 0;
}

bool IsLegacyAdmiralTrailEntity(int entity, const char[] sClass)
{
	if (!StrEqual(sClass, "env_spritetrail", false) && !StrEqual(sClass, "func_rotating", false)) return false;

	int parent = GetMoveParentSafe(entity);
	if (IsRealPlayer(parent)) return true;

	if (parent > MaxClients && IsValidEntity(parent))
	{
		if (IsAdmiralTaggedEntity(parent)) return true;

		char sParentClass[64];
		if (GetEntityClassname(parent, sParentClass, sizeof(sParentClass)) && StrEqual(sParentClass, "func_rotating", false))
		{
			int grandParent = GetMoveParentSafe(parent);
			if (IsRealPlayer(grandParent)) return true;
		}
	}

	return false;
}

bool IsLegacyAdmiralPetEntity(int entity, const char[] sClass)
{
	if (!StrEqual(sClass, "prop_dynamic", false) && !StrEqual(sClass, "prop_dynamic_override", false)) return false;
	if (!HasEntProp(entity, Prop_Data, "m_ModelName")) return false;

	char sModel[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));

	return StrContains(sModel, "models/pet/", false) != -1 || StrContains(sModel, "models/infected/jockey.mdl", false) != -1;
}

int GetMoveParentSafe(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity)) return -1;
	if (HasEntProp(entity, Prop_Send, "m_hMoveParent")) return GetEntPropEnt(entity, Prop_Send, "m_hMoveParent");
	if (HasEntProp(entity, Prop_Data, "m_hMoveParent")) return GetEntPropEnt(entity, Prop_Data, "m_hMoveParent");
	return -1;
}

/* =================================================================================================================== *
 *                                     Database: Connection, Schema, Player Data                                       *
 *==================================================================================================================== */

void ScheduleClientDatabaseLoad(int client, float delay)
{
	if (!IsRealPlayer(client)) return;

	if (g_bLoadQueued[client]) return;

	g_bLoadQueued[client] = true;
	CreateTimer(delay, Timer_ClientDatabaseLoad, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_ClientDatabaseLoad(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return Plugin_Handled;

	g_bLoadQueued[client] = false;

	if (!g_hDatabase || !g_bSchemaReady) return Plugin_Handled;

	Database_RetrievePlayerData(client);
	LoadClientTotalReputation(client);
	return Plugin_Handled;
}

int FindClientBySteamID(const char[] steamid)
{
	char current[32];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsRealPlayer(i)) continue;
		if (!Admiral_GetClientSteamID(i, current, sizeof(current))) continue;
		if (StrEqual(current, steamid, false)) return i;
	}
	return 0;
}

bool TryBeginDatabaseWrite(int client, const char[] action)
{
	if (!g_bWriteBusy)
	{
		g_bWriteBusy = true;
		return true;
	}

	if (client > 0 && client <= MaxClients && IsClientInGame(client))
		CPrintToChat(client, "{green}[Admiral] {default}Database is finishing another %s. Try again in a moment.", action);

	return false;
}

void FinishDatabaseWrite()
{
	g_bWriteBusy = false;
}

void Database_OnConfigExecuted()
{
	if (g_hDatabase || g_bDbConnecting) return;

	if (g_sDataBase[0] == '\0' || IsCharSpace(g_sDataBase[0]))
	{
		LogError("Admiral system Database config is empty");
		return;
	}

	if (!SQL_CheckConfig(g_sDataBase))
	{
		LogError("Admiral system Database config '%s' doesn't exist in databases.cfg", g_sDataBase);
		return;
	}

	g_bDbConnecting = true;
	Database.Connect(OnDatabaseConnected, g_sDataBase);
}

void OnDatabaseConnected(Database db, const char[] error, any data)
{
	g_bDbConnecting = false;
	
	if (!db || error[0] != '\0')
	{
		g_bSchemaReady = false;
		LogError("Couldn't connect to the Admiral system Database: %s", error);
		if (g_hTimer_DatabaseRetry == null) g_hTimer_DatabaseRetry = CreateTimer(5.0, Timer_RetryDatabaseConnection, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	g_hDatabase = db;

	DBDriver driver = g_hDatabase.Driver;
	driver.GetIdentifier(g_SQLDriver, sizeof(g_SQLDriver));

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		if (GetFeatureStatus(FeatureType_Native, "SQL_SetCharset") == FeatureStatus_Available) SQL_SetCharset(g_hDatabase, "utf8mb4");
		else g_hDatabase.Query(OnDatabaseInit, "SET NAMES 'utf8mb4' COLLATE 'utf8mb4_unicode_ci';");
	}

	InitDatabase();
	RefreshPlayersData();
}

Action Timer_RetryDatabaseConnection(Handle timer)
{
	g_hTimer_DatabaseRetry = null;
	if (g_hDatabase == null && !g_bDbConnecting) Database_OnConfigExecuted();
	return Plugin_Handled;
}

void InitDatabase()
{
	if (!g_hDatabase) return;

	g_bSchemaReady = true;

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_DataBase(steamid VARCHAR(64) NOT NULL PRIMARY KEY, name VARCHAR(128) NOT NULL DEFAULT '', jointime INT NOT NULL DEFAULT 0, duration INT NOT NULL DEFAULT 0, timeleft INT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_DataBase SET duration = -1, timeleft = -1 WHERE duration < 0 OR timeleft < 0;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "ALTER TABLE Admiral_DataBase MODIFY steamid VARCHAR(64) NOT NULL;");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_admiral_active_time ON Admiral_DataBase(duration, jointime);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_admiral_name ON Admiral_DataBase(name);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Total(steamid VARCHAR(32) NOT NULL PRIMARY KEY, name VARCHAR(128) NOT NULL DEFAULT '', current_rep INT NOT NULL DEFAULT 0, lifetime_rep INT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "ALTER TABLE Admiral_Rep_Total ADD COLUMN lifetime_rep INT NOT NULL DEFAULT 0;");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_Rep_Total SET lifetime_rep = current_rep WHERE lifetime_rep < current_rep;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Log(id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, sender VARCHAR(32) NOT NULL, receiver VARCHAR(32) NOT NULL, sender_name VARCHAR(128) NOT NULL DEFAULT '', receiver_name VARCHAR(128) NOT NULL DEFAULT '', timestamp INT NOT NULL, INDEX idx_sender_time(sender, timestamp), INDEX idx_sender_receiver_time(sender, receiver, timestamp), INDEX idx_receiver_time(receiver, timestamp)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_sender_time ON Admiral_Rep_Log(sender, timestamp);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_sender_receiver_time ON Admiral_Rep_Log(sender, receiver, timestamp);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_receiver_time ON Admiral_Rep_Log(receiver, timestamp);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Redeem_Log(id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, steamid VARCHAR(32) NOT NULL, name VARCHAR(128) NOT NULL DEFAULT '', cost INT NOT NULL DEFAULT 0, hours INT NOT NULL DEFAULT 0, timestamp INT NOT NULL, INDEX idx_redeem_steamid_time(steamid, timestamp), INDEX idx_redeem_steamid_id(steamid, id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_redeem_steamid_time ON Admiral_Rep_Redeem_Log(steamid, timestamp);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX idx_redeem_steamid_id ON Admiral_Rep_Redeem_Log(steamid, id);");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_Rep_Total t LEFT JOIN (SELECT steamid, SUM(cost) AS spent FROM Admiral_Rep_Redeem_Log GROUP BY steamid) r ON r.steamid = t.steamid SET t.lifetime_rep = t.current_rep + COALESCE(r.spent, 0) WHERE t.lifetime_rep < t.current_rep + COALESCE(r.spent, 0);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Challenges(steamid VARCHAR(32) NOT NULL PRIMARY KEY, name VARCHAR(128) NOT NULL DEFAULT '', date_index INT NOT NULL DEFAULT 0, progress INT NOT NULL DEFAULT 0, completed TINYINT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);
	}
	else
	{
		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_DataBase(steamid TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', jointime INTEGER NOT NULL DEFAULT 0, duration INTEGER NOT NULL DEFAULT 0, timeleft INTEGER NOT NULL DEFAULT 0);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_DataBase SET duration = -1, timeleft = -1 WHERE duration < 0 OR timeleft < 0;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_active_time ON Admiral_DataBase(duration, jointime);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_name ON Admiral_DataBase(name);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Total(steamid TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', current_rep INTEGER NOT NULL DEFAULT 0, lifetime_rep INTEGER NOT NULL DEFAULT 0);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "ALTER TABLE Admiral_Rep_Total ADD COLUMN lifetime_rep INTEGER NOT NULL DEFAULT 0;");
		g_hDatabase.Query(OnDatabaseAlterIgnore, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_Rep_Total SET lifetime_rep = current_rep WHERE lifetime_rep < current_rep;");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Log(id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL, receiver TEXT NOT NULL, sender_name TEXT NOT NULL DEFAULT '', receiver_name TEXT NOT NULL DEFAULT '', timestamp INTEGER NOT NULL);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_rep_sender_time ON Admiral_Rep_Log(sender, timestamp);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_rep_sender_receiver_time ON Admiral_Rep_Log(sender, receiver, timestamp);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_rep_receiver_time ON Admiral_Rep_Log(receiver, timestamp);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Rep_Redeem_Log(id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', cost INTEGER NOT NULL DEFAULT 0, hours INTEGER NOT NULL DEFAULT 0, timestamp INTEGER NOT NULL);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_rep_redeem_steamid_time ON Admiral_Rep_Redeem_Log(steamid, timestamp);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE INDEX IF NOT EXISTS idx_admiral_rep_redeem_steamid_id ON Admiral_Rep_Redeem_Log(steamid, id);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "UPDATE Admiral_Rep_Total SET lifetime_rep = current_rep + COALESCE((SELECT SUM(cost) FROM Admiral_Rep_Redeem_Log r WHERE r.steamid = Admiral_Rep_Total.steamid), 0) WHERE lifetime_rep < current_rep + COALESCE((SELECT SUM(cost) FROM Admiral_Rep_Redeem_Log r WHERE r.steamid = Admiral_Rep_Total.steamid), 0);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);

		strcopy(g_SQLBuffer, sizeof(g_SQLBuffer), "CREATE TABLE IF NOT EXISTS Admiral_Challenges(steamid TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', date_index INTEGER NOT NULL DEFAULT 0, progress INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0);");
		g_hDatabase.Query(OnDatabaseInit, g_SQLBuffer);
	}
}

bool IsExpectedDatabaseMigrationError(const char[] error)
{
	if (error[0] == '\0') return true;
	return StrContains(error, "doesn't exist", false) != -1 || StrContains(error, "does not exist", false) != -1 || StrContains(error, "no such table", false) != -1 || StrContains(error, "already exists", false) != -1 || StrContains(error, "duplicate", false) != -1 || StrContains(error, "unknown column", false) != -1 || StrContains(error, "no such column", false) != -1;
}

bool IsExpectedDatabaseSchemaError(const char[] error)
{
	if (error[0] == '\0') return true;
	return StrContains(error, "already exists", false) != -1 || StrContains(error, "duplicate column", false) != -1 || StrContains(error, "duplicate key", false) != -1 || StrContains(error, "duplicate name", false) != -1 || StrContains(error, "duplicate", false) != -1;
}

void OnDatabaseAlterIgnore(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || error[0] != '\0')
	{
		if (!IsExpectedDatabaseSchemaError(error) && !IsExpectedDatabaseMigrationError(error))
			LogError("Database query failed (%s)", error);
	}
}

void OnDatabaseInit(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || error[0] != '\0') LogError("Database initiation query failed (%s)", error);
}

bool Admiral_GetClientSteamID(int client, char[] steamid, int maxLen)
{
	if (maxLen <= 0) return false;
	steamid[0] = '\0';

	if (client <= 0 || client > MaxClients) return false;

	if (g_sAdmiralSteamId[client][0] != '\0')
	{
		strcopy(steamid, maxLen, g_sAdmiralSteamId[client]);
		return true;
	}

	if (!IsClientInGame(client) || IsFakeClient(client)) return false;
	if (!GetClientAuthId(client, AuthId_SteamID64, steamid, maxLen, true)) return false;

	strcopy(g_sAdmiralSteamId[client], sizeof(g_sAdmiralSteamId[]), steamid);
	return true;
}

bool Admiral_ValidateCallbackClient(int userid, const char[] expectedSteam, int &client)
{
	client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client)) return false;

	char currentSteam[32];
	if (!Admiral_GetClientSteamID(client, currentSteam, sizeof(currentSteam))) return false;
	if (!StrEqual(currentSteam, expectedSteam, false)) return false;

	return true;
}

void SchedulePlayerDataRetry(int client, float delay)
{
	if (!IsRealPlayer(client) || g_iLoadRetries[client] >= 5) return;

	g_iLoadRetries[client]++;
	CreateTimer(delay, Timer_RetryPlayerDataLoad, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_RetryPlayerDataLoad(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client) || g_bDataLoaded[client]) return Plugin_Handled;

	g_bDataLoading[client] = false;
	Database_RetrievePlayerData(client);
	return Plugin_Handled;
}

Action Timer_PlayerDataLoadTimeout(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client) || g_bDataLoaded[client] || !g_bDataLoading[client]) return Plugin_Handled;

	g_bDataLoading[client] = false;
	LogError("Admiral data load timed out for %N. Retrying.", client);
	SchedulePlayerDataRetry(client, 0.2);
	return Plugin_Handled;
}

void Database_RetrievePlayerData(int client)
{
	if (!IsRealPlayer(client)) return;

	if (!g_hDatabase)
	{
		if (!g_bDbConnecting) Database_OnConfigExecuted();
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}

	if (!g_bSchemaReady)
	{
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}

	if (!g_bChallengeDataLoaded[client]) LoadClientChallengeData(client);

	if (g_bDataLoaded[client]) return;
	if (g_bDataLoading[client]) return;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid)))
	{
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}

	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	g_bDataLoading[client] = true;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(g_iDataRevision[client]);
	pack.WriteString(steamid);

	CreateTimer(5.0, Timer_PlayerDataLoadTimeout, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT name, jointime, duration, timeleft FROM Admiral_DataBase WHERE steamid = '%s' LIMIT 1;", steamEsc);
	g_hDatabase.Query(OnDatabaseSelect, g_SQLBuffer, pack);
}

void OnDatabaseSelect(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	int revision = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;

	if (revision != g_iDataRevision[client])
	{
		g_bDataLoading[client] = false;
		return;
	}

	g_bDataLoading[client] = false;

	if (results == null || error[0] != '\0')
	{
		LogError("Failed to load Admiral data for %N / %s (error: %s)", client, steamid, error);
		g_bDataLoaded[client] = false;
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}

	if (results.FetchRow())
	{
		results.FetchString(0, CPlayers[client].m_sName, sizeof(CPlayer::m_sName));
		CPlayers[client].m_iJoinTime = results.FetchInt(1);
		CPlayers[client].m_iTimeDuration = results.FetchInt(2);
		CPlayers[client].m_iTimeLeft = results.FetchInt(3);
		NormalizeAdmiralAccessData(CPlayers[client].m_iJoinTime, CPlayers[client].m_iTimeDuration, CPlayers[client].m_iTimeLeft);
		g_bDataLoaded[client] = true;
		g_iLoadRetries[client] = 0;
		g_bPrivCleared[client] = !IsPlayerAdmiral(client);

		if (CPlayers[client].m_iTimeDuration != TIME_FOREVER && CPlayers[client].m_iTimeDuration > 0 && CPlayers[client].m_iTimeLeft <= 0)
		{
			ExpireAdmiralAccess(client);
			return;
		}

		if (IsPlayerAdmiral(client)) RestoreActiveAdmiralPrivileges(client);
		else CreateTimer(0.2, Timer_ResetAppearance, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	char name[MAX_NAME_LENGTH], nameEsc[256], steamEsc[64];
	GetSafeClientName(client, name, sizeof(name));
	EscapeSQLStringSafe(name, nameEsc, sizeof(nameEsc));
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	strcopy(CPlayers[client].m_sName, sizeof(CPlayer::m_sName), name);
	CPlayers[client].m_iJoinTime = 0;
	CPlayers[client].m_iTimeDuration = 0;
	CPlayers[client].m_iTimeLeft = 0;

	if (g_bWriteBusy)
	{
		g_bDataLoading[client] = false;
		SchedulePlayerDataRetry(client, 0.25);
		return;
	}

	DataPack next = new DataPack();
	next.WriteCell(userid);
	next.WriteCell(g_iDataRevision[client]);
	next.WriteString(steamid);

	g_bDataLoading[client] = true;

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', 0, 0, 0) ON DUPLICATE KEY UPDATE name = VALUES(name);",
			steamEsc, nameEsc);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', 0, 0, 0) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name;",
			steamEsc, nameEsc);
	}

	g_hDatabase.Query(OnDatabaseInitPlayer, g_SQLBuffer, next);
}

void OnDatabaseInitPlayer(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	int revision = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;

	if (revision != g_iDataRevision[client])
	{
		g_bDataLoading[client] = false;
		return;
	}

	if (results == null || error[0] != '\0')
	{
		g_bDataLoading[client] = false;
		LogError("Database initiation for Admiral player %N / %s failed (%s)", client, steamid, error);
		g_bDataLoaded[client] = false;
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}
	
	char steamEsc[64];
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	DataPack next = new DataPack();
	next.WriteCell(userid);
	next.WriteCell(revision);
	next.WriteString(steamid);

	FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer), "SELECT jointime, duration, timeleft FROM Admiral_DataBase WHERE steamid = '%s' LIMIT 1;", steamEsc);
	g_hDatabase.Query(OnDatabaseInitPlayerReload, g_SQLBuffer, next);
}

void OnDatabaseInitPlayerReload(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	int revision = pack.ReadCell();
	char steamid[32];
	pack.ReadString(steamid, sizeof(steamid));
	delete pack;

	int client;
	if (!Admiral_ValidateCallbackClient(userid, steamid, client)) return;

	g_bDataLoading[client] = false;

	if (revision != g_iDataRevision[client]) return;

	if (results == null || error[0] != '\0')
	{
		LogError("Admiral post-init reload failed for %N / %s (%s)", client, steamid, error);
		g_bDataLoaded[client] = false;
		SchedulePlayerDataRetry(client, 1.0);
		return;
	}

	int joinTime = 0, duration = 0, timeLeft = 0;
	if (results.FetchRow())
	{
		joinTime = results.FetchInt(0);
		duration = results.FetchInt(1);
		timeLeft = results.FetchInt(2);
	}
	NormalizeAdmiralAccessData(joinTime, duration, timeLeft);

	CPlayers[client].m_iJoinTime = joinTime;
	CPlayers[client].m_iTimeDuration = duration;
	CPlayers[client].m_iTimeLeft = timeLeft;

	g_bDataLoaded[client] = true;
	g_iLoadRetries[client] = 0;
	g_bPrivCleared[client] = !IsPlayerAdmiral(client);

	if (duration != TIME_FOREVER && duration > 0 && timeLeft <= 0)
	{
		ExpireAdmiralAccess(client);
		return;
	}

	if (IsPlayerAdmiral(client)) RestoreActiveAdmiralPrivileges(client);
	else CreateTimer(0.2, Timer_ResetAppearance, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void Database_SavePlayerData(int client)
{
	if (!g_hDatabase || client <= 0 || client > MaxClients) return;
	if (!g_bDataLoaded[client]) return;

	char steamid[32];
	if (!Admiral_GetClientSteamID(client, steamid, sizeof(steamid))) return;

	char name[MAX_NAME_LENGTH];
	if (IsClientInGame(client)) GetClientName(client, name, sizeof(name));
	else strcopy(name, sizeof(name), CPlayers[client].m_sName);

	if (name[0] == '\0') strcopy(name, sizeof(name), steamid);
	SafelyCheckPlayerName(name, sizeof(name));

	GetAdmiralTimeLeft(client);
	Database_SaveAdmiralSnapshot(GetClientUserId(client), steamid, name, CPlayers[client].m_iJoinTime, CPlayers[client].m_iTimeDuration, CPlayers[client].m_iTimeLeft, 0);
}

void Database_SaveAdmiralSnapshot(int userid, const char[] steamid, const char[] name, int joinTime, int duration, int timeLeft, int retry)
{
	if (!g_hDatabase || steamid[0] == '\0') return;

	if (g_bWriteBusy)
	{
		DataPack retryPack = new DataPack();
		retryPack.WriteCell(userid);
		retryPack.WriteCell(retry);
		retryPack.WriteString(steamid);
		retryPack.WriteString(name);
		retryPack.WriteCell(joinTime);
		retryPack.WriteCell(duration);
		retryPack.WriteCell(timeLeft);
		CreateTimer(0.25, Timer_RetryPlayerDataSave, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
		return;
	}

	NormalizeAdmiralAccessData(joinTime, duration, timeLeft);

	char nameEsc[256], steamEsc[64];
	EscapeSQLStringSafe(name, nameEsc, sizeof(nameEsc));
	EscapeSQLStringSafe(steamid, steamEsc, sizeof(steamEsc));

	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	pack.WriteCell(retry);
	pack.WriteString(steamid);
	pack.WriteString(name);
	pack.WriteCell(joinTime);
	pack.WriteCell(duration);
	pack.WriteCell(timeLeft);

	if (StrEqual(g_SQLDriver, MYSQL, false))
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name = VALUES(name), jointime = VALUES(jointime), duration = VALUES(duration), timeleft = VALUES(timeleft);",
			steamEsc, nameEsc, joinTime, duration, timeLeft);
	}
	else
	{
		FormatEx(g_SQLBuffer, sizeof(g_SQLBuffer),
			"INSERT INTO Admiral_DataBase(steamid, name, jointime, duration, timeleft) VALUES('%s', '%s', %d, %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, jointime = excluded.jointime, duration = excluded.duration, timeleft = excluded.timeleft;",
			steamEsc, nameEsc, joinTime, duration, timeLeft);
	}

	g_hDatabase.Query(OnDatabaseSave, g_SQLBuffer, pack);
}

void OnDatabaseSave(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int userid = pack.ReadCell();
	int retry = pack.ReadCell();

	char steamid[32], name[MAX_NAME_LENGTH];
	pack.ReadString(steamid, sizeof(steamid));
	pack.ReadString(name, sizeof(name));

	int joinTime = pack.ReadCell();
	int duration = pack.ReadCell();
	int timeLeft = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(userid);

	if (results != null && error[0] == '\0')
	{
		if (IsRealPlayer(client)) g_iLoadRetries[client] = 0;

		if (duration == TIME_FOREVER || (duration > 0 && (joinTime + duration) > GetTime())) CacheAdmiralUpsert(steamid, name, joinTime, duration, timeLeft);
		else CacheAdmiralRemove(steamid);
		return;
	}

	LogError("Failed to save Admiral data for %s / %s (join:%d duration:%d left:%d retry:%d error:%s)", name, steamid, joinTime, duration, timeLeft, retry, error);

	if (retry < 3)
	{
		DataPack retryPack = new DataPack();
		retryPack.WriteCell(userid);
		retryPack.WriteCell(retry + 1);
		retryPack.WriteString(steamid);
		retryPack.WriteString(name);
		retryPack.WriteCell(joinTime);
		retryPack.WriteCell(duration);
		retryPack.WriteCell(timeLeft);
		CreateTimer(1.0, Timer_RetryPlayerDataSave, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
	}
}

Action Timer_RetryPlayerDataSave(Handle timer, DataPack pack)
{
	pack.Reset();

	int userid = pack.ReadCell();
	int retry = pack.ReadCell();

	char steamid[32], name[MAX_NAME_LENGTH];
	pack.ReadString(steamid, sizeof(steamid));
	pack.ReadString(name, sizeof(name));

	int joinTime = pack.ReadCell();
	int duration = pack.ReadCell();
	int timeLeft = pack.ReadCell();
	Database_SaveAdmiralSnapshot(userid, steamid, name, joinTime, duration, timeLeft, retry);
	return Plugin_Handled;
}

bool Admiral_CheckDatabaseReady(int client)
{
	if (g_hDatabase != null && g_bSchemaReady) return true;

	if (client > 0 && client <= MaxClients && IsClientInGame(client))
		CPrintToChat(client, g_bDbConnecting ? "{green}[Admiral] {default}Database is still connecting. Try again in a few seconds." : "{green}[Admiral] {default}Database is not connected.");

	if (!g_hDatabase && !g_bDbConnecting) Database_OnConfigExecuted();
	return false;
}

void GetSafeClientName(int client, char[] name, int maxLen)
{
	GetClientName(client, name, maxLen);
	SafelyCheckPlayerName(name, maxLen);
}

void GetSafeEscapedClientName(int client, char[] escapedName, int maxLen)
{
	char name[MAX_NAME_LENGTH];
	GetSafeClientName(client, name, sizeof(name));
	EscapeSQLStringSafe(name, escapedName, maxLen);
}

void EscapeSQLStringSafe(const char[] input, char[] output, int maxLen)
{
	if (maxLen <= 0) return;

	output[0] = '\0';
	if (g_hDatabase != null)
	{
		int written;
		if (SQL_EscapeString(g_hDatabase, input, output, maxLen, written)) return;
	}

	int out;
	for (int i = 0; input[i] != '\0' && out < maxLen - 1; i++)
	{
		if (input[i] == 39 && out < maxLen - 2) output[out++] = 39;
		output[out++] = input[i];
	}

	output[out] = '\0';
}

void SafelyCheckPlayerName(char[] Name, int size)
{
	ReplaceString(Name, size, "<?php", "");
	ReplaceString(Name, size, "<?PHP", "");
	ReplaceString(Name, size, "?>", "");
	ReplaceString(Name, size, "\\", "");
	ReplaceString(Name, size, "\"", "");
	ReplaceString(Name, size, "'", "");
	ReplaceString(Name, size, ";", "");
	ReplaceString(Name, size, "\xef\xbf\xbd", "");
	ReplaceString(Name, size, "`", "");
}

DataPack Client_CreatePack(int client, const char[] steamid)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(steamid);
	return pack;
}

/* =================================================================================================================== *
 *                                         Stock / General Utility Functions                                           *
 *==================================================================================================================== */

void FormatAdmiralTimeShort(int seconds, char[] buffer, int maxLen)
{
	if (seconds == TIME_FOREVER)
	{
		strcopy(buffer, maxLen, "Permanent");
		return;
	}

	if (seconds <= 0)
	{
		strcopy(buffer, maxLen, "None");
		return;
	}

	int days = seconds / 86400;
	int hours = (seconds / 3600) % 24;
	int minutes = (seconds / 60) % 60;

	if (days > 0) FormatEx(buffer, maxLen, "%dd %dh", days, hours);
	else if (hours > 0) FormatEx(buffer, maxLen, "%dh %dm", hours, minutes);
	else FormatEx(buffer, maxLen, "%dm", minutes);
}

void NormalizeAdmiralAccessData(int &joinTime, int &duration, int &timeLeft)
{
	if (duration < 0 || timeLeft < 0)
	{
		if (joinTime <= 0) joinTime = GetTime();
		duration = TIME_FOREVER;
		timeLeft = TIME_FOREVER;
		return;
	}

	if (duration <= 0)
	{
		timeLeft = 0;
		return;
	}

	timeLeft = joinTime + duration - GetTime();
	if (timeLeft <= 0) timeLeft = 0;
}

int GetAdmiralTimeLeft(int client)
{
	if (client <= 0 || client > MaxClients) return 0;

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER)
	{
		CPlayers[client].m_iTimeLeft = TIME_FOREVER;
		return CPlayers[client].m_iTimeLeft;
	}

	if (CPlayers[client].m_iTimeDuration <= 0)
	{
		CPlayers[client].m_iTimeLeft = 0;
		return 0;
	}

	CPlayers[client].m_iTimeLeft = CPlayers[client].m_iJoinTime + CPlayers[client].m_iTimeDuration - GetTime();
	if (CPlayers[client].m_iTimeLeft <= 0) CPlayers[client].m_iTimeLeft = 0;

	return CPlayers[client].m_iTimeLeft;
}

bool IsPlayerAdmiral(int client)
{
	if (!IsRealPlayer(client)) return false;

	if (!g_bDataLoaded[client])
	{
		Database_RetrievePlayerData(client);
		return false;
	}

	if (CPlayers[client].m_iTimeDuration == TIME_FOREVER)
	{
		CPlayers[client].m_iTimeLeft = TIME_FOREVER;
		return true;
	}

	if (CPlayers[client].m_iTimeDuration <= 0)
	{
		CPlayers[client].m_iTimeLeft = 0;
		return false;
	}

	CPlayers[client].m_iTimeLeft = CPlayers[client].m_iJoinTime + CPlayers[client].m_iTimeDuration - GetTime();

	if (CPlayers[client].m_iTimeLeft <= 0)
	{
		ExpireAdmiralAccess(client);
		return false;
	}

	return true;
}

bool IsPlayerAdmin(int client)
{
	return CheckCommandAccess(client, "sm_root", ADMFLAG_ROOT, false);
}

bool IsPlayerTank(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == L4D2Class_Tank && GetEntProp(client, Prop_Send, "m_nSequence") < 65);
}

bool IsPlayerHunter(int victim)
{
	return GetClientTeam(victim) == L4D2Team_Infected && L4D2_GetPlayerZombieClass(victim) == L4D2ZombieClass_Hunter;
}

bool IsRealPlayer(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

stock bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsGrounded(int client)
{
	return (GetEntProp(client, Prop_Data, "m_fFlags") & FL_ONGROUND) > 0;
}

bool IsOnLadder(int client)
{
    return GetEntityMoveType(client) == MOVETYPE_LADDER;
}

bool IsPlayerIncapacitated(int client)
{
    return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) > 0;
}

bool IsHandingFromLedge(int client)
{
	return GetEntProp(client, Prop_Send, "m_isHangingFromLedge") != 0 || GetEntProp(client, Prop_Send, "m_isFallingFromLedge") != 0;
}

bool IsPlayerGrabbed(int client)
{
	if (GetEntProp(client, Prop_Send, "m_pummelAttacker") > 0) return true;
	if (GetEntProp(client, Prop_Send, "m_carryAttacker") > 0) return true;
	if (GetEntProp(client, Prop_Send, "m_pounceAttacker") > 0) return true;
	if (GetEntProp(client, Prop_Send, "m_jockeyAttacker") > 0) return true;
	if (GetEntProp(client, Prop_Send, "m_tongueOwner") > 0) return true;
	return false;
}