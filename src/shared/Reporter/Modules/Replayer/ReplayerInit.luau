--!strict

local Replayer = {}

--=======================
-- // SERVICES
--=======================

Replayer.Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService")
}

--======================
-- // MODULES
--======================

Replayer.Modules = {
	Config = require(script.Parent.Config),
	Bitpacker = require(script.Parent.Helpers.Bitpacker.BitpackerInit),
	Base64 = require(script.Parent.Helpers.Base64)
}

--=======================
-- // DATA
--=======================

Replayer.RigConnections = {} :: { [Model]: RBXScriptConnection }
Replayer.Connections = {} :: { [Model]: RBXScriptConnection }
Replayer.Data = {} :: { [Model]: { LastTime: number, CFrameArray: { CFrame }, LastCFrame: CFrame?, UserId: number } }

--=======================
-- // PRIVATE API
--=======================

-- Round(): Rounds a number with an optional decimal parameter
-- @param number: The number to round
-- @param decimals: The amount of decimal places to round to
-- @return number: The rounded number
local function Round(number: number, decimals: number?): number
	local mult = 10 ^ (decimals or 3)
	return math.floor(number * mult + 0.5) / mult
end

-- CompressRotation(): Compress rotation to smaller range if possible
-- @param degrees: The degree to compress
-- @return: The compressed degree
local function CompressRotation(degrees: number): number
	while degrees > 180 do
		degrees -= 360
	end
	
	while degrees < -180 do
		degrees += 360
	end
	
	return Round(degrees, Replayer.Modules.Config.Compression.ROTATION_PRECISION)
end

-- DeltaCompress(): Store differences between consecutive frames
-- @param parsedArray: Array of parsed frames
-- @return {any}: The compressed array
local function DeltaCompress(parsedArray: {any}): {any}
	if #parsedArray <= 1 then return parsedArray end

	local compressed = {parsedArray[1]}

	for i = 2, #parsedArray do
		local delta = {}
		for j = 1, #parsedArray[i] do
			delta[j] = parsedArray[i][j] - parsedArray[i - 1][j]
		end
		table.insert(compressed, delta)
	end

	return compressed
end

-- DeltaDecompress(): Store differences between consecutive frames
-- @param compressed: The compressed array
-- @return {any}: Array of parsed frames
local function DeltaDecompress(compressed: {any}): {any}
	if #compressed <= 1 then return compressed end

	local decompressed = {compressed[1]}

	for i = 2, #compressed do
		local frame = {}
		for j = 1, #compressed[i] do
			frame[j] = decompressed[i-1][j] + compressed[i][j]
		end
		table.insert(decompressed, frame)
	end

	return decompressed
end

-- IsSignificantChange(): Check if CFrame change is significant enough to record
-- @param newCFrame: New CFrame to compare
-- @param lastCFrame: Last CFrame to compare against
-- @return boolean: True if significant, False otherwise
local function IsSignificantChange(newCFrame: CFrame, lastCFrame: CFrame?): boolean
	if not lastCFrame then return true end

	local positionDelta = (newCFrame.Position - lastCFrame.Position).Magnitude
	if positionDelta >= Replayer.Modules.Config.Compression.MIN_POSITION_DELTA then return true end

	local rx1, ry1, rz1 = newCFrame:ToOrientation()
	local rx2, ry2, rz2 = lastCFrame:ToOrientation()

	local rotationDelta = math.max(
		math.abs(math.deg(rx1 - rx2)),
		math.abs(math.deg(ry1 - ry2)),
		math.abs(math.deg(rz1 - rz2))
	)

	return rotationDelta >= Replayer.Modules.Config.Compression.MIN_ROTATION_DELTA
end

-- CatmullRomInterpolate(): Catmull-Rom spline interpolation
-- @param p0: First CFrame
-- @param p1: Second CFrame
-- @param p2: Third CFrame
-- @param p3: Fourth CFrame
-- @param t: Interpolation factor
-- @return CFrame: Interpolated CFrame
local function CatmullRomInterpolate(p0: CFrame, p1: CFrame, p2: CFrame, p3: CFrame, t: number): CFrame
	if not p0 or not p3 then
		return p1:Lerp(p2, t)
	end

	local easedT = t * t * (3 - 2 * t)

	return p1:Lerp(p2, easedT)
end

-- ParseCFrameArray(): Converts an array of CFrames into a table of component lists
-- @param CFrameArray: Array of CFrames to parse
-- @return {any}: Array of tables containing CFrame components
local function ParseCFrameArray(CFrameArray: {CFrame}): {any}
	local parsed = {}

	for _, cf in CFrameArray do
		local pos = cf.Position
		local rx, ry, rz = cf:ToOrientation()

		table.insert(parsed, {
			Round(pos.X, Replayer.Modules.Config.Compression.POSITION_PRECISION),
			Round(pos.Y, Replayer.Modules.Config.Compression.POSITION_PRECISION),
			Round(pos.Z, Replayer.Modules.Config.Compression.POSITION_PRECISION),
			CompressRotation(math.deg(rx)),
			CompressRotation(math.deg(ry)),
			CompressRotation(math.deg(rz))
		})
	end

	return parsed
end

