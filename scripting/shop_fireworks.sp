#pragma semicolon 1

#include <sdktools>
#include <shop>
#include <csgo_colors>
#include <fireworks_core>

#pragma newdecls required

int g_iCvPlayerCooldown,
	g_iCvCooldown,
	g_iCvRoundUses,
	g_iCvMapUses;

int g_iRoundUsesCount[MAXPLAYERS+1], g_iMapUsesCount[MAXPLAYERS+1], g_iTotalFireworks;
Handle g_hCooldownTimer[MAXPLAYERS+1], g_hCommonCooldownTimer;
ConVar cvar_PlayerCooldown, cvar_Cooldown, cvar_RoundUses, cvar_MapUses;
StringMap g_hTrie;

public Plugin myinfo = { name = "[Shop] Fireworks", author = "T1MOXA", version = "1.0.0", url = "http://justskill.pro/" };

public void OnPluginStart() {
	g_hTrie = new StringMap();

	cvar_PlayerCooldown = CreateConVar("sm_shop_fireworks_player_cooldown", "60", "Время между использованием для одного игрока.");
	cvar_PlayerCooldown.AddChangeHook(OnConVarChange);
	g_iCvPlayerCooldown = cvar_PlayerCooldown.IntValue;
	
	cvar_Cooldown = CreateConVar("sm_shop_fireworks_common_cooldown", "30", "Время между использованием для всех игроков.");
	cvar_Cooldown.AddChangeHook(OnConVarChange);
	g_iCvCooldown = cvar_Cooldown.IntValue;
	
	cvar_RoundUses = CreateConVar("sm_shop_fireworks_max_round_uses", "2", "Макисмальное количесво использований игроком за раунд.");
	cvar_RoundUses.AddChangeHook(OnConVarChange);
	g_iCvRoundUses = cvar_RoundUses.IntValue;
	
	cvar_MapUses = CreateConVar("sm_shop_fireworks_max_map_uses", "10", "Макисмальное количесво использований игроком за карту.");
	cvar_MapUses.AddChangeHook(OnConVarChange);
	g_iCvMapUses = cvar_MapUses.IntValue;
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	AutoExecConfig(true, "shop_fireworks");
	
	if (Shop_IsStarted()) Shop_Started();
}

public void OnConVarChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if (cvar == cvar_PlayerCooldown) g_iCvPlayerCooldown = cvar.IntValue;
	else if (cvar == cvar_Cooldown) g_iCvCooldown = cvar_Cooldown.IntValue;
	else if (cvar == cvar_RoundUses) g_iCvRoundUses = cvar_RoundUses.IntValue;
	else if (cvar == cvar_MapUses) g_iCvMapUses = cvar_MapUses.IntValue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) { 
	for(int i = 1; i <= MaxClients; i++) g_iRoundUsesCount[i] = 0;
	g_iTotalFireworks = 0;
}

public void Shop_Started() {
	if (!Fireworks_IsFireworksLoaded()) {
		SetFailState("Плагин Fireworks Core не загружен.");
		return;
	}
	
	KeyValues hKv = new KeyValues("Fireworks");
	CategoryId iCategoryID = Shop_RegisterCategory("Fireworks", "Фейерверки", "");
	
	char sPath[PLATFORM_MAX_PATH];
	Shop_GetCfgFile(sPath, sizeof(sPath), "fireworks.ini");
	if (!FileToKeyValues(hKv, sPath)) SetFailState("Файл конфигурации не найден %s", sPath);
	
	char sName[64], sSectionName[64], sDescription[128];
	hKv.Rewind();

	if (hKv.GotoFirstSubKey()) {
		do {
			if (hKv.GetSectionName(sSectionName, sizeof(sSectionName))) {
				if (!Fireworks_IsFireworkExists(sSectionName)) {
					LogError("Файл конфигурации для %s не найден!", sSectionName);
					continue;
				}
				
				hKv.GetString("name", sName, sizeof(sName));
				g_hTrie.SetString(sName, sSectionName);
				hKv.GetString("description", sDescription, sizeof(sDescription), "");
				
				Shop_StartItem(iCategoryID, sName);
				Shop_SetInfo(sName, sDescription, hKv.GetNum("price", -1), hKv.GetNum("sell_price", -1), Item_Finite, 1, hKv.GetNum("gold_price", -1), hKv.GetNum("gold_sell_price", -1));
				Shop_SetCallbacks(_, OnUseItem);
				Shop_EndItem();
			}
		}
		while (hKv.GotoNextKey());
	}
	delete hKv;
}

