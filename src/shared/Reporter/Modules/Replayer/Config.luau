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