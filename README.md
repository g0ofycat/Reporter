# Reporter Module

*A Roblox anti-cheat reporting system to track, record, and analyze player movements. **Also includes full history of all past reports on a player.***

## Features

- Record player movements for a configurable duration
- Automatically score players for potential exploits
- Save and retrieve reports from a DataStore
- Maintain player-specific report history
- Replay recorded movements for review
- Cancel or delete active reports

## Overview

The module uses **two Datastores**: `ReportStores` and `ReportHistory`.

- **ReportStores:** An unordered DataStore storing all reports. The key is the **unique report ID**.
- **ReportHistory:** Stores each player’s report history. The key format is `"Player_"..Player.UserId`.

It's also noted that the module that is being showcased is also paired with a Anticheat Implementation **(BasicAnticheatInit.luau)** that is not required to have but is also used to showcase how to use Reporter **(ReporterInit.luau)** is supposed to be use.

### Report Structure

```lua
export type ReportData = {
	ReportId: string,
	PlayerId: number,
	PlayerName: string,
	Reason: string,
	MovementKey: string,
	Score: number,
	Timestamp: number,
	RecordTime: number
}

local reportData = {
	ReportId = reportId, -- Acts as the key for the rest of the values in 'ReportStores'
	PlayerId = Player.UserId, -- The User ID of the person suspected of exploiting
	PlayerName = Player.Name, -- The player's name of the person suspected of exploiting
	Reason = Reason, -- The reason they were reported
	MovementKey = movementKey, -- Encoded string that is used to replay the player's movement
	Score = score, -- The score is calculated by how young the players account is and how many mutual friends they have. It's a common trend between exploiters I found when making this module. Check FriendCheckerInit.luau for more information. This doesn't have a part in actually detecting the cheater though, use this if you want to sort players based on how likely they are.
	Timestamp = tick(), -- When the player was reported
	RecordTime = recordTimeNum -- How long the suspected exploiter was recorded for
} :: ReportData
```

*Each API function is fully documented within ReporterInit.luau for easy reference.*

**NOTE:** In the Replayer configuration, you should **update the references to the Rig Folder to point to your actual Rig Folder** instead of workspace.

### Replayer configuration

```lua
--!strict

local Config = {}

Config.Instances = {
	RIG_FOLDER = workspace, -- // Folder to parent the rigs to
	TEMPLATE_RIG = script.Parent.Assets.TEMPLATE_RIG -- // The template rig to clone for recording
}

Config.Compression = {
	POSITION_PRECISION = 2, -- // Position precision (decimals)
	ROTATION_PRECISION = 1, -- // Degrees precision (decimals)
	MIN_POSITION_DELTA = 0.1, -- // Minimum position change to record
	MIN_ROTATION_DELTA = 2 -- // Minimum rotation change (degrees)
}

table.freeze(Config)

return Config
```

## API

```lua
-- // Reporter.Report(Player, RecordTime, Reason)
-- Records a player's movements for a specified duration to detect potential exploits.
-- Parameters:
--   Player: The Roblox Player instance to report.
--   RecordTime: Number of seconds to record the player's movement.
--   Reason: A string explaining why the player is being reported.
-- Returns immediately:
--   movementKey: An encoded string representing the player's movement (used for replaying).
--   score: A calculated exploit likelihood score based on account age and mutual friends.
--   reportId: A unique identifier for this report, used to retrieve or manage it later.
-- Notes:
--   - Recording occurs asynchronously; the player’s movement is saved in the background.
--   - This function does not automatically ban or block players; it only records and scores them.
--   - Use the returned movementKey with Reporter.Replay() to visualize the player's movements.
local movementKey, score, reportId = Reporter.Report(player, 5, "Speed Hack")

print("Report created with ID:", reportId, "Score:", score)

-- // Reporter.DeleteReport(reportId, userId?)
-- Deletes a report from the main DataStore and optionally from a specific player's history.
-- Parameters:
--   reportId: The unique ID of the report to delete.
--   userId (optional): The UserId of the player to also remove this report from their history.
-- Returns:
--   success: true if the report was successfully deleted from all specified locations.
local success = Reporter.DeleteReport(reportId, player.UserId)

if success then
    print("Report successfully deleted from main store and player history.")
end

-- // Reporter.CancelReport(Player)
-- Cancels an active report that is currently recording a player's movements.
-- Parameters:
--   Player: The Roblox Player instance whose report you want to cancel.
-- Returns:
--   cancelled: true if an active report was found and successfully cancelled.
local cancelled = Reporter.CancelReport(player)

if cancelled then
    print(player.Name .. "'s active report was cancelled and recording stopped.")
end

-- // Reporter.GetReport(reportId)
-- Retrieves a report by its unique ID from the main DataStore.
-- Parameters:
--   reportId: The unique ID of the report.
-- Returns:
--   report: The report data table if found, otherwise nil.
local report = Reporter.GetReport(reportId)

if report then
    print("Report retrieved successfully for player:", report.PlayerName)
end

-- // Reporter.Replay(movementKey)
-- Replays a previously recorded player's movements using the movement key.
-- Parameters:
--   movementKey: The encoded movement data returned from Reporter.Report.
Reporter.Replay(movementKey)

print("Movement replay initiated for the recorded session.")

-- // Reporter.GetPlayerHistory(userId)
-- Retrieves the history of all reports associated with a player.
-- Parameters:
--   userId: The UserId of the player.
-- Returns:
--   history: An array of ReportHistoryEntry objects.
local history = Reporter.GetPlayerHistory(player.UserId)

print("Player has", #history, "past reports recorded in their history.")

-- // Reporter.IsPlayerBeingReported(Player)
-- Checks if a player currently has an active report being recorded.
-- Parameters:
--   Player: The Roblox Player instance.
-- Returns:
--   isBeingReported: true if a report is currently active for this player.
local isBeingReported = Reporter.IsPlayerBeingReported(player)

print(player.Name .. " is currently being reported:", isBeingReported)

-- // Reporter.GetActiveReports()
-- Retrieves a list of all currently active reports in the system.
-- Returns:
--   activeReports: A table containing ActiveReportInfo for each active report.
local activeReports = Reporter.GetActiveReports()

for _, reportInfo in ipairs(activeReports) do
    print("Active report ID:", reportInfo.ReportId, "Player:", reportInfo.PlayerName, "Duration:", reportInfo.Duration)
end
```

## Example Usage

```lua
local Players = game:GetService("Players")

local BasicAnticheat = require(game.ReplicatedStorage.Anticheat.BasicAnticheat.BasicAnticheatInit)
local Reporter = require(game.ReplicatedStorage.Anticheat.Reporter.ReporterInit)

BasicAnticheat.Init() -- // Optional, Anticheat Implementation with Reporter

Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Wait()
	
	local REPORT_ID = "ID HERE" -- // 'Report ID' Here
	
	local Report = Reporter.GetReport(REPORT_ID) -- // Returns ReportData?
	
	print(Report)
	
	Reporter.Replay(Report.MovementKey)
end)
```