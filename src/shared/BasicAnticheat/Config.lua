--!strict

local Config = {}

Config.ANTI_CHEAT = {
	VIOLATION_LIMIT = 5, -- // Amount of violations before being banned
	RECORD_TIME = 5, -- // How long to record the suspected player of cheating
	REPORT_COOLDOWN = 60, -- // How long the cooldown is before reporting the player again
	MAX_SPEED = 125, -- // How fast the player can go before getting flagged
	MAX_HEIGHT_GAIN = 100, -- // How high the player can go before getting flagged
	MAX_TELEPORT_DISTANCE = 200, -- // How horizontally fast the player moves before getting flagged
	CHECK_INTERVAL = 5 -- // (Seconds) How fast to check the player for cheating
}

table.freeze(Config)

return Config