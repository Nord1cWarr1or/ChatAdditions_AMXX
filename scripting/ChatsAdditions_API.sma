#include <amxmodx>
#include <reapi>

#pragma semicolon 1
#pragma ctrlchar '\'
#pragma dynamic 524288

#include <ChatsAdditions_API>


		/* ----- START SETTINGS----- */
/*	// TODO on Preprocessor logic
#tryinclude <VtcApi>
#if !defined _VtcApi_Included
	#error INSTALL:[ VTC API include ]. More info: dev-cs.ru/resources/203
#endif
*/

#define DEBUG
#if defined DEBUG
 #define DBG_BOTS 0 // Bot count for testing
#endif

/**
 *	Database type for storage gags
 *		DB_NVault,
 *		DB_JSON,  // TODO: 
 *		DB_MySQL,
 *		DB_SQLite
 */
#define DATABASE_TYPE DB_SQLite

		/* ----- END OF SETTINGS----- */










/* Forwards pointers */
new g_pFwd_Client_Say,
	g_pFwd_Client_SayTeam,
	g_pFwd_Client_Voice;

new g_PlayersGags[MAX_PLAYERS + 1][gag_s];

static const Float: UPDATER_FREQ = 3.0;

#if !defined DATABASE_TYPE
	#error Please uncomment DATABASE_TYPE and select!
#endif

// Select the db driver
#if DATABASE_TYPE == DB_NVault
	#include <ChatAdditions_inc/CA_NVault>
#elseif DATABASE_TYPE == DB_JSON
	// #include <ChatAdditions_inc/CA_JSON>
#elseif DATABASE_TYPE == DB_MySQL
	#include <ChatAdditions_inc/CA_MySQL>
#elseif DATABASE_TYPE == DB_SQLite
	#include <ChatAdditions_inc/CA_SQLite>
#endif

new const VERSION[] = "1.0.0-alpha";

public plugin_init()
{
	/* Hooks */
		// Text
	register_clcmd("say", "ClCmd_Hook_Say");
	register_clcmd("say_team", "ClCmd_Hook_SayTeam");

		// Voice
	RegisterHookChain(RG_CSGameRules_CanPlayerHearPlayer, "CSGameRules_CanPlayerHearPlayer", .post = false);

	set_task(UPDATER_FREQ, "Gags_Thinker", .flags = "b");

#if defined DEBUG && defined DBG_BOTS
  #if DBG_BOTS != 0
	DBG_AddBots(.count = DBG_BOTS);
  #endif
#endif
}

public plugin_end()
{
	Storage_Destroy();

	DestroyForward(g_pFwd_Client_Say);
	DestroyForward(g_pFwd_Client_SayTeam);
	DestroyForward(g_pFwd_Client_Voice);
}

public plugin_natives()
{
	register_library("Chats_Additions_API");
	register_native("ca_set_user_gag", "native_ca_set_user_gag");
	register_native("ca_get_user_gag", "native_ca_get_user_gag");
	register_native("ca_remove_user_gag", "native_ca_remove_user_gag");

	register_native("ca_get_storage_type", "native_ca_get_storage_type");
}

public plugin_precache()
{
	register_plugin(
		.plugin_name	= "Chats Additions API",
		.version		= VERSION,
		.author			= "Sergey Shorokhov"
	);

	// Find in db drivers inc. ( CA_API_NVault | CA_API_SQLx | ... )
	if(!Init_Storage())
	{
		set_fail_state("[ERROR]: Storage Driver not loaded!\n\
			DATABASE_TYPE = '%s'", DB_Names[DATABASE_TYPE]
		);
	}

	g_pFwd_Client_Say = CreateMultiForward("CA_Client_Say", ET_STOP, FP_CELL);
	g_pFwd_Client_SayTeam = CreateMultiForward("CA_Client_SayTeam", ET_STOP, FP_CELL);
	g_pFwd_Client_Voice = CreateMultiForward("CA_Client_Voice", ET_STOP, FP_CELL, FP_CELL);
}


