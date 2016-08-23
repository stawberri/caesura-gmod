caesura = {}

-- How much should time for everything be slowed with time stopped
caesura.PAUSED_TIME_MULTIPLIER = 0.5

--
-- React to timescale changing, and create main hook.
--

-- Store the current timescale.
caesura.timescale = 1

if SERVER then
	-- Find out if phys_timescale has changed.
	local function HasTimescaleChanged()
		local phys_timescale = GetConVarNumber( "phys_timescale" )
		if phys_timescale ~= caesura.timescale then
			-- Timescale has changed! Call hook!
			hook.Run( "caesuraTimescaleChanged",  caesura.timescale, phys_timescale ) -- Arguments: oldTimescale, newTimescale.
			caesura.timescale = phys_timescale
			umsg.Start( "c~RT" )
				umsg.Char( math.Round( math.Clamp( caesura.timescale, 0, 2 ) * 100 ) - 128 ) -- Clamp timescale from 0 to 2, then convert to char (3 sig figs)
			umsg.End()
		end
	end
	hook.Add( "Tick", "caesuraHasTimescaleChanged", HasTimescaleChanged )

	-- Send timescale to someone when they first connect
	local function SendTimescale( ply )
		umsg.Start( "c~RT", ply )
			umsg.Char( math.Round( math.Clamp( caesura.timescale, 0, 2 ) * 100 ) - 128 )
		umsg.End()
	end
	hook.Add( "PlayerInitialSpawn", "caesuraSendTimescale", SendTimescale )
end

if CLIENT then
	-- Utility function to make remapping timescale to other stuff easier.
	local function TimescaleMap( default, timeStopped )
		return math.Remap( caesura.timescale, 0, 1, timeStopped, default )
	end

	-- Apply shader effects.
	local function ScreenspaceEffect()
		-- Change colors a little.
		local colorModify = {
			["$pp_colour_addr"] = 0,
			["$pp_colour_addg"] = 0,
			["$pp_colour_addb"] = 0,
			["$pp_colour_brightness"] = TimescaleMap( 0, -0.03 ),
			["$pp_colour_contrast"] = TimescaleMap( 1, 1.12 ),
			["$pp_colour_colour"] = TimescaleMap( 1, 0.15 ),
			["$pp_colour_mulr"] = TimescaleMap( 1, 0.05 ),
			["$pp_colour_mulg"] = 0,
			["$pp_colour_mulb"] = TimescaleMap( 1, -0.05 )
		}
		DrawColorModify( colorModify )

		-- Sharpen stuff
		local sharpen = {
			["contrast"] = TimescaleMap( 0, 0.33 ),
			["distance"] = TimescaleMap( 0, 2.5 )
		}
		DrawSharpen( sharpen["contrast"], sharpen["distance"] )

		-- Bloom stuff
		local bloom = {
			["darken"] = TimescaleMap( 1, -0.1 ),
			["multiply"] = TimescaleMap( 0, 0.05 ),
			["sizeX"] = TimescaleMap( 0, 25 ),
			["sizeY"] = TimescaleMap( 0, 25 ),
			["passes"] = 0,
			["colorMultiply"] = TimescaleMap ( 0, 20 ),
			["red"] = 1,
			["green"] = 1,
			["blue"] = 1
		}
		DrawBloom( bloom["darken"], bloom["multiply"], bloom["sizeX"], bloom["sizeY"], bloom["passes"], bloom["colorMultiply"], bloom["red"], bloom["green"], bloom["blue"] )
	end

	-- Other things every tick
	local function TimeStoppedPerTick()
		-- RunConsoleCommand( "StopSound" ) -- Terrible idea. Stops time freezing sounds.
	end

	-- Timescale has just changed from normal. Time to turn on stuff.
	local function FromNormal()
		hook.Add( "RenderScreenspaceEffects", "caesuraScreenspaceEffect", ScreenspaceEffect )
		hook.Add( "Tick", "caesuraTimeStoppedTick", TimeStoppedPerTick )
	end

	-- Timescale has just changed to normal. Time to turn off stuff.
	local function ToNormal()
		hook.Remove( "RenderScreenspaceEffects", "caesuraScreenspaceEffect" )
		hook.Remove( "Tick", "caesuraTimeStoppedTick" )
	end

	-- phys_timescale has changed. Time to do stuff.
	local function TimescaleChanged( msg )
		-- Move some variables around
		local oldTimescale = caesura.timescale
		caesura.timescale = ( msg:ReadChar() + 128 ) / 100

		hook.Run( "caesuraTimescaleChanged",  oldTimescale, caesura.timescale ) -- Arguments: oldTimescale, newTimescale
		-- Unlike on server, can't do anything

		-- Find out if time has just changed to or from normal
		if oldTimescale == 1 then FromNormal()
		elseif caesura.timescale == 1 then ToNormal()
		end
	end
	usermessage.Hook( "c~RT", TimescaleChanged )
