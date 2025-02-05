﻿Init_log()
{
	local
	global vars, settings

	If !IsObject(vars.log.file) ;at script-startup
	{
		vars.log.file := FileOpen(vars.log.file_location, "r", "UTF-8")
		log_content := vars.log.file.Read(), log_content := SubStr(log_content, StrLen(log_content) * 0.75), log_content := SubStr(log_content, InStr(log_content, "`n") + 1)
	}
	Else log_content := LLK_FileRead(vars.log.file_location, 1, "65001"), log_content := SubStr(log_content, StrLen(log_content) * 0.5), log_content := SubStr(log_content, InStr(log_content, "`n") + 1) ;when specifying "active character" in the settings menu

	Loop, Parse, log_content, `n ;extract relevant lines only
	{
		If (A_Index = 1)
			log_content := ""
		If LLK_PatternMatch(A_LoopField, "", ["Generating level ", " : ", ".login.", "*****"])
			log_content .= A_LoopField "`n"
	}

	vars.log.parsing := "areaID, areaname, areaseed, arealevel, areatier, act, level, date_time"
	Loop, Parse, % vars.log.parsing, `,, %A_Space%
		vars.log[A_LoopField] := ""
	
	log_length := StrLen(log_content), settings.general.character := LLK_IniRead("ini\config.ini", "settings", "active character")
	check := Blank(settings.general.character) ? 0 : InStr(log_content, " " settings.general.character " (")
	
	While !vars.log.areaID || !vars.log.level ;parse log until current area and level was found
	{
		log_chunk := SubStr(log_content, 1 - 5000*A_Index, 5500), log_chunk := SubStr(log_chunk, InStr(log_chunk, "`n") + 1) ;break up log into smaller chunks of 5000 characters (with 10% buffer to avoid incomplete lines)
		While (SubStr(log_chunk, 0) != "`r") ;remove incomplete line at the end
			log_chunk := SubStr(log_chunk, 1, -1)
		log_chunk := SubStr(log_chunk, 1, -1)

		If !settings.general.lang_client ;check if the current client-language is supported, i.e. if any available language-pack matches the client.txt
			LangClient(log_chunk)

		If vars.log.areaID && !check || (5000*A_Index >= log_length) ;break if character could not be found
			Break
		If vars.log.areaID && !InStr(log_chunk, " " settings.general.character " (") ;skip chunk if it doesn't contain level-up messages
			Continue

		LogParse(log_chunk, areaID, areaname, areaseed, arealevel, areatier, act, level, date_time) ;pass log-chunk to parse-function to extract the required information: the info is returned via ByRef variables
		Loop, Parse, % vars.log.parsing, `,, %A_Space%
			If Blank(vars.log[A_LoopField]) && !Blank(%A_LoopField%)
				vars.log[A_LoopField] := %A_LoopField% ;store parsed info globally (only once, and as close to the end of the log as possible)
	}
	vars.log.level := !vars.log.level ? 0 : vars.log.level, settings.general.lang_client := settings.general.lang_client ? settings.general.lang_client : "unknown"
}

LogLoop(mode := 0)
{
	local
	global vars, settings
	static button_color
	
	Critical
	If settings.qol.alarm && !vars.alarm.drag && vars.alarm.timestamp && (vars.alarm.timestamp <= A_Now || vars.alarm.toggle)
		Alarm()

	guide := vars.leveltracker.guide ;short-cut variable
	If !WinActive("ahk_group poe_ahk_window") || !vars.log.file_location || !WinExist("ahk_group poe_window")
		Return

	If IsObject(vars.maptracker)
		vars.maptracker.hideout := MaptrackerTowncheck() ? 1 : 0 ;flag to determine if the player is using a portal to re-enter the map (as opposed to re-entering from side-content)

	log_content := vars.log.file.Read(), level0 := vars.log.level
	If !Blank(log_content)
	{
		LogParse(log_content, areaID, areaname, areaseed, arealevel, areatier, act, level, date_time)
		Loop, Parse, % vars.log.parsing, `,, %A_Space%
		{
			If !Blank(%A_LoopField%)
				vars.log[A_LoopField] := %A_LoopField%
			If (A_Index = 1) && !Blank(%A_LoopField%)
				vars.log.areaname := "" ;make it blank because there sometimes is a desync between it and areaID, i.e. they are parsed in two separate loop-ticks
		}
		If (!Blank(areaID) && (areaID != vars.leveltracker.guide.target_area) || IsNumber(level) && (level0 != level)) && WinExist("ahk_id "vars.hwnd.leveltracker.main) ;player has leveled up or moved to a different location: update overlay for zone-layouts, exp-gain, and act clarifications
			LeveltrackerProgress(1)
		If settings.qol.alarm && vars.alarm.timestamp && (areaID = "1_1_1") ;for oni-goroshi farming: re-entering Twilight Strand resets timer to 0:00
			vars.alarm.timestamp := A_Now

		If settings.qol.lab && InStr(areaID, "labyrinth_airlock") ;entering Aspirants' Plaza: reset previous lab-progress (if there is any)
			Lab("init")
		Else If settings.qol.lab && areaname && (InStr(vars.log.areaID, "labyrinth_") && !LLK_PatternMatch(vars.log.areaID, "", ["Airlock", "_trials_"]) || InStr(areaID, "labyrinth_") && !LLK_PatternMatch(areaID, "", ["Airlock", "_trials_"])) ;entering a new room
		{
			For index, room in vars.lab.rooms ;go through previously-entered rooms to check if player is backtracking or not
				If (room.name = areaname && room.seed = vars.log.areaseed)
				{
					check := index
					Break
				}
			If check
				Lab("backtrack", check)
			Else If LLK_HasVal(vars.lab.exits.names, areaname) ;check which adjacent room has been entered
				For index, room in vars.lab.exits.names
					If (room = areaname) && Blank(vars.lab.rooms[vars.lab.exits.numbers[index]].seed)
					{
						Lab("progress", vars.lab.exits.numbers[index])
						Break
					}
		}
	}
	
	If mode
		Return

	If settings.qol.lab && InStr(vars.log.areaID, "labyrinth_") && !InStr(vars.log.areaID, "Airlock") && vars.log.areaseed && vars.lab.rooms.Count() && !vars.lab.rooms[vars.lab.room.1].seed
		vars.lab.rooms[vars.lab.room.1].seed := vars.log.areaseed, vars.lab.room.3 := vars.log.areaseed

	If settings.features.leveltracker && (A_TickCount > vars.leveltracker.last_manual + 2000) && vars.hwnd.leveltracker.main && (vars.log.areaID = vars.leveltracker.guide.target_area) && !vars.leveltracker.fast ;advance the guide when entering target-location
	{
		Leveltracker("+")
		If vars.leveltracker.overlays
			LeveltrackerOverlays()
	}
	
	If settings.features.mapinfo && vars.mapinfo.expedition_areas && vars.log.areaname && LLK_HasVal(vars.mapinfo.expedition_areas, vars.log.areaname) && !vars.mapinfo.active_map.expedition_filter
	{
		Loop, % vars.mapinfo.categories.Count()
		{
			parse := InStr(vars.mapinfo.categories[A_Index], "(") ? SubStr(vars.mapinfo.categories[A_Index], 1, InStr(vars.mapinfo.categories[A_Index], "(") - 2) : vars.mapinfo.categories[A_Index]
			If LLK_HasVal(vars.mapinfo.expedition_areas, parse) && (parse != vars.log.areaname)
				vars.mapinfo.categories[A_Index] := ""
		}
		vars.mapinfo.active_map.name := LangTrans("maps_logbook") ": " vars.log.areaname, vars.mapinfo.active_map.expedition_filter := 1
	}

	MaptrackerTimer()
	LeveltrackerTimer()

	If settings.leveltracker.geartracker && vars.leveltracker.gear_ready && WinExist("ahk_id "vars.hwnd.leveltracker_button.main)
	{
		button_color := (button_color = "Lime") ? "Aqua" : "Lime"
		Gui, leveltracker_button: Color, % button_color
	}
	Else If (!vars.leveltracker.gear_ready || !settings.leveltracker.geartracker) && (button_color = "Lime")
	{
		Gui, leveltracker_button: Color, Aqua
		button_color := "Aqua"
	}
}