public Gags_Thinker()
{
	static aPlayersId[MAX_PLAYERS], iCount;

#if defined DEBUG
// +bots in counter
	get_players(aPlayersId, iCount, .flags = "h");
#else
	get_players(aPlayersId, iCount, .flags = "ch");
#endif

	for(new i; i < iCount; i++)
	{
		static pPlayer;	pPlayer = aPlayersId[i];

		check_user_gag(pPlayer);
	}
}


/** HOOKS -> */
	// Client use "say" command
public ClCmd_Hook_Say(const pPlayer)
{
	static retVal;
	ExecuteForward(g_pFwd_Client_Say, retVal, pPlayer);

	return retVal == PLUGIN_HANDLED ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

	// Client use "say_team" command
public ClCmd_Hook_SayTeam(const pPlayer)
{
	static retVal;
	ExecuteForward(g_pFwd_Client_SayTeam, retVal, pPlayer);

	return retVal == PLUGIN_HANDLED ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

	// Engine Set client VoiceMask
public CSGameRules_CanPlayerHearPlayer(const listener, const sender) {
	if(listener == sender)
		return HC_CONTINUE;

	new bool: bCanHear = true;

	new retVal;
	ExecuteForward(g_pFwd_Client_Voice, retVal, listener, sender);
	if(retVal == PLUGIN_HANDLED)
		bCanHear = false;
	
	if(!bCanHear) {
		SetHookChainReturn(ATYPE_BOOL, bCanHear);
		return HC_BREAK;
	}

	return HC_CONTINUE;
}

/** <- HOOKS */

/** API -> */
public native_ca_set_user_gag(pPlugin, iParams)
{
	enum { Player = 1, m_GagData };

	static pPlayer; pPlayer = get_param(Player);
	static aGagData[gag_s]; get_array(m_GagData, aGagData, sizeof aGagData);

	// Sets next ungag time
	aGagData[_ExpireTime] += get_systime();
	aGagData[Player] = pPlayer;

	save_user_gag(pPlayer, aGagData);
}

save_user_gag(pPlayer, aGagData[gag_s])
{
	// static szAuthId[32], szIP[32], szName[MAX_NAME_LENGTH];
	get_user_authid(pPlayer, aGagData[_AuthId], 31);
	get_user_ip(pPlayer, aGagData[_IP], 31, .without_port = true);
	// get_user_name(pPlayer, szName, charsmax(szName));
	aGagData[_Player] = pPlayer;
	get_user_authid(aGagData[_AdminId], aGagData[_AdminAuthId], 31);
	get_user_ip(aGagData[_AdminId], aGagData[_AdminIP], 31, .without_port = true);

	Player_GagSet(pPlayer, aGagData);

	// Save player gag on Storage
	save_to_storage(aGagData[_AuthId], aGagData[_IP], aGagData);

	client_cmd(pPlayer, "-voicerecord");
}

public native_ca_get_user_gag(pPlugin, iParams) {
	enum { Player = 1, m_GagData };

	new pPlayer = get_param(Player);

	if(g_PlayersGags[pPlayer][_bitFlags] != m_REMOVED) {
		set_array(m_GagData, g_PlayersGags[pPlayer], sizeof g_PlayersGags[]);
		return true;
	}

	return false;
}

public native_ca_remove_user_gag(pPlugin, iParams)
{
	enum { Player = 1 };

	static pPlayer; pPlayer = get_param(Player);
	Player_GagReset(pPlayer);
}

public DB_Types: native_ca_get_storage_type(pPlugin, iParams)
{
	return DATABASE_TYPE;
}


load_user_gag(pPlayer)
{
	static any: aGagData[gag_s];

	static szIP[32]; get_user_ip(pPlayer, szIP, charsmax(szIP), .without_port = true);
	static szAuthId[32]; get_user_authid(pPlayer, szAuthId, charsmax(szAuthId));
	aGagData[_Player] = pPlayer;

	load_from_storage(szAuthId, szIP, aGagData);
}

check_user_gag(pPlayer)
{
	static iSysTime; iSysTime = get_systime();

	if(g_PlayersGags[pPlayer][_bitFlags] != m_REMOVED && g_PlayersGags[pPlayer][_ExpireTime] < iSysTime)
	{
		// The user has expired gag - should reset
		g_PlayersGags[pPlayer][_bitFlags] = m_REMOVED;

			// TODO
			// Reset user gag
		// save_user_gag(pPlayer, aGagData);
#if defined DEBUG
		server_print("\n   - check_user_gag() USER[%i] HAS EXPIRED GAG - RESETED!", pPlayer);
#endif
	}
}

/** <- API */

/** On Players Events -> */
	// Client Connected & Authorized 
public client_putinserver(pPlayer)
{
	// Get player gag from Storage
	load_user_gag(pPlayer);
}

	// The client left the server
public client_disconnected(pPlayer)
{
	GagData_Reset(g_PlayersGags[pPlayer]);
}
/** <- On Players Events */

stock Player_GagSet(pPlayer, aGagData[])
{
	g_PlayersGags[pPlayer][_bitFlags]		= any: aGagData[_bitFlags];
	g_PlayersGags[pPlayer][_Reason]			= any: aGagData[_Reason];
	g_PlayersGags[pPlayer][_ExpireTime]		= any: aGagData[_ExpireTime];
}

stock Player_GagReset(pPlayer)
{
	GagData_Reset(g_PlayersGags[pPlayer]);

	// Remove player gag from Storage
	get_user_authid(pPlayer, g_PlayersGags[pPlayer][_AuthId], 31);
	get_user_ip(pPlayer, g_PlayersGags[pPlayer][_IP], 31, .without_port = true);
	remove_from_storage(g_PlayersGags[pPlayer][_AuthId], g_PlayersGags[pPlayer][_IP], g_PlayersGags[pPlayer]);
}

stock GetFnLog(Fn[], aGagData[gag_s], szAuthId[])
{
	server_print("	%s(%s) ->\n\
		\t Flags='%i'\n\
		\t Reason='%s'\n\
		\t Time='%i", Fn, szAuthId,
		aGagData[_bitFlags], aGagData[_Reason], aGagData[_ExpireTime]
	);
}

// Debug stocks
#if defined DBG_BOTS
stock DBG_AddBots(count)
{
	set_cvar_num("bot_quota", count);

	server_cmd("bot_stop 1");
}
#endif

public plugin_cfg()
	PluginAnnouncement();

public PluginAnnouncement()
{
	new szMsg[2048], szCurrentTime[32], iLen;
	get_time("%m/%d/%Y - %H:%M:%S", szCurrentTime, charsmax(szCurrentTime));

#define FMT_ADD iLen += formatex(szMsg[iLen], charsmax(szMsg) - iLen
// Start
	iLen = formatex(szMsg, charsmax(szMsg), "\n ###\n\n");

	FMT_ADD, "\
			\t\t .[ - Chat Additions API - ].\n\
		\t Version: '%s' (compiled: %s) \n\
		\t Storage Used: '%s' \n\
		\t Current Time: '%s' \n\
	", VERSION, __DATE__, DB_Names[DATABASE_TYPE], szCurrentTime
	);
#if defined DEBUG
	FMT_ADD, "\
		\t\t[ Debug - ENABLED ]:\n\
	");

 #if defined DBG_BOTS
  #if DBG_BOTS != 0
	FMT_ADD, "\
		 \t    DBG_BOTS = %i\n\
	", DBG_BOTS);
  #endif
 #endif
#endif

// Ending
	FMT_ADD, "\n ### \n");

	server_print(szMsg);
}