end

--
-- Create console triggers and main sound engine
--

-- Character message from this section that I'm reusing elsewhere now. (A little redundant with above)
local function CharMsg() end
local function RecMsg() end
local MiscActions = {}

if SERVER then
	local timescaleChanging = true -- Should we ignore inputs?

	-- Send off a umsg with a char (used for playing sounds)
	function CharMsg( msg, char, filter )
		umsg.Start( "c~T" .. msg, filter )
			umsg.Char( char )
		umsg.End()
	end

	local function accountForTimescale( num ) -- caesuraChained.lua sets acutal timescale to 1/3, so this is necesscary to make timed functions work.
		if caesura.timescale == 0 then return num * caesura.PAUSED_TIME_MULTIPLIER end
		return num
	end

	local function HasCaesuraPermission( ply )
		if hook.Run( "caesuraUserPermissionCheck", ply ) then
			return true
		else
			return false
		end
	end

	local soundID -- This lets me simplify logic later
	local timescaleChanging = false -- Should we ignore inputs?
	local currentlyCharging = {} -- Make a table to hold people currently charging.
	-- Handle button-press-down
	function caesura.PlusCaesura( ply, cmd, args, fullstring )
		if not HasCaesuraPermission( ply ) or timescaleChanging then return end
		CharMsg( "", 1, ply ) -- Let client know we're charging - okay if this never gets called
		local noSound = next(currentlyCharging) ~= nil
		currentlyCharging[ply] = "caesuraKeyholdTimer" .. ply:SteamID() -- This value will be used later
		if caesura.timescale ~= 0 then -- want to pause time
			ply:SetVar( "caesuraPausingTime", true )
			soundID = 2
		else
			ply:SetVar( "caesuraPausingTime", false )
			soundID = 3
		end
		if not noSound then CharMsg( "S", soundID ) CharMsg( "P", soundID ) end
		-- Make a timer to automatically cancel after 30 seconds
		timer.Create( currentlyCharging[ply], accountForTimescale( 15 ), 1, function()
			if timescaleChanging then return end
			if currentlyCharging[ply] then -- Redundant check just to be sure
				currentlyCharging[ply] = nil
				CharMsg( "P", 8, ply ) -- Play timeout sound
				if next(currentlyCharging) == nil then
					CharMsg( "S", soundID, ply ) -- Stop sound instantly for player involved
					CharMsg( "F", soundID ) -- Fade out other people
				end
			end
		end )
	end
	concommand.Add( "+caesura", caesura.PlusCaesura )

	-- Handle button-press-up
	function caesura.MinusCaesura( ply, cmd, args, fullstring )
		if not HasCaesuraPermission( ply ) then return end
		CharMsg( "", 0, ply ) -- Let client know we've stopped charging - definitely must be called
		if timescaleChanging then return end
		timescaleChanging = true
		-- Did it get canceled?
		if currentlyCharging[ply] then
			-- Remove timers since we ended early.
			for k, v in pairs( currentlyCharging ) do
				timer.Destroy( v )
			end
			CharMsg( "", 0 )
			table.Empty( currentlyCharging ) -- Cancel everyone else's charge

			CharMsg( "S", soundID ) -- Stop sound that was probably playing.
			-- Were we trying to pause time?
			if ply:GetVar( "caesuraPausingTime", true ) then
				if caesura.timescale ~= 0 then -- Has something else changed timescale?
					CharMsg( "P", 1 ) -- Play switching sound and wait a bit to match up effect with sound
					timer.Simple( .1 , function()
						RunConsoleCommand( "phys_timescale", "0" )
						timescaleChanging = false
					end )
				else
					timescaleChanging = false
				end
			else -- Does the same thing as lines above
				if caesura.timescale == 0 then
					CharMsg( "P", 4 )
					timer.Simple( accountForTimescale( .2 ) , function()
						RunConsoleCommand( "phys_timescale", "1" )
						timescaleChanging = false
					end)
				else
					timescaleChanging = false
				end
			end
		else
			timescaleChanging = false
		end
	end
	concommand.Add( "-caesura", caesura.MinusCaesura )

	-- Cancel charging
	function caesura.CancelCaesura( ply, cmd, args, fullstring )
		if not HasCaesuraPermission( ply ) then return end
		CharMsg( "", 0, ply ) -- Let client know we've stopped charging
		if currentlyCharging[ply] then
			CharMsg( "P", 5, ply )
			if not timescaleChanging then
				timer.Destroy( currentlyCharging[ply] )
				currentlyCharging[ply] = nil
				if next(currentlyCharging) == nil then
					CharMsg( "S", soundID ) -- Stop sound instantly for player involved
					CharMsg( "F", soundID ) -- Fade out for other people
				end
				return true
			end
		end
	end
	concommand.Add( "caesura_cancel", caesura.CancelCaesura )

	-- Simple Toggle
	function caesura.ToggleCaesura( ply, cmd, args, fullstring )
		if not HasCaesuraPermission( ply ) then return end
		CharMsg( "", 0 ) -- Stop all charging
		if not timescaleChanging then
			timescaleChanging = true
			-- Remove all charges and timers
			for k, v in pairs( currentlyCharging ) do
				timer.Destroy( v )
			end
			if next(currentlyCharging) ~= nil then
				CharMsg( "S", soundID ) -- Stop sound that was probably playing.
				table.Empty( currentlyCharging )
			end
			if caesura.timescale == 0 then
				CharMsg( "P", 6 )
				RunConsoleCommand( "phys_timescale", "1" )
			else
				CharMsg( "P", 7 )
				RunConsoleCommand( "phys_timescale", "0" )
			end
			timescaleChanging = false
		end
	end
	concommand.Add( "caesura", caesura.ToggleCaesura )