LogParse(content, ByRef areaID, ByRef areaname, ByRef areaseed, ByRef arealevel, ByRef areatier, ByRef act, ByRef level, ByRef date_time)
{
	local
	global vars, settings, db

	Loop, Parse, content, `n, % "`r" vars.lang.system_fullstop.1
	{
		If LLK_PatternMatch(A_LoopField, "", vars.log.skip)
			Continue
		
		If InStr(A_LoopField, "Generating level ", 1)
		{
			parse := SubStr(A_Loopfield, InStr(A_Loopfield, "area """) + 6), areaID := SubStr(parse, 1, InStr(parse, """") -1) ;store PoE-internal location name in var
			areaseed := SubStr(A_Loopfield, InStr(A_Loopfield, "with seed ") + 10), areaname := ""
			date_time := SubStr(A_LoopField, 1, InStr(A_LoopField, " ",,, 2) - 1)
			act := db.leveltracker.areas[areaID].act ;store current act
			arealevel := parse := SubStr(A_LoopField, InStr(A_LoopField, "level ") + 6, InStr(A_LoopField, " area """) - InStr(A_LoopField, "level ") - 6)
			If (parse - 67 > 0)
				areatier := (parse - 67 < 10 ? "0" : "") parse - 67
			Else areatier := arealevel
		}
		Else If InStr(A_LoopField, " connected to ") && InStr(A_LoopField, ".login.") || InStr(A_LoopField, "*****")
			areaID := "login"

		If LangMatch(A_LoopField, vars.lang.log_enter)
			parse := SubStr(A_LoopField, InStr(A_LoopField, vars.lang.log_enter.1)), areaname := LLK_StringCase(LangTrim(parse, vars.lang.log_enter, LangTrans("log_location")))

		If !Blank(settings.general.character) && InStr(A_LoopField, " " settings.general.character " ") && LangMatch(A_LoopField, vars.lang.log_level)
		{
			level := SubStr(A_Loopfield, InStr(A_Loopfield, vars.lang.log_level.1)), level := LangTrim(level, vars.lang.log_level)
			If settings.leveltracker.geartracker && vars.hwnd.geartracker.main
				GeartrackerGUI("refresh")
		}

		If settings.features.maptracker && (vars.log.areaID = vars.maptracker.map.id) && (LangMatch(A_LoopField, vars.lang.log_slain) || LangMatch(A_LoopField, vars.lang.log_suicide))
			vars.maptracker.map.deaths += 1

		If settings.features.maptracker && settings.maptracker.kills && vars.maptracker.refresh_kills && LangMatch(A_LoopField, vars.lang.log_killed)
		{
			parse := SubStr(A_LoopField, InStr(A_LoopField, vars.lang.log_killed.1)), parse := LangTrim(parse, vars.lang.log_killed)
			Loop, Parse, parse
				parse := (A_Index = 1) ? "" : parse, parse .= IsNumber(A_LoopField) ? A_LoopField : ""
			If (vars.maptracker.refresh_kills = 1)
				vars.maptracker.map.kills := [parse], LLK_ToolTip(LangTrans("maptracker_kills", 2),,,,, "Lime"), vars.tooltip_mouse := "", vars.maptracker.refresh_kills := 2
			Else If (vars.maptracker.refresh_kills > 1) && MaptrackerTowncheck()
				vars.maptracker.map.kills.2 := parse, LLK_ToolTip(LangTrans("maptracker_kills", 2),,,,, "Lime"), vars.maptracker.refresh_kills := 3
		}

		If settings.features.maptracker && settings.maptracker.mechanics && vars.maptracker.map.id && (vars.log.areaID = vars.maptracker.map.id)
			MaptrackerParseDialogue(A_LoopField)
	}
}
