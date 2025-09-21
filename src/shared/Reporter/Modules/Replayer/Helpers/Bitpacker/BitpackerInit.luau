--!strict

local Bitpacker = {}

--======================
-- // MODULES
--======================

local Types = require(script.Parent.Types)

--=======================
-- // PRIVATE API
--=======================

-- GetValueSize(): Gets the values size in bytes
-- @param value: The value to get the size of
-- @return size: The size of the value
local function GetValueSize(value: any): number
	local valueType = type(value)

	if valueType == "string" then
		return 1 + 1 + #value
	elseif valueType == "number" then
		if value == math.floor(value) then
			if value >= 0 and value <= 255 then
				return 1 + 1
			elseif value >= -32768 and value <= 32767 then
				return 1 + 2
			elseif value >= -2147483648 and value <= 2147483647 then
				return 1 + 4
			else
				return 1 + 8
			end
		else
			return 1 + 4
		end
	elseif valueType == "boolean" then
		return 1 + 1
	elseif valueType == "table" then
		local size = 1 + 2
		for k, v in value do
			size += GetValueSize(k)
			size += GetValueSize(v)
		end
		return size
	else
		error("Unsupported type: " .. valueType)
	end
end

-- GetRawSize(): Gets the raw size (in bytes) of the current data
-- @param value: The value to check
-- @return number: The amount of bytes
local function GetRawSize(value: any): number
	local valueType = type(value)

	if valueType == "string" then
		return #value
	elseif valueType == "number" then
		return 8
	elseif valueType == "boolean" then
		return 1
	elseif valueType == "table" then
		local size = 0
		for k, v in value do
			size += GetRawSize(k)
			size += GetRawSize(v)
		end
		return size
	else
		error("Unsupported type: " .. valueType)
	end
end

-- CalculateBufferSize(): Calculates the buffer size of a table of data
-- @param data: The table of data
-- @return size: The size of the buffer
local function CalculateBufferSize(data: Types.PackableTable): number
	local size = 2

	for key, value in data do
		size += GetValueSize(key)
		size += GetValueSize(value)
	end

	return size
end

-- GetOptimalNumberEncoding(): Gets the optimal number coding based on a value and ranges
-- @param value: The number
-- @return marker, size
local function GetOptimalNumberEncoding(value: number): (number, number)
	if value == math.floor(value) then
		if value >= 0 and value <= 255 then
			return 2, 1
		elseif value >= -32768 and value <= 32767 then
			return 3, 2
		elseif value >= -2147483648 and value <= 2147483647 then
			return 4, 4
		else
			return 6, 8
		end
	else
		return 5, 4
	end
end