end

if CLIENT then
	function RecMsg( msg, callback ) -- Makes messages standarized
		return usermessage.Hook( "c~T" .. msg, callback )
	end

	local sounds = {} -- CSoundPatch, volume, pitch, autostop time (or false), fade time

	-- Make sounds. This is called in a function because there's no LocalPlayer() right when people connect.
	local function CreateSounds( msg )
		-- Timestop click
		sounds[1] = { CreateSound( LocalPlayer(), "weapons/fiveseven/fiveseven_slidepull.wav" ), 1, 185, 0.23904761904762 }

		-- Timestop charge
		sounds[2] = { CreateSound( LocalPlayer(), "ambient/machines/spin_loop.wav" ), .25, 230, false, 0.66 }

		-- Timestart charge
		sounds[3] = { CreateSound( LocalPlayer(), "npc/roller/mine/rmine_movefast_loop1.wav" ), .5, 200, false, 0.66 }

		-- Timestart sound
		sounds[4] = { CreateSound( LocalPlayer(), "weapons/aug/aug_boltslap.wav" ), 0.50, 110, 0.37006802721088 }

		-- Cancel sound
		sounds[5] = { CreateSound( LocalPlayer(), "buttons/lever7.wav" ), 1, 200, 0.25113378684807 }

		-- Toggle start sound
		sounds[6] = { CreateSound( LocalPlayer(), "weapons/scout/scout_clipin.wav" ), 1, 200, 0.35446712018141 }

		-- Toggle stop sound
		sounds[7] = { CreateSound( LocalPlayer(), "weapons/tmp/tmp_clipin.wav" ), 1, 110, 0.28866213151927 }

		-- Timeout sound
		sounds[8] = { CreateSound( LocalPlayer(), "buttons/lever8.wav" ), 1, 150, 0.53222222222222 }
	end

	-- Play sounds
	local function PlaySounds( msg )
		if next(sounds) == nil then CreateSounds() end -- Make our sound table if it doesn't exist
		local sound = sounds[msg:ReadChar()] -- Get sound out
		if sound then
			local randomPitch = math.random( sound[3] - 25, sound[3] + 25 ) -- Randomize pitches a little for variety!

			-- Speed up sounds if time is paused (and sounds are slowed)
			if caesura.timescale == 0 then
				randomPitch = randomPitch / caesura.PAUSED_TIME_MULTIPLIER
			end

			sound[1]:PlayEx( sound[2], randomPitch ) -- Play it with settings we came up with!
			if sound[4] then -- if there's a auto-ending time
				timer.Create( "caesuraSoundTimer" .. tostring( sound ), sound[4], 1, function() -- make a timer to stop it.
					if sound[5] then -- Does it have a fade time?
						sound[1]:FadeOut( sound[5] )
					else
						sound[1]:Stop()
					end
				end )
			end
		end
	end
	RecMsg( "P", PlaySounds )

	-- Manually stop sounds
	local function StopSounds( msg )
		if next(sounds) == nil then return end -- If sound table doesn't exist, don't do anything
		sound = sounds[msg:ReadChar()] -- Get sound out
		if sound then
			timer.Destroy( "caesuraSoundTimer" .. tostring( sound ) ) -- Stop auto-ending timer, since we might have a new sound by then
			sound[1]:Stop()
		end
	end
	RecMsg( "S", StopSounds )

	local function FadeOutSounds( msg )
		if next(sounds) == nil then return end
		sound = sounds[msg:ReadChar()] -- Get sound out
		if sound then
			timer.Destroy( "caesuraSoundTimer" .. tostring( sound ) ) -- Stop auto-ending timer, since we might have a new sound by then
			if sound[5] then -- Does it actually have a fade time?
				sound[1]:FadeOut( sound[5] )
			else
				sound[1]:Stop()
			end
		end
	end
	RecMsg( "F", FadeOutSounds )

	local caesuraActive = false -- Is it being held down?

	-- Handle cancelling with reload -- or any other bind!
	-- CreateClientConVar( "caesura_cancel_bind", "+reload", true )
	CreateConVar( "caesura_cancel_bind", "+reload", { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_SERVER_CAN_EXECUTE }, "Pressing this bind will cancel your current Caesura charge." )
	local function CancelCaesuraClient( ply, bind, pressed )
		if caesuraActive then
			local convar = GetConVarString( "caesura_cancel_bind" )
			if string.find( convar, "caesura" ) then
				convar = "" -- If their command contains the word caesura it would probably cause a conflict.
				RunConsoleCommand( "caesura_cancel_bind", convar )
			end
			if convar ~= "" and string.find( bind, convar ) then
				RunConsoleCommand( "caesura_cancel" )
				return true
			end
		end
	end
	hook.Add( "PlayerBindPress", "caesuraCancelCaesuraBind", CancelCaesuraClient )

	MiscActions[0] = function() caesuraActive = false end
	MiscActions[1] = function() caesuraActive = true end
	-- MiscActions[2] - Disable Server Messages
	-- MiscActions[3] - Enable Server Messages
	local function Misc( msg )
		local i = msg:ReadChar()
		if MiscActions[i] ~= nil then	
			MiscActions[i]()
		end
	end
	RecMsg( "", Misc )