public ShopAction OnUseItem(int iClient, CategoryId category_id, const char[] category, ItemId item_id, const char[] sItem, bool isOn, bool elapsed) {
	if (!IsClientInGame(iClient)) {
		return Shop_Raw;
	}
	
	if (g_iTotalFireworks > 2) {
		CGOPrintToChat(iClient, "{OLIVE}В ближайшее время было создано слишком много фейерверков. Попробуйте позже.");
		return Shop_Raw;
	}
	
	if (!IsPlayerAlive(iClient)) {
		CGOPrintToChat(iClient, "{LIGHTRED}Вы должны быть живы чтоб использовать фейерверки!");
		return Shop_Raw;
	}
	
	if (g_iCvRoundUses != 0 && g_iRoundUsesCount[iClient] >= g_iCvRoundUses) {
		CGOPrintToChat(iClient, "{LIGHTRED}Вы исчерпали свой лимит на фейерверки в этом раунде.");
		return Shop_Raw;
	}
	
	if (g_iCvMapUses != 0 && g_iMapUsesCount[iClient] >= g_iCvMapUses) {
		CGOPrintToChat(iClient, "{LIGHTRED}Вы исчерпали свой лимит на фейерверки на этой карте.");
		return Shop_Raw;
	}
	
	if(g_hCommonCooldownTimer) {
		CGOPrintToChat(iClient, "{OLIVE}Не так давно кто-то уже запускал салют, подождите еще немного :)");
		return Shop_Raw;
	}
	
	if(g_hCooldownTimer[iClient]) {
		CGOPrintToChat(iClient, "{OLIVE}Не так давно вы уже запускали салют, подождите еще немного :)");
		return Shop_Raw;
	}
	
	Shop_ToggleClientCategoryOff(iClient, category_id);
	
	char sName[64];
	if (g_hTrie.GetString(sItem, sName, sizeof(sName))) {
		float fOrigin[3], fAngles[3];
		if (GetClientViewOriginAndAngles(iClient, fOrigin, fAngles)) {
			Fireworks_SpawnFirework(sName, fOrigin, fAngles);
		}
		
		if(g_iCvPlayerCooldown) g_hCooldownTimer[iClient] = CreateTimer(float(g_iCvPlayerCooldown), PrivateCooldownTimer, iClient);
		if(g_iCvCooldown) g_hCommonCooldownTimer = CreateTimer(float(g_iCvCooldown), CooldownTimer);

		g_iRoundUsesCount[iClient]++;
		g_iMapUsesCount[iClient]++;
		g_iTotalFireworks++;
		CGOPrintToChat(iClient, "%t", "{GREEN}Вы использовали салют {DEFAULT}w(°ｏ°)w");
		
		CreateTimer(20.0, Timer_DecreaseTotal);
		
		return Shop_UseOn;
	}

	CGOPrintToChat(iClient, "%t", "Error", sItem);
	
	return Shop_Raw;
}

public Action Timer_DecreaseTotal(Handle hTimer) { g_iTotalFireworks--; }
		
bool GetClientViewOriginAndAngles(const int iClient, float[3] vOrigin, float[3] vAngles) {
	GetClientEyePosition(iClient, vOrigin);
	GetClientEyeAngles(iClient, vAngles);
	
	TR_TraceRayFilter(vOrigin, vAngles, MASK_SOLID, RayType_Infinite, TR_DontHitSelf, iClient);

	if (TR_DidHit(null)) {
		TR_GetEndPosition(vOrigin, null);
		return true;
	}
	
	return false;
}

public bool TR_DontHitSelf(int iEntity, int iMask, any iData) { return ( iEntity != iData ); }

public Action PrivateCooldownTimer(Handle hTimer, any iClient) {
	if(!g_hCommonCooldownTimer) CGOPrintToChat(iClient, "%t", "Ready");
	g_hCooldownTimer[iClient] = null;
}

public Action CooldownTimer(Handle hTimer) { g_hCommonCooldownTimer = null; }

public void OnClientDisconnect(int iClient) {
	if(g_hCooldownTimer[iClient]) KillTimer(g_hCooldownTimer[iClient]); g_hCooldownTimer[iClient] = null;
	g_iRoundUsesCount[iClient] = 0;
	g_iMapUsesCount[iClient] = 0;
}

public void OnMapStart() {
	for(int i; i <= MaxClients; i++) {
		g_iRoundUsesCount[i] = 0;
		g_iMapUsesCount[i] = 0;
	}
}

public void OnPluginEnd() { Shop_UnregisterMe(); }