-- WriteValue(): Writes a value of a buffer
-- @param buf: The buffer
-- @param offset: How much to offset the bytes by
-- @param value: The value to write
-- @return offset: The offset of the buffer
local function WriteValue(buf: buffer, offset: number, value: any): number
	local valueType = type(value)

	if valueType == "string" then
		buffer.writeu8(buf, offset, 1)
		offset += 1
		assert(#value <= 255, "String too long (max 255 characters)")
		buffer.writeu8(buf, offset, #value)
		offset += 1
		buffer.writestring(buf, offset, value)
		offset += #value
	elseif valueType == "number" then
		local marker, size = GetOptimalNumberEncoding(value)
		buffer.writeu8(buf, offset, marker)
		offset += 1
		if marker == 2 then
			buffer.writeu8(buf, offset, value)
		elseif marker == 3 then
			buffer.writei16(buf, offset, value)
		elseif marker == 4 then
			buffer.writei32(buf, offset, value)
		elseif marker == 5 then
			buffer.writef32(buf, offset, value)
		else
			buffer.writef64(buf, offset, value)
		end
		offset += size
	elseif valueType == "boolean" then
		buffer.writeu8(buf, offset, 7)
		offset += 1
		buffer.writeu8(buf, offset, value and 1 or 0)
		offset += 1
	elseif valueType == "table" then
		buffer.writeu8(buf, offset, 8)
		offset += 1
		local count = 0
		for _ in value do count += 1 end
		buffer.writeu16(buf, offset, count)
		offset += 2
		for k, v in value do
			offset = WriteValue(buf, offset, k)
			offset = WriteValue(buf, offset, v)
		end
	else
		error("Unsupported type: " .. valueType)
	end
	return offset
end

-- ReadValue(): Reads a value of a buffer
-- @param buf: The buffer to read
-- @param offset: How much to offset the bytes by
-- @return (any, number)
local function ReadValue(buf: buffer, offset: number): (any, number)
	local typeMarker = buffer.readu8(buf, offset)
	offset += 1

	if typeMarker == 1 then
		local len = buffer.readu8(buf, offset)
		offset += 1
		local str = buffer.readstring(buf, offset, len)
		offset += len
		return str, offset
	elseif typeMarker == 2 then
		local value = buffer.readu8(buf, offset)
		offset += 1
		return value, offset
	elseif typeMarker == 3 then
		local value = buffer.readi16(buf, offset)
		offset += 2
		return value, offset
	elseif typeMarker == 4 then
		local value = buffer.readi32(buf, offset)
		offset += 4
		return value, offset
	elseif typeMarker == 5 then
		local value = buffer.readf32(buf, offset)
		offset += 4
		return value, offset
	elseif typeMarker == 6 then
		local value = buffer.readf64(buf, offset)
		offset += 8
		return value, offset
	elseif typeMarker == 7 then
		local value = buffer.readu8(buf, offset) == 1
		offset += 1
		return value, offset
	elseif typeMarker == 8 then
		local count = buffer.readu16(buf, offset)
		offset += 2
		local tbl = {}
		for _ = 1, count do
			local key, newOffset = ReadValue(buf, offset)
			offset = newOffset
			local value, newOffset2 = ReadValue(buf, offset)
			offset = newOffset2
			tbl[key] = value
		end
		return tbl, offset
	else
		error("Unknown type marker: " .. typeMarker)
	end
end

--=======================
-- // PUBLIC API
--=======================

-- Pack(): Packs any table into a compressed buffer string
-- @param data: The table to pack (supports strings, numbers, booleans, and nested tables)
-- @return string: The packed buffer as a string
function Bitpacker.Pack(data: Types.PackableTable): string
	local size = CalculateBufferSize(data)
	local buf = buffer.create(size)
	local offset = 0

	local fieldCount = 0
	
	for _ in data do
		fieldCount += 1
	end

	buffer.writeu16(buf, offset, fieldCount)
	
	offset += 2

	for key, value in data do
		offset = WriteValue(buf, offset, key)
		offset = WriteValue(buf, offset, value)
	end

	return buffer.tostring(buf)
end

-- Unpack(): Unpacks a buffer string back into the original table structure
-- @param data: The packed buffer string
-- @return PackableTable: The unpacked table with original structure and types
function Bitpacker.Unpack(data: string): any
	local buf = buffer.fromstring(data)
	local offset = 0

	local fieldCount = buffer.readu16(buf, offset)
	offset += 2

	local result = {}

	for _ = 1, fieldCount do
		local key, newOffset = ReadValue(buf, offset)
		offset = newOffset
		local value, newOffset2 = ReadValue(buf, offset)
		offset = newOffset2
		result[key] = value
	end

	return result
end

-- GetPackedSize(): Calculates the size of the packed data without actually packing it
-- @param data: The table to calculate the size for
-- @return number: The size in bytes the packed data would occupy
function Bitpacker.GetPackedSize(data: Types.PackableTable): number
	return CalculateBufferSize(data)
end

-- GetCurrentSize(): Gets the current size of the table without compression
-- @param data: The table to calculate the size for
-- @return number: The amount of bytes
function Bitpacker.GetCurrentSize(data: Types.PackableTable): number
	local total = 0
	
	for k, v in data do
		total += GetRawSize(k)
		total += GetRawSize(v)
	end

	return total
end

return Bitpacker