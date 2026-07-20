package.path = 'maps/EntryMap/script/?.lua;' .. package.path

local runtime_token = require 'pub.runtime_token'

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

do
    local call
    local crypto = {
        aes_encrypt = function(key, iv, plain_text, plain_length)
            call = {
                key = key,
                iv = iv,
                plain_text = plain_text,
                plain_length = plain_length,
            }
            local encrypted = string.char(0, 1, 15, 16, 127, 128, 254, 255)
                .. 'abcdefgh'
            return encrypted, #encrypted
        end,
    }

    local token, expires_at = runtime_token.generate(1234567, 100, crypto)
    assert_equal(expires_at, 1440100, 'expiry')
    assert_equal(call.key, '1234567890123456', 'AES key')
    assert_equal(call.iv, '1234567890123456', 'AES iv')
    assert_equal(call.plain_text, '1234567 1440100 192.168.82.11', 'token plain text')
    assert_equal(call.plain_length, #call.plain_text, 'token plain length')
    assert_equal(token, '00010f107f80feff6162636465666768', 'hex token')
end

do
    local token, err = runtime_token.generate('bad-aid', 100, {})
    assert_equal(token, nil, 'invalid aid token')
    assert_equal(err, 'aid must be an integer', 'invalid aid error')
end

do
    local token, err = runtime_token.generate(1234567, 100, {})
    assert_equal(token, nil, 'missing AES token')
    assert_equal(err, 'y3_crypto.aes_encrypt is unavailable', 'missing AES error')
end

do
    local crypto = {
        aes_encrypt = function()
            return nil, 'test encryption failure'
        end,
    }
    local token, err = runtime_token.generate(1234567, 100, crypto)
    assert_equal(token, nil, 'AES failure token')
    assert_equal(err, 'test encryption failure', 'AES failure error')
end

do
    local crypto = {
        aes_encrypt = function()
            error('test encryption exception')
        end,
    }
    local token, err = runtime_token.generate(1234567, 100, crypto)
    assert_equal(token, nil, 'AES exception token')
    assert_equal(err:match('test encryption exception$'), 'test encryption exception', 'AES exception error')
end

do
    local crypto = {
        aes_encrypt = function()
            return string.rep('x', 16), 15
        end,
    }
    local token, err = runtime_token.generate(1234567, 100, crypto)
    assert_equal(token, nil, 'length mismatch token')
    assert_equal(err, 'AES encrypted length mismatch: reported=15 actual=16', 'length mismatch error')
end

print('runtime_token_test: PASS')
