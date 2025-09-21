--!strict

local Reporter = {}

--======================
-- // SERVICES
--======================

Reporter.Services = {
	Players = game:GetService("Players"),
	DataStoreService = game:GetService("DataStoreService"),
	HttpService = game:GetService("HttpService"),
}

--======================
-- // MODULES
--======================

Reporter.Modules = {
	Config = require(script.Parent.Misc.Config),
	Replayer = require(script.Parent.Modules.Replayer.ReplayerInit),
	FriendChecker = require(script.Parent.Modules.FriendChecker.FriendCheckerInit)
}

--======================
-- // DATA-STORES
--======================

local ReportStores = Reporter.Services.DataStoreService:GetDataStore("ReportStores") -- // Unordered DataStores that holds all reports
local ReportHistory = Reporter.Services.DataStoreService:GetDataStore("ReportHistory") -- // Per-Player DataStores that holds all reports of a player

--======================
-- // TYPES
--======================

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

export type ReportHistoryEntry = {
	ReportId: string,
	Timestamp: number,
	Reason: string,
	Score: number
}

export type ActiveReportData = {
	ReportId: string,
	StartTime: number,
	Player: Player
}

export type ActiveReportInfo = {
	UserId: number,
	PlayerName: string,
	ReportId: string,
	StartTime: number,
	Duration: number
}

--======================
-- // DATA
--======================

Reporter.ActiveReports = {} :: { [number]: ActiveReportData } -- // Used for Caching Reports that are in this server

--======================
-- // PRIVATE API
--======================

-- GenerateReportId(): Generate a unique report ID using HttpService GUID
-- @return string: Unique identifier string for the report
local function GenerateReportId(): string
	return Reporter.Services.HttpService:GenerateGUID(false)
end

-- ValidateRecordTime(): Validate and convert recording time to acceptable bounds
-- @param RecordTime: Time value to validate (string or number)
-- @return (boolean, number): Validation success boolean and converted time number
local function ValidateRecordTime(RecordTime): (boolean, number)
	local timeNum = tonumber(RecordTime)

	if not timeNum then
		return false, 0
	end

	local config = Reporter.Modules.Config.Recording
	if timeNum < config.MIN_RECORD_TIME or timeNum > config.MAX_RECORD_TIME then
		return false, 0
	end

	return true, timeNum
end

-- SaveReportData(): Save report data to DataStore with retry logic and exponential backoff
-- @param reportId: Unique identifier for the report
-- @param data: Report data table to save
-- @return boolean: True if save was successful, false otherwise
local function SaveReportData(reportId: string, data: ReportData): boolean
	local retryDelay = Reporter.Modules.Config.DataStores.RETRY_DELAY

	for attempt = 1, Reporter.Modules.Config.DataStores.MAX_RETRIES do
		local success = pcall(function()
			ReportStores:SetAsync(reportId, data)
		end)

		if success then
			return true
		else
			warn(string.format("Failed to save report data (attempt %d/%d): %s", attempt, Reporter.Modules.Config.DataStores.MAX_RETRIES, tostring(error)))
			if attempt < Reporter.Modules.Config.DataStores.MAX_RETRIES then
				task.wait(retryDelay)
				retryDelay *= 2
			end
		end
	end

	return false
end

-- UpdatePlayerHistory(): Update a player's report history in the DataStore (History length: Config.Player.MAX_HISTORY_LENGTH)
-- @param userId: The player's UserId
-- @param reportData: The report data to add to history
local function UpdatePlayerHistory(userId: number, reportData: ReportData): ()
	local success, result = pcall(function()
		local key = "Player_" .. userId

		return ReportHistory:UpdateAsync(key, function(oldHistory)
			local history = oldHistory or {}

			table.insert(history, {
				ReportId = reportData.ReportId,
				Timestamp = reportData.Timestamp,
				Reason = reportData.Reason,
				Score = reportData.Score
			})

			if #history > Reporter.Modules.Config.Player.MAX_HISTORY_LENGTH then
				table.remove(history, 1)
			end

			return history
		end)
	end)

	if not success then
		warn("UpdatePlayerHistory failed:", result)
	end
end

-- AddToActiveReports(): Add a player to the active reports tracking
-- @param Player: The player being reported
-- @param reportId: The unique report identifier
local function AddToActiveReports(Player: Player, reportId: string): ()
	Reporter.ActiveReports[Player.UserId] = {
		ReportId = reportId,
		StartTime = tick(),
		Player = Player
	}
end

-- RemoveFromActiveReports(): Remove a player from the active reports tracking
-- @param Player: The player to remove from active reports
local function RemoveFromActiveReports(Player: Player): ()
	Reporter.ActiveReports[Player.UserId] = nil
end

--======================
-- // PUBLIC API
--======================