end

--
-- Other things that change as a result of the timescale changing.
--

-- Some variables to keep track of what these values were
local caesuraCommandsOriginalTimescale
local caesuraCommandsOriginalGravity

-- Some variables announce that they've been changed. They're in one function here to keep track of them.
local function changeAnnouncedServerVariables(stop)
	-- CharMsg( "", 2 ) -- See Below for why this is disabled
	if stop then
		RunConsoleCommand( "ai_disabled", 1 )

		caesuraCommandsOriginalGravity = GetConVarNumber( "sv_gravity" )
		RunConsoleCommand( "sv_gravity", caesuraCommandsOriginalGravity/3 )
	else
		RunConsoleCommand( "ai_disabled", 0 )

		RunConsoleCommand( "sv_gravity", caesuraCommandsOriginalGravity )
	end
	-- CharMsg( "", 3 ) -- See Below for why this is disabled
end

-- Now this is some client code to disable and reenable that chat filter.
--[[ Doesn't actually work. - The associated console variable can't be changed via Lua
	if CLIENT then
		local chatfilter = -1
		local SERVER_MESSAGE = 8
		local NOT_SERVER_MESSAGE = bit.bnot(SERVER_MESSAGE)

		function chatfilterToggle(disableServerMessages)
			if disableServerMessages and chatfilter == -1 then
				chatfilter = GetConVarNumber( "cl_chatfilters" )
				if bit.band(chatfilter, SERVER_MESSAGE) ~= 0 then
					RunConsoleCommand( "cl_chatfilters", bit.band( chatfilter, NOT_SERVER_MESSAGE ) )
				end
			elseif chatfilter ~= -1 then
				RunConsoleCommand( "cl_chatfilters", chatfilter )
				chatfilter = -1
			end
		end
	end
	MiscActions[2] = function() chatfilterToggle(true) end -- Disable Server Messages
	MiscActions[3] = function() chatfilterToggle(false) end -- Enable Server Messages
]]


