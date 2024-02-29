
script_name('pilot')
script_author('vladiss')
script_version('1')

require('lib.moonloader')
local imgui = require('mimgui')
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local ev = require ("lib.samp.events")
local inicfg = require('inicfg')
local ffi = require('ffi')
local effil = require("effil")
local dlstatus = require("moonloader").download_status
local myfile = getWorkingDirectory().."//config//routes.json"


update_state =false

local script_vers = 1
local script_vers_text = "1.00"

local update_url = "https://raw.githubusercontent.com/thesirvladiss/pilotbot/main/update.ini"
local update_path = getWorkingDirectory() .. "/update.ini"

local script_url = ""
local script_path = thisScript().path

local play = false
local table_ = {}
local wm = require 'windows.message'
local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof

local renderWindow, freezePlayer, removeCursor = new.bool(), new.bool(), new.bool()
local sizeX, sizeY = getScreenResolution()
local pilotact = new.bool()

local control = {
    activate = new.bool(false),
    circle = new.int(0),
    circleStats = 0,
    timeStats = 0,
    step = 0,
    path = nil,
}
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
end)
local mainIni = inicfg.load({
    main = {
    autoEat = false,
    eatProcent = 1,
    offAdm = false,
    token = '',
    userId = ''
    }
}, 'autopilot/settings.ini')
if not doesFileExist('moonloader/config/autopilot/settings.ini') then
	inicfg.save(mainIni,'autopilot/settings.ini')
end
local autoEat = new.bool(mainIni.main.autoEat)
local eatProcent = new.int(mainIni.main.eatProcent)
local offAdm = new.bool(mainIni.main.offAdm)
local tkn = new.char[256](u8(mainIni.main.token))
local uid = new.char[256](u8(mainIni.main.userId))

function threadHandle(runner, url, args, resolve, reject)
    local t = runner(url, args)
    local r = t:get(0)
    while not r do
        r = t:get(0)
        wait(0)
    end
    local status = t:status()
    if status == 'completed' then
        local ok, result = r[1], r[2]
        if ok then resolve(result) else reject(result) end
    elseif err then
        reject(err)
    elseif status == 'canceled' then
        reject(status)
    end
    t:cancel(0)
end

function requestRunner()
    return effil.thread(function(u, a)
        local https = require 'ssl.https'
        local ok, result = pcall(https.request, u, a)
        if ok then
            return {true, result}
        else
            return {false, result}
        end
    end)
end

function async_http_request(url, args, resolve, reject)
    local runner = requestRunner()
    if not reject then reject = function() end end
    lua_thread.create(function()
        threadHandle(runner, url, args, resolve, reject)
    end)
end

function encodeUrl(str)
    str = str:gsub(' ', '%+')
    str = str:gsub('\n', '%%0A')
    return u8:encode(str, 'CP1251')
end

function sendTelegramNotification(msg) 
    msg = msg:gsub('{......}', '') 
    msg = encodeUrl(msg) 
    async_http_request('https://api.telegram.org/bot' .. mainIni.main.token .. '/sendMessage?chat_id=' .. mainIni.main.userId .. '&text='..msg,'', function(result) end) 
end

function get_telegram_updates() 
    while not updateid do wait(1) end 
    local runner = requestRunner()
    local reject = function() end
    local args = ''
    while true do
        url = 'https://api.telegram.org/bot'..mainIni.main.token..'/getUpdates?chat_id='..mainIni.main.userId..'&offset=-1'
        threadHandle(runner, url, args, processing_telegram_messages, reject)
        wait(0)
    end
end

function getLastUpdate() 
    async_http_request('https://api.telegram.org/bot'..mainIni.main.token..'/getUpdates?chat_id='..mainIni.main.userId..'&offset=-1','',function(result)
        if result then
            local proc_table = decodeJson(result)
            if proc_table.ok then
                if #proc_table.result > 0 then
                    local res_table = proc_table.result[1]
                    if res_table then
                        updateid = res_table.update_id
                    end
                else
                    updateid = 1 
                end
            end
        end
    end)
