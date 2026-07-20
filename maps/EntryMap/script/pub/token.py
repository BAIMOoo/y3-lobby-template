import time
import struct
import hashlib
from Crypto.Cipher import AES
import binascii
import time
import secrets

import random

def generate_seven_digit_number():
    # 生成一个7位数的最小值和最大值
    min_value = 1000000  # 最小的7位数
    max_value = 9999999  # 最大的7位数

    # 使用random.randint生成一个在最小值和最大值之间的随机数
    random_number = random.randint(min_value, max_value)

    return random_number

def pad(s):
    return s + (AES.block_size - len(s) % AES.block_size) * chr(0)

def TestPackToken():
    aid = generate_seven_digit_number()
    print('aid:',aid)
    test_str = "{} {} 192.168.82.11".format(aid, int(time.time()) + 1440000)
    plain_text_block = pad(test_str).encode('utf-8')

    key = b'1234567890123456'
    iv = b'1234567890123456'
    cipher = AES.new(key, AES.MODE_CBC, iv)
    ciphertext = cipher.encrypt(plain_text_block)

    result = binascii.hexlify(ciphertext).decode('utf-8')
    # print(result)
    return result

str = '\n\n'
for i in range(10):
    a = TestPackToken()
    str = str + f"'{a}',\n"
    # time.sleep(1)  # 暂停1秒

print(str)