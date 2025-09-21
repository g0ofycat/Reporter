--!strict

local Config = {}

Config.DataStores = {
	MAX_RETRIES = 3, -- // How many tries the DataStore should try to save
	RETRY_DELAY = 1 -- // The delay between each failure before giving up
}

Config.Recording = {
	RECORD_RATE = 1/30, -- // Frame rate for recording (Default: 30 FPS)
	MIN_RECORD_TIME = 1, -- // Minimum time the player has to record for when Reporting
	MAX_RECORD_TIME = 30 -- // Maximum time the player has to record for when Reporting
}

Config.Player = {
	MAX_HISTORY_LENGTH = 50 -- // How many reports each player can hold
}

table.freeze(Config)

return Config