end

function ev.onShowDialog(id, style, title, b1, b2, text)
		if style == 2 or style == 4 then
            title = title
            text = text
		end
		if style == 5 then
            title = title
            text = text
		end
        if style == 0 then
            title = title
            text = text
        end
		sendTelegramNotification(title .. '\n' .. text)
end
local newFrame = imgui.OnFrame(
    function() return renderWindow[0] end,
    function(player)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 2, sizeY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(600, 400), imgui.Cond.FirstUseEver)
        imgui.Begin("Pilot Menu", renderWindow, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
        if imgui.Checkbox(u8"Состояние бота", control.activate) then
            control.timeStats = os.time()
        end
        imgui.SliderInt(u8'Количество рейсов', control.circle, 1, 999)

        imgui.Checkbox(u8"Авто еда", autoEat)
        mainIni.main.autoEat = autoEat[0]

        imgui.Text(u8'Процент сытости, при котором кушать:')
		imgui.SliderInt(u8'', eatProcent, 1, 99)
        mainIni.main.eatProcent = eatProcent[0]
        imgui.Checkbox(u8"Крашить игру, если вас заметил админ", autoEat)

        imgui.InputText(u8'Токен бота', tkn, sizeof(tkn))
        mainIni.main.token= u8:decode(ffi.string(tkn))

        imgui.InputText(u8'UserId', uid,sizeof(tkn))
        mainIni.main.userId= ffi.string(uid)
        if imgui.Button(u8'Сохранить настройки бота') then
            inicfg.save(mainIni, 'autopilot/settings.ini')
            sampAddChatMessage('Настройки сохранены', -1)
        end
        imgui.Separator()
        imgui.Text(u8'Всего рейсов сделано:' .. control.circleStats)
        imgui.Text(u8'Время работы:' .. get_timer(control.timeStats))
        imgui.End()
    end
)
function main()
    while not isSampAvailable() do wait(0) end
    sampRegisterChatCommand("pilot", function ()
        renderWindow[0] = not renderWindow[0]
    end) 
    sampRegisterChatCommand('route', playRoute)
    if not doesFileExist(myfile) then
		print('Config file not found!')
		createDirectory(getWorkingDirectory()..'\\config')
		local file = io.open(myfile, "w") file:close()
	else
		local file = io.open(myfile, "r")
		local fText = file:read()
		if fText ~= nil then
			table_ = decodeJson(fText)
		end
		file:close()
	end
    sampAddChatMessage("[Pilot] Активация /pilot", -1)

    downloadUrlToFile(update_url, update_path, function (id, status)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            updateIni = inicfg.load(nil, update_path)
            if tonumber(updateIni.info.vers) > script_vers then
                sampAddChatMessage('Есть обновление! Версия: ' .. updateIni.info.vers_text, -1)
                update_state = true
            end
            os.remove(update_path)
        end
    end)
    while true do
        wait(0)
        if update_state then
            downloadUrlToFile(script_url, script_path, function (id, status)
                if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                    this.script():reload()
                end
            end)
            break
        end
        if control.activate[0] then
            if control.circleStats == control.circle[0] and control.circleStats ~= 0 then
                control.step = 999
            end
            if control.step == 0 then
                setGameKeyState(21, -256)
                wait(2000)
                sampUseListboxItemByText(1421,"Частный самолет")
                sampCloseCurrentDialogWithButton()
                control.step = 5
            end
            if control.step == 1 then
                if control.path== "sf-ls" or control.path == "lv-ls" then
                    workthread = lua_thread.create(function()
                        playRoute("fls")
                    end)
                end
                if control.path== "sf-lv" or control.path == "ls-lv" then
                    workthread = lua_thread.create(function()
                    playRoute("flv")
                    end)
                end
                if control.path== "ls-sf" or control.path == "lv-sf" then
                    workthread = lua_thread.create(function()
                    playRoute("fsf")
                    end)
                end
                control.step = 6
            end
            if control.step == 2 then
                _, _, eat, _ = sampTextdrawGetBoxEnabledColorAndSize(2061)
                eat = (eat - imgui.ImVec2(sampTextdrawGetPos(2061)).x) * 1.83
                if autoEat[0] and math.floor(eat) < eatProcent[0] then
                    if sampTextdrawIsExists(2061) then
                        workthread = lua_thread.create(function()
                        playRoute("autoeat")
                        end)
                    else
                        sampAddChatMessage('У вас не включена полоска голода!', -1)
                    end
                else
                    workthread = lua_thread.create(function()
                    playRoute("fend")
                    end)
                end
                control.circleStats = control.circleStats + 1
                control.step = 5
            end
            if control.step == 4 then
                sampUseListboxItemByText(185,"Комплексный Обед")
                wait(1000)
                sampUseListboxItemByText(185,"Крылышки")
                wait(1000)
                sampUseListboxItemByText(185,"Крылышки")
                sampCloseCurrentDialogWithButton()
                wait(2000)
                workthread = lua_thread.create(function()
                    playRoute("aend")
                end)
                control.step = 5
            end
            if control.step == 5 then
                wait(1000)
            end
            if control.step == 3 then
                wait(4500)                
                if control.path == "ls-lv" then
                    workthread = lua_thread.create(function()
                    playRoute("lslv1")
                    end)
                end
                if control.path == "ls-sf" then
                    workthread = lua_thread.create(function()
                    playRoute("lssf1")
                    end)
                end
                if control.path == "lv-ls" then
                    workthread = lua_thread.create(function()
                    playRoute("lvls1")
                    end)
                end
                if control.path == "lv-sf" then
                    workthread = lua_thread.create(function()
                    playRoute("lvsf1")
                    end)
                end
                if control.path == "sf-ls" then
                    workthread = lua_thread.create(function()
                    playRoute("sfls1")
                    end)
                end
                if control.path == "sf-lv" then
                    workthread = lua_thread.create(function()
                    playRoute("sflv1")
                    end)
                end
                control.step = 5
            end
            if control.step == 999 then
                sampAddChatMessage('Все рейсы были выполнены!', -1)
                control.circleStats = 0
                control.activate[0] = not control.activate[0]
            end
        else
            control.step = 0
        end
    end
