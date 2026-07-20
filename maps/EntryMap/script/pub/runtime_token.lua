local M = {}

local TOKEN_KEY = '1234567890123456'
local TOKEN_IV = '1234567890123456'
local TOKEN_HOST = '192.168.82.11'
local TOKEN_TTL = 1440000

local function binary_to_hex(binary)
    return (binary:gsub('.', function(char)
        return string.format('%02x', string.byte(char))
    end))
end

---@param aid integer
---@param current_time integer
---@param crypto? table
---@return string? token
---@return integer|string expires_at_or_error
function M.generate(aid, current_time, crypto)
    aid = math.tointeger(aid)
    current_time = math.tointeger(current_time)
    if not aid then
        return nil, 'aid must be an integer'
    end
    if not current_time then
        return nil, 'current_time must be an integer'
    end

    crypto = crypto or rawget(_G, 'y3_crypto')
    if not crypto or type(crypto.aes_encrypt) ~= 'function' then
        return nil, 'y3_crypto.aes_encrypt is unavailable'
    end

    local expires_at = current_time + TOKEN_TTL
    local plain_text = string.format('%d %d %s', aid, expires_at, TOKEN_HOST)
    local ok, encrypted, encrypted_length = pcall(
        crypto.aes_encrypt,
        TOKEN_KEY,
        TOKEN_IV,
        plain_text,
        #plain_text
    )
    if not ok then
        return nil, tostring(encrypted)
    end
    if not encrypted then
        return nil, tostring(encrypted_length or 'AES encryption failed')
    end
    if type(encrypted) ~= 'string' then
        return nil, string.format('AES returned %s instead of binary string', type(encrypted))
    end
    encrypted_length = math.tointeger(encrypted_length)
    if not encrypted_length then
        return nil, 'AES did not return an integer encrypted length'
    end
    if encrypted_length ~= #encrypted then
        return nil, string.format(
            'AES encrypted length mismatch: reported=%s actual=%d',
            tostring(encrypted_length),
            #encrypted
        )
    end
    if encrypted_length == 0 or encrypted_length % 16 ~= 0 then
        return nil, string.format('AES encrypted length is invalid: %d', encrypted_length)
    end

    return binary_to_hex(encrypted), expires_at
end

return M
