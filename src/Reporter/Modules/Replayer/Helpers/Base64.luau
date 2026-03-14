--!strict

local Base64 = {}

--=======================
-- // VARIABLES
--=======================

Base64.Characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--=======================
-- // PUBLIC API
--=======================

-- Encode(): Encodes a string to Base64 for serialization
-- @param input: The string to convert
-- @return string: The encoded string
function Base64.Encode(input: string): string
	local output = {}
	local chars = Base64.Characters

	for i = 1, #input, 3 do
		local a = input:byte(i) or 0
		local b = input:byte(i + 1) or 0
		local c = input:byte(i + 2) or 0

		local n = bit32.lshift(a, 16) + bit32.lshift(b, 8) + c

		local c1 = bit32.band(bit32.rshift(n, 18), 0x3F) + 1
		local c2 = bit32.band(bit32.rshift(n, 12), 0x3F) + 1
		local c3 = bit32.band(bit32.rshift(n, 6), 0x3F) + 1
		local c4 = bit32.band(n, 0x3F) + 1

		local byteCount = math.min(3, #input - i + 1)
		output[#output + 1] = chars:sub(c1, c1)
		output[#output + 1] = chars:sub(c2, c2)
		output[#output + 1] = (byteCount < 2) and "=" or chars:sub(c3, c3)
		output[#output + 1] = (byteCount < 3) and "=" or chars:sub(c4, c4)
	end

	return table.concat(output)
end

-- Decode(): Decodes a Base64 string
-- @param input: The string to convert
-- @return string: The decoded string
function Base64.Decode(input: string): string
	local output = {}
	local bytes = {}
	local map = {}

	for i = 1, #Base64.Characters do
		map[string.sub(Base64.Characters, i, i)] = i - 1
	end

	input = input:gsub("[^%w+/=]", "")

	for i = 1, #input, 4 do
		local a = map[string.sub(input, i, i)] or 0
		local b = map[string.sub(input, i + 1, i + 1)] or 0
		local c = map[string.sub(input, i + 2, i + 2)] or 0
		local d = map[string.sub(input, i + 3, i + 3)] or 0

		local n = bit32.lshift(a, 18) + bit32.lshift(b, 12) + bit32.lshift(c, 6) + d

		local byte1 = bit32.rshift(n, 16) % 256
		local byte2 = bit32.rshift(n, 8) % 256
		local byte3 = n % 256

		table.insert(bytes, string.char(byte1))
		if input:sub(i + 2, i + 2) ~= "=" then
			table.insert(bytes, string.char(byte2))
		end
		if input:sub(i + 3, i + 3) ~= "=" then
			table.insert(bytes, string.char(byte3))
		end
	end

	return table.concat(bytes)
end

return Base64