end

function sampUseListboxItemByText(id,text, plain)
    if not sampIsDialogActive() then return -1 end
        plain = not (plain == false)
    for i = 0, sampGetListboxItemsCount() -1 do
        if sampGetListboxItemText(i):find(text, 1, plain) then
            sampSendDialogResponse(id, 1, i,nil)
            return i
        end
    end
    return -1
end
function onReceivePacket(id)
    if id == 32 then
        control.activate[0] = not control.activate[0]
        sendTelegramNotification("Потеря соединения с сервером.")
        sampAddChatMessage('Автопилот выключен!', -1)
    end
end
function ev.onServerMessage(color, text)
    lua_thread.create(function()
        if text:gsub('{%w+}', ''):find("%['Лас Вентурас'%s-%->%s-'Сан Фиерро'%]") then
            control.path = "lv-sf"
            wait(1500)
            playRoute("start")
        end
        if text:gsub('{%w+}', ''):find("%['Лас Вентурас'%s-%->%s-'Лос Сантос'%]") then
            control.path = "lv-ls"
            wait(1500)
            playRoute("start")
        end
        if text:gsub('{%w+}', ''):find("%['Сан Фиерро'%s-%->%s-'Лас Вентурас'%]") then
            control.path = "sf-lv"
            wait(1500)
            playRoute("start")
        end
        if text:gsub('{%w+}', ''):find("%['Сан Фиерро'%s-%->%s-'Лос Сантос'%]") then
            control.path = "sf-ls"
            wait(1500)
            playRoute("start")
        end
        if text:gsub('{%w+}', ''):find("%['Лос Сантос'%s-%->%s-'Сан Фиерро'%]") then
            control.path = "ls-sf"
            wait(1500)
            playRoute("start")
        end
        if text:gsub('{%w+}', ''):find("%['Лос Сантос'%s-%->%s-'Лас Вентурас'%]") then
            control.path = "ls-lv"
            wait(1500)
            playRoute("start")
        end
        if text:find('администратор') or text:find('ответил вам') or text:find("заспавнил вас") or text:find('A: (.+) ответил вам%:') or text:find('%(%( A: (.+)%[%d+%]%:') or text:find('%(%( администратор .+%[(%d+)%]%:') then
            sendTelegramNotification('Подозрение на админа: '..text)
            if offAdm then
                callFunction(0x823BDB , 3, 3, 0, 0, 0)
            end
        end
    end)