-- Enable some console commands and change timescale and stuff!
local function caesuraCommands(oldTimescale, newTimescale)
	if newTimescale == 0 then
		if SERVER then
			changeAnnouncedServerVariables(true)

			caesuraCommandsOriginalTimescale = game.GetTimeScale()
			game.SetTimeScale( caesuraCommandsOriginalTimescale * caesura.PAUSED_TIME_MULTIPLIER )
		elseif CLIENT then
			RunConsoleCommand( "ragdoll_sleepaftertime", 0 ) -- Redundant, but it's safe to make sure.
		end
	else
		if SERVER then
			changeAnnouncedServerVariables(false)

			game.SetTimeScale( caesuraCommandsOriginalTimescale )
		elseif CLIENT then
			RunConsoleCommand( "ragdoll_sleepaftertime", "5.0f" )
		end
	end
end
hook.Add( "caesuraTimescaleChanged", "caesuraCommands", caesuraCommands )

local function allNPCRagdollsAreServer( ply, npc )
	npc:SetShouldServerRagdoll( true )
end
hook.Add( "PlayerSpawnedNPC", "caesuraMakeAllNPCsServerRagdolls", allNPCRagdollsAreServer )

-- Enable some stuff that only works if cheats is enabled!
local function caesuraCheats(oldTimescale, newTimescale)
	if GetConVarNumber( "sv_cheats" ) == 1 then
		if CLIENT then
			RunConsoleCommand( "cl_phys_timescale", newTimescale ) -- Super redundant, but it's safe to make sure.
		end
	end
end
hook.Add( "caesuraTimescaleChanged", "caesuraCheats", caesuraCheats )

-- Adjust sounds for when time is stopped
local function adjustSlowdownSounds( soundData )
	-- Don't change sound data for some sounds
	if table.HasValue( { CHAN_REPLACE, CHAN_VOICE2, CHAN_VOICE_BASE }, soundData["Flags"] ) then return end

	-- Change sound data to match time slowing
	soundData["Pitch"] = soundData["Pitch"] * caesura.PAUSED_TIME_MULTIPLIER
	soundData["Volume"] = soundData["Volume"] * caesura.PAUSED_TIME_MULTIPLIER
	return true
end

-- Actually use that effect when time is stopped.
local function slowdownSounds(oldTimescale, newTimescale)
	if newTimescale == 0 then
		-- Apply sound modifications
		hook.Add( "EntityEmitSound", "caesuraSlowdownSounds", adjustSlowdownSounds )
	else
		-- Disable sound modifications
		hook.Remove( "EntityEmitSound", "caesuraSlowdownSounds" )
	end
end
hook.Add( "caesuraTimescaleChanged", "caesuraSlowdownSounds", slowdownSounds )

--
-- Checks for permissions to use caesura.
--

if SERVER then
	local function AdminPermission( ply )
		if ply:IsAdmin() then return true end
	end
	hook.Add( "caesuraUserPermissionCheck", "caesuraAdminPermission", AdminPermission )
end