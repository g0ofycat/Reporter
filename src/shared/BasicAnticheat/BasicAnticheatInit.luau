--!strict

local BasicAnticheat = {}

--======================
-- // SERVICES
--======================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--======================
-- // MODULES
--======================

local Reporter = require(script.Parent.Parent.Reporter.ReporterInit)

local Config = require(script.Parent.Config)

--======================
-- // TYPES
--======================

export type PlayerData = {
	lastPos: Vector3,
	lastCheck: number,
	lastReport: number,
	heartbeat: RBXScriptConnection
}

--======================
-- // DATA
--======================

BasicAnticheat.PlayerData = {} :: { [number]: PlayerData }
BasicAnticheat.ViolationCounts = {} :: { [number]: number }

--======================
-- // PRIVATE API
--======================

-- isValidPosition(): Validates if a player's position change is legitimate
-- @param player: The player being checked
-- @param newPosition: Current position
-- @param oldPosition: Previous position (can be nil)
-- @param dt: Delta time since last check
-- @return isValid: Boolean indicating if position is valid
-- @return reason: String describing violation type
local function isValidPosition(player: Player, newPosition: Vector3, oldPosition: Vector3?, dt: number): (boolean, string?)
	if not oldPosition then 
		return true
	end

	local horizontalDist = Vector3.new(
		newPosition.X - oldPosition.X, 
		0, 
		newPosition.Z - oldPosition.Z
	).Magnitude

	local horizontalSpeed = horizontalDist / dt
	local heightGain = (newPosition.Y - oldPosition.Y) / dt

	if horizontalSpeed > Config.ANTI_CHEAT.MAX_SPEED then
		return false, "Speed detection"
	end

	if horizontalDist > Config.ANTI_CHEAT.MAX_TELEPORT_DISTANCE then
		return false, "Teleport detection"
	end

	if heightGain > Config.ANTI_CHEAT.MAX_HEIGHT_GAIN then
		return false, "Flying detection"
	end

	return true
end

-- recordViolation(): Records a violation for the specified player
-- @param player: The player who committed a violation
-- @param reason: String describing the violation reason
local function recordViolation(player: Player, reason: string): ()
	BasicAnticheat.ViolationCounts[player.UserId] = (BasicAnticheat.ViolationCounts[player.UserId] or 0) + 1
	warn(string.format("Anti-cheat violation: %s (%d) - %s", player.Name, player.UserId, reason))

	local playerData = BasicAnticheat.PlayerData[player.UserId]

	if playerData then
		local now = tick()
	
		if now - playerData.lastReport >= Config.ANTI_CHEAT.REPORT_COOLDOWN and BasicAnticheat.ViolationCounts[player.UserId] < Config.ANTI_CHEAT.VIOLATION_LIMIT then
			warn(string.format("Now Reporting %s for %s", player.Name, reason))
			Reporter.Report(player, Config.ANTI_CHEAT.RECORD_TIME, reason)
			playerData.lastReport = now
		elseif BasicAnticheat.ViolationCounts[player.UserId] >= Config.ANTI_CHEAT.VIOLATION_LIMIT then
			local config: BanConfigType = {
				UserIds = { player.UserId },
				Duration = 999,
				DisplayReason = "[ANTICHEAT]: You have been banned. Appeal in the community server.",
				PrivateReason = reason,
				ExcludeAltAccounts = false,
				ApplyToUniverse = true,
			}

			local success, err = pcall(function()
				return Players:BanAsync(config)
			end)
			
			if success then
				print(`recordViolation(): {player.UserId} has been banned.`)
			else
				warn(`recordViolation(): Failed to ban {player.UserId}: {err}.`)
			end
		end
	end
end

-- monitorPlayer(): Sets up monitoring for a specific player
-- @param player: The player to monitor
local function monitorPlayer(player: Player): ()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: Part

	if BasicAnticheat.PlayerData[player.UserId] and BasicAnticheat.PlayerData[player.UserId].heartbeat then
		BasicAnticheat.PlayerData[player.UserId].heartbeat:Disconnect()
	end

	local data: PlayerData = {
		lastPos = root.Position,
		lastCheck = tick(),
		lastReport = 0,
		heartbeat = nil :: any,
	}
	
	BasicAnticheat.PlayerData[player.UserId] = data

	data.heartbeat = RunService.Heartbeat:Connect(function()
		if not player.Parent or not character.Parent then
			if data.heartbeat then
				data.heartbeat:Disconnect()
			end
			return
		end

		local now = tick()
		local dt = now - data.lastCheck

		if dt < Config.ANTI_CHEAT.CHECK_INTERVAL then 
			return 
		end

		local newPos = root.Position
		local valid, reason = isValidPosition(player, newPos, data.lastPos, dt)

		if not valid and reason then
			recordViolation(player, reason)
		end

		data.lastPos = newPos
		data.lastCheck = now
	end)
end

--======================
-- // PUBLIC API
--======================

-- Init(): Initializes the anti-cheat system
function BasicAnticheat.Init(): ()
	Players.PlayerAdded:Connect(function(player: Player)
		BasicAnticheat.ViolationCounts[player.UserId] = 0

		player.CharacterAdded:Connect(function()
			monitorPlayer(player)
		end)

		if player.Character then
			monitorPlayer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		if BasicAnticheat.PlayerData[player.UserId] and BasicAnticheat.PlayerData[player.UserId].heartbeat then
			BasicAnticheat.PlayerData[player.UserId].heartbeat:Disconnect()
		end

		BasicAnticheat.PlayerData[player.UserId] = nil
		BasicAnticheat.ViolationCounts[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		BasicAnticheat.ViolationCounts[player.UserId] = 0
		if player.Character then
			monitorPlayer(player)
		end
	end
end

-- GetViolationCount(): Gets violation count for a specific player
-- @param player: The player to check
-- @return count: Current violation count
function BasicAnticheat.GetViolationCount(player: Player): number
	return BasicAnticheat.ViolationCounts[player.UserId] or 0
end

-- ResetViolations(): Resets violation count for a specific player
-- @param player: The player to reset
function BasicAnticheat.ResetViolations(player: Player): ()
	BasicAnticheat.ViolationCounts[player.UserId] = 0
end

return BasicAnticheat