-- Report(): Report a player for exploiting and save it to a DataStore
-- @param Player: The player to report
-- @param RecordTime: Time in seconds to record the player's movement
-- @param Reason: The reason for the report
-- @return (string?, number?, string?): The MovementKey, exploit likelihood score, and unique report ID
function Reporter.Report(Player: Player, RecordTime: number, Reason: string): (string?, number?, string?)
	local isValidTime, recordTimeNum = ValidateRecordTime(RecordTime)

	if not isValidTime then
		warn("Reporter.Report(): Invalid record time. Must be between " .. 
			Reporter.Modules.Config.Recording.MIN_RECORD_TIME .. " and " .. 
			Reporter.Modules.Config.Recording.MAX_RECORD_TIME .. " seconds")
		return nil, nil, nil
	end

	if not Reason or Reason == "" then
		warn("Reporter.Report(): Reason cannot be empty")
		return nil, nil, nil
	end

	if Reporter.IsPlayerBeingReported(Player) then
		warn("Reporter.Report(): Player is already being reported")
		return nil, nil, nil
	end

	local reportId = GenerateReportId()
	
	AddToActiveReports(Player, reportId)

	task.spawn(function()
		local success, movementKey, score = pcall(function()
			local recordConnection = Reporter.Modules.Replayer.StartRecording(
				Player.Character :: Model, 
				Reporter.Modules.Config.Recording.RECORD_RATE
			)

			if not recordConnection then
				error("Failed to start recording")
			end

			task.wait(recordTimeNum)

			local movementKey = Reporter.Modules.Replayer.StopRecording(Player.Character :: Model)
			local score = Reporter.Modules.FriendChecker.Scan(Player)

			return movementKey, score
		end)

		RemoveFromActiveReports(Player)

		if not success then
			warn("Reporter.Report(): Error during recording - " .. tostring(movementKey))
			return
		end

		local reportData = {
			ReportId = reportId,
			PlayerId = Player.UserId,
			PlayerName = Player.Name,
			Reason = Reason,
			MovementKey = movementKey,
			Score = score,
			Timestamp = tick(),
			RecordTime = recordTimeNum
		} :: ReportData

		local saveSuccess = SaveReportData(reportId, reportData)
		if not saveSuccess then
			warn("Reporter.Report(): Failed to save report to DataStore")
		end

		task.spawn(UpdatePlayerHistory, Player.UserId, reportData)

		print(string.format("Report created for %s (ID: %s) - Score: %d", Player.Name, reportId, score))
	end)

	return nil, nil, reportId
end

-- DeleteReport(): Delete a report from both the main store and the player's history
-- @param reportId: The unique report ID to delete
-- @param userId?: The player’s UserId if you want to remove from their history too
-- @return boolean: True if deletion succeeded
function Reporter.DeleteReport(reportId: string, userId: number?): boolean
	local successMain, errMain = pcall(function()
		ReportStores:RemoveAsync(reportId)
	end)

	local successHistory = true
	
	if userId then
		local key = "Player_" .. userId
		
		local success, result = pcall(function()
			return ReportHistory:UpdateAsync(key, function(oldHistory)
				if not oldHistory then return {} end
				for i = #oldHistory, 1, -1 do
					if oldHistory[i].ReportId == reportId then
						table.remove(oldHistory, i)
					end
				end

				return oldHistory
			end)
		end)
		
		successHistory = success
		
		if not success then
			warn("Reporter.DeleteReport(): Failed to update player history - " .. tostring(result))
		end
	end

	if not successMain then
		warn("Reporter.DeleteReport(): Failed to delete report from main store - " .. tostring(errMain))
	end
	
	if userId and not successHistory then
		warn("Reporter.DeleteReport(): Failed to delete report from player history")
	end

	return successMain and successHistory
end

-- CancelReport(): Cancel an active report for a player
-- @param Player: The player whose report to cancel
-- @return boolean: Boolean indicating success
function Reporter.CancelReport(Player: Player): boolean
	if not Reporter.IsPlayerBeingReported(Player) then
		return false
	end

	pcall(function()
		Reporter.Modules.Replayer.StopRecording(Player.Character :: Model)
	end)

	RemoveFromActiveReports(Player)

	print(string.format("Report cancelled for %s", Player.Name))

	return true
end

-- GetReport(): Retrieve a report by ID
-- @param reportId: The unique report ID
-- @return ReportData?: Report data table or nil if not found
function Reporter.GetReport(reportId: string): ReportData?
	local success, result = pcall(function()
		return ReportStores:GetAsync(reportId)
	end)

	if success then
		return result
	else
		warn("Reporter.GetReport(): Failed to retrieve report - " .. tostring(result))
		return nil
	end
end

-- Replay(): Replay recorded player movement from encoded movement data
-- @param movementKey: The movement key
function Reporter.Replay(movementKey: string): ()
	Reporter.Modules.Replayer.ReplayMovement(movementKey, Reporter.Modules.Config.Recording.RECORD_RATE)
end

-- GetPlayerHistory(): Get report history for a player
-- @param userId: The player's UserId
-- @return { ReportHistoryEntry }: Array of report history or empty array
function Reporter.GetPlayerHistory(userId: number): { ReportHistoryEntry }
	local success, result = pcall(function()
		return ReportHistory:GetAsync("Player_" .. userId) or {}
	end)

	if success then
		return result
	else
		warn("Reporter.GetPlayerHistory(): Failed to retrieve history - " .. tostring(result))
		return {}
	end
end

-- IsPlayerBeingReported(): Check if a player is currently being reported
-- @param Player: The player to check
-- @return boolean: True if player is currently being reported
function Reporter.IsPlayerBeingReported(Player: Player): boolean
	return Reporter.ActiveReports[Player.UserId] ~= nil
end

-- GetActiveReports(): Get list of currently active reports
-- @return { ActiveReportInfo }: Table of active reports with player information
function Reporter.GetActiveReports(): { ActiveReportInfo }
	local reports = {}
	
	for userId, reportData in Reporter.ActiveReports do
		table.insert(reports, {
			UserId = userId,
			PlayerName = reportData.Player.Name,
			ReportId = reportData.ReportId,
			StartTime = reportData.StartTime,
			Duration = tick() - reportData.StartTime
		})
	end
	
	return reports
end

-- Initialize(): Set up the reporter system and event connections
function Reporter.Initialize()
	Reporter.Services.Players.PlayerRemoving:Connect(function(Player)
		if Reporter.IsPlayerBeingReported(Player) then
			Reporter.CancelReport(Player)
		end
	end)
end

--======================
-- // INIT
--======================

Reporter.Initialize()

return Reporter