--!strict

local FriendChecker = {}

--======================
-- // SERVICES
--======================

FriendChecker.Services = {
	Players = game:GetService("Players")
}

--======================
-- // MODULES
--======================

FriendChecker.Modules = {
	Config = require(script.Parent.Config)
}

--======================
-- // DATA
--======================

FriendChecker.FriendsCache = {} :: { [number]: { any } }

--======================
-- // PRIVATE API
--======================

-- ExtractFriendPages(): Iterate over FriendPages
-- @param friendPages: Friend Pages
-- @return () -> ({ Id: number, Username: string, DisplayName: string, IsOnline: boolean }, number): item, pageNumber
local function ExtractFriendPages(friendPages: FriendPages): () -> ({ Id: number, Username: string, DisplayName: string, IsOnline: boolean }, number)
	return coroutine.wrap(function()
		local PageNumber = 1

		while true do
			for _, item in friendPages:GetCurrentPage() do
				coroutine.yield(item, PageNumber)
			end

			if friendPages.IsFinished then
				break
			end

			friendPages:AdvanceToNextPageAsync()
			PageNumber += 1
		end
	end)
end

-- GetFriendsUserIds(): Collects UserIds of all friends from FriendPages
-- @param friendPages: Friend Pages
-- @return { number }: An array of all of the UserIds
local function GetFriendsUserIds(friendPages: FriendPages): { number }
	local UserIds = {}

	for item, _pageNo in ExtractFriendPages(friendPages) do
		table.insert(UserIds, item.Id)
	end

	return UserIds
end

--======================
-- // PUBLIC API
--======================

-- Scan(): Checks to see if the player is likely an exploiter
-- @param player: The player to check
-- @return number: (Points) - How likely the player is to be an exploiter, decreased by higher account ages
function FriendChecker.Scan(player: Player): number
	local PlayerPoints = 0
	
	local ANTI_CHEAT = FriendChecker.Modules.Config.ANTI_CHEAT

	if player.AccountAge < ANTI_CHEAT.AGE_LIMIT then
		PlayerPoints += ANTI_CHEAT.AGE_POINTS
	end

	local FriendIds = FriendChecker.ListFriends(player)

	if #FriendIds == 0 then
		return 0
	end

	local playerFriendSet = {}
	local sampled = {}
	local available = {table.unpack(FriendIds)}
	local sampleSize = math.min(ANTI_CHEAT.FRIENDS_TO_CHECK, #available)

	for _, fid in FriendIds do
		playerFriendSet[fid] = true
	end

	for i = 1, sampleSize do
		local randIndex = math.random(1, #available)
		sampled[i] = available[randIndex]
		available[randIndex] = available[#available]
		available[#available] = nil
	end

	for _, friendId in sampled do
		local OtherFriends = FriendChecker.GetFriendIds(friendId)

		for _, fid in OtherFriends do
			if playerFriendSet[fid] then
				PlayerPoints += ANTI_CHEAT.MUTUAL_POINTS
			end
		end
	end

	return math.round(PlayerPoints / math.max(0.1, math.log(player.AccountAge + 1) / 5))
end

-- GetFriendIds(): Collects all friend UserIds for the given user (Caches)
-- @param userId number: The UserId to fetch friends for
-- @return { number }: An array of UserIds
function FriendChecker.GetFriendIds(userId: number): { number }
	if FriendChecker.FriendsCache[userId] then
		return FriendChecker.FriendsCache[userId]
	end

	local success, FriendPages = pcall(function()
		return FriendChecker.Services.Players:GetFriendsAsync(userId)
	end)

	if not success then
		FriendChecker.FriendsCache[userId] = {}
		return {}
	end

	local ids = GetFriendsUserIds(FriendPages)

	FriendChecker.FriendsCache[userId] = ids

	return ids
end

-- ListFriends(): Returns list of friend IDs for the given player
-- @param player: The player to check
-- @return { number }: An array of all of the UserIds
function FriendChecker.ListFriends(player: Player): { number }	
	return FriendChecker.GetFriendIds(player.UserId)
end

--======================
-- // CONNECTIONS
--======================

FriendChecker.Services.Players.PlayerRemoving:Connect(function(player)
	FriendChecker.FriendsCache[player.UserId] = nil
end)

return FriendChecker