end

function ev.onShowDialog(dialogId, title)
    lua_thread.create(function() 
        if dialogId == 1423 or title == "Подтверждение" then
            wait(1000)
            sampCloseCurrentDialogWithButton()
        end
    end)
end


function playRoute(arg)
	local index = 0
	for k, v in ipairs(table_) do
		if (v[1].name):find(arg) then index = k end
	end
	if index ~= 0 then 
		local timeTable_ = tableCopy(table_[index])
		local wait_ = timeTable_[1].name:match('%[(%d+)%]') or 50
		table.remove(timeTable_, 1)
		play = true
			printStyledString('~y~route played',2000,4)
			while #timeTable_ ~= 0 do wait(wait_)
				if not pause then
					if timeTable_[1].mode == 'onFoot' then
						local sync = samp_create_sync_data('player')
						sync.leftRightKeys = timeTable_[1].leftRightKeys
						sync.upDownKeys = timeTable_[1].upDownKeys
						sync.keysData = timeTable_[1].keysData
						sync.position = {timeTable_[1].position.x, timeTable_[1].position.y, timeTable_[1].position.z}
						sync.quaternion = {timeTable_[1].quaternion.w, timeTable_[1].quaternion.x, timeTable_[1].quaternion.y, timeTable_[1].quaternion.z}  
						sync.moveSpeed = {timeTable_[1].moveSpeed.x, timeTable_[1].moveSpeed.y, timeTable_[1].moveSpeed.z}
						sync.animationId = timeTable_[1].animationId
						sync.animationFlags = timeTable_[1].animationFlags
						sync.send()
						setCharCoordinatesDontResetAnim(PLAYER_PED, timeTable_[1].position.x, timeTable_[1].position.y, timeTable_[1].position.z)
						setCharHeading(PLAYER_PED, timeTable_[1].heading)
					elseif timeTable_[1].mode == 'onVeh' and isCharInAnyCar(PLAYER_PED) and getDriverOfCar(storeCarCharIsInNoSave(PLAYER_PED)) == PLAYER_PED then
						local vHandle = storeCarCharIsInNoSave(PLAYER_PED)
						setCarCoordinates(vHandle, timeTable_[1].position.x, timeTable_[1].position.y, timeTable_[1].position.z)
						setVehicleQuaternion(vHandle, timeTable_[1].quaternionFix.x, timeTable_[1].quaternionFix.y, timeTable_[1].quaternionFix.z, timeTable_[1].quaternionFix.w)
						local sync = samp_create_sync_data('vehicle')
						sync.leftRightKeys = timeTable_[1].leftRightKeys
						sync.upDownKeys = timeTable_[1].upDownKeys
						sync.keysData = timeTable_[1].keysData
						sync.position = {timeTable_[1].position.x, timeTable_[1].position.y, timeTable_[1].position.z}
						sync.quaternion = {timeTable_[1].quaternion.w, timeTable_[1].quaternion.x, timeTable_[1].quaternion.y, timeTable_[1].quaternion.z}  
						sync.moveSpeed = {timeTable_[1].moveSpeed.x, timeTable_[1].moveSpeed.y, timeTable_[1].moveSpeed.z}
						sync.send()
					end
					table.remove(timeTable_, 1)
				end
			end
			play = false
			printStyledString('~y~route ended',2000,4)
            if arg == "lslv1" or arg == "lssf1" or arg =="lvls1" or arg =="lvsf1" or arg == "sfls1" or arg == "sflv1" then 
                wait(1000)
                setGameKeyState(15, -256)
                wait(1500)
                control.step = 1
            end
            if arg == "start" then
                setGameKeyState(21, -256)
                control.step = 3
            end
            if arg == "fend" or arg == "aend" then
                control.step = 0
            end
            if arg == "autoeat" then
                control.step = 4
            end
            if arg == "flv" or arg == "fls" or arg == "fsf" then
                wait(1000)
                control.step = 2
            end
	else
		sampAddChatMessage('Route not found!', -1)
	end
