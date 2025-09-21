local Config = {}

Config.ANTI_CHEAT = {
	FRIENDS_TO_CHECK = 20, -- // Number of random friends to sample when checking for mutual exploiters
	MUTUAL_POINTS = 5, -- // The amount of points the player gets per-mutual
	AGE_LIMIT = 90, -- // Account age limit in days; younger accounts may be considered exploiters
	AGE_POINTS = 15 -- // The amount of points the player gets if they're below AGE_LIMIT
}

table.freeze(Config)

return Config