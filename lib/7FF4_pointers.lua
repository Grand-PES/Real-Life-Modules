-- by FerJo75
-- v1.1: 3/Mar/2025

local m = { version = 1.1 }
local arrPointers_Addr = 0 -- game session main pointers address

function m.get_7ff4_pointers( offPointer ) -- offset of desired pointer

  local arr_uFormats = { "u8", "u16", "u32", "u32", "u64", "u64", "u64", "u64" } -- formats for 'index' Bytes when packing/unpacking

  local function _get_mem_value( addr, nBytes ) -- 8 bytes by default; use negative nBytes for signed format!

    nBytes = nBytes or 8
    local posBytes = math.abs( nBytes )

    local bytesFormat = arr_uFormats[ posBytes ]
    if nBytes < 0 then bytesFormat = bytesFormat:gsub( "u", "i", 1 ) end -- signed format ?

    return memory.unpack( bytesFormat, memory.read( addr, posBytes ) )
  end

  if arrPointers_Addr == 0 then -- still not set!

    local iniAddr = 0

    local function _get_absDestination( offRelative )

      local relAddr = _get_mem_value( iniAddr + offRelative, -4 ) -- 4 bytes signed !

      return iniAddr + relAddr + ( offRelative + 4 ) -- final address: initial + rel_offset + length_of_instruction (= offRelative + 4 )
    end

    local addr = memory.search_process( "\x48\x8B\x48\x48\x48\x81\xC1\xE0\xFE\xE9\x00" ) -- "pointer-of-7ff4-pointers"
    --[[ iniAddr  : E8 XXXXXXXX         - call <target_function> | call address => our pretended absolute address!
         addr     : 48 8B 48 48         - mov rcx,[rax+48]       | found AoB => our desired opcode is 5 bytes prior to that
         addr + 4 : 48 81 C1 E0FEE900   - add rcx,00E9FEE0       ]]--
    if not addr then error( "Unable to locate AoB for 'pointer-of-7ff4-pointers'... impossible to continue !" ) end

    iniAddr = addr - 5
    addr = _get_absDestination( 1 ) -- address of the called instruction; 1 = distance in bytes to the relative offset

    iniAddr = addr
    -- iniAddr   : 48 8B 05 XXXXXXXX   - mov rax,[<pointer_of_pointers>]  | targeted function
    addr = _get_absDestination( 3 ) -- address of the pointer; 3 = distance in bytes to the relative offset

    arrPointers_Addr = _get_mem_value( addr ) -- 8 bytes address
    if arrPointers_Addr == 0 then return end -- still not available !
  end
  return _get_mem_value( arrPointers_Addr + ( offPointer or 0 ) )
end

function m.init(ctx)
  ctx.base_pointers = m
end
return m
