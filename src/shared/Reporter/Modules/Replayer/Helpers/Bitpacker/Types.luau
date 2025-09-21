--!strict

--=======================
-- // TYPES
--=======================

export type PackableValue = string | number | boolean | PackableTable
export type PackableTable = { [PackableValue]: PackableValue }

export type Bitpacker = {
	Pack: (data: PackableTable) -> string,
	Unpack: (data: string) -> any,
	GetPackedSize: (data: PackableTable) -> number,
	GetCurrentSize: (data: PackableTable) -> number
}

return nil