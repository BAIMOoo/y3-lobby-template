---@class ECAHelper
---@field call fun(name: '大厅服务请求完成', 回调数据: table)
---@field call fun(name: '大厅服务状态变化', 事件数据: table)

---@diagnostic disable: invisible

y3.eca = y3.eca or {}
y3.eca.register_custom_event_impl = y3.eca.register_custom_event_impl or function (name, impl) end
y3.eca.register_custom_event_resolve = y3.eca.register_custom_event_resolve or function (name, resolve) end

y3.eca.register_custom_event_impl('大厅服务请求完成', function (_, 回调数据)
    y3.game.send_custom_event(1876423410, {
        ["回调数据"] = 回调数据
    })
end)

y3.eca.register_custom_event_impl('大厅服务状态变化', function (_, 事件数据)
    y3.game.send_custom_event(1204774815, {
        ["事件数据"] = 事件数据
    })
end)

y3.const.CustomEventName = y3.const.CustomEventName or {}

y3.const.CustomEventName['大厅服务请求完成'] = 1876423410
y3.const.CustomEventName['大厅服务状态变化'] = 1204774815

---@enum(key, partial) y3.Const.CustomEventName
local CustomEventName = {
    ['大厅服务请求完成'] = 1876423410,
    ['大厅服务状态变化'] = 1204774815,
}

y3.eca.register_custom_event_resolve("大厅服务请求完成", function (data)
    data.name = "大厅服务请求完成"
    data.data = {
        ["回调数据"] = data.c_param_dict["回调数据"],
    }
    return data
end)
y3.eca.register_custom_event_resolve("大厅服务状态变化", function (data)
    data.name = "大厅服务状态变化"
    data.data = {
        ["事件数据"] = data.c_param_dict["事件数据"],
    }
    return data
end)

---@alias EventParam.游戏-消息.大厅服务请求完成 { c_param_1: 1876423410, c_param_dict: py.Dict, event: "大厅服务请求完成", data: { ["回调数据"]: table } }
---@alias EventParam.游戏-消息.大厅服务状态变化 { c_param_1: 1204774815, c_param_dict: py.Dict, event: "大厅服务状态变化", data: { ["事件数据"]: table } }

---@class Game
---@diagnostic disable-next-line: duplicate-doc-field
---@field event fun(self: Game, event: "游戏-消息", event_id: "大厅服务请求完成", callback: fun(trigger: Trigger, data: EventParam.游戏-消息.大厅服务请求完成))
---@diagnostic disable-next-line: duplicate-doc-field
---@field event fun(self: Game, event: "游戏-消息", event_id: "大厅服务状态变化", callback: fun(trigger: Trigger, data: EventParam.游戏-消息.大厅服务状态变化))
