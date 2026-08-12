--玩家状态
PlayerState = {
    Normal = 1,     --空闲
    Matching = 2,   --匹配
}

--队伍状态
TeamState = {
    Normal = 1,     --正常
    Matching = 2,   --匹配中
}

--聊天频道 = {
ChannelType = {
    Team = 4,       --队伍聊天
}

---@class CallInfo
---@field public call_id integer 'call id'
---@field public service_uuid integer 'service uuid'
---@field public method_index integer 'method index'
---@field public request_data string 'request proto data'

---@class PlayerInfo
---@field public aid integer '玩家ID'
---@field public head_icon string '头像'
---@field public name string '玩家昵称'
---@field public state integer '玩家状态'
---@field public score integer '玩家分数
---@field public map_id string '当前地图版本id'
---@field public in_game boolean '是否在游戏中'
---@field public state_change_reason? 0|1|2|3 # 状态改变的原因，0：无；1：匹配成功；2：取消匹配；3: 开始匹配
---@field public game_play_id integer '地图固定id'

---@class MatchInfo
---@field public map_id string '地图版本ID'
---@field public level_id string 'level id'
---@field public game_mode integer 'game mode'
---@field public game_play_id string '地图固定id'

---@class ChatSender
---@field public aid integer '发送者ID'
---@field nickname string '发送者昵称'
---@field head_icon string '发送者头像'







---@class Role
---@field public role_color string
---@field public role_name string
---@field public camp_id integer
---@field public role_type integer

---@class CampInfo
---@field public camp table
---@field public role table
---@field public camp_limit integer

---@class BattleMapInfo
---@field public map_id string
---@field public game_play_id string
---@field public map_type integer
---@field public logic_fps integer //逻辑帧 默认30
---@field public camp_info CampInfo //阵营信息

---@class MultiBattleSlotField
---@field public aid integer
---@field public role_id integer
---@field public camp_id integer
---@field public nickname string
---@field public repo table
---@field public archives table


---本地多开战场参数
---@class MultiBattleField
---@field public owner_aid string //本地多开作者aid
---@field public timestamp integer //发起请求时间戳
---@field public region string  //作者所在地区
---@field public game_mode integer //游戏模式
---@field public token string  //令牌
---@field public slots table  //槽位信息
---@field public map_info BattleMapInfo //地图信息
---@field public stuff_templates table //地图道具模板

---切副本
---@class DungeonSpaceField '副本信息'
---@field public game_map_id string '地图版本ID'
---@field public level_id string 'level id'
---@field public game_mode integer 'game mode'

---@class DungeonPlayerField '玩家信息'
---@field public aid string '玩家ID'
---@field public version string '客户端版本；多人副本RPC必填，当前固定为2.0'