end

function samp_create_sync_data(sync_type, copy_from_player)
    local ffi = require 'ffi'
    local sampfuncs = require 'sampfuncs'
    -- from SAMP.Lua
    local raknet = require 'samp.raknet'
    -- require 'samp.synchronization'
    copy_from_player = copy_from_player or true
    local sync_traits = {
        player = {'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData},
        vehicle = {'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData},
        passenger = {'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData},
        aim = {'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData},
        trailer = {'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData},
        unoccupied = {'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil},
        bullet = {'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil},
        spectator = {'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil}
    }
    local sync_info = sync_traits[sync_type]
    local data_type = 'struct ' .. sync_info[1]
    local data = ffi.new(data_type, {})
    local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
    -- copy player's sync data to the allocated memory
    if copy_from_player then
        local copy_func = sync_info[3]
        if copy_func then
            local _, player_id
            if copy_from_player == true then
                _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            else
                player_id = tonumber(copy_from_player)
            end
            copy_func(player_id, raw_data_ptr)
        end
    end
    -- function to send packet
    local func_send = function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, sync_info[2])
        raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
        raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
        raknetDeleteBitStream(bs)
    end
    -- metatable to access sync data and 'send' function
    local mt = {
        __index = function(t, index)
            return data[index]
        end,
        __newindex = function(t, index, value)
            data[index] = value
        end
    }
    return setmetatable({send = func_send}, mt)
end

function setCharCoordinatesDontResetAnim(char, x, y, z)
  if doesCharExist(char) then
    local ptr = getCharPointer(char)
    setEntityCoordinates(ptr, x, y, z)
  end
end

function setEntityCoordinates(entityPtr, x, y, z)
  if entityPtr ~= 0 then
    local matrixPtr = readMemory(entityPtr + 0x14, 4, false)
    if matrixPtr ~= 0 then
      local posPtr = matrixPtr + 0x30
      writeMemory(posPtr + 0, 4, representFloatAsInt(x), false) -- X
      writeMemory(posPtr + 4, 4, representFloatAsInt(y), false) -- Y
      writeMemory(posPtr + 8, 4, representFloatAsInt(z), false) -- Z
    end
  end
end

function tableCopy(t)
	local t2 = {}
	for k,v in pairs(t) do
		t2[k] = v
	end
	return t2
end

function ev.onSendPlayerSync(data)
	if pause then return data elseif play then return false end
end

function ev.onSendVehicleSync(data)
	if pause then return data elseif play then return false end
end
function get_timer(time)
    local jobsTime = os.time() - time
	return string.format("%s:%s:%s", string.format("%s%s", (tonumber(os.date("%H", jobsTime)) < tonumber(os.date("%H", 0)) and 24 + tonumber(os.date("%H", jobsTime)) - tonumber(os.date("%H", 0)) or tonumber(os.date("%H", jobsTime)) - tonumber(os.date("%H", 0))) < 10 and 0 or "", tonumber(os.date("%H", jobsTime)) < tonumber(os.date("%H", 0)) and 24 + tonumber(os.date("%H", jobsTime)) - tonumber(os.date("%H", 0)) or tonumber(os.date("%H", jobsTime)) - tonumber(os.date("%H", 0))), os.date("%M", jobsTime), os.date("%S", jobsTime))
end