-- UnparseCFrameArray(): Converts a table of CFrame components back into actual CFrames
-- @param parsedArray: Array of tables containing CFrame components
-- @return {CFrame}: Array of reconstructed CFrames
local function UnparseCFrameArray(parsedArray: {any}): {CFrame}
	local cframes = {}

	for _, c in parsedArray do
		local x, y, z, rx, ry, rz = unpack(c)
		table.insert(cframes,
			CFrame.new(x, y, z) *
				CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
		)
	end

	return cframes
end

-- CreateRigMovement(): Creates and replays a rig's movement using a CFrame array at the given playback rate
-- @param UserId: The UserId to set the rigs appearance to
-- @param cframes: An array of CFrames to follow
-- @param playbackRate: Seconds per frame interpolation
local function CreateRigMovement(UserId: number, cframes: {CFrame}, playbackRate: number): ()
	local StartTime = tick()
	local TotalFrames = #cframes
	local currentIndex = 1

	local Player = Replayer.Services.Players:GetPlayerByUserId(UserId)
	local Rig = Replayer.Modules.Config.Instances.TEMPLATE_RIG:Clone()

	local HumanoidRootPart = Rig:WaitForChild("HumanoidRootPart")
	local Humanoid = Rig:WaitForChild("Humanoid")

	local success, description = pcall(function()
		return Replayer.Services.Players:GetHumanoidDescriptionFromUserId(UserId)
	end)
	
	Rig.Name = Player and Player.DisplayName or ("Rig_" .. UserId)
	Rig.Parent = Replayer.Modules.Config.Instances.RIG_FOLDER
	
	if success and description then
		Humanoid:ApplyDescription(description)
	end

	local totalDuration = TotalFrames * playbackRate
	local startTime = tick()

	Replayer.RigConnections[Rig] = Replayer.Services.RunService.Heartbeat:Connect(function(deltaTime)
		local elapsed = tick() - startTime
		local progress = elapsed / totalDuration

		if progress >= 1 or currentIndex >= TotalFrames then
			Replayer.RigConnections[Rig]:Disconnect()
			Rig:Destroy()
			return
		end

		local framePosition = progress * (TotalFrames - 1) + 1
		local frameIndex = math.floor(framePosition)
		local frameAlpha = framePosition - frameIndex

		frameIndex = math.max(1, math.min(frameIndex, TotalFrames - 1))

		local startCFrame = cframes[frameIndex]
		local endCFrame = cframes[frameIndex + 1]

		local p0 = cframes[math.max(1, frameIndex - 1)]
		local p3 = cframes[math.min(TotalFrames, frameIndex + 2)]

		HumanoidRootPart.CFrame = CatmullRomInterpolate(p0, startCFrame, endCFrame, p3, frameAlpha)
	end)
end

--=======================
-- // PUBLIC API
--=======================

-- StartRecording(): Starts tracking the Characters movement
-- @param character: The character to track
-- @param recordRate: The rate to record the movements
-- @return RBXScriptConnection: The Heartbeat Connection
function Replayer.StartRecording(character: Model, recordRate: number): RBXScriptConnection
	assert(character, "character cannot be nil")
	assert(recordRate, "recordRate cannot be nil")
	
	local Player = Replayer.Services.Players:GetPlayerFromCharacter(character)
	local HumanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	Replayer.Data[character] = {
		LastTime = 0,
		CFrameArray = {},
		LastCFrame = nil,
		UserId = Player.UserId
	}
	
	Replayer.Connections[character] = Replayer.Services.RunService.Heartbeat:Connect(function()
		local nowTime = os.clock()
		local data = Replayer.Data[character]
		local currentCFrame = HumanoidRootPart.CFrame

		if nowTime - data.LastTime >= recordRate then
			if IsSignificantChange(currentCFrame, data.LastCFrame) then
				data.LastTime = nowTime
				data.LastCFrame = currentCFrame
				table.insert(data.CFrameArray, currentCFrame)
			end
		end
	end)

	return Replayer.Connections[character]
end

-- StopRecording(): Stops recording the character if you have recorded them
-- @param character: The character to stop recording
-- @return string?: The Encoded array of the Player UserId and the tracked CFrames
function Replayer.StopRecording(character: Model): string?
	local connection = Replayer.Connections[character]
	local data = Replayer.Data[character]

	if connection and data then
		connection:Disconnect()
		Replayer.Connections[character] = nil
		Replayer.Data[character] = nil

		local parsed = ParseCFrameArray(data.CFrameArray)
		local deltaCompressed = DeltaCompress(parsed)

		local output = {
			CFrames = deltaCompressed,
			UserId = data.UserId,
			OriginalLength = #data.CFrameArray
		}

		return Replayer.Modules.Base64.Encode(Replayer.Modules.Bitpacker.Pack(output))
	end

	return nil
end

-- ReplayMovement(): Replays the movement with a Rig using the output of .StopRecording()
-- @param recordedArray: The encoded CFrame string that .StopRecording() outputs
-- @param playbackRate: Seconds to wait between frames
function Replayer.ReplayMovement(recordedArray: string, playbackRate: number): ()
	assert(recordedArray, "recordedArray cannot be nil")
	assert(playbackRate, "playbackRate cannot be nil")

	local decodedArray = Replayer.Modules.Bitpacker.Unpack(Replayer.Modules.Base64.Decode(recordedArray))

	local cframes = UnparseCFrameArray(DeltaDecompress(decodedArray.CFrames))

	CreateRigMovement(decodedArray.UserId, cframes, playbackRate)
end

return Replayer