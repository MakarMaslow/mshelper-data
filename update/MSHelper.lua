script_name('MS Helper')
script_author('Makar Maslow And Anray Maslow')
script_description('MSHelper')

require 'lib.moonloader'
local sampev = require 'lib.samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local bit = require 'bit'

local cfg_path = 'ms_helper.ini'

-- SAFE NO-FILES MODE
-- Не создаём папки config/MSHelper и не читаем/пишем дополнительные players.ini/prices.ini.
-- Это убирает os.execute('mkdir'), который на некоторых сборках сворачивает игру.
local stable_dir = ''
local players_path = ''
local prices_path = ''

local function ensure_stable_dir() return true end
local function read_kv_ini(path, section) return {} end
local function write_kv_ini(path, section, tbl) return true end
local function write_default_file_if_missing(path, section, tbl) return true end

local stable_player_org = {}
local stable_price_overrides = {}

local main_window = imgui.new.bool(false)
local gos_window = imgui.new.bool(false)
local patient_window = imgui.new.bool(false)
local invite_window = imgui.new.bool(false)
local uninvite_window = imgui.new.bool(false)
local rang_window = imgui.new.bool(false)
local interview_window = imgui.new.bool(false)
local invite_player_id = imgui.new.int(0)
local uninvite_player_id = imgui.new.int(0)
local rang_player_id = imgui.new.int(0)
local interview_player_id = imgui.new.int(0)
local uninvite_reason_buffer = imgui.new.char[128]()
local active_tab = 4 -- открываем /ms сначала на безопасной вкладке Команды
local selected_binder_slot = 1
local binder_wait_key_slot = 0
local selected_patient = -1
local selected_illness = 1
local interview_step = 1
local interview_action_busy = false
local interview_player_nick = ''
local pending_main_window_toggle = false
local selected_action_edit = 'mask'
local rpgos_tab = 1
local selected_gos_hospital = 'sf'
local edit_dialog_mode = nil
local edit_dialog_a = 0
local edit_dialog_b = 0
local pending_bed_hint_until = 0
local last_bed_hint_time = 0
local dis_dialog_id = -1
local dis_dialog_until = 0
local dis_command_until = 0
local analysis_dialog_id = -1
local analysis_dialog_until = 0
local analysis_command_until = 0

-- RP-строки для системного лечения через /dis id.
-- Нумерация соответствует пунктам в диалоге "Лечение болезней" на сервере.
local dis_illness_rp = {
    '/me аккуратно подготовил свечи и передал пациенту с рекомендациями по применению',
    '/me размял руки и аккуратно провел лечебный массаж пациенту',
    '/me подготовил капельницу и подключил ее пациенту, контролируя состояние',
    '/me достал антибиотики и передал пациенту курс лечения',
    '/me подготовил ингалятор и помог пациенту провести ингаляцию'
}

-- RP-строки для системной команды /analysis id.
-- Нумерация соответствует пунктам в диалоге анализов на сервере.
local analysis_rp = {
    '/me оформил направление на сдачу крови и передал его пациенту',
    '/me передал пациенту стерильный контейнер для сдачи анализа мочи',
    '/me подготовил направление на компьютерную томографию и передал его пациенту',
    '/me подготовил направление на магнитно-резонансную томографию и передал его пациенту'
}

local illnesses = {
    {'Головная боль', 'Цитрамон'},
    {'Боль в животе, тошнота', 'Энтерофурил'},
    {'Боль в паху', 'Ибупрофен'},
    {'Сердечная боль', 'Валидол'},
    {'Простуда и жар', 'Парацетамол'},
    {'Кашель', 'Синекод'},
    {'Боль в горле', 'Стрепсилс'},
    {'Аллергия', 'Супрастин'},
    {'Ожоги', 'Пантенол'},
    {'Капли для глаз', 'Тобрекс'},
    {'Боль в почках', 'Но-шпа'},
    {'Повышенное давление', 'Каптоприл'},
    {'Пониженное давление', 'Цитрамон'}
}

local cfg = inicfg.load({
    main = {
        female = true,
        clean_online = false,
        show_heal_debug = false,
        tag_where_ok = true,
        tag_r = false,
        tag_f = false,
        interaction_key = 71, -- G
        heal_price = 300,
        hide_smi_ads = false,
        hide_job_chat = false,
        custom_find = false,
        hide_admin_punishments = true,
        doctor_name = '',
        theme = 'cyan'
    },
    prices = {
        civil = 800,
        ambulance = 300,
        gangs = 2500,
        yakuza = 3000,
        smi = 1,
        mo = 1,
        lkn = 3000,
        pravo = 3000,
        mz = 3000,
        rm = 3000,
        mvd = 1,
        heal = 300
    },
    org = {
        auto_detect = true,
        fallback = 'civil'
    },
    reconnect = {
        auto = false,
        delay = 5,
        server_ip = '',
        server_port = 0
    },
    shpora = {
        server_mode = 'auto',
        manual_server = 'green'
    },
    phone = {
        enabled = true,
        greeting = ''
    },
    gos = {
        line1 = 'МЗ | Сейчас пройдет собеседование в больницу ш. San-Fierro.',
        line2 = 'МЗ | Критерии: 3 года в штате, базовые права, не иметь судимостей.',
        line3 = 'МЗ | Высокие премии и лояльный коллектив только у нас. GPS: 3-13.',
        cooldown_until = 0
    },
    gos_sf = {
        line1 = 'МЗ | Сейчас пройдет собеседование в больницу ш. San-Fierro.',
        line2 = 'МЗ | Критерии: 3 года в штате, базовые права, не иметь судимостей.',
        line3 = 'МЗ | Высокие премии и лояльный коллектив только у нас. GPS: 3-13.',
        single = 'МЗ | Сейчас пройдет собеседование в больницу ш. San-Fierro. GPS: 3-13.'
    },
    gos_ls = {
        line1 = 'МЗ | Сейчас пройдет собеседование в больницу г. Los-Santos.',
        line2 = 'МЗ | Критерии: 3 года в штате, базовые права, не иметь судимостей.',
        line3 = 'МЗ | Высокие премии и лояльный коллектив только у нас. GPS: укажите GPS.',
        single = 'МЗ | Сейчас пройдет собеседование в больницу г. Los-Santos. GPS: укажите GPS.'
    },
    gos_lv = {
        line1 = 'МЗ | Сейчас пройдет собеседование в больницу г. Las-Venturas.',
        line2 = 'МЗ | Критерии: 3 года в штате, базовые права, не иметь судимостей.',
        line3 = 'МЗ | Высокие премии и лояльный коллектив только у нас. GPS: укажите GPS.',
        single = 'МЗ | Сейчас пройдет собеседование в больницу г. Las-Venturas. GPS: укажите GPS.'
    },
    gos_mz = {
        line1 = 'Ищем новых сотрудников в Министерство Здравоохранения.',
        line2 = 'Приходите на собеседование в Больницы всех штатов.',
        line3 = 'Документы и хорошее настроение. GPS 3-12, 3-13, 3-14.',
        single = 'Ищем новых сотрудников в Министерство Здравоохранения.'
    },
    rpgos1 = {
        line1 = '[RP] Уважаемые жители штата, проводится набор в организацию.',
        line2 = '[RP] Собеседование проходит в холле организации.',
        line3 = '[RP] При себе иметь паспорт, лицензии и мед.карту.'
    },
    rpgos2 = {
        line1 = '[RP] Уважаемые жители штата, проводится мероприятие.',
        line2 = '[RP] Подробности уточняйте у сотрудников организации.',
        line3 = '[RP] Желаем всем приятного времяпровождения.'
    },
    rpgos3 = {
        line1 = '[RP] Уважаемые жители штата, организация работает в штатном режиме.',
        line2 = '[RP] По вопросам обращайтесь к сотрудникам организации.',
        line3 = '[RP] Благодарим за внимание.'
    },
    rpgos4 = {
        line1 = '[RP] Уважаемые жители штата, просим соблюдать порядок.',
        line2 = '[RP] Следите за объявлениями и указаниями сотрудников.',
        line3 = '[RP] Спасибо за понимание.'
    }
}, cfg_path)

cfg.main = cfg.main or {}
cfg.main.clean_online = false -- Чистый онлайн убран из меню и отключен.
-- Имя врача для RP-приветствия.
-- По умолчанию пустое: скрипт пытается взять ник самого игрока.
-- Если автоник не работает на сборке игрока, можно вручную прописать имя через /msname Имя Фамилия.
if cfg.main.doctor_name == nil then cfg.main.doctor_name = '' end
if cfg.main.female == nil then cfg.main.female = true end
if cfg.main.tag_r == nil then cfg.main.tag_r = false end
if cfg.main.tag_f == nil then cfg.main.tag_f = false end
if cfg.main.r_tag == nil then cfg.main.r_tag = '' end
if cfg.main.f_tag == nil then cfg.main.f_tag = '' end
_G.MSHelper_TagREnabled = imgui.new.bool(cfg.main.tag_r == true)
_G.MSHelper_TagFEnabled = imgui.new.bool(cfg.main.tag_f == true)
_G.MSHelper_TagRBuffer = imgui.new.char[64](cfg.main.r_tag or '')
_G.MSHelper_TagFBuffer = imgui.new.char[64](cfg.main.f_tag or '')
_G.MSHelper_OkReportId = _G.MSHelper_OkReportId or imgui.new.int(0)
-- Техническая отладка лечения убрана из меню и принудительно отключена.
-- Скрытие рабочего чата /j и /jn убрано: на сервере уже есть штатная настройка.
cfg.main.show_heal_debug = false
if cfg.main.hide_smi_ads == nil then cfg.main.hide_smi_ads = false end
cfg.main.hide_job_chat = false
if cfg.main.custom_find == nil then cfg.main.custom_find = false end
cfg.main.custom_tab = false -- Custom TAB убран: на некоторых сборках ломал ввод в поля /ms
cfg.main.hide_admin_punishments = true -- скрытие админ-наказаний включено всегда, пункт из меню убран
if cfg.main.theme == nil then cfg.main.theme = 'cyan' end
cfg.reconnect = cfg.reconnect or {}
if cfg.reconnect.auto == nil then cfg.reconnect.auto = false end
if cfg.reconnect.delay == nil then cfg.reconnect.delay = 5 end
if cfg.reconnect.server_ip == nil then cfg.reconnect.server_ip = '' end
if cfg.reconnect.server_port == nil then cfg.reconnect.server_port = 0 end
cfg.shpora = cfg.shpora or {}
if cfg.shpora.server_mode == nil then cfg.shpora.server_mode = 'auto' end
if cfg.shpora.manual_server == nil then cfg.shpora.manual_server = 'green' end

cfg.phone = cfg.phone or {}
if cfg.phone.enabled == nil then cfg.phone.enabled = true end
-- По умолчанию приветствие /p пустое, но если игрок сам ввёл даже старую стандартную фразу,
-- больше не очищаем её при запуске.
if cfg.phone.greeting == nil then
    cfg.phone.greeting = ''
end
MSH_PHONE_GREET_ENABLED = imgui.new.bool(cfg.phone.enabled == true)
MSH_PHONE_GREET_BUFFER = imgui.new.char[512](cfg.phone.greeting or '')
MSH_PHONE_GREET_DELAY = 700

-- Custom TAB убран. Оставляем значения выключенными для совместимости со старыми конфигами.
MSH_CUSTOM_TAB_ENABLED = imgui.new.bool(false)
MSH_CUSTOM_TAB_WINDOW = imgui.new.bool(false)
MSH_CUSTOM_TAB_SEARCH_BUFFER = imgui.new.char[64]('')
MSH_CUSTOM_TAB_LAST_TOGGLE = 0
MSH_CUSTOM_TAB_SUPPRESS_UNTIL = 0

-- MS Helper | Кастомный /find сотрудников.
-- Не трогает клавишу TAB. Если включён, обычная команда /find открывает удобное окно MS Helper.
MSH_CUSTOM_FIND_ENABLED = MSH_CUSTOM_FIND_ENABLED or imgui.new.bool(cfg.main.custom_find == true)
MSH_FIND_STAFF_WINDOW = MSH_FIND_STAFF_WINDOW or imgui.new.bool(false)
MSH_FIND_ACTION_WINDOW = MSH_FIND_ACTION_WINDOW or imgui.new.bool(false)
MSH_FIND_SEARCH_BUFFER = MSH_FIND_SEARCH_BUFFER or imgui.new.char[96]('')
MSH_FIND_ROWS = MSH_FIND_ROWS or {}
MSH_FIND_META = MSH_FIND_META or { total = '?', online = '?' }
MSH_FIND_SELECTED = MSH_FIND_SELECTED or { id = -1, nick = '', rank = '', phone = '', extra = '' }
MSH_FIND_EXPECT_UNTIL = MSH_FIND_EXPECT_UNTIL or 0
MSH_FIND_ALLOW_SYSTEM_ONCE = MSH_FIND_ALLOW_SYSTEM_ONCE or false
MSH_FIND_AUTO_REFRESH_NEXT = MSH_FIND_AUTO_REFRESH_NEXT or 0
MSH_FIND_AUTO_REFRESH_BUSY = MSH_FIND_AUTO_REFRESH_BUSY or false

local rc = {
    auto = imgui.new.bool(false), -- авто-реконнект отключен: на некоторых сборках вызывает ошибку coroutine
    delay = imgui.new.int(tonumber(cfg.reconnect.delay) or 5),
    running = false,
    was_connected = false,
    next_try_at = 0,
    last_state_check = 0,
    last_server_save = 0
}
if rc and rc.auto then rc.auto[0] = false end
cfg.player_org = cfg.player_org or {}
stable_player_org = cfg.player_org


-- ЕЦП для автоматических цен лечения.
-- Важно: больше НЕ перезаписываем сохраненные цены при каждом запуске.
-- Если вы поменяли цену в меню, она останется после перезапуска скрипта.
cfg.prices = cfg.prices or {}
if cfg.prices.civil == nil then cfg.prices.civil = 800 end
if cfg.prices.ambulance == nil then cfg.prices.ambulance = 300 end
if cfg.prices.gangs == nil then cfg.prices.gangs = 2500 end
if cfg.prices.yakuza == nil then cfg.prices.yakuza = 3000 end
if cfg.prices.smi == nil then cfg.prices.smi = 1 end
if cfg.prices.mo == nil then cfg.prices.mo = 1 end
if cfg.prices.lkn == nil then cfg.prices.lkn = 3000 end
if cfg.prices.pravo == nil then cfg.prices.pravo = 3000 end
if cfg.prices.mz == nil then cfg.prices.mz = 3000 end
if cfg.prices.rm == nil then cfg.prices.rm = 3000 end
if cfg.prices.mvd == nil then cfg.prices.mvd = 1 end
if cfg.prices.heal == nil then cfg.prices.heal = 300 end

cfg.actions = cfg.actions or {}
cfg.actions.skip = nil
local action_list = {'mask','find','lock','healme','changeskin','c60'}
for _, k in ipairs(action_list) do if cfg.actions[k] == nil then cfg.actions[k] = true end end

cfg.rptexts = cfg.rptexts or {
    -- Пустое значение = встроенная RP-отыгровка.
    -- Свой текст можно задать через меню /ms или командой /msrp key текст.
    mask = '',
    find = '',
    lock = '',
    healme = '',
    changeskin = '',
    c60 = ''
}
local legacy_action_rp_defaults = {
    mask = '/me достал медицинскую маску и аккуратно надел её на лицо',
    find = '/me открыл рабочий планшет и проверил данные.',
    lock = '/me достал ключи и провернул замок.',
    healme = '/me достал из сумки лекарство и принял его.',
    changeskin = '/me выдал сотруднику новую рабочую форму.',
    c60 = '/me движением руки закатал рукав затем посмотрел на часы.'
}
for _, k in ipairs(action_list) do
    if cfg.rptexts[k] == nil or cfg.rptexts[k] == legacy_action_rp_defaults[k] then
        cfg.rptexts[k] = ''
    end
    -- Если раньше кнопка "Подставить RP" сохранила битую кодировку,
    -- очищаем такую строку, чтобы вернулся нормальный встроенный RP.
    if type(cfg.rptexts[k]) == 'string' and (cfg.rptexts[k]:find('Рџ') or cfg.rptexts[k]:find('Рґ') or cfg.rptexts[k]:find('Рј') or cfg.rptexts[k]:find('С‚')) then
        cfg.rptexts[k] = ''
    end
end
-- Миграция старого шаблона /c 60: убираем ник в конце, если он был сохранен ранее.
if type(cfg.rptexts.c60) == 'string' then
    cfg.rptexts.c60 = cfg.rptexts.c60:gsub('%s*%(%s*{nick}%s*%)', ''):gsub('{nick}', '')
end
cfg.ruk = cfg.ruk or { staff_id = 0, radio_text = 'явитесь в больницу' }
local action_enabled = {}
for _, k in ipairs(action_list) do action_enabled[k] = imgui.new.bool(cfg.actions[k]) end

local action_labels = {
    mask = '/mask', find = '/find', lock = '/lock 1-8', healme = '/healme',
    changeskin = '/changeskin', c60 = '/c 60'
}

local action_rp_buffers = {}
for _, k in ipairs(action_list) do
    if cfg.rptexts[k] == nil then cfg.rptexts[k] = '' end
    if k == 'changeskin' and type(cfg.rptexts[k]) == 'string' then
        if cfg.rptexts[k]:find('Nick Name', 1, true)
            or cfg.rptexts[k]:find('{игрока}', 1, true)
            or cfg.rptexts[k]:find('пакет с формой для', 1, true)
            or cfg.rptexts[k]:find('передала пакет с формой', 1, true)
            or cfg.rptexts[k]:find('выдал пакет с формой', 1, true) then
            cfg.rptexts[k] = '/do В руках заранее подготовленный комплект с формой. | /me передает пакет с формой сотруднику'
        end
    end
    action_rp_buffers[k] = imgui.new.char[256](cfg.rptexts[k] or '')
end

local ruk_staff_id = imgui.new.int(cfg.ruk.staff_id or 0)
local ruk_radio_text = imgui.new.char[128](cfg.ruk.radio_text or 'явитесь в больницу')
local script_started_at = os.time()
local last_activity_at = os.time()
local last_clean_c60 = 0

local pending_invites = {}
local script_invite_guard = false
local script_uninvite_guard = false
local script_rang_guard = false
local script_drive_guard = false
local script_givemed_guard = false
local script_action_guard = false
local script_binder_guard = false
local script_heal_guard = false
local script_to_guard = false

local last_med_call_id = -1
local last_med_call_nick = ''
local last_med_call_time = 0

local binder = {}
for i = 1, 22 do
    local s = 'slot' .. i
    if not cfg[s] then cfg[s] = { text = '', key = 0, delay = 1000, command = 'b'..i } end
    if cfg[s].key == nil then cfg[s].key = 0 end
    if cfg[s].delay == nil then cfg[s].delay = 1000 end
    if cfg[s].command == nil then cfg[s].command = 'b'..i end
    binder[i] = imgui.new.char[512](cfg[s].text or '')
end

local binder_key = {}
local binder_delay = {}
local binder_command = {}
for i = 1, 22 do
    local s = 'slot' .. i
    binder_key[i] = imgui.new.int(cfg[s].key or 0)
    binder_delay[i] = imgui.new.int(cfg[s].delay or 1000)
    binder_command[i] = imgui.new.char[32](cfg[s].command or ('b'..i))
end

local gos_hospitals = {
    { key = 'sf', title = 'SF' },
    { key = 'ls', title = 'LS' },
    { key = 'lv', title = 'LV' },
    { key = 'mz', title = 'МЗ' }
}

local gos_lines = {}
local gos_single_lines = {}
for _, h in ipairs(gos_hospitals) do
    local sec_name = 'gos_' .. h.key
    cfg[sec_name] = cfg[sec_name] or {}
    -- Миграция старых сохраненных строк: старый cfg.gos остается для КД, а строки переносим в SF.
    if h.key == 'sf' and cfg.gos then
        cfg[sec_name].line1 = cfg[sec_name].line1 or cfg.gos.line1
        cfg[sec_name].line2 = cfg[sec_name].line2 or cfg.gos.line2
        cfg[sec_name].line3 = cfg[sec_name].line3 or cfg.gos.line3
        cfg[sec_name].single = cfg[sec_name].single or cfg.gos.single or cfg.gos.line1
    end
    gos_lines[h.key] = {
        imgui.new.char[256](cfg[sec_name].line1 or ''),
        imgui.new.char[256](cfg[sec_name].line2 or ''),
        imgui.new.char[256](cfg[sec_name].line3 or '')
    }
    gos_single_lines[h.key] = imgui.new.char[256](cfg[sec_name].single or cfg[sec_name].line1 or '')
end

local function normalize_gos_hospital(key)
    key = tostring(key or ''):lower()
    if key == 'сф' or key == 'san-fierro' or key == 'sf' then return 'sf' end
    if key == 'лс' or key == 'los-santos' or key == 'ls' then return 'ls' end
    if key == 'лв' or key == 'las-venturas' or key == 'lv' then return 'lv' end
    if key == 'мз' or key == 'mz' or key == 'all' or key == 'all-mz' then return 'mz' end
    return nil
end

local function active_gos_lines()
    return gos_lines[selected_gos_hospital] or gos_lines.sf
end

local function active_gos_single_line()
    return gos_single_lines[selected_gos_hospital] or gos_single_lines.sf
end

local rpgos_lines = {}
for set = 1, 4 do
    local sec = cfg['rpgos' .. set] or {}
    rpgos_lines[set] = {
        imgui.new.char[256](sec.line1 or ''),
        imgui.new.char[256](sec.line2 or ''),
        imgui.new.char[256](sec.line3 or '')
    }
end

local price = {}
for k, v in pairs(cfg.prices) do
    local ov = stable_price_overrides[k]
    if ov and tonumber(ov) then v = tonumber(ov); cfg.prices[k] = v end
    price[k] = imgui.new.int(v)
end
if next(stable_price_overrides) == nil then
    local defaults = {}
    for k, v in pairs(cfg.prices) do defaults[k] = tostring(v) end
    write_kv_ini(prices_path, 'prices', defaults)
end

local org_names = {
    ambulance = 'В карете',
    civil = 'Гражданский', gangs = 'Банды', yakuza = 'Yakuza', smi = 'СМИ',
    mo = 'МО', lkn = 'ЛКН', pravo = 'Право', mz = 'МЗ', rm = 'РМ', mvd = 'МВД'
}
local org_order = {'civil','gangs','yakuza','smi','mo','lkn','pravo','mz','rm','mvd'}
-- Автоопределение организации всегда включено. Переключатель в меню скрыт,
-- чтобы обычному игроку не нужно было настраивать этот пункт вручную.
cfg.org = cfg.org or {}
cfg.org.auto_detect = true
local auto_org = imgui.new.bool(true)
local manual_player_org = {}

local function trim(s) return (s or ''):gsub('^%s+', ''):gsub('%s+$', '') end

local function normalize_binder_command(raw, slot)
    local cmd = trim(tostring(raw or ''))
    cmd = cmd:gsub('^/', '')
    cmd = cmd:match('^(%S+)') or ''
    if cmd == '' then cmd = 'b' .. tostring(slot or 1) end
    if #cmd > 30 then cmd = cmd:sub(1, 30) end
    return cmd
end

local function binder_command_label(slot)
    if not binder_command[slot] then return '/b' .. tostring(slot) end
    return '/' .. normalize_binder_command(ffi.string(binder_command[slot]), slot)
end

local function vk_name(vk)
    vk = tonumber(vk) or 0
    if vk == 0 then return 'не назначена' end
    if vk >= 0x30 and vk <= 0x39 then return string.char(vk) end
    if vk >= 0x41 and vk <= 0x5A then return string.char(vk) end
    if vk >= 0x70 and vk <= 0x7B then return 'F' .. tostring(vk - 0x6F) end
    if vk >= 0x60 and vk <= 0x69 then return 'Num' .. tostring(vk - 0x60) end

    local names = {
        [0x08] = 'Backspace', [0x14] = 'CapsLock', [0x20] = 'Space',
        [0x21] = 'PageUp', [0x22] = 'PageDown', [0x23] = 'End', [0x24] = 'Home',
        [0x25] = 'Left', [0x26] = 'Up', [0x27] = 'Right', [0x28] = 'Down',
        [0x2D] = 'Insert', [0x2E] = 'Delete',
        [0x6A] = 'Num*', [0x6B] = 'Num+', [0x6D] = 'Num-', [0x6E] = 'Num.', [0x6F] = 'Num/',
        [0xBA] = ';', [0xBB] = '+', [0xBC] = ',', [0xBD] = '-', [0xBE] = '.', [0xBF] = '/',
        [0xC0] = '~', [0xDB] = '[', [0xDC] = '\\', [0xDD] = ']', [0xDE] = "'"
    }
    return names[vk] or ('VK ' .. tostring(vk))
end

local function get_pressed_binder_key()
    local keys = {}

    for vk = 0x30, 0x39 do table.insert(keys, vk) end -- 0-9
    for vk = 0x41, 0x5A do table.insert(keys, vk) end -- A-Z
    for vk = 0x70, 0x7B do table.insert(keys, vk) end -- F1-F12
    for vk = 0x60, 0x69 do table.insert(keys, vk) end -- Num0-Num9

    local extra = {
        0x08, 0x14, 0x1B, 0x20, 0x21, 0x22, 0x23, 0x24,
        0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E,
        0x6A, 0x6B, 0x6D, 0x6E, 0x6F,
        0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE
    }
    for _, vk in ipairs(extra) do table.insert(keys, vk) end

    for _, vk in ipairs(keys) do
        if wasKeyPressed and wasKeyPressed(vk) then
            return vk
        end
    end

    return nil
end


local function map_org_name(raw)
    raw = trim(tostring(raw or ''))
    if raw == '' or raw == 'None' or raw == 'none' or raw == 'nil' then return nil end
    if raw == 'МЗ' then return 'mz' end
    if raw == 'МВД' then return 'mvd' end
    if raw == 'СМИ' then return 'smi' end
    if raw == 'МО' then return 'mo' end
    if raw == 'ЛКН' then return 'lkn' end
    if raw == 'РМ' then return 'rm' end
    if raw == 'Yakuza' or raw == 'Якудза' then return 'yakuza' end
    local low = raw:lower()
    if low:find('граждан') or low:find('civil') then return 'civil' end
    if low:find('банд') or low:find('gang') or low:find('grove') or low:find('ballas') or low:find('vagos') or low:find('rifa') then return 'gangs' end
    if low:find('yakuza') or low:find('якуд') then return 'yakuza' end
    if low:find('сми') or low:find('news') then return 'smi' end
    if low == 'мо' or low:find('арм') or low:find('министерство обор') then return 'mo' end
    if low:find('лкн') or low:find('la cosa') or low:find('lcn') then return 'lkn' end
    if low:find('прав') or low:find('право') or low:find('government') then return 'pravo' end
    if low == 'мз' or low:find('больниц') or low:find('минздрав') or low:find('medical') then return 'mz' end
    if low == 'рм' or low:find('russian') or low:find('русск') then return 'rm' end
    if low:find('мвд') or low:find('полици') or low:find('фбр') or low:find('дпс') or low:find('lspd') or low:find('sfpd') or low:find('lvpd') then return 'mvd' end
    return nil
end

local function color_to_hex(color)
    if not color then return '' end
    return string.format('%08X', color)
end

local function rgb_from_samp_color(color)
    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)
    if r == 0 and g == 0 and b == 0 then
        r = bit.band(bit.rshift(color, 24), 0xFF)
        g = bit.band(bit.rshift(color, 16), 0xFF)
        b = bit.band(bit.rshift(color, 8), 0xFF)
    end
    return r, g, b
end

local function classify_tab_rgb(r, g, b)
    -- Advance RP: таблица цветов обновлена по новому списку.
    -- Определяем по RGB с допусками, чтобы работало на разных сборках/HUD.
    local rgb = string.format('%02X%02X%02X', r, g, b)

    local exact = {
        ['FFFFFF'] = {'civil', 'белый TAB: без организации'},

        ['CCFF00'] = {'pravo', 'TAB: Правительство'},
        ['0000FF'] = {'mvd', 'TAB: LSPD / МВД'},
        ['33AAFF'] = {'mvd', 'TAB: SFPD / МВД'},
        ['0055FF'] = {'mvd', 'TAB: FBI / МВД'},
        ['808000'] = {'mo', 'TAB: Army / МО'},
        ['FF6600'] = {'smi', 'TAB: СМИ'},
        ['FF8282'] = {'mz', 'TAB: Больница / МЗ'},

        ['00AA00'] = {'gangs', 'TAB: Grove Street'},
        ['CC00FF'] = {'gangs', 'TAB: Ballas'},
        ['FFFF00'] = {'gangs', 'TAB: Los Santos Vagos'},
        ['6699FF'] = {'gangs', 'TAB: The Rifa'},
        ['00CCFF'] = {'gangs', 'TAB: Varios Los Aztecas'},

        ['C8A2C8'] = {'lkn', 'TAB: La Cosa Nostra'},
        ['FF66CC'] = {'yakuza', 'TAB: Yakuza'},
        ['8B0000'] = {'rm', 'TAB: Russian Mafia'}
    }
    if exact[rgb] then return exact[rgb][1], exact[rgb][2] end

    if r >= 235 and g >= 235 and b >= 235 then
        return 'civil', 'белый TAB: без организации RGB='..rgb
    end

    -- Advance Green: реальные цвета с твоих скринов
    -- Правительство: Drake_Marten, примерно RGB 152,177,26
    if r >= 120 and r <= 190 and g >= 150 and g <= 220 and b <= 65 then
        return 'pravo', 'Правительство Green RGB='..rgb
    end

    -- Госы
    if r >= 185 and r <= 225 and g >= 235 and b <= 70 then
        return 'pravo', 'Правительство RGB='..rgb
    end
    if b >= 210 and r <= 80 and g <= 130 then
        return 'mvd', 'МВД/LSPD/FBI RGB='..rgb
    end
    if b >= 210 and r >= 35 and r <= 95 and g >= 130 and g <= 205 then
        return 'mvd', 'SFPD/МВД RGB='..rgb
    end
    if r >= 100 and r <= 165 and g >= 100 and g <= 165 and b <= 60 then
        return 'mo', 'МО/Army RGB='..rgb
    end
    if r >= 230 and g >= 75 and g <= 140 and b <= 60 then
        return 'smi', 'СМИ RGB='..rgb
    end
    if r >= 235 and g >= 95 and g <= 175 and b >= 95 and b <= 175 then
        return 'mz', 'МЗ/Больница RGB='..rgb
    end

    -- Банды
    if r <= 70 and g >= 130 and g <= 210 and b <= 70 then
        return 'gangs', 'Grove RGB='..rgb
    end
    if r >= 170 and r <= 235 and g <= 80 and b >= 200 then
        return 'gangs', 'Ballas RGB='..rgb
    end
    -- Advance Green: Vagos, Aurelio_Santaro, примерно RGB 154,135,8
    if r >= 120 and r <= 190 and g >= 100 and g <= 170 and b <= 45 then
        return 'gangs', 'Vagos Green RGB='..rgb
    end
    if r >= 230 and g >= 230 and b <= 90 then
        return 'gangs', 'Vagos RGB='..rgb
    end
    if r >= 75 and r <= 140 and g >= 115 and g <= 190 and b >= 200 then
        return 'gangs', 'Rifa RGB='..rgb
    end
    if r <= 80 and g >= 170 and g <= 235 and b >= 200 then
        return 'gangs', 'Aztecas RGB='..rgb
    end

    -- Мафии Advance Green по твоим скринам.
    -- Важно: порядок имеет значение. Сначала LCN/Yakuza, потом RM,
    -- чтобы тёмно-красная Yakuza не попадала в RM.

    -- LCN: Vito_Neri — тёмно-розовый/бордово-фиолетовый.
    -- Расширенный диапазон, потому что на Green этот цвет бывает очень тёмным.
    if r >= 40 and r <= 180 and g <= 125 and b >= 25 and b <= 180 and r >= g + 10 and b >= g + 5 then
        return 'lkn', 'LCN Green RGB='..rgb
    end

    -- Yakuza: Orlando_Straduvari — красный
    if r >= 90 and g <= 70 and b <= 70 and r > g * 2 and r > b * 2 then
        return 'yakuza', 'Yakuza Green RGB='..rgb
    end

    -- RM: Adolfo_Rizzo — тёмная бирюза
    if r <= 70 and g >= 45 and g <= 140 and b >= 45 and b <= 140 and math.abs(g - b) <= 45 then
        return 'rm', 'Russian Mafia Green RGB='..rgb
    end

    -- Старые/стандартные цвета мафий
    if r >= 165 and r <= 230 and g >= 130 and g <= 200 and b >= 165 and b <= 230 then
        return 'lkn', 'LCN RGB='..rgb
    end
    if r >= 230 and g >= 70 and g <= 150 and b >= 170 and b <= 240 then
        return 'yakuza', 'Yakuza RGB='..rgb
    end
    if r >= 100 and r <= 175 and g <= 60 and b <= 60 then
        return 'yakuza', 'Yakuza/RM красный RGB='..rgb
    end

    local function dist(hex)
        local rr = tonumber(hex:sub(1,2), 16)
        local gg = tonumber(hex:sub(3,4), 16)
        local bb = tonumber(hex:sub(5,6), 16)
        return math.sqrt((r-rr)^2 + (g-gg)^2 + (b-bb)^2)
    end

    local nearest_org, nearest_why, nearest_d = nil, nil, 9999
    for hex, data in pairs(exact) do
        local d = dist(hex)
        if d < nearest_d then
            nearest_d = d
            nearest_org = data[1]
            nearest_why = data[2] .. ' приблизительно, RGB=' .. rgb .. ', d=' .. math.floor(d)
        end
    end

    if nearest_d <= 55 then return nearest_org, nearest_why end
    return nil, 'цвет TAB не распознан RGB=' .. rgb
end


local function ms_safe_player_connected(pid)
    pid = tonumber(pid) or -1
    if pid < 0 or pid > 1000 then return false end
    local ok, connected = pcall(sampIsPlayerConnected, pid)
    return ok and connected == true
end

local function detect_org_by_color(pid)
    if not ms_safe_player_connected(pid) then
        return cfg.org.fallback or 'civil', 'нет игрока'
    end

    local ok_color, color = pcall(sampGetPlayerColor, pid)
    if not ok_color or not color then
        return cfg.org.fallback or 'civil', 'цвет игрока недоступен'
    end
    local hex = color_to_hex(color)

    -- В Advance RP/MoonLoader цвет чаще приходит как 0xAARRGGBB.
    -- Поэтому берём именно младшие 24 бита: RR GG BB.
    -- Старый вариант ещё проверял RGB2 и из-за этого белый 0x00FFFFFF
    -- мог ошибочно определяться как Aztecas/банды.
    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)

    local org, why = classify_tab_rgb(r, g, b)
    if org then
        return org, string.format('%s | HEX:%s RGB:%d,%d,%d', why, hex, r, g, b)
    end

    return cfg.org.fallback or 'civil', string.format('TAB не распознан | HEX:%s RGB:%d,%d,%d', hex, r,g,b)
end

local function safe_nick(pid)
    if pid and pid >= 0 and ms_safe_player_connected(pid) then
        local ok, nick = pcall(sampGetPlayerNickname, pid)
        if ok and nick then return nick end
    end
    return nil
end

local function org_from_saved_nick(pid)
    local nick = safe_nick(pid)
    if nick and stable_player_org and stable_player_org[nick] then
        return stable_player_org[nick], 'база'
    end
    return nil, 'нет в базе'
end

local function save_org_for_player(pid, org)
    local nick = safe_nick(pid)
    if nick and org then
        stable_player_org[nick] = org
        cfg.player_org = cfg.player_org or {}
        cfg.player_org[nick] = org
        write_kv_ini(players_path, 'players', stable_player_org)
        inicfg.save(cfg, cfg_path)
        return nick
    end
    return nil
end

local function delete_org_for_player(pid)
    local nick = safe_nick(pid)
    if nick then
        stable_player_org[nick] = nil
        if cfg.player_org then cfg.player_org[nick] = nil end
        write_kv_ini(players_path, 'players', stable_player_org)
        inicfg.save(cfg, cfg_path)
        return nick
    end
    return nil
end

local function get_patient_org(pid)
    if manual_player_org[pid] then
        return manual_player_org[pid], 'выбрано вручную'
    end

    -- Сначала берём актуальный цвет TAB. Это важнее старой базы из ms_helper.ini,
    -- потому что в базе могли сохраниться ошибочные организации после прошлых версий.
    -- Автоопределение всегда включено и больше не выводится отдельной настройкой в меню.
    local detected, method = detect_org_by_color(pid)
    if detected and detected ~= 'civil' then
        return detected, method
    end

    -- База по нику используется только как запасной вариант, если цвет не распознался.
    local saved, why_saved = org_from_saved_nick(pid)
    if saved then return saved, why_saved end

    return cfg.org.fallback or 'civil', 'default'
end

local function get_patient_price(pid)
    local org, why = get_patient_org(pid)
    local value = price[org] and price[org][0] or cfg.prices[org] or cfg.prices.civil or 800
    return value, org, why
end




-- =========================================================
-- Access gate removed by request.
-- These compatibility stubs keep older wrappers working, but they do not
-- restrict /ms, /mgos, or any MS Helper command.
-- =========================================================
function MSHelper_RequireMedic(label) return true end
function MSHelper_RequireLeader(label) return true end
function MSHelper_IsSelfMedic() return true end
function MSHelper_IsLeader() return true end
MSHelper_AccessHandleDialog = nil
MSHelper_RequestAccessStats = nil

local function is_forbidden_binder_key(vk)
    vk = tonumber(vk) or 0
    -- Запрещаем клавиши, которые часто сворачивают игру/конфликтуют с Windows, SAMP и лаунчером.
    local forbidden = {
        [0x01]=true,[0x02]=true,[0x03]=true,[0x04]=true,[0x05]=true,[0x06]=true, -- мышь
        [0x09]=true, -- TAB
        [0x0D]=true, -- ENTER
        [0x10]=true,[0x11]=true,[0x12]=true, -- Shift/Ctrl/Alt
        [0x1B]=true, -- ESC
        [0x5B]=true,[0x5C]=true, -- Win keys
        [0xA0]=true,[0xA1]=true,[0xA2]=true,[0xA3]=true,[0xA4]=true,[0xA5]=true -- L/R Shift/Ctrl/Alt
    }
    return forbidden[vk] == true
end

local function sanitize_binder_key_obj(obj)
    if obj and is_forbidden_binder_key(obj[0]) then
        obj[0] = 0
        helper_msg('Эта клавиша запрещена для биндера, чтобы игра не сворачивалась. Используйте F2-F12 или Num-клавиши.')
        return true
    end
    return false
end

local function save()
    cfg.main = cfg.main or {}
    cfg.main.show_heal_debug = false
    cfg.main.hide_job_chat = false
    if MSH_CUSTOM_FIND_ENABLED then cfg.main.custom_find = MSH_CUSTOM_FIND_ENABLED[0] end
    for i = 1, 22 do
        cfg['slot'..i].text = ffi.string(binder[i])
        if binder_key[i] and is_forbidden_binder_key(binder_key[i][0]) then binder_key[i][0] = 0 end
        cfg['slot'..i].key = binder_key[i][0]
        cfg['slot'..i].delay = binder_delay[i][0]
        local normalized_cmd = normalize_binder_command(ffi.string(binder_command[i]), i)
        cfg['slot'..i].command = normalized_cmd
        ffi.copy(binder_command[i], normalized_cmd, 31)
    end
    cfg.gos = cfg.gos or {}
    for _, h in ipairs(gos_hospitals) do
        local sec_name = 'gos_' .. h.key
        cfg[sec_name] = cfg[sec_name] or {}
        cfg[sec_name].line1 = ffi.string(gos_lines[h.key][1])
        cfg[sec_name].line2 = ffi.string(gos_lines[h.key][2])
        cfg[sec_name].line3 = ffi.string(gos_lines[h.key][3])
        cfg[sec_name].single = ffi.string(gos_single_lines[h.key])
    end
    -- Оставляем старые поля для совместимости со старыми версиями конфига.
    cfg.gos.line1 = ffi.string(gos_lines.sf[1]); cfg.gos.line2 = ffi.string(gos_lines.sf[2]); cfg.gos.line3 = ffi.string(gos_lines.sf[3]); cfg.gos.single = ffi.string(gos_single_lines.sf)
    for set = 1, 4 do
        cfg['rpgos' .. set] = cfg['rpgos' .. set] or {}
        cfg['rpgos' .. set].line1 = ffi.string(rpgos_lines[set][1])
        cfg['rpgos' .. set].line2 = ffi.string(rpgos_lines[set][2])
        cfg['rpgos' .. set].line3 = ffi.string(rpgos_lines[set][3])
    end
    cfg.org.auto_detect = true
    auto_org[0] = true
    cfg.reconnect = cfg.reconnect or {}
    if rc.delay[0] < 1 then rc.delay[0] = 1 end
    if rc.delay[0] > 120 then rc.delay[0] = 120 end
    cfg.reconnect.auto = rc.auto[0]
    cfg.reconnect.delay = rc.delay[0]
    cfg.main.custom_tab = false
    cfg.ruk.staff_id = ruk_staff_id[0]
    cfg.ruk.radio_text = ffi.string(ruk_radio_text)
    cfg.phone = cfg.phone or {}
    cfg.phone.enabled = MSH_PHONE_GREET_ENABLED[0]
    cfg.phone.greeting = ffi.string(MSH_PHONE_GREET_BUFFER)
    for _, k in ipairs(action_list) do
        cfg.actions[k] = action_enabled[k][0]
        if action_rp_buffers and action_rp_buffers[k] then
            cfg.rptexts[k] = ffi.string(action_rp_buffers[k])
        end
    end
    local price_ini = {}
    for k, v in pairs(price) do cfg.prices[k] = v[0]; price_ini[k] = tostring(v[0]) end
    write_kv_ini(prices_path, 'prices', price_ini)
    write_kv_ini(players_path, 'players', stable_player_org)
    if _G.MSHelper_TagREnabled then cfg.main.tag_r = _G.MSHelper_TagREnabled[0] end
    if _G.MSHelper_TagFEnabled then cfg.main.tag_f = _G.MSHelper_TagFEnabled[0] end
    if _G.MSHelper_TagRBuffer then cfg.main.r_tag = ffi.string(_G.MSHelper_TagRBuffer) end
    if _G.MSHelper_TagFBuffer then cfg.main.f_tag = ffi.string(_G.MSHelper_TagFBuffer) end
    cfg.main.theme = tostring(cfg.main.theme or 'cyan')
    inicfg.save(cfg, cfg_path)
end

local function save_phone_settings(show_message)
    cfg.phone = cfg.phone or {}
    if MSH_PHONE_GREET_ENABLED then cfg.phone.enabled = MSH_PHONE_GREET_ENABLED[0] end
    if MSH_PHONE_GREET_BUFFER then
        local text = ffi.string(MSH_PHONE_GREET_BUFFER)
        cfg.phone.greeting = text
    end
    inicfg.save(cfg, cfg_path)
    if show_message and helper_msg then
        local saved_text = tostring(cfg.phone and cfg.phone.greeting or '')
        if saved_text ~= '' then
            helper_msg('Приветствие /p сохранено. Символов: ' .. tostring(#saved_text) .. '.')
        else
            helper_msg('Приветствие /p очищено или поле осталось пустым.')
        end
    end
end

local function set_phone_greeting_utf8(text_utf8, show_message)
    text_utf8 = tostring(text_utf8 or '')
    cfg.phone = cfg.phone or {}
    cfg.phone.greeting = text_utf8
    if MSH_PHONE_GREET_ENABLED then cfg.phone.enabled = MSH_PHONE_GREET_ENABLED[0] end
    if MSH_PHONE_GREET_BUFFER then
        ffi.fill(MSH_PHONE_GREET_BUFFER, 512, 0)
        ffi.copy(MSH_PHONE_GREET_BUFFER, text_utf8, math.min(#text_utf8, 511))
    end
    inicfg.save(cfg, cfg_path)
    if show_message and helper_msg then
        if text_utf8 ~= '' then
            helper_msg('Приветствие /p сохранено через команду.')
        else
            helper_msg('Приветствие /p очищено.')
        end
    end
end

function MSHelper_CmdPhoneGreeting(arg)
    arg = trim(tostring(arg or ''))
    if arg == '' then
        local cur = tostring(cfg.phone and cfg.phone.greeting or '')
        if cur ~= '' then
            helper_msg('Текущее приветствие /p: ' .. cur)
        else
            helper_msg('Приветствие /p пустое. Используйте: /msphone текст')
        end
        return
    end
    if arg:lower() == 'clear' or arg:lower() == 'очистить' then
        set_phone_greeting_utf8('', true)
        return
    end
    set_phone_greeting_utf8(u8:encode(arg), true)
end

local function chat(msg) sampSendChat(u8:decode(msg)) end
function helper_msg(text) sampAddChatMessage('{159A9C}[MS Helper] {FFFFFF}' .. u8:decode(text), -1) end


-- ===== MS Helper | Журнал смены и отчёт =====
-- Журнал смены сохраняется в moonloader/config/ms_helper_shift.ini.
-- После перезахода/перезапуска скрипта отчёт не пропадает, пока игрок сам не нажмёт "Очистить смену".
MSH_REPORT_CFG_PATH = MSH_REPORT_CFG_PATH or 'ms_helper_shift.ini'

function MSHelper_ReportLoad()
    MSH_REPORT = { started_at = os.time(), entries = {}, counters = {} }

    local defaults = {
        main = { started_at = os.time() },
        counters = {
            medcard = 0,
            heal_ambulance = 0,
            heal_hospital = 0,
            analysis = 0,
            dis = 0
        },
        entries = {}
    }

    local ok, data = pcall(function() return inicfg.load(defaults, MSH_REPORT_CFG_PATH) end)
    if not ok or type(data) ~= 'table' then data = defaults end

    if type(data.main) == 'table' and tonumber(data.main.started_at) then
        MSH_REPORT.started_at = tonumber(data.main.started_at)
    end

    if type(data.counters) == 'table' then
        for k, v in pairs(data.counters) do
            MSH_REPORT.counters[tostring(k)] = tonumber(v) or 0
        end
    end

    local loaded_entries = {}
    if type(data.entries) == 'table' then
        for key, value in pairs(data.entries) do
            local idx = tonumber(tostring(key):match('line(%d+)')) or tonumber(key)
            local raw = tostring(value or '')
            if idx and raw ~= '' then
                local tm, kind, body = raw:match('^([^|]*)|([^|]*)|(.*)$')
                table.insert(loaded_entries, {
                    idx = idx,
                    time = tm or '',
                    kind = kind or 'other',
                    text = body or raw
                })
            end
        end
    end

    table.sort(loaded_entries, function(a, b) return (a.idx or 0) < (b.idx or 0) end)
    for _, e in ipairs(loaded_entries) do
        table.insert(MSH_REPORT.entries, { time = e.time or '', kind = e.kind or 'other', text = e.text or '' })
    end
end

function MSHelper_ReportSave()
    if not MSH_REPORT then return false end
    MSH_REPORT.counters = MSH_REPORT.counters or {}
    MSH_REPORT.entries = MSH_REPORT.entries or {}

    local data = {
        main = { started_at = tonumber(MSH_REPORT.started_at) or os.time() },
        counters = {},
        entries = {}
    }

    for k, v in pairs(MSH_REPORT.counters) do
        data.counters[tostring(k)] = tonumber(v) or 0
    end

    local max_entries = math.min(#MSH_REPORT.entries, 60)
    for i = 1, max_entries do
        local e = MSH_REPORT.entries[i] or {}
        local line = tostring(e.time or '') .. '|' .. tostring(e.kind or 'other') .. '|' .. tostring(e.text or ''):gsub('|', '/')
        data.entries['line' .. tostring(i)] = line
    end

    local ok = pcall(function() return inicfg.save(data, MSH_REPORT_CFG_PATH) end)
    return ok == true
end

MSHelper_ReportLoad()
MSH_REPORT = MSH_REPORT or { started_at = os.time(), entries = {}, counters = {} }
MSH_REPORT.counters = MSH_REPORT.counters or {}
MSH_REPORT.entries = MSH_REPORT.entries or {}
MSH_REPORT_TEXT_BUFFER = MSH_REPORT_TEXT_BUFFER or imgui.new.char[4096]('')
MSH_NOTE_TARGET_BUFFER = MSH_NOTE_TARGET_BUFFER or imgui.new.char[32]('')

function MSHelper_ReportKindTitle(kind)
    kind = tostring(kind or '')
    if kind == 'medcard' then return 'Медкарта' end
    if kind == 'heal_ambulance' then return 'Карета' end
    if kind == 'heal_hospital' then return 'Больница' end
    if kind == 'heal' then return 'Лечение' end
    if kind == 'analysis' then return 'Анализы' end
    if kind == 'dis' then return 'Процедура' end
    if kind == 'interview' then return 'Собеседование' end
    if kind == 'note' then return 'Личное дело' end
    return 'Действие'
end

function MSHelper_ReportAdd(kind, text)
    kind = tostring(kind or 'other')
    text = tostring(text or '')
    if text == '' then return false end
    MSH_REPORT = MSH_REPORT or { started_at = os.time(), entries = {}, counters = {} }
    MSH_REPORT.counters = MSH_REPORT.counters or {}
    MSH_REPORT.entries = MSH_REPORT.entries or {}
    MSH_REPORT.counters[kind] = (tonumber(MSH_REPORT.counters[kind]) or 0) + 1
    table.insert(MSH_REPORT.entries, 1, { time = os.date('%H:%M:%S'), kind = kind, text = text })
    while #MSH_REPORT.entries > 60 do table.remove(MSH_REPORT.entries) end
    if MSHelper_ReportRefreshBuffer then MSHelper_ReportRefreshBuffer() end
    if MSHelper_ReportSave then MSHelper_ReportSave() end
    return true
end

function MSHelper_ReportDurationText()
    MSH_REPORT = MSH_REPORT or { started_at = os.time(), entries = {}, counters = {} }
    local sec = math.max(0, os.time() - (tonumber(MSH_REPORT.started_at) or os.time()))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    return string.format('%02d:%02d', h, m)
end

function MSHelper_ReportBuildText()
    MSH_REPORT = MSH_REPORT or { started_at = os.time(), entries = {}, counters = {} }
    MSH_REPORT.counters = MSH_REPORT.counters or {}
    local c = MSH_REPORT.counters
    local dis_count = tonumber(c.dis or 0) or 0
    local dis_full = math.floor(dis_count / 5)
    return table.concat({
        'Отчёт за смену МЗ',
        'Выдано медкарт: ' .. tostring(c.medcard or 0),
        'Лечение в карете [/heal]: ' .. tostring((c.heal_ambulance or 0) + (c.heal or 0)),
        'Лечение в больнице [/medhelp]: ' .. tostring(c.heal_hospital or 0),
        'Проведено процедур [5/5 = 1 полное лечение]: ' .. tostring(dis_count) .. ' (полных: ' .. tostring(dis_full) .. ')'
    }, '\n')
end

function MSHelper_ReportRefreshBuffer()
    if not MSH_REPORT_TEXT_BUFFER then return end
    local text = MSHelper_ReportBuildText()
    ffi.fill(MSH_REPORT_TEXT_BUFFER, 4096, 0)
    ffi.copy(MSH_REPORT_TEXT_BUFFER, text, math.min(#text, 4095))
end

function MSHelper_ReportReset()
    MSH_REPORT = { started_at = os.time(), entries = {}, counters = {} }
    if MSHelper_ReportSave then MSHelper_ReportSave() end
    MSHelper_ReportRefreshBuffer()
    if helper_msg then helper_msg('Журнал смены очищен.') end
end

function MSHelper_ReportCopy()
    local text = MSHelper_ReportBuildText()
    if type(setClipboardText) == 'function' then
        setClipboardText(text)
        if helper_msg then helper_msg('Отчёт скопирован в буфер обмена.') end
    else
        if helper_msg then helper_msg('Буфер обмена недоступен на этой сборке. Скопируйте текст из поля отчёта в /ms.') end
    end
end

function MSHelper_SendNoteRp(kind, open_note)
    kind = tostring(kind or 'other')
    open_note = open_note == true
    note_target = ''
    if MSH_NOTE_TARGET_BUFFER then note_target = trim(ffi.string(MSH_NOTE_TARGET_BUFFER)) end
    if open_note and note_target == '' then
        if helper_msg then helper_msg('Укажите ID или ник сотрудника для /note.') end
        return false
    end
    if (MSH_NOTE_RP_BUSY or false) then
        if helper_msg then helper_msg('RP для личного дела уже отправляется.') end
        return false
    end

    local title = 'служебная запись'
    local line1 = '/me открыл личное дело сотрудника и внимательно изучил записи'
    local line2 = '/me внёс новую служебную запись в личное дело сотрудника'
    local line3 = '/do Запись в личном деле подготовлена.'

    if kind == 'award' then
        title = 'награда'
        line1 = '/me открыл личное дело сотрудника и подготовил запись о награждении'
        line2 = '/me внёс запись о награждении сотрудника в личное дело'
        line3 = '/do Запись о награждении подготовлена.'
    elseif kind == 'warn' then
        title = 'выговор'
        line1 = '/me открыл личное дело сотрудника и проверил дисциплинарные записи'
        line2 = '/me внёс дисциплинарную запись в личное дело сотрудника'
        line3 = '/do Выговор подготовлен к фиксации в личном деле.'
    elseif kind == 'black' then
        title = 'чёрный список'
        line1 = '/me открыл личное дело сотрудника и подготовил отметку для чёрного списка'
        line2 = '/me внёс отметку в личное дело сотрудника'
        line3 = '/do Отметка для чёрного списка подготовлена.'
    elseif kind == 'edit' then
        title = 'изменение записи'
        line1 = '/me открыл личное дело сотрудника и нашёл ранее внесённую запись'
        line2 = '/me подготовил изменение ранее внесённой записи'
        line3 = '/do Изменение записи подготовлено.'
    end

    lua_thread.create(function()
        MSH_NOTE_RP_BUSY = true
        chat(line1)
        wait(850)
        chat(line2)
        wait(850)
        chat(line3)
        wait(350)
        if open_note and note_target ~= '' then
            -- Автовыбор пункта в первом окне /note.
            -- Игроку останется только вписать текст записи руками.
            MSH_NOTE_AUTO_KIND = kind
            MSH_NOTE_AUTO_LISTBOX = MSHelper_NoteKindToListbox and MSHelper_NoteKindToListbox(kind) or -1
            MSH_NOTE_AUTO_UNTIL = os.clock() + 8
            MSH_NOTE_AUTO_TARGET = note_target
            -- Важно: не пытаемся угадывать диалог по тексту. На Advance Launcher
            -- заголовок/текст может приходить в другой кодировке, поэтому берём
            -- первый диалог, который откроется сразу после нашей команды /note.
            MSH_NOTE_AUTO_FORCE_NEXT = true
            MSH_NOTE_AUTO_SENT_AT = os.clock()
            sampSendChat('/note ' .. note_target)
            -- Запасной способ автовыбора: на Advance Launcher первое окно /note
            -- может не успеть обработаться через onShowDialog. Поэтому после открытия
            -- системного диалога пробуем выбрать пункт прямо в текущем активном окне.
            wait(650)
            if MSHelper_NoteAutoSelectCurrentDialog and MSHelper_NoteAutoSelectCurrentDialog() ~= true then
                wait(650)
                if MSHelper_NoteAutoSelectCurrentDialog then MSHelper_NoteAutoSelectCurrentDialog() end
            end
        end
        wait(250)
        MSH_NOTE_RP_BUSY = false
        if MSHelper_ReportAdd then
            if open_note and note_target ~= '' then
                MSHelper_ReportAdd('note', 'RP + /note: ' .. title .. ' для ' .. note_target)
            else
                MSHelper_ReportAdd('note', 'RP личного дела: ' .. title)
            end
        end
    end)
    return true
end


function MSHelper_NoteKindToListbox(kind)
    kind = tostring(kind or 'other')
    if kind == 'award' then return 0 end
    if kind == 'warn' then return 1 end
    if kind == 'black' then return 2 end
    if kind == 'other' then return 3 end
    if kind == 'edit' then return 4 end
    return -1
end

function MSHelper_NoteContains(raw, needle_utf8)
    raw = tostring(raw or '')
    needle_utf8 = tostring(needle_utf8 or '')
    if raw == '' or needle_utf8 == '' then return false end
    MSH_NOTE_CONTAINS_NEEDLE = needle_utf8
    if u8 and u8.decode then
        MSH_NOTE_CONTAINS_OK, MSH_NOTE_CONTAINS_CP = pcall(function() return u8:decode(needle_utf8) end)
        if MSH_NOTE_CONTAINS_OK and MSH_NOTE_CONTAINS_CP then MSH_NOTE_CONTAINS_NEEDLE = MSH_NOTE_CONTAINS_CP end
    end
    return raw:lower():find(tostring(MSH_NOTE_CONTAINS_NEEDLE):lower(), 1, true) ~= nil
end

function MSHelper_IsNoteFirstDialog(title, body)
    title = tostring(title or '')
    body = tostring(body or '')
    if not MSHelper_NoteContains(title, 'Запись в личное дело') then return false end
    if MSHelper_NoteContains(body, 'Что Вы хотите записать') then return false end
    if MSHelper_NoteContains(body, 'Создана запись') then return false end
    if MSHelper_NoteContains(body, 'Ник:') or MSHelper_NoteContains(body, 'Тип записи') or MSHelper_NoteContains(body, 'Текст:') then return false end
    return MSHelper_NoteContains(body, 'Наградить')
        and MSHelper_NoteContains(body, 'выговор')
        and (MSHelper_NoteContains(body, 'чёрный список') or MSHelper_NoteContains(body, 'черный список'))
end

function MSHelper_NoteDoSelect(dialogId, listbox)
    listbox = tonumber(listbox) or -1
    if listbox < 0 then return false end
    dialogId = tonumber(dialogId) or -1

    -- Метод 1: прямой SA-MP ответ по ID диалога.
    if dialogId >= 0 then
        pcall(sampSendDialogResponse, dialogId, 1, listbox, '')
    end

    -- Метод 2: для лаунчерного/активного окна — выбрать строку и нажать "Далее".
    -- На некоторых сборках именно этот вариант работает стабильнее прямого ответа.
    if sampIsDialogActive then
        local ok_active, active = pcall(sampIsDialogActive)
        if ok_active and active == true then
            if sampSetCurrentDialogListItem then pcall(sampSetCurrentDialogListItem, listbox) end
            if sampCloseCurrentDialogWithButton then pcall(sampCloseCurrentDialogWithButton, 1) end
        end
    end
    return true
end

function MSHelper_TryAutoSelectNoteDialog(dialogId, title, body)
    if not MSH_NOTE_AUTO_UNTIL or (MSH_NOTE_AUTO_UNTIL or 0) < os.clock() then return nil end
    MSH_NOTE_AUTO_LISTBOX = tonumber(MSH_NOTE_AUTO_LISTBOX) or -1
    if MSH_NOTE_AUTO_LISTBOX < 0 then return nil end

    local allow = false

    -- Основной режим: мы сами только что отправили /note, значит следующий диалог — нужное меню /note.
    if MSH_NOTE_AUTO_FORCE_NEXT == true then
        allow = true
    elseif MSHelper_IsNoteFirstDialog and MSHelper_IsNoteFirstDialog(title, body) then
        allow = true
    end

    if not allow then return nil end

    local lb = MSH_NOTE_AUTO_LISTBOX
    MSH_NOTE_AUTO_UNTIL = 0
    MSH_NOTE_AUTO_FORCE_NEXT = false

    -- Отвечаем сразу, без ожидания. Игрок не должен видеть первое меню выбора.
    pcall(MSHelper_NoteDoSelect, dialogId, lb)

    -- Страховка: если лаунчер всё-таки показал окно, через долю секунды выбираем пункт ещё раз.
    lua_thread.create(function()
        wait(180)
        pcall(MSHelper_NoteAutoSelectCurrentDialog)
        wait(350)
        pcall(MSHelper_NoteAutoSelectCurrentDialog)
        MSH_NOTE_AUTO_LISTBOX = -1
        MSH_NOTE_AUTO_KIND = nil
        MSH_NOTE_AUTO_TARGET = nil
        MSH_NOTE_AUTO_FORCE_NEXT = false
    end)

    return false
end

function MSHelper_NoteAutoSelectCurrentDialog()
    MSH_NOTE_AUTO_LISTBOX = tonumber(MSH_NOTE_AUTO_LISTBOX) or -1
    if MSH_NOTE_AUTO_LISTBOX < 0 then return false end
    if not sampIsDialogActive then return false end

    local ok_active, active = pcall(sampIsDialogActive)
    if not ok_active or active ~= true then return false end

    local dialog_id = -1
    if sampGetCurrentDialogId then
        local ok_id, id = pcall(sampGetCurrentDialogId)
        if ok_id and id ~= nil then dialog_id = tonumber(id) or -1 end
    end

    local ok = pcall(MSHelper_NoteDoSelect, dialog_id, MSH_NOTE_AUTO_LISTBOX)
    if ok then return true end
    return false
end

function MSHelper_DrawNoteRpBlock()
    imgui.TextColored(MSHelper_AccentColor(), 'RP + /note')
    imgui.TextWrapped('Укажите ID или ник сотрудника. Если игрок offline, можно написать ник: /note Nick_Name. Кнопка сначала отправит RP-отыгровку, затем откроет /note ID/ник и сама выберет нужный пункт в первом окне.')
    imgui.PushItemWidth(220)
    imgui.InputText('ID или ник сотрудника##msh_note_target', MSH_NOTE_TARGET_BUFFER, 32)
    imgui.PopItemWidth()
    if imgui.Button('Награда + /note', imgui.ImVec2(170, 30)) then MSHelper_SendNoteRp('award', true) end
    imgui.SameLine()
    if imgui.Button('Выговор + /note', imgui.ImVec2(170, 30)) then MSHelper_SendNoteRp('warn', true) end
    imgui.SameLine()
    if imgui.Button('ЧС + /note', imgui.ImVec2(150, 30)) then MSHelper_SendNoteRp('black', true) end
    if imgui.Button('Другая запись + /note', imgui.ImVec2(190, 30)) then MSHelper_SendNoteRp('other', true) end
    imgui.SameLine()
    if imgui.Button('Изменить запись + /note', imgui.ImVec2(210, 30)) then MSHelper_SendNoteRp('edit', true) end
    imgui.Separator()
    imgui.TextDisabled('Запасной режим: только RP, без открытия /note.')
    if imgui.Button('Только RP: награда', imgui.ImVec2(170, 28)) then MSHelper_SendNoteRp('award', false) end
    imgui.SameLine()
    if imgui.Button('Только RP: выговор', imgui.ImVec2(170, 28)) then MSHelper_SendNoteRp('warn', false) end
end

function MSHelper_DrawJournalTab()
    if MSHelper_ReportRefreshBuffer then MSHelper_ReportRefreshBuffer() end
    imgui.TextColored(MSHelper_AccentColor(), 'Журнал смены / отчёт')
    imgui.TextDisabled('Смена сохраняется в ms_helper_shift.ini и не пропадает после перезапуска.')
    if imgui.Button('Сформировать отчёт', imgui.ImVec2(180, 30)) then
        MSHelper_ReportRefreshBuffer()
        if helper_msg then helper_msg('Отчёт сформирован. Его можно скопировать из поля ниже.') end
    end
    imgui.SameLine()
    if imgui.Button('Скопировать отчёт', imgui.ImVec2(170, 30)) then MSHelper_ReportCopy() end
    imgui.SameLine()
    if imgui.Button('Очистить смену', imgui.ImVec2(150, 30)) then MSHelper_ReportReset() end

    imgui.PushItemWidth(-1)
    imgui.InputTextMultiline('Готовый отчёт##msh_report_text', MSH_REPORT_TEXT_BUFFER, 4096, imgui.ImVec2(-1, 135), imgui.InputTextFlags.ReadOnly)
    imgui.PopItemWidth()

    imgui.Separator()
    MSHelper_DrawNoteRpBlock()

end


-- Связка "Чистый онлайн" с системным точным временем Advance.
-- На Advance точное время открывается через /c 60 или /c 060. Данные обновляются после этого диалога или командой /mstime.
MSHelper_TimeStats = MSHelper_TimeStats or {
    hour = '',
    today = '',
    yesterday = '',
    afk_today = '',
    afk_yesterday = '',
    updated_at = 0,
    updated_clock = '',
    silent_until = 0
}

function MSHelper_TimeCleanLine(s)
    s = tostring(s or '')
    s = s:gsub('{%x%x%x%x%x%x}', '')
    s = s:gsub('\t', ' ')
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

function MSHelper_TimeToUtf8(s)
    s = MSHelper_TimeCleanLine(s)
    if s == '' then return '' end
    if u8 and u8.encode then
        local ok, result = pcall(function() return u8:encode(s) end)
        if ok and result then return result end
    end
    return s
end

function MSHelper_TimeLabel(label)
    if u8 and u8.decode then
        local ok, result = pcall(function() return u8:decode(label) end)
        if ok and result then return result end
    end
    return tostring(label or '')
end

function MSHelper_TimeExtract(body, label_utf8)
    body = tostring(body or '')
    local label = MSHelper_TimeLabel(label_utf8)
    for line in (body .. '\n'):gmatch('([^\r\n]+)') do
        local clean = MSHelper_TimeCleanLine(line)
        if clean:find(label, 1, true) then
            local value = clean:match(':%s*(.+)$') or ''
            return MSHelper_TimeToUtf8(value)
        end
    end
    return ''
end

function MSHelper_IsTimeDialog(title, body)
    local all = tostring(title or '') .. '\n' .. tostring(body or '')
    return all:find(MSHelper_TimeLabel('Точное время'), 1, true) ~= nil
        or all:find(MSHelper_TimeLabel('Время в игре сегодня'), 1, true) ~= nil
        or all:find(MSHelper_TimeLabel('AFK за сегодня'), 1, true) ~= nil
end

function MSHelper_SaveTimeStats(title, body)
    if not MSHelper_IsTimeDialog(title, body) then return false end

    MSHelper_TimeStats.hour = MSHelper_TimeExtract(body, 'Время в игре за час')
    MSHelper_TimeStats.today = MSHelper_TimeExtract(body, 'Время в игре сегодня')
    MSHelper_TimeStats.yesterday = MSHelper_TimeExtract(body, 'Время в игре вчера')
    MSHelper_TimeStats.afk_today = MSHelper_TimeExtract(body, 'AFK за сегодня')
    MSHelper_TimeStats.afk_yesterday = MSHelper_TimeExtract(body, 'AFK за вчера')
    MSHelper_TimeStats.updated_at = os.time()
    MSHelper_TimeStats.updated_clock = os.date('%H:%M:%S')

    return true
end

function MSHelper_TimeStatsText(short_mode)
    if not MSHelper_TimeStats or (MSHelper_TimeStats.updated_at or 0) <= 0 then
        return 'Системное время /c 60: нет данных. Обновить можно командой /mstime.'
    end

    if short_mode then
        return string.format(
            '/c 60: игра сегодня %s, AFK сегодня %s',
            MSHelper_TimeStats.today ~= '' and MSHelper_TimeStats.today or '?',
            MSHelper_TimeStats.afk_today ~= '' and MSHelper_TimeStats.afk_today or '?'
        )
    end

    return string.format(
        'Системное время /c 60: сегодня игра %s, AFK %s | вчера игра %s, AFK %s | обновлено %s',
        MSHelper_TimeStats.today ~= '' and MSHelper_TimeStats.today or '?',
        MSHelper_TimeStats.afk_today ~= '' and MSHelper_TimeStats.afk_today or '?',
        MSHelper_TimeStats.yesterday ~= '' and MSHelper_TimeStats.yesterday or '?',
        MSHelper_TimeStats.afk_yesterday ~= '' and MSHelper_TimeStats.afk_yesterday or '?',
        MSHelper_TimeStats.updated_clock ~= '' and MSHelper_TimeStats.updated_clock or '?'
    )
end

function MSHelper_HandleTimeDialog(dialogId, style, title, button1, button2, body)
    if MSHelper_SaveTimeStats(title, body) then
        if (MSHelper_TimeStats.silent_until or 0) > os.clock() then
            return false
        end
    end
end

function MSHelper_RequestTimeStats(silent)
    if silent then
        MSHelper_TimeStats.silent_until = os.clock() + 4
    end

    -- Чистый онлайн убран. Эта функция оставлена только для совместимости,
    -- если где-то в старом конфиге/бинде остался вызов /c 60.
    sampSendChat('/c 60')
end

function MSHelper_CmdTimeStats(arg)
    MSHelper_RequestTimeStats(true)
end



-- Цветовые темы меню MS Helper.
-- Сохраняются в ms_helper.ini: [main] theme=...
MSHelper_ThemeOrder = {'cyan', 'blue', 'purple', 'red', 'green', 'light'}
MSHelper_ThemeLabels = {
    cyan = 'Бирюзовая',
    blue = 'Синяя',
    purple = 'Фиолетовая',
    red = 'Красная',
    green = 'Зелёная',
    light = 'Светлая'
}
MSHelper_Themes = {
    cyan = {
        text={0.93,0.96,0.96,1.00}, disabled={0.54,0.61,0.63,1.00}, window={0.025,0.038,0.045,0.98}, child={0.030,0.055,0.065,0.96}, popup={0.025,0.040,0.050,0.99}, border={0.22,0.36,0.39,0.90},
        frame={0.040,0.070,0.080,1.00}, frame_hover={0.07,0.24,0.25,1.00}, frame_active={0.08,0.50,0.52,1.00}, title={0.010,0.020,0.025,1.00}, title_active={0.015,0.035,0.045,1.00},
        button={0.07,0.55,0.56,0.95}, button_hover={0.10,0.68,0.68,1.00}, button_active={0.05,0.42,0.44,1.00}, header={0.07,0.55,0.56,0.90}, header_hover={0.09,0.65,0.66,1.00}, header_active={0.05,0.45,0.46,1.00},
        check={0.12,0.90,0.90,1.00}, scrollbar_bg={0.020,0.030,0.035,0.80}, scrollbar_grab={0.22,0.33,0.35,1.00}, scrollbar_grab_hover={0.08,0.55,0.56,1.00}, separator={0.25,0.40,0.42,0.80}, accent={0.12,0.85,0.86,1.00}
    },
    blue = {
        text={0.92,0.95,1.00,1.00}, disabled={0.50,0.57,0.68,1.00}, window={0.020,0.030,0.070,0.98}, child={0.030,0.045,0.090,0.96}, popup={0.025,0.035,0.080,0.99}, border={0.18,0.30,0.55,0.90},
        frame={0.035,0.055,0.110,1.00}, frame_hover={0.08,0.20,0.45,1.00}, frame_active={0.10,0.33,0.72,1.00}, title={0.010,0.018,0.050,1.00}, title_active={0.020,0.045,0.110,1.00},
        button={0.10,0.34,0.80,0.95}, button_hover={0.16,0.45,0.95,1.00}, button_active={0.07,0.25,0.62,1.00}, header={0.10,0.34,0.80,0.90}, header_hover={0.16,0.45,0.95,1.00}, header_active={0.07,0.25,0.62,1.00},
        check={0.30,0.60,1.00,1.00}, scrollbar_bg={0.018,0.025,0.060,0.80}, scrollbar_grab={0.18,0.25,0.40,1.00}, scrollbar_grab_hover={0.16,0.45,0.95,1.00}, separator={0.18,0.30,0.55,0.80}, accent={0.30,0.60,1.00,1.00}
    },
    purple = {
        text={0.96,0.93,1.00,1.00}, disabled={0.62,0.54,0.68,1.00}, window={0.040,0.025,0.060,0.98}, child={0.055,0.035,0.080,0.96}, popup={0.045,0.028,0.070,0.99}, border={0.38,0.25,0.48,0.90},
        frame={0.065,0.040,0.090,1.00}, frame_hover={0.22,0.10,0.35,1.00}, frame_active={0.48,0.18,0.70,1.00}, title={0.030,0.015,0.045,1.00}, title_active={0.060,0.030,0.090,1.00},
        button={0.48,0.20,0.75,0.95}, button_hover={0.60,0.28,0.90,1.00}, button_active={0.36,0.14,0.58,1.00}, header={0.48,0.20,0.75,0.90}, header_hover={0.60,0.28,0.90,1.00}, header_active={0.36,0.14,0.58,1.00},
        check={0.75,0.42,1.00,1.00}, scrollbar_bg={0.035,0.020,0.055,0.80}, scrollbar_grab={0.30,0.22,0.36,1.00}, scrollbar_grab_hover={0.60,0.28,0.90,1.00}, separator={0.38,0.25,0.48,0.80}, accent={0.75,0.42,1.00,1.00}
    },
    red = {
        text={1.00,0.94,0.94,1.00}, disabled={0.68,0.54,0.54,1.00}, window={0.055,0.020,0.020,0.98}, child={0.075,0.030,0.030,0.96}, popup={0.060,0.025,0.025,0.99}, border={0.50,0.22,0.22,0.90},
        frame={0.090,0.035,0.035,1.00}, frame_hover={0.32,0.08,0.08,1.00}, frame_active={0.72,0.12,0.12,1.00}, title={0.040,0.012,0.012,1.00}, title_active={0.090,0.025,0.025,1.00},
        button={0.78,0.12,0.12,0.95}, button_hover={0.92,0.20,0.20,1.00}, button_active={0.55,0.08,0.08,1.00}, header={0.78,0.12,0.12,0.90}, header_hover={0.92,0.20,0.20,1.00}, header_active={0.55,0.08,0.08,1.00},
        check={1.00,0.32,0.32,1.00}, scrollbar_bg={0.045,0.018,0.018,0.80}, scrollbar_grab={0.34,0.20,0.20,1.00}, scrollbar_grab_hover={0.92,0.20,0.20,1.00}, separator={0.50,0.22,0.22,0.80}, accent={1.00,0.32,0.32,1.00}
    },
    green = {
        text={0.92,1.00,0.94,1.00}, disabled={0.52,0.65,0.56,1.00}, window={0.020,0.045,0.028,0.98}, child={0.028,0.065,0.038,0.96}, popup={0.023,0.050,0.030,0.99}, border={0.18,0.42,0.24,0.90},
        frame={0.035,0.075,0.045,1.00}, frame_hover={0.08,0.26,0.12,1.00}, frame_active={0.10,0.55,0.22,1.00}, title={0.012,0.030,0.018,1.00}, title_active={0.025,0.060,0.035,1.00},
        button={0.12,0.55,0.25,0.95}, button_hover={0.18,0.72,0.34,1.00}, button_active={0.08,0.40,0.18,1.00}, header={0.12,0.55,0.25,0.90}, header_hover={0.18,0.72,0.34,1.00}, header_active={0.08,0.40,0.18,1.00},
        check={0.24,0.95,0.45,1.00}, scrollbar_bg={0.015,0.035,0.020,0.80}, scrollbar_grab={0.18,0.32,0.21,1.00}, scrollbar_grab_hover={0.18,0.72,0.34,1.00}, separator={0.18,0.42,0.24,0.80}, accent={0.24,0.95,0.45,1.00}
    },
    light = {
        text={0.08,0.10,0.12,1.00}, disabled={0.45,0.50,0.55,1.00}, window={0.94,0.96,0.98,0.98}, child={0.90,0.93,0.96,0.96}, popup={0.96,0.97,0.99,0.99}, border={0.65,0.75,0.85,0.90},
        frame={0.84,0.89,0.94,1.00}, frame_hover={0.70,0.82,0.95,1.00}, frame_active={0.50,0.70,0.92,1.00}, title={0.78,0.86,0.94,1.00}, title_active={0.70,0.82,0.95,1.00},
        button={0.42,0.62,0.86,0.95}, button_hover={0.34,0.56,0.82,1.00}, button_active={0.25,0.45,0.72,1.00}, header={0.42,0.62,0.86,0.90}, header_hover={0.34,0.56,0.82,1.00}, header_active={0.25,0.45,0.72,1.00},
        check={0.20,0.48,0.82,1.00}, scrollbar_bg={0.86,0.90,0.95,0.80}, scrollbar_grab={0.65,0.75,0.85,1.00}, scrollbar_grab_hover={0.34,0.56,0.82,1.00}, separator={0.65,0.75,0.85,0.80}, accent={0.20,0.48,0.82,1.00}
    }
}

function MSHelper_Vec4(v)
    return imgui.ImVec4(v[1], v[2], v[3], v[4] or 1.0)
end

function MSHelper_GetThemeKey()
    local key = tostring(cfg.main and cfg.main.theme or 'cyan')
    if not MSHelper_Themes[key] then key = 'cyan' end
    return key
end

function MSHelper_AccentColor(alpha)
    local t = MSHelper_Themes[MSHelper_GetThemeKey()] or MSHelper_Themes.cyan
    local a = t.accent or MSHelper_Themes.cyan.accent
    return imgui.ImVec4(a[1], a[2], a[3], alpha or a[4] or 1.0)
end

function MSHelper_ApplyTheme()
    if not imgui or not imgui.GetStyle then return end
    local key = MSHelper_GetThemeKey()
    if cfg.main then cfg.main.theme = key end
    local t = MSHelper_Themes[key] or MSHelper_Themes.cyan
    local style = imgui.GetStyle()
    style.WindowRounding = 8; style.FrameRounding = 5; style.ChildRounding = 8; style.GrabRounding = 6; style.ScrollbarRounding = 6
    style.WindowPadding = imgui.ImVec2(14, 12); style.ItemSpacing = imgui.ImVec2(10, 8); style.FramePadding = imgui.ImVec2(9, 6)
    style.WindowBorderSize = 1; style.ChildBorderSize = 1; style.FrameBorderSize = 1
    local c = style.Colors
    c[imgui.Col.Text] = MSHelper_Vec4(t.text)
    c[imgui.Col.TextDisabled] = MSHelper_Vec4(t.disabled)
    c[imgui.Col.WindowBg] = MSHelper_Vec4(t.window)
    c[imgui.Col.ChildBg] = MSHelper_Vec4(t.child)
    c[imgui.Col.PopupBg] = MSHelper_Vec4(t.popup)
    c[imgui.Col.Border] = MSHelper_Vec4(t.border)
    c[imgui.Col.FrameBg] = MSHelper_Vec4(t.frame)
    c[imgui.Col.FrameBgHovered] = MSHelper_Vec4(t.frame_hover)
    c[imgui.Col.FrameBgActive] = MSHelper_Vec4(t.frame_active)
    c[imgui.Col.TitleBg] = MSHelper_Vec4(t.title)
    c[imgui.Col.TitleBgActive] = MSHelper_Vec4(t.title_active)
    c[imgui.Col.Button] = MSHelper_Vec4(t.button)
    c[imgui.Col.ButtonHovered] = MSHelper_Vec4(t.button_hover)
    c[imgui.Col.ButtonActive] = MSHelper_Vec4(t.button_active)
    c[imgui.Col.Header] = MSHelper_Vec4(t.header)
    c[imgui.Col.HeaderHovered] = MSHelper_Vec4(t.header_hover)
    c[imgui.Col.HeaderActive] = MSHelper_Vec4(t.header_active)
    c[imgui.Col.CheckMark] = MSHelper_Vec4(t.check)
    c[imgui.Col.ScrollbarBg] = MSHelper_Vec4(t.scrollbar_bg)
    c[imgui.Col.ScrollbarGrab] = MSHelper_Vec4(t.scrollbar_grab)
    c[imgui.Col.ScrollbarGrabHovered] = MSHelper_Vec4(t.scrollbar_grab_hover)
    c[imgui.Col.Separator] = MSHelper_Vec4(t.separator)
end

function MSHelper_SetTheme(key, silent)
    key = tostring(key or ''):lower()
    local aliases = {['бирюзовая']='cyan', ['синяя']='blue', ['фиолетовая']='purple', ['красная']='red', ['зелёная']='green', ['зеленая']='green', ['светлая']='light'}
    key = aliases[key] or key
    if not MSHelper_Themes[key] then
        helper_msg('Темы: cyan, blue, purple, red, green, light. Или выберите тему в /ms > Основное.')
        return false
    end
    cfg.main.theme = key
    MSHelper_ApplyTheme()
    save()
    return true
end

function MSHelper_CmdTheme(arg)
    arg = trim(tostring(arg or ''))
    if arg ~= '' then
        MSHelper_SetTheme(arg)
        return
    end
    local current = MSHelper_GetThemeKey()
    local next_key = MSHelper_ThemeOrder[1]
    for i, key in ipairs(MSHelper_ThemeOrder) do
        if key == current then
            next_key = MSHelper_ThemeOrder[(i % #MSHelper_ThemeOrder) + 1]
            break
        end
    end
    MSHelper_SetTheme(next_key)
end

function MSHelper_DrawThemeSettings()
    imgui.TextColored(MSHelper_AccentColor(), 'Тема меню')
    local current = MSHelper_GetThemeKey()
    for i, key in ipairs(MSHelper_ThemeOrder) do
        if i > 1 and ((i - 1) % 3) ~= 0 then imgui.SameLine() end
        local label = MSHelper_ThemeLabels[key] or key
        local selected = current == key
        if selected then
            imgui.PushStyleColor(imgui.Col.Button, MSHelper_AccentColor(0.95))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, MSHelper_AccentColor(1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, MSHelper_AccentColor(0.85))
        end
        if imgui.Button(label .. '##ms_theme_' .. key, imgui.ImVec2(150, 28)) then
            MSHelper_SetTheme(key, true)
        end
        if selected then imgui.PopStyleColor(3) end
    end
    imgui.Separator()
end

_G.MSHelper_TagWrapGuard = _G.MSHelper_TagWrapGuard or false

function _G.MSHelper_TrimText(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function _G.MSHelper_GetRadioTag(cmd_name)
    cmd_name = tostring(cmd_name or ''):lower()

    -- Тег ставим только в обычные рации /r и /f.
    -- В /rn и /fn тег не добавляем.
    if cmd_name == 'r' then
        if not (_G.MSHelper_TagREnabled and _G.MSHelper_TagREnabled[0]) then return '' end
        if not _G.MSHelper_TagRBuffer then return '' end
        return _G.MSHelper_TrimText(ffi.string(_G.MSHelper_TagRBuffer))
    end
    if cmd_name == 'f' then
        if not (_G.MSHelper_TagFEnabled and _G.MSHelper_TagFEnabled[0]) then return '' end
        if not _G.MSHelper_TagFBuffer then return '' end
        return _G.MSHelper_TrimText(ffi.string(_G.MSHelper_TagFBuffer))
    end
    return ''
end

function _G.MSHelper_ApplyRadioTag(command)
    command = tostring(command or '')
    local cmd_name, body = command:match('^/(%S+)%s+(.+)$')
    if not cmd_name or not body then return command end

    cmd_name = cmd_name:lower()
    if cmd_name ~= 'r' and cmd_name ~= 'f' then
        return command
    end

    local tag_utf = _G.MSHelper_GetRadioTag(cmd_name)
    if tag_utf == '' then return command end

    body = _G.MSHelper_TrimText(body)
    if body == '' then return command end

    -- Если тег уже стоит в начале сообщения, повторно не добавляем.
    if body:sub(1, #tag_utf) == tag_utf then return command end
    local tag_cp = u8:decode(tag_utf)
    if body:sub(1, #tag_cp) == tag_cp then return command end

    return '/' .. cmd_name .. ' ' .. tag_cp .. ' ' .. body
end

function _G.MSHelper_WrapTaggedRadioCommand(command, limit)
    command = tostring(command or '')
    limit = tonumber(limit) or (_G.MSHelper_CHAT_WRAP_LIMIT or 110)

    local cmd_name, body = command:match('^/(%S+)%s+(.+)$')
    if not cmd_name or not body then return nil end
    cmd_name = cmd_name:lower()
    if cmd_name ~= 'r' and cmd_name ~= 'f' then return nil end

    local tag_utf = _G.MSHelper_GetRadioTag(cmd_name)
    if tag_utf == '' then return nil end
    local tag_cp = u8:decode(tag_utf)
    if body:sub(1, #tag_cp) ~= tag_cp then return nil end

    local rest = _G.MSHelper_TrimText(body:sub(#tag_cp + 1))
    if rest == '' then return { '/' .. cmd_name .. ' ' .. tag_cp } end

    local prefix = '/' .. cmd_name .. ' ' .. tag_cp .. ' '
    local body_limit = limit - #prefix
    if body_limit < 30 then body_limit = 30 end

    local result = {}
    if _G.MSHelper_WrapTextDots then
        for _, chunk in ipairs(_G.MSHelper_WrapTextDots(rest, body_limit)) do
            if chunk and chunk ~= '' then table.insert(result, prefix .. chunk) end
        end
    else
        table.insert(result, prefix .. rest)
    end

    return result
end

function _G.MSHelper_SendCommandPrepared(command)
    command = tostring(command or '')
    if command == '' then return end

    -- Команда отправляется сразу уже с тегом. Это исправляет ситуацию,
    -- когда первая строка серии /r уходила без тега, а последующие уже с тегом.
    if _G.MSHelper_ApplyRadioTag then
        command = _G.MSHelper_ApplyRadioTag(command)
    end

    _G.MSHelper_TagWrapGuard = true
    _G.MSHelper_TagWrapToken = (_G.MSHelper_TagWrapToken or 0) + 1
    local __ms_tag_token = _G.MSHelper_TagWrapToken
    sampSendChat(command)
    lua_thread.create(function()
        wait(120)
        if _G.MSHelper_TagWrapToken == __ms_tag_token then
            _G.MSHelper_TagWrapGuard = false
        end
    end)
end

function _G.MSHelper_SendOkReport(arg)
    local raw = tostring(arg or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local id = nil

    if raw ~= '' then
        id = tonumber(raw:match('^(%d+)$'))
    end

    -- Если /ok был вызван без ID, берем ID из поля меню только когда он реально заполнен.
    -- Пустой /ok и ID 0 не отправляем, чтобы сервер не принимал доклад за ID 0.
    if not id and _G.MSHelper_OkReportId then
        local saved_id = tonumber(_G.MSHelper_OkReportId[0]) or -1
        if saved_id > 0 then id = saved_id end
    end

    if not id or id <= 0 then
        helper_msg('Введите ID сотрудника: /ok id. ID 0 больше не отправляется.')
        return false
    end

    local nick = safe_nick(id)
    if not nick or nick == '' then
        helper_msg('Игрок ID ' .. tostring(id) .. ' не найден. Не могу получить ник для доклада.')
        return false
    end

    nick = nick:gsub('_', ' ')

    if _G.MSHelper_OkReportId then _G.MSHelper_OkReportId[0] = id end
    _G.MSHelper_SendCommandPrepared(u8:decode('/r ' .. nick .. ', Ваш доклад принят.'))
    return true
end

function _G.MSHelper_DrawRadioTagSettings()
    imgui.TextColored(MSHelper_AccentColor(), 'Теги в рацию')
    imgui.TextWrapped('Если галочка включена, скрипт будет сам добавлять указанный тег только в /r и /f. В /rn и /fn тег не ставится.')

    if imgui.Checkbox('» Тэг в R чат##ms_tag_r_on', _G.MSHelper_TagREnabled) then save() end
    imgui.SameLine()
    imgui.PushItemWidth(260)
    if imgui.InputText('Тэг для /r##ms_tag_r_text', _G.MSHelper_TagRBuffer, 64) then save() end
    imgui.PopItemWidth()

    if imgui.Checkbox('» Тэг в F чат##ms_tag_f_on', _G.MSHelper_TagFEnabled) then save() end
    imgui.SameLine()
    imgui.PushItemWidth(260)
    if imgui.InputText('Тэг для /f##ms_tag_f_text', _G.MSHelper_TagFBuffer, 64) then save() end
    imgui.PopItemWidth()

    imgui.TextWrapped('Пример: поставьте тег [ЗМЗ] или [Прямой Заместитель], и сообщение /r Привет уйдет как /r [ЗМЗ] Привет. или /r [Прямой Заместитель] Привет.')
end

function _G.MSHelper_DrawOkReportBlock()
    imgui.TextColored(MSHelper_AccentColor(), 'Принять доклад')
    imgui.PushItemWidth(110)
    imgui.InputInt('ID сотрудника##ms_ok_report_id', _G.MSHelper_OkReportId, 0, 0)
    if _G.MSHelper_OkReportId[0] < 0 then _G.MSHelper_OkReportId[0] = 0 end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Принять доклад в рацию##ms_ok_report_btn', imgui.ImVec2(230, 30)) then
        _G.MSHelper_SendOkReport()
    end
    imgui.TextWrapped('Команда: /ok id. В /r уйдет: Ник Фамилия, Ваш доклад принят.')
end

-- Разделитель/автоперенос длинных сообщений.
-- Встроено из Separate Messages: длинные IC, /r, /f, /b, /me, /do и похожие чаты делятся на несколько строк.
_G.MSHelper_CHAT_WRAP_LIMIT = _G.MSHelper_CHAT_WRAP_LIMIT or 90
_G.MSHelper_ChatWrapGuard = false
_G.MSHelper_WrapCommandMap = _G.MSHelper_WrapCommandMap or {
    c = true, s = true, b = true, r = true, m = true, d = true, f = true,
    rb = true, fb = true, rt = true, pt = true, ft = true, cs = true,
    t = true, ct = true, fam = true, vr = true, al = true
}

function _G.MSHelper_WrapTextWords(text, limit)
    text = tostring(text or '')
    limit = tonumber(limit) or 72
    if limit < 20 then limit = 20 end
    if #text <= limit then return { text } end

    _G.MSHelper_WrapTmpChunks = {}
    _G.MSHelper_WrapTmpRest = text

    while #_G.MSHelper_WrapTmpRest > limit do
        _G.MSHelper_WrapTmpPart = _G.MSHelper_WrapTmpRest:sub(1, limit)
        _G.MSHelper_WrapTmpCut = nil

        for i = #_G.MSHelper_WrapTmpPart, 1, -1 do
            if _G.MSHelper_WrapTmpPart:sub(i, i):match('%s') then
                _G.MSHelper_WrapTmpCut = i
                break
            end
        end

        if not _G.MSHelper_WrapTmpCut or _G.MSHelper_WrapTmpCut < 15 then
            _G.MSHelper_WrapTmpCut = limit
        end

        _G.MSHelper_WrapTmpPart = _G.MSHelper_WrapTmpRest:sub(1, _G.MSHelper_WrapTmpCut):gsub('%s+$', '')
        if _G.MSHelper_WrapTmpPart == '' then
            _G.MSHelper_WrapTmpPart = _G.MSHelper_WrapTmpRest:sub(1, limit)
            _G.MSHelper_WrapTmpCut = limit
        end

        table.insert(_G.MSHelper_WrapTmpChunks, _G.MSHelper_WrapTmpPart)
        _G.MSHelper_WrapTmpRest = _G.MSHelper_WrapTmpRest:sub(_G.MSHelper_WrapTmpCut + 1):gsub('^%s+', '')

        if #_G.MSHelper_WrapTmpChunks >= 8 then break end
    end

    if _G.MSHelper_WrapTmpRest ~= '' then
        table.insert(_G.MSHelper_WrapTmpChunks, _G.MSHelper_WrapTmpRest)
    end

    return _G.MSHelper_WrapTmpChunks
end

function _G.MSHelper_WrapTextDots(text, limit)
    _G.MSHelper_WrapTmpPlainChunks = _G.MSHelper_WrapTextWords(text, limit)
    if #_G.MSHelper_WrapTmpPlainChunks <= 1 then return _G.MSHelper_WrapTmpPlainChunks end

    _G.MSHelper_WrapTmpDotted = {}
    for i, chunk in ipairs(_G.MSHelper_WrapTmpPlainChunks) do
        if i == 1 then
            table.insert(_G.MSHelper_WrapTmpDotted, tostring(chunk):gsub('%s+$', '') .. '...')
        else
            table.insert(_G.MSHelper_WrapTmpDotted, '...' .. tostring(chunk):gsub('^%s+', ''))
        end
    end
    return _G.MSHelper_WrapTmpDotted
end

function _G.MSHelper_IsWrapCommandPrefix(prefix)
    prefix = tostring(prefix or ''):lower():gsub('^/', '')
    return _G.MSHelper_WrapCommandMap[prefix] == true or prefix == 'me' or prefix == 'do'
end

function _G.MSHelper_BuildWrappedCommandLines(command)
    command = tostring(command or '')
    if command == '' then return nil end

    _G.MSHelper_WrapTmpCmdName, _G.MSHelper_WrapTmpBody = command:match('^/(%S+)%s+(.+)$')
    if not _G.MSHelper_WrapTmpCmdName or not _G.MSHelper_WrapTmpBody then return nil end

    _G.MSHelper_WrapTmpCmdLower = _G.MSHelper_WrapTmpCmdName:lower()

    if (_G.MSHelper_WrapTmpCmdLower == 'r' or _G.MSHelper_WrapTmpCmdLower == 'f') and _G.MSHelper_WrapTaggedRadioCommand then
        _G.MSHelper_WrapTmpTaggedLines = _G.MSHelper_WrapTaggedRadioCommand(command, 90)
        if _G.MSHelper_WrapTmpTaggedLines and #_G.MSHelper_WrapTmpTaggedLines > 1 then
            return _G.MSHelper_WrapTmpTaggedLines
        end
    end

    if _G.MSHelper_WrapCommandMap[_G.MSHelper_WrapTmpCmdLower] == true then
        if #_G.MSHelper_WrapTmpBody <= 80 then return nil end

        _G.MSHelper_WrapTmpLines = {}
        if _G.MSHelper_WrapTmpBody:sub(1, 2) == '((' then
            _G.MSHelper_WrapTmpInner = _G.MSHelper_WrapTmpBody:sub(3):gsub('^%s+', ''):gsub('%s*%)%)%s*$', '')
            _G.MSHelper_WrapTmpPrefix = '/' .. _G.MSHelper_WrapTmpCmdLower .. ' (( '
            _G.MSHelper_WrapTmpSuffix = ' ))'
            _G.MSHelper_WrapTmpBodyLimit = 72
        else
            _G.MSHelper_WrapTmpInner = _G.MSHelper_WrapTmpBody
            _G.MSHelper_WrapTmpPrefix = '/' .. _G.MSHelper_WrapTmpCmdLower .. ' '
            _G.MSHelper_WrapTmpSuffix = ''
            _G.MSHelper_WrapTmpBodyLimit = 72
        end

        for _, chunk in ipairs(_G.MSHelper_WrapTextDots(_G.MSHelper_WrapTmpInner, _G.MSHelper_WrapTmpBodyLimit)) do
            table.insert(_G.MSHelper_WrapTmpLines, _G.MSHelper_WrapTmpPrefix .. chunk .. _G.MSHelper_WrapTmpSuffix)
        end

        if #_G.MSHelper_WrapTmpLines > 1 then return _G.MSHelper_WrapTmpLines end
        return nil
    end

    if _G.MSHelper_WrapTmpCmdLower == 'me' or _G.MSHelper_WrapTmpCmdLower == 'do' then
        if #_G.MSHelper_WrapTmpBody <= 75 then return nil end

        _G.MSHelper_WrapTmpLines = {}
        _G.MSHelper_WrapTmpChunks = _G.MSHelper_WrapTextDots(_G.MSHelper_WrapTmpBody, 72)

        for i, chunk in ipairs(_G.MSHelper_WrapTmpChunks) do
            if i == 1 then
                table.insert(_G.MSHelper_WrapTmpLines, '/' .. _G.MSHelper_WrapTmpCmdLower .. ' ' .. chunk)
            else
                _G.MSHelper_WrapTmpDoChunk = tostring(chunk)
                if _G.MSHelper_WrapTmpDoChunk:sub(-1) ~= '.' then
                    _G.MSHelper_WrapTmpDoChunk = _G.MSHelper_WrapTmpDoChunk .. '.'
                end
                table.insert(_G.MSHelper_WrapTmpLines, '/do ' .. _G.MSHelper_WrapTmpDoChunk)
            end
        end

        if #_G.MSHelper_WrapTmpLines > 1 then return _G.MSHelper_WrapTmpLines end
        return nil
    end

    return nil
end

function _G.MSHelper_WrapOutgoingLine(text, limit)
    text = tostring(text or '')
    limit = tonumber(limit) or 90
    if #text <= limit then return { text } end
    return _G.MSHelper_WrapTextDots(text, 72)
end

function _G.MSHelper_SendWrappedLines(lines, delay_ms)
    lua_thread.create(function()
        _G.MSHelper_ChatWrapGuard = true
        _G.MSHelper_TagWrapGuard = true
        for _, line in ipairs(lines or {}) do
            if line and line ~= '' then
                sampSendChat(line)
                wait(tonumber(delay_ms) or 220)
            end
        end
        wait(120)
        _G.MSHelper_ChatWrapGuard = false
        _G.MSHelper_TagWrapGuard = false
    end)
end

function sampev.onSendChat(text)
    if _G.MSHelper_ChatWrapGuard then return end
    _G.MSHelper_WrapTmpChatLines = _G.MSHelper_WrapOutgoingLine(text, 90)
    if _G.MSHelper_WrapTmpChatLines and #_G.MSHelper_WrapTmpChatLines > 1 then
        _G.MSHelper_SendWrappedLines(_G.MSHelper_WrapTmpChatLines, 220)
        return false
    end
end

local function cp1251(text)
    return u8:decode(text)
end

MSH_PHONE_GREET_WAIT_UNTIL = 0
MSH_PHONE_GREET_LAST_SENT_AT = 0
MSH_PHONE_CALL_UNTIL = 0

function MSH_PHONE_IS_INCOMING_CALL(raw_text, low_text)
    raw_text = tostring(raw_text or '')
    low_text = tostring(low_text or raw_text):lower()
    local function has(text)
        return low_text:find(cp1251(text):lower(), 1, true) ~= nil
    end

    -- Advance RP / лаунчер: системная строка входящего звонка.
    -- Например: "Используйте /p чтобы ответить или /h чтобы отклонить вызов".
    if has('/p') and has('/h') and (has('ответ') or has('вызов') or has('звон')) then
        return true
    end
    return false
end

function MSH_PHONE_GREET_IS_ACCEPTED(raw_text, low_text)
    raw_text = tostring(raw_text or '')
    low_text = tostring(low_text or raw_text):lower()

    local function has(text)
        return low_text:find(cp1251(text):lower(), 1, true) ~= nil
    end

    if has('труб') and (has('взя') or has('подня') or has('ответ') or has('разговор')) then
        return true
    end
    if has('звон') and (has('ответ') or has('принял') or has('принят')) then
        return true
    end
    if has('телефон') and (has('разговор') or has('соединение') or has('связь установлена')) then
        return true
    end
    if low_text:find('phone', 1, true) and (low_text:find('answer', 1, true) or low_text:find('accept', 1, true)) then
        return true
    end

    return false
end

function MSH_PHONE_GREET_SEND_ACCEPTED()
    if not (MSH_PHONE_GREET_ENABLED and MSH_PHONE_GREET_ENABLED[0]) then return end

    local now = os.clock()
    if now - (MSH_PHONE_GREET_LAST_SENT_AT or 0) < 3 then return end
    MSH_PHONE_GREET_LAST_SENT_AT = now
    MSH_PHONE_GREET_WAIT_UNTIL = 0
    MSH_PHONE_CALL_UNTIL = 0

    lua_thread.create(function()
        wait(MSH_PHONE_GREET_DELAY or 700)
        local text = trim(ffi.string(MSH_PHONE_GREET_BUFFER))
        if text ~= '' then chat(text) end
    end)
end

local function clamp_reconnect_delay(value)
    value = tonumber(value) or tonumber(cfg.reconnect and cfg.reconnect.delay) or 5
    if value < 1 then value = 1 end
    if value > 120 then value = 120 end
    return math.floor(value)
end

local function reconnect_get_gamestate()
    if type(sampGetGamestate) == 'function' then
        return sampGetGamestate()
    end
    return -1
end

local function reconnect_save_current_server()
    cfg.reconnect = cfg.reconnect or {}
    if type(sampGetCurrentServerAddress) == 'function' then
        local ip, port = sampGetCurrentServerAddress()
        if ip ~= nil and tostring(ip) ~= '' then
            cfg.reconnect.server_ip = tostring(ip)
            cfg.reconnect.server_port = tonumber(port) or tonumber(cfg.reconnect.server_port) or 0
            return true
        end
    end
    return false
end

local function reconnect_try_disconnect()
    -- Не используем pcall в игровых потоках: на некоторых сборках MoonLoader это может
    -- вызывать ошибку coroutine. Вызываем только существующие стандартные функции.
    if type(sampDisconnectWithReason) == 'function' then
        sampDisconnectWithReason(0)
        return true
    end
    if type(sampSetGamestate) == 'function' then
        sampSetGamestate(5)
        return true
    end
    return false
end

local function reconnect_try_connect()
    cfg.reconnect = cfg.reconnect or {}
    local ip = tostring(cfg.reconnect.server_ip or '')
    local port = tonumber(cfg.reconnect.server_port) or 0

    -- Если доступна прямая функция подключения — используем сохраненный адрес.
    if ip ~= '' and port > 0 and type(sampConnectToServer) == 'function' then
        sampConnectToServer(ip, port)
        return true
    end

    -- Запасной способ для обычного реконнекта на текущий сервер.
    if type(sampSetGamestate) == 'function' then
        sampSetGamestate(1)
        return true
    end

    return false
end

local function reconnect_start(delay, reason)
    delay = clamp_reconnect_delay(delay)

    if rc.running then
        helper_msg('Реконнект уже выполняется. Осталось примерно ' .. tostring(math.max(0, (rc.next_try_at or os.time()) - os.time())) .. ' сек.')
        return false
    end

    if rc.delay and rc.delay[0] ~= delay then
        rc.delay[0] = delay
        cfg.reconnect.delay = delay
    end

    -- Сохраняем адрес только если мы ещё подключены. Если соединение уже потеряно,
    -- используем последний сохранённый IP/порт из ms_helper.ini.
    if reconnect_get_gamestate() == 3 then
        reconnect_save_current_server()
        reconnect_try_disconnect()
    end

    rc.running = true
    rc.next_try_at = os.time() + delay
    rc.reconnect_reason = tostring(reason or 'manual')
    helper_msg((rc.reconnect_reason == 'auto' and 'Авто-реконнект' or 'Реконнект') .. ' через ' .. delay .. ' сек.')
    save()
    return true
end

local function reconnect_toggle_auto(arg)
    local value = tostring(arg or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if value == 'on' or value == '1' or value == 'вкл' or value == 'yes' then
        rc.auto[0] = true
    elseif value == 'off' or value == '0' or value == 'выкл' or value == 'no' then
        rc.auto[0] = false
    else
        rc.auto[0] = not rc.auto[0]
    end
    cfg.reconnect.auto = rc.auto[0]
    save()
    helper_msg('Авто-реконнект: ' .. (rc.auto[0] and 'включен' or 'выключен') .. '. Проверка идёт отдельным безопасным потоком.')
end

local function reconnect_status()
    cfg.reconnect = cfg.reconnect or {}
    local ip = tostring(cfg.reconnect.server_ip or '')
    local port = tonumber(cfg.reconnect.server_port) or 0
    local server = (ip ~= '' and port > 0) and (ip .. ':' .. port) or 'сервер ещё не сохранён'
    helper_msg('Реконнект: авто ' .. (rc.auto[0] and 'включен' or 'выключен') .. ' | задержка ' .. tostring(clamp_reconnect_delay(rc.delay[0])) .. ' сек. | ' .. server .. '.')
end

local function reconnect_process()
    -- ВАЖНО: эта функция больше НЕ вызывается каждый кадр из MainTick.
    -- Она работает только из отдельного потока раз в секунду, поэтому не должна
    -- вызывать ошибку MoonLoader "cannot resume non-suspended coroutine".
    local now = os.time()
    if now == rc.last_state_check then return end
    rc.last_state_check = now

    if rc.delay[0] < 1 then rc.delay[0] = 1 end
    if rc.delay[0] > 120 then rc.delay[0] = 120 end

    local state = reconnect_get_gamestate()

    if state == 3 then
        rc.was_connected = true
        rc.next_try_at = 0
        rc.running = false
        if now - (rc.last_server_save or 0) >= 10 then
            rc.last_server_save = now
            reconnect_save_current_server()
            cfg.reconnect.auto = rc.auto[0]
            cfg.reconnect.delay = rc.delay[0]
            inicfg.save(cfg, cfg_path)
        end
        return
    end

    if rc.running then
        if (rc.next_try_at or 0) > 0 and now >= rc.next_try_at then
            rc.next_try_at = 0
            if reconnect_try_connect() then
                helper_msg('Пробую подключиться к серверу.')
            else
                helper_msg('Не нашел функцию подключения. Попробуйте /sconnect на сервере или отдельный Reconnect.cs.')
            end
            -- Даём игре несколько секунд на подключение. Если не получилось,
            -- автоматический режим повторит попытку позже.
            rc.running = false
        end
        return
    end

    if rc.auto[0] and rc.was_connected then
        rc.next_try_at = now + clamp_reconnect_delay(rc.delay[0])
        rc.running = true
        rc.reconnect_reason = 'auto'
        helper_msg('Соединение потеряно. Авто-реконнект через ' .. clamp_reconnect_delay(rc.delay[0]) .. ' сек.')
    end
end

function MSHelper_ReconnectStartWorker()
    if _G.MSHelper_ReconnectWorkerStarted then return end
    _G.MSHelper_ReconnectWorkerStarted = true

    lua_thread.create(function()
        wait(2500)
        while true do
            reconnect_process()
            wait(1000)
        end
    end)
end

local function nick_or_id(pid)
    pid = tonumber(pid) or -1
    local nick = safe_nick(pid)
    if nick then return nick:gsub('_', ' ') end
    return 'ID ' .. tostring(pid)
end

local function interview_candidate_label(pid, nick)
    -- Для отчёта после /sobes нужен только ник без подчёркивания, без ID игрока.
    pid = tonumber(pid) or -1
    nick = tostring(nick or safe_nick(pid) or ''):gsub('_', ' ')
    if nick == '' then nick = 'кандидат' end
    return nick
end

local function send_interview_leadership_report(pid, nick)
    if MSHelper_ReportAdd then MSHelper_ReportAdd('interview', 'Проведено собеседование: ' .. interview_candidate_label(pid, nick)) end
    _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Кандидат ') .. interview_candidate_label(pid, nick) .. u8:decode(' Прошел успешно собеседование.'))
end

local function send_interview_no_invite_fallback(pid, nick)
    chat('Хорошо, вы нам подходите. Я сейчас передам руководству.')
    wait(700)
    send_interview_leadership_report(pid, nick)
end

local function send_uninvite_radio_by_reason(nick, reason, reason_type)
    reason = trim(tostring(reason or ''))
    reason_type = tostring(reason_type or 'fire')

    if reason_type == 'vacation' then
        _G.MSHelper_SendCommandPrepared(u8:decode('/f Сотрудник ') .. nick .. u8:decode(' был отправлен в отпуск.'))
    elseif reason_type == 'transfer' then
        _G.MSHelper_SendCommandPrepared(u8:decode('/f Сотрудник ') .. nick .. u8:decode(' был переведен в другое подразделение.'))
    else
        _G.MSHelper_SendCommandPrepared(u8:decode('/f Сотрудник ') .. nick .. u8:decode(' был уволен по причине: ') .. reason)
    end
end


local function run_invite_sequence_inline(pid, nick, opts)
    pid = tonumber(pid) or -1
    nick = nick or nick_or_id(pid)
    opts = opts or {}

    _G.MSHelper_InviteBusy = true
    _G.MSHelper_InviteBlocked = false
    _G.MSHelper_InviteNoAccess = false
    _G.MSHelper_InviteWatchUntil = os.clock() + 5

    chat('/me достал из папки трудовой договор, медицинскую форму и служебную рацию')
    -- Сервер Advance часто отвечает "Подождите" если после RP сразу отправить системную команду.
    -- Увеличенная пауза убирает антифлуд и не дает скрипту продолжать цепочку при отказе сервера.
    wait(1700)
	
    script_invite_guard = true
    sampSendChat('/invite ' .. pid)
    wait(650)
    script_invite_guard = false

    wait(1200)
    if _G.MSHelper_InviteBlocked then
        _G.MSHelper_InviteBusy = false
        helper_msg('Сервер попросил подождать. Повторите /invite ' .. pid .. ' через пару секунд.')
        return false
    end

    if _G.MSHelper_InviteNoAccess then
        _G.MSHelper_InviteBusy = false
        if opts.interview_no_invite_fallback then
            helper_msg('Нет доступа к /invite. Сообщаю кандидату и передаю результат руководству.')
            send_interview_no_invite_fallback(pid, nick)
        else
            helper_msg('Нет доступа к /invite.')
        end
        return false
    end

    _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Поздравляем, ') .. nick .. u8:decode(' с началом карьеры в нашей организации!'))
    _G.MSHelper_InviteBusy = false
    return true
end

local function send_invite_sequence(pid)
    pid = tonumber(pid) or -1
    if pid < 0 or not ms_safe_player_connected(pid) then
        helper_msg('Используйте: /invite id')
        return false
    end

    local raw_nick = safe_nick(pid)
    local nick = raw_nick and raw_nick:gsub('_', ' ') or nick_or_id(pid)

    if _G.MSHelper_InviteBusy then
        helper_msg('Подождите, приглашение уже выполняется.')
        return false
    end

    lua_thread.create(function()
        -- Не оборачиваем всю цепочку в pcall: внутри есть wait(), а на некоторых сборках
        -- yield внутри pcall может приводить к нестабильности/крашу SA-MP.
        run_invite_sequence_inline(pid, nick)
        script_invite_guard = false
        _G.MSHelper_InviteBusy = false
    end)

    return true
end

local function send_new_employee_radio(pid)
    pid = tonumber(pid) or -1
    if pid < 0 then
        helper_msg('Используйте: /invite id')
        return false
    end

    local nick = nick_or_id(pid):gsub('_', ' ')

    lua_thread.create(function()
        _G.MSHelper_SendCommandPrepared(u8:decode('/r Поздравляем нашего нового сотрудника ') .. nick .. u8:decode('!'))
    end)

    pending_invites[pid] = nil
    return true
end

local function send_uninvite_sequence(pid, reason, reason_is_utf8, reason_type)
    pid = tonumber(pid) or -1
    reason = trim(tostring(reason or ''))
    local sendReason = reason
    if reason_is_utf8 then
        sendReason = u8:decode(reason)
    end
    if pid < 0 or reason == '' then
        helper_msg('Используйте: /uni id причина')
        return false
    end
    if not ms_safe_player_connected(pid) then
        helper_msg('Игрок ID '..pid..' не подключен.')
        return false
    end
    local nick = nick_or_id(pid)
    lua_thread.create(function()
        chat('/me взял форму и рацию сотрудника затем положил ее в пакет')
        wait(900)

        -- Причину НЕ декодируем через u8:decode(reason), потому что текст из команды уже приходит в кодировке игры.
        -- Из-за лишнего decode сервер мог получать пустую/битую причину и показывать только ник увольняющего.
        send_uninvite_radio_by_reason(nick, sendReason, reason_type)

        wait(900)
        script_uninvite_guard = true
        sampSendChat('/uninvite ' .. pid .. ' ' .. sendReason)
        wait(250)
        script_uninvite_guard = false
    end)
    return true
end


local function send_rang_sequence(pid, sign)
    pid = tonumber(pid) or -1
    sign = trim(tostring(sign or ''))
    if pid < 0 or (sign ~= '+' and sign ~= '-') then
        helper_msg('Используйте: /rang id + или /rang id -')
        return false
    end
    if not ms_safe_player_connected(pid) then
        helper_msg('Игрок ID '..pid..' не подключен.')
        return false
    end
    lua_thread.create(function()
        chat('/me достал планшет зашел в базу данных')
        wait(900)
        chat('/do Изменил данные о сотруднике.')
        wait(900)
        script_rang_guard = true
        sampSendChat('/rang ' .. pid .. ' ' .. sign)
        wait(250)
        script_rang_guard = false
    end)
    return true
end


local function send_drive_sequence()
    lua_thread.create(function()
        _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Внимание! Происходит эвакуация техники на парковку! 15 секунд'))
        wait(5000)
        _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Внимание! Происходит эвакуация техники на парковку! 10 секунд'))
        wait(5000)
        _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Внимание! Происходит эвакуация техники на парковку! 5 секунд'))
        wait(5000)
        _G.MSHelper_SendCommandPrepared('/r ' .. u8:decode('Внимание! Происходит эвакуация техники на парковку!'))
        wait(700)
        script_drive_guard = true
        sampSendChat('/drive')
        wait(250)
        script_drive_guard = false
    end)
    return true
end

-- /drive 1 — быстрый респ транспорта без оповещения в /r.
function _G.MSHelper_SendDriveQuick()
    lua_thread.create(function()
        script_drive_guard = true
        sampSendChat('/drive')
        wait(250)
        script_drive_guard = false
    end)
    return true
end


local function send_givemed_sequence(pid)
    pid = tonumber(pid) or -1
    if pid < 0 or not ms_safe_player_connected(pid) then
        helper_msg('Используйте: /givemed id')
        return false
    end

    -- После запуска выдачи медкарты закрываем мини-меню пациента, чтобы оно не мешало игре.
    if patient_window then patient_window[0] = false end

    lua_thread.create(function()
        chat('/me взял чистую медицинскую карту, затем начал ее заполнять')
        wait(900)
        chat('/do Медицинская карта полностью готова.')
        wait(900)
        chat('/me передает гражданину медицинскую карту')
        wait(700)

        script_givemed_guard = true
        sampSendChat('/givemed ' .. pid)
        wait(250)
        script_givemed_guard = false
        if MSHelper_ReportAdd then MSHelper_ReportAdd('medcard', 'Выдана медицинская карта: ' .. last_call_nick_for_id(pid)) end
    end)

    return true
end

local function invite_no_access_message_matches(raw_text, low_text)
    raw_text = tostring(raw_text or '')
    low_text = tostring(low_text or raw_text):lower()

    local function has(text)
        return low_text:find(cp1251(text):lower(), 1, true) ~= nil
    end

    local mentions_invite = low_text:find('/invite', 1, true)
        or low_text:find('invite', 1, true)
        or has('инвайт')
        or has('приглас')
        or has('команд')

    local no_access = has('нет доступа')
        or has('у вас нет доступа')
        or has('нет прав')
        or has('нет полномочий')
        or has('недостаточно прав')
        or has('недостаточно полномочий')
        or has('недоступ')
        or has('вы не можете')
        or has('не можете использовать')
        or has('вам нельзя')
        or has('команда доступна')
        or has('доступна только')
        or has('доступно только')
        or has('доступен только')
        or has('только лидер')
        or has('только для лидеров')
        or has('только замест')
        or has('руковод')

    -- Эта проверка вызывается только в коротком окне сразу после отправки /invite,
    -- поэтому серверный ответ без упоминания самой команды тоже считаем отказом доступа.
    return no_access or (mentions_invite and no_access)
end

local function invite_accept_message_matches(raw_text, low_text, data)
    if not data then return false end

    local has_accept_text =
        low_text:find(cp1251('принимает'), 1, true) or
        low_text:find(cp1251('принял'), 1, true) or
        low_text:find(cp1251('приняла'), 1, true) or
        low_text:find(cp1251('принято'), 1, true) or
        low_text:find(cp1251('принята'), 1, true) or
        low_text:find(cp1251('принят'), 1, true) or
        low_text:find(cp1251('вступил'), 1, true) or
        low_text:find(cp1251('вступила'), 1, true) or
        low_text:find(cp1251('теперь работает'), 1, true) or
        low_text:find(cp1251('теперь сотрудник'), 1, true)

    if not has_accept_text then return false end

    local variants = {}
    if data.nick and data.nick ~= '' then table.insert(variants, data.nick) end
    if data.raw_nick and data.raw_nick ~= '' then
        table.insert(variants, data.raw_nick)
        table.insert(variants, data.raw_nick:gsub('_', ' '))
    end
    if data.id ~= nil then
        table.insert(variants, 'ID ' .. tostring(data.id))
        table.insert(variants, '[' .. tostring(data.id) .. ']')
        table.insert(variants, '(' .. tostring(data.id) .. ')')
    end

    for _, v in ipairs(variants) do
        if v and v ~= '' and raw_text:find(v, 1, true) then
            return true
        end
    end

    return false
end


local function remember_med_call_from_message(text)
    local raw_text = tostring(text or '')
    if raw_text == '' then return false end

    local has_call_text =
        raw_text:find(cp1251('Поступил вызов'), 1, true) or
        raw_text:find(cp1251('поступил вызов'), 1, true) or
        raw_text:find(cp1251('поступил вызов.'):gsub('%.', ''), 1, true)

    if not has_call_text then
        return false
    end

    -- Пример серверной строки: "От игрока Makar Maslow[982] поступил вызов".
    -- Берём ник и ID из квадратных скобок, чтобы потом /to id мог сам написать ник в /r.
    local nick, id
    for n, i in raw_text:gmatch('([^%[%]\r\n]+)%s*%[(%d+)%]') do
        nick, id = n, i
    end

    if not id then return false end

    nick = trim(nick or '')
    nick = nick:gsub('^' .. cp1251('от игрока') .. '%s+', '')
    nick = nick:gsub('^' .. cp1251('От игрока') .. '%s+', '')
    nick = trim(nick):gsub('_', ' ')
    if nick == '' then nick = 'ID ' .. tostring(id) end

    last_med_call_id = tonumber(id) or -1
    last_med_call_nick = nick
    last_med_call_time = os.time()

    if cfg.main.show_heal_debug then
        helper_msg('Запомнил вызов гражданина: ' .. nick .. '[' .. tostring(last_med_call_id) .. ']')
    end

    return true
end

local function ms_contains_text(raw_text, needle_utf8)
    raw_text = tostring(raw_text or '')
    needle_utf8 = tostring(needle_utf8 or '')
    if raw_text == '' or needle_utf8 == '' then return false end

    -- На разных сборках MoonLoader строка сервера может прийти либо UTF-8, либо CP1251.
    -- Поэтому проверяем оба варианта, чтобы фильтр СМИ не промахивался.
    if raw_text:find(needle_utf8, 1, true) then return true end
    if raw_text:find(u8:decode(needle_utf8), 1, true) then return true end
    return false
end


function MSHelper_SendDisRpOnce(index)
    local rp = dis_illness_rp[tonumber(index) or -1]
    if not rp or rp == '' then return false end

    local now = os.time()
    if now - (_G.MSHelper_DisRpLastSentAt or 0) < 3 then return true end
    _G.MSHelper_DisRpLastSentAt = now

    if patient_window then patient_window[0] = false end
    lua_thread.create(function()
        wait(650)
        chat(rp)
        if MSHelper_ReportAdd then MSHelper_ReportAdd('dis', 'Процедура лечения болезней: пункт №' .. tostring(index)) end
    end)
    return true
end

function MSHelper_SendAnalysisRpOnce(index)
    local rp = analysis_rp[tonumber(index) or -1]
    if not rp or rp == '' then return false end

    local now = os.time()
    if now - (_G.MSHelper_AnalysisRpLastSentAt or 0) < 3 then return true end
    _G.MSHelper_AnalysisRpLastSentAt = now

    if patient_window then patient_window[0] = false end
    lua_thread.create(function()
        wait(650)
        chat(rp)
        if MSHelper_ReportAdd then MSHelper_ReportAdd('analysis', 'Проведён анализ: пункт №' .. tostring(index)) end
    end)
    return true
end

function MSHelper_HandleProcedureServerRp(raw_text)
    raw_text = tostring(raw_text or '')
    if raw_text == '' then return false end

    -- Фоллбек на серверное подтверждение. На некоторых сборках событие выбора диалога
    -- /dis не приходит в sampev.onSendDialogResponse, хотя процедура уже применена.
    if ms_contains_text(raw_text, 'Вы направили') and ms_contains_text(raw_text, 'на процедуру') then
        if ms_contains_text(raw_text, 'Свеч') then return MSHelper_SendDisRpOnce(1) end
        if ms_contains_text(raw_text, 'Массаж') or ms_contains_text(raw_text, 'массаж') then return MSHelper_SendDisRpOnce(2) end
        if ms_contains_text(raw_text, 'Капельниц') or ms_contains_text(raw_text, 'капельниц') then return MSHelper_SendDisRpOnce(3) end
        if ms_contains_text(raw_text, 'Антибиот') or ms_contains_text(raw_text, 'антибиот') then return MSHelper_SendDisRpOnce(4) end
        if ms_contains_text(raw_text, 'Ингаляц') or ms_contains_text(raw_text, 'ингаляц') then return MSHelper_SendDisRpOnce(5) end
    end

    -- Такой же запасной вариант для /analysis, если диалог выбора анализов не был пойман.
    if ms_contains_text(raw_text, 'Вы направили') and (
        ms_contains_text(raw_text, 'анализ') or
        ms_contains_text(raw_text, 'кров') or
        ms_contains_text(raw_text, 'моч') or
        ms_contains_text(raw_text, 'томограф') or
        ms_contains_text(raw_text, 'МРТ') or
        ms_contains_text(raw_text, 'КТ')
    ) then
        if ms_contains_text(raw_text, 'кров') or ms_contains_text(raw_text, 'Кров') then return MSHelper_SendAnalysisRpOnce(1) end
        if ms_contains_text(raw_text, 'моч') or ms_contains_text(raw_text, 'Моч') then return MSHelper_SendAnalysisRpOnce(2) end
        if ms_contains_text(raw_text, 'компьютер') or ms_contains_text(raw_text, 'Компьютер') or ms_contains_text(raw_text, 'КТ') then return MSHelper_SendAnalysisRpOnce(3) end
        if ms_contains_text(raw_text, 'магнит') or ms_contains_text(raw_text, 'Магнит') or ms_contains_text(raw_text, 'МРТ') then return MSHelper_SendAnalysisRpOnce(4) end
    end

    return false
end

local function is_smi_ad_message(text)
    local raw_text = tostring(text or '')
    if raw_text == '' then return false end

    -- Убираем цветовые коды {FFFFFF}, если сервер/другие скрипты их добавили.
    local plain = raw_text:gsub('{%x+}', '')
    -- Иногда в хуке может прийти уже видимая строка с временем в начале.
    plain = plain:gsub('^%s*%[%d%d:%d%d:%d%d%]%s*', '')
    local ascii_low = plain:lower()

    -- Объявления от СМИ на Advance могут приходить как:
    --   TV | текст | Отправил ...
    --   SF | текст | Отправил ...
    --   LS | текст | Отправил ...
    --   LV | текст | Отправил ...
    --   [TV | текст ...]
    -- Поэтому ловим не только TV, а все городские/эфирные префиксы СМИ.
    local ad_prefixes = {'tv', 'sf', 'ls', 'lv'}
    for _, p in ipairs(ad_prefixes) do
        if ascii_low:match('^%s*%[?' .. p .. '%s*|') then return true end
        if ascii_low:find(' ' .. p .. ' |', 1, true) then
            if ms_contains_text(plain, 'Отправил') or ms_contains_text(plain, 'отправил') then return true end
        end
    end

    -- Самый надежный признак объявления: есть "| Отправил ... (тел. ...)".
    -- Так скрываются варианты, где префикс отличается от TV/SF/LS/LV.
    if plain:find('|', 1, true) then
        local has_sender = ms_contains_text(plain, 'Отправил') or ms_contains_text(plain, 'отправил')
        local has_phone = ms_contains_text(plain, 'тел.') or ms_contains_text(plain, 'телефон') or ascii_low:find('tel', 1, true)
        if has_sender and has_phone then return true end
    end

    -- Системная строка после проверки объявления сотрудником СМИ.
    if ms_contains_text(plain, 'Объявление проверил сотрудник СМИ') then return true end
    if ms_contains_text(plain, 'объявление проверил сотрудник СМИ') then return true end
    if ms_contains_text(plain, 'проверил сотрудник СМИ') then return true end
    if ms_contains_text(plain, 'сотрудник СМИ') and ms_contains_text(plain, 'Объявление') then return true end

    return false
end


function MSHelper_IsJobChatMessage(text)
    local raw_text = tostring(text or '')
    if raw_text == '' then return false end

    -- Скрываем именно рабочий чат /j и /jn в чате.
    -- На Advance строки могут приходить как:
    --   [J] ...
    --   [JN] ...
    --   (( [J] ... ))
    --   (( [JN] ... ))
    -- и иногда сервер/другие скрипты вставляют цветовые коды {RRGGBB}.
    local plain = raw_text:gsub('{%x%x%x%x%x%x%x%x}', '')
    plain = plain:gsub('{%x%x%x%x%x%x}', '')
    plain = plain:gsub('{%x+}', '')
    plain = plain:gsub('%c', '')
    plain = plain:gsub('^%s*%[%d%d:%d%d:%d%d%]%s*', '')
    plain = plain:gsub('^%s*%(%(%s*', '')
    plain = plain:gsub('%s*%)%)%s*$', '')

    local lead = plain:lower():gsub('^%s+', '')

    -- Главные форматы рабочего чата. Не трогаем [R]/[RN]/[F]/[FN].
    if lead:match('^%[%s*j%s*%]') then return true end
    if lead:match('^%[%s*jn%s*%]') then return true end

    -- Запасной ловец, если перед [J]/[JN] остались служебные скобки или пробелы.
    if lead:match('^%(*%s*%[%s*j%s*%]') then return true end
    if lead:match('^%(*%s*%[%s*jn%s*%]') then return true end

    -- Форматы без квадратных скобок: J | текст, JN | текст, /j текст, /jn текст.
    if lead:match('^j%s*[%]|:>]') then return true end
    if lead:match('^jn%s*[%]|:>]') then return true end
    if lead:match('^/j%s+') then return true end
    if lead:match('^/jn%s+') then return true end

    -- Системные подсказки/варианты названия канала.
    if ms_contains_text(plain, 'Рабочий чат') or ms_contains_text(plain, 'рабочий чат') then return true end
    if ms_contains_text(plain, 'Раб. чат') or ms_contains_text(plain, 'раб. чат') then return true end
    if lead:find('work chat', 1, true) or lead:find('job chat', 1, true) then return true end

    return false
end

function MSHelper_CleanServerLineForFilter(text)
    local plain = tostring(text or '')
    plain = plain:gsub('{%x%x%x%x%x%x%x%x}', '')
    plain = plain:gsub('{%x%x%x%x%x%x}', '')
    plain = plain:gsub('{%x+}', '')
    plain = plain:gsub('%c', '')
    plain = plain:gsub('^%s*%[%d%d:%d%d:%d%d%]%s*', '')
    return plain
end

function MSHelper_LineHasAny(text, words)
    for _, word in ipairs(words) do
        if ms_contains_text(text, word) then return true end
    end
    return false
end

function MSHelper_IsAdminPunishmentMessage(text)
    local plain = MSHelper_CleanServerLineForFilter(text)
    if plain == '' then return false end

    local low = plain:lower()
    local has_admin = MSHelper_LineHasAny(plain, {
        'Администратор', 'администратор', 'Админ', 'админ'
    }) or low:find('administrator', 1, true) or low:find('admin ', 1, true)

    if not has_admin then return false end

    -- Advance RP использует разные формулировки наказаний.
    -- Например: "Администратор Nick поставил затычку игроку Name на 60 мин. Причина: ..."
    -- Поэтому проверяем не только ban/kick/mute, но и русские варианты "затычки", КПЗ и деморгана.
    local has_action = MSHelper_LineHasAny(plain, {
        'забанил', 'забанила', 'забанен', 'забанена', 'выдал бан', 'выдала бан',
        'заблокировал', 'заблокировала', 'заблокировал аккаунт', 'заблокировала аккаунт',
        'кикнул', 'кикнула', 'выкинул', 'выкинула', 'отключил', 'отключила',
        'замутил', 'замутила', 'выдал мут', 'выдала мут', 'мут игроку',
        'поставил затычку', 'поставила затычку', 'затычку игроку', 'выдал затычку', 'выдала затычку',
        'заткнул', 'заткнула', 'mute', 'muted',
        'выдал предупреждение', 'выдала предупреждение', 'выдал warn', 'выдала warn',
        'выдал варн', 'выдала варн', 'warn',
        'посадил', 'посадила', 'посадил игрока', 'посадила игрока',
        'отправил в деморган', 'отправила в деморган', 'деморган', 'jail', 'jailed', 'кпз', 'КПЗ',
        'ban', 'banned', 'kick', 'kicked'
    })

    if not has_action then return false end

    -- Страховка, чтобы не скрывать обычные объявления от администрации.
    -- Наказание обычно содержит игрока, срок или причину.
    local looks_like_punishment = MSHelper_LineHasAny(plain, {
        'игрока', 'Игрока', 'игроку', 'Игроку', 'Причина', 'причина',
        'дней', 'день', 'час', 'часов', 'минут', 'мин.', 'секунд',
        'на 5', 'на 10', 'на 15', 'на 30', 'на 60', 'на 120',
        'reason', 'player'
    }) or low:find('reason', 1, true) or low:find('player', 1, true)

    return looks_like_punishment
end

function sampev.onServerMessage(color, text)
    if text then
        local raw_text = tostring(text)
        local low_text = raw_text:lower()

        -- Ловим системную строку входящего звонка. Это нужно для лаунчера/кнопки P:
        -- даже если /p отправит не MS Helper, приветствие всё равно сработает после подтверждения сервера.
        if MSH_PHONE_IS_INCOMING_CALL and MSH_PHONE_IS_INCOMING_CALL(raw_text, low_text) then
            MSH_PHONE_CALL_UNTIL = os.clock() + 20
        end

        -- Телефонное приветствие срабатывает только после системного ответа сервера,
        -- что трубка действительно взята/звонок принят.
        if ((MSH_PHONE_GREET_WAIT_UNTIL or 0) > os.clock()) or ((MSH_PHONE_CALL_UNTIL or 0) > os.clock()) then
            if MSH_PHONE_GREET_IS_ACCEPTED(raw_text, low_text) then
                MSH_PHONE_GREET_SEND_ACCEPTED()
                MSH_PHONE_CALL_UNTIL = 0
            end
        else
            MSH_PHONE_GREET_WAIT_UNTIL = 0
        end

        -- Если сервер ответил антифлудом или отказом доступа на /invite, не продолжаем обычную цепочку.
        if (_G.MSHelper_InviteWatchUntil or 0) > os.clock() then
            local wait_hint = cp1251('подожд'):lower()
            local wait_hint2 = cp1251('следующим действием'):lower()
            if low_text:find(wait_hint, 1, true) or low_text:find(wait_hint2, 1, true) or low_text:find('wait', 1, true) then
                _G.MSHelper_InviteBlocked = true
            end
            if invite_no_access_message_matches(raw_text, low_text) then
                _G.MSHelper_InviteNoAccess = true
            end
        end

        if cfg.main.hide_smi_ads and is_smi_ad_message(raw_text) then
            return false
        end

        -- Фильтр рабочего чата /j и /jn убран: используйте серверную настройку.

        if MSHelper_IsAdminPunishmentMessage(raw_text) then
            return false
        end

        remember_med_call_from_message(raw_text)
        MSHelper_HandleProcedureServerRp(raw_text)
        if MSHelper_TrySendMedhelpGoodbye then MSHelper_TrySendMedhelpGoodbye(raw_text) end
        for pid, data in pairs(pending_invites) do
            if os.time() - (data.time or 0) > 180 then
                pending_invites[pid] = nil
            elseif invite_accept_message_matches(raw_text, low_text, data) then
                send_new_employee_radio(pid)
                break
            end
        end
    end

    if os.time() <= pending_bed_hint_until and text then
        local msg = tostring(text):lower()
        local p1 = cp1251('не лежит в больнице'):lower()
        local p2 = cp1251('займите койку'):lower()
        if msg:find(p1, 1, true) or msg:find(p2, 1, true) then
            if os.time() - last_bed_hint_time >= 3 then
                last_bed_hint_time = os.time()
                lua_thread.create(function()
                    wait(450)
                    chat('Пожалуйста, займите койку.')
                    wait(700)
                    chat('/n Подойдите к койке и нажмите на "Enter" или "Alt".')
                end)
            end
        end
    end
end


local action_rp
_G.MSHelper_ActionBusy = _G.MSHelper_ActionBusy or false
_G.MSHelper_BinderBusy = _G.MSHelper_BinderBusy or false
local send_binder_slot
local find_binder_slot_by_command
local send_ambulance_heal_sequence
local send_to_call_sequence

local function get_action_key_from_command(command)
    local cmd = tostring(command or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')

    if cmd == '/mask' then return 'mask' end
    -- Один RP-текст для всех типов транспорта: /lock, /lock 1 ... /lock 8.
    if cmd == '/lock' or cmd:match('^/lock%s+[1-8]%s*$') then return 'lock' end
    if cmd == '/healme' then return 'healme' end
    -- /c 60: короткая RP-отыгровка, затем системная команда точного времени.
    if cmd == '/c 60' or cmd == '/c 060' or cmd == '/c60' then return 'c60' end

    -- Команды ниже могут быть с аргументами: /find id, /changeskin id и т.д.
    if cmd == '/find' or cmd:match('^/find%s+') then return 'find' end
    if cmd == '/changeskin' or cmd:match('^/changeskin%s+') then return 'changeskin' end

    return nil
end

local function last_call_nick_for_id(pid)
    pid = tonumber(pid) or -1
    if pid == last_med_call_id and os.time() - (last_med_call_time or 0) <= 900 then
        return (last_med_call_nick ~= '' and last_med_call_nick or ('ID ' .. tostring(pid)))
    end

    local nick = safe_nick(pid)
    if nick and nick ~= '' then return nick:gsub('_', ' ') end
    return 'ID ' .. tostring(pid)
end

send_ambulance_heal_sequence = function(pid, amount)
    pid = tonumber(pid) or -1
    amount = tonumber(amount)

    if pid < 0 then
        helper_msg('Используйте: /heal id цена')
        return false
    end

    if not amount then
        -- Лечение в карете на Advance: единая цена 300$ для всех.
        amount = 300
    end

    if amount <= 0 then
        helper_msg('Цена лечения должна быть больше 0. Используйте: /heal id цена')
        return false
    end

    lua_thread.create(function()
        chat('/me внимательно осмотрев пациента, подготовил медикаменты в карете скорой помощи')
        wait(1100)
        chat('/do Медицинская сумка и необходимое оборудование находятся рядом.')
        wait(1100)
        chat('/todo Открыв медицинскую сумку*Сейчас я окажу вам помощь, стоимость: ' .. amount .. '$.')
        wait(1100)
        chat('/me оказал пациенту первую медицинскую помощь')
        wait(900)

        script_heal_guard = true
        sampSendChat('/heal ' .. pid .. ' ' .. amount)
        wait(250)
        script_heal_guard = false
        if MSHelper_ReportAdd then MSHelper_ReportAdd('heal_ambulance', 'Лечение в карете: ID ' .. tostring(pid) .. ', цена ' .. tostring(amount) .. '$') end

        if cfg.main.show_heal_debug then
            helper_msg('Карета: /heal ID ' .. pid .. ' цена ' .. amount .. '$')
        end
    end)

    return true
end

send_to_call_sequence = function(pid)
    pid = tonumber(pid) or -1
    if pid < 0 then
        helper_msg('Используйте: /to id игрока')
        return false
    end

    local nick = last_call_nick_for_id(pid)

    lua_thread.create(function()
        chat('/me достал рацию и открыл планшет вызовов скорой помощи')
        wait(900)
        sampSendChat(u8:decode('/do На экране отображается поступивший вызов от гражданина ') .. nick .. u8:decode('.'))
        wait(900)
        _G.MSHelper_SendCommandPrepared(u8:decode('/r Принял вызов гражданина ') .. nick .. u8:decode(', выезжаю.'))
        wait(900)

        script_to_guard = true
        sampSendChat('/to ' .. pid)
        wait(250)
        script_to_guard = false
    end)

    return true
end



function sampev.onSendCommand(command)
    local cmd = tostring(command or '')

    if _G.MSHelper_TagWrapGuard or _G.MSHelper_ChatWrapGuard then return end

    -- Если игрок не сотрудник МЗ, MS Helper не перехватывает команды и не добавляет RP/теги.
    -- Обычные серверные команды при этом продолжают работать.
    if MSHelper_IsSelfMedic and not MSHelper_IsSelfMedic() then return end

    -- Кастомный /find сотрудников: команду на сервер не блокируем,
    -- но помечаем следующее окно /find для перерисовки в окно MS Helper.
    if MSH_CUSTOM_FIND_ENABLED and MSH_CUSTOM_FIND_ENABLED[0] and cmd:match('^/find%s*$') then
        MSH_FIND_EXPECT_UNTIL = os.clock() + 6
    end

    -- Перехватываем /ok до отправки на сервер.
    -- На Advance у сервера тоже есть /ok, и пустой /ok может уходить как ID 0,
    -- если не заблокировать его именно в onSendCommand.
    local ok_arg = cmd:match('^/ok%s+(.+)$')
    if cmd:match('^/ok%s*$') or ok_arg then
        _G.MSHelper_SendOkReport(ok_arg or '')
        return false
    end

    local tagged_cmd = _G.MSHelper_ApplyRadioTag(cmd)
    if tagged_cmd ~= cmd then
        local wrapped_tagged_cmd = _G.MSHelper_BuildWrappedCommandLines(tagged_cmd)
        if wrapped_tagged_cmd and #wrapped_tagged_cmd > 1 then
            _G.MSHelper_SendWrappedLines(wrapped_tagged_cmd, 220)
        else
            _G.MSHelper_SendCommandPrepared(tagged_cmd)
        end
        return false
    end

    local wrapped_cmd = _G.MSHelper_BuildWrappedCommandLines(cmd)
    if wrapped_cmd and #wrapped_cmd > 1 then
        _G.MSHelper_SendWrappedLines(wrapped_cmd, 220)
        return false
    end

    -- Если команда была отправлена самим скриптом, пропускаем ее дальше на сервер.
    if script_action_guard or script_binder_guard or script_heal_guard or script_to_guard or script_invite_guard or script_uninvite_guard or script_rang_guard or script_drive_guard or script_givemed_guard then return end

    -- Телефон /p: сначала ждём системное подтверждение сервера, что трубка действительно взята.
    -- Если подтверждения нет, приветствие не отправляется.
    if MSH_PHONE_GREET_ENABLED and MSH_PHONE_GREET_ENABLED[0] and cmd:lower():match('^/p%s*$') then
        MSH_PHONE_GREET_WAIT_UNTIL = os.clock() + 5
    elseif cmd:lower():match('^/h%s*$') then
        MSH_PHONE_GREET_WAIT_UNTIL = 0
        MSH_PHONE_CALL_UNTIL = 0
    end

    -- Команды биндера: /b1, /b2 или своя команда из вкладки «Биндер».
    local binder_slot = find_binder_slot_by_command(cmd)
    if binder_slot then
        send_binder_slot(binder_slot)
        return false
    end

    -- Ручной ввод системных команд тоже идет через RP-отыгровку, затем отправляется исходная команда.
    local action_key = get_action_key_from_command(cmd)
    if action_key and action_rp then
        action_rp(action_key, cmd)
        return false
    end

    -- /heal id цена — лечение в карете скорой помощи через RP, затем системная команда /heal.
    local heal_id, heal_amount = cmd:match('^/heal%s+(%d+)%s+(%d+)%s*$')
    if heal_id and send_ambulance_heal_sequence then
        send_ambulance_heal_sequence(tonumber(heal_id), tonumber(heal_amount))
        return false
    end

    local heal_id_only = cmd:match('^/heal%s+(%d+)%s*$')
    if heal_id_only and send_ambulance_heal_sequence then
        send_ambulance_heal_sequence(tonumber(heal_id_only), nil)
        return false
    end

    if cmd:match('^/heal%s*$') and send_ambulance_heal_sequence then
        helper_msg('Используйте: /heal id цена')
        return false
    end

    -- /to id — принять последний/указанный вызов через RP и сообщить в рацию.
    local to_id = cmd:match('^/to%s+(%d+)%s*$')
    if to_id and send_to_call_sequence then
        send_to_call_sequence(tonumber(to_id))
        return false
    end

    -- /drive 1 — быстрый возврат транспорта без оповещения в /r.
    if cmd:match('^/drive%s+1%s*$') and not script_drive_guard then
        _G.MSHelper_SendDriveQuick()
        return false
    end

    -- /drive — предупреждение в рацию, затем стандартная команда возврата транспорта.
    if cmd:match('^/drive%s*$') and not script_drive_guard then
        send_drive_sequence()
        return false
    end
    -- /invite без ID открывает окно ввода ID
    if cmd:match('^/invite%s*$') and not script_invite_guard then
        invite_window[0] = true
        return false
    end

    -- /invite id тоже запускает RP-отыгровку
    local invite_full_id = cmd:match('^/invite%s+(%d+)%s*$')
    if invite_full_id and not script_invite_guard then
        send_invite_sequence(tonumber(invite_full_id))
        return false
    end

    -- /inv оставлен как короткий алиас: вся RP-отыгровка находится в /invite
    if cmd:match('^/inv%s*$') and not script_invite_guard then
        invite_window[0] = true
        return false
    end

    local invite_id = cmd:match('^/inv%s+(%d+)%s*$')
    if invite_id and not script_invite_guard then
        send_invite_sequence(tonumber(invite_id))
        return false
    end

    -- /uninvite без аргументов открывает окно ID + причина
    if cmd:match('^/uninvite%s*$') and not script_uninvite_guard then
        uninvite_window[0] = true
        return false
    end

    -- /uni без аргументов открывает окно ID + причина
    if cmd:match('^/uni%s*$') and not script_uninvite_guard then
        uninvite_window[0] = true
        return false
    end

    -- /uni id причина — короткая команда скрипта
    local uninvite_id, reason = cmd:match('^/uni%s+(%d+)%s+(.+)$')
    if uninvite_id and not script_uninvite_guard then
        send_uninvite_sequence(tonumber(uninvite_id), reason)
        return false
    end

    local uninvite_id_no_reason = cmd:match('^/uni%s+(%d+)%s*$')
    if uninvite_id_no_reason and not script_uninvite_guard then
        uninvite_player_id[0] = tonumber(uninvite_id_no_reason)
        ffi.copy(uninvite_reason_buffer, '')
        uninvite_window[0] = true
        helper_msg('Укажите причину увольнения в окне.')
        return false
    end

    -- /uninvite id причина — стандартная команда тоже идёт через RP + причину
    local real_uninvite_id, real_reason = cmd:match('^/uninvite%s+(%d+)%s+(.+)$')
    if real_uninvite_id and not script_uninvite_guard then
        send_uninvite_sequence(tonumber(real_uninvite_id), real_reason)
        return false
    end

    local real_uninvite_id_no_reason = cmd:match('^/uninvite%s+(%d+)%s*$')
    if real_uninvite_id_no_reason and not script_uninvite_guard then
        uninvite_player_id[0] = tonumber(real_uninvite_id_no_reason)
        ffi.copy(uninvite_reason_buffer, '')
        uninvite_window[0] = true
        helper_msg('Укажите причину увольнения в окне.')
        return false
    end


    -- /givemed id — выдача медицинской карты с RP-отыгровкой.
    local givemed_id = cmd:match('^/givemed%s+(%d+)%s*$')
    if givemed_id and not script_givemed_guard then
        send_givemed_sequence(tonumber(givemed_id))
        return false
    end

    if cmd:match('^/givemed%s*$') and not script_givemed_guard then
        helper_msg('Используйте: /givemed id')
        return false
    end

    -- /dis id — системное лечение болезней. Запоминаем, что сейчас должен открыться серверный диалог.
    -- Команду не блокируем, только потом ловим выбор пункта и отправляем RP.
    if cmd:match('^/dis%s+%d+%s*$') then
        dis_command_until = os.time() + 15
    end

    -- /analysis id — направление на анализы. Запоминаем, что сейчас должен открыться серверный диалог.
    -- Команду не блокируем, только потом ловим выбор пункта и отправляем RP.
    if cmd:match('^/analysis%s+%d+%s*$') then
        analysis_command_until = os.time() + 15
    end

    -- /rang без аргументов открывает окно ID + выбор + или -
    if cmd:match('^/rang%s*$') and not script_rang_guard then
        rang_window[0] = true
        return false
    end

    -- /rang id открывает окно с уже введенным ID
    local rang_id_no_sign = cmd:match('^/rang%s+(%d+)%s*$')
    if rang_id_no_sign and not script_rang_guard then
        rang_player_id[0] = tonumber(rang_id_no_sign)
        rang_window[0] = true
        helper_msg('Выберите действие ранга в окне: + или -.')
        return false
    end

    local rang_id, rang_sign = cmd:match('^/rang%s+(%d+)%s+([%+%-])%s*$')
    if rang_id and not script_rang_guard then
        send_rang_sequence(tonumber(rang_id), rang_sign)
        return false
    end
end


local DIALOG_MS_EDIT = 19002

local function open_ms_edit_dialog(mode, a, b, title, current)
    edit_dialog_mode = mode
    edit_dialog_a = a or 0
    edit_dialog_b = b or 0
    sampShowDialog(DIALOG_MS_EDIT, u8:decode(title), u8:decode(current or ''), u8:decode('Сохранить'), u8:decode('Отмена'), 1)
end

local function is_dis_dialog(title, text)
    local t = tostring(title or ''):lower()
    local body = tostring(text or ''):lower()

    -- На разных сборках текст диалога может приходить немного по-разному,
    -- поэтому проверяем и заголовок, и содержимое, и сами пункты болезней.
    if t:find(cp1251('лечение болезней'):lower(), 1, true) then return true end
    if body:find(cp1251('выберите процедуру'):lower(), 1, true) then return true end
    if body:find(cp1251('свечи'):lower(), 1, true) and body:find(cp1251('геморрой'):lower(), 1, true) then return true end
    if body:find(cp1251('массажи'):lower(), 1, true) and body:find(cp1251('грыжа'):lower(), 1, true) then return true end
    if body:find(cp1251('капельница'):lower(), 1, true) and body:find(cp1251('наркозависимость'):lower(), 1, true) then return true end
    if body:find(cp1251('приём антибиотиков'):lower(), 1, true) or body:find(cp1251('прием антибиотиков'):lower(), 1, true) then return true end
    if body:find(cp1251('ингаляция'):lower(), 1, true) and body:find(cp1251('ангина'):lower(), 1, true) then return true end

    -- Если перед этим была введена /dis id, считаем следующий похожий серверный список диалогом лечения.
    return os.time() <= dis_command_until and body:find(cp1251('лечение не выполняется'):lower(), 1, true) ~= nil
end

local function is_analysis_dialog(title, text)
    local t = tostring(title or ''):lower()
    local body = tostring(text or ''):lower()

    -- Диалог /analysis на разных сборках может иметь разный заголовок,
    -- поэтому проверяем и название, и сами пункты меню.
    if t:find(cp1251('анализ'):lower(), 1, true) then return true end
    if body:find(cp1251('сдача крови'):lower(), 1, true) then return true end
    if body:find(cp1251('сдача мочи'):lower(), 1, true) then return true end
    if body:find(cp1251('компьютерная томография'):lower(), 1, true) then return true end
    if body:find(cp1251('магнитно-резонансная томография'):lower(), 1, true) then return true end
    if body:find(cp1251('мрт'):lower(), 1, true) and body:find(cp1251('кт'):lower(), 1, true) then return true end

    -- Запасной режим: если только что была команда /analysis id,
    -- считаем ближайший серверный список с выбором пунктов диалогом анализов.
    return os.time() <= analysis_command_until and (
        body:find(cp1251('кров'):lower(), 1, true) ~= nil or
        body:find(cp1251('моч'):lower(), 1, true) ~= nil or
        body:find(cp1251('томограф'):lower(), 1, true) ~= nil
    )
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if MSHelper_AccessHandleDialog and MSHelper_AccessHandleDialog(dialogId, style, title, button1, button2, text) == false then
        return false
    end

    if MSHelper_HandleTimeDialog and MSHelper_HandleTimeDialog(dialogId, style, title, button1, button2, text) == false then
        return false
    end

    if MSH_CUSTOM_FIND_ENABLED and MSH_CUSTOM_FIND_ENABLED[0] and MSHelper_IsStaffFindDialog and MSHelper_IsStaffFindDialog(title, text) then
        if MSH_FIND_ALLOW_SYSTEM_ONCE == true then
            MSH_FIND_ALLOW_SYSTEM_ONCE = false
        else
            if MSHelper_FindOpenFromDialog and MSHelper_FindOpenFromDialog(title, text) then
                return false
            end
        end
    end

    if MSHelper_TryAutoSelectNoteDialog and MSHelper_TryAutoSelectNoteDialog(dialogId, title, text) == false then
        return false
    end

    if is_dis_dialog(title, text) then
        dis_dialog_id = dialogId
        dis_dialog_until = os.time() + 60
    end
    if is_analysis_dialog(title, text) then
        analysis_dialog_id = dialogId
        analysis_dialog_until = os.time() + 60
    end
end

function sampev.onSendDialogResponse(dialogId, button, listbox, input)
    -- RP для системного /dis id.
    -- Важно: на некоторых сборках Advance Blue событие onShowDialog может не успеть
    -- сохранить ID серверного окна, поэтому страхуемся через dis_command_until.
    local lb = tonumber(listbox) or -1
    local is_tracked_dis_dialog = (dialogId == dis_dialog_id and os.time() <= dis_dialog_until)
    local is_recent_dis_choice = (os.time() <= dis_command_until and lb >= 0 and lb <= 4)

    if button == 1 and (is_tracked_dis_dialog or is_recent_dis_choice) then
        -- После выбора процедуры закрываем мини-меню пациента.
        if patient_window then patient_window[0] = false end

        MSHelper_SendDisRpOnce(lb + 1)
        dis_dialog_id = -1
        dis_dialog_until = 0
        dis_command_until = 0
    end

    -- RP для системного /analysis id.
    -- Аналогично /dis: ловим выбор пункта и после серверного выбора отправляем нужную /me.
    local is_tracked_analysis_dialog = (dialogId == analysis_dialog_id and os.time() <= analysis_dialog_until)
    local is_recent_analysis_choice = (os.time() <= analysis_command_until and lb >= 0 and lb <= 3)

    if button == 1 and (is_tracked_analysis_dialog or is_recent_analysis_choice) then
        -- После выбора анализа закрываем мини-меню пациента.
        if patient_window then patient_window[0] = false end

        MSHelper_SendAnalysisRpOnce(lb + 1)
        analysis_dialog_id = -1
        analysis_dialog_until = 0
        analysis_command_until = 0
    end

    if dialogId == DIALOG_MS_EDIT then
        if button == 1 then
            local value = tostring(input or '')
            if edit_dialog_mode == 'gos' and edit_dialog_a >= 1 and edit_dialog_a <= 3 then
                ffi.copy(active_gos_lines()[edit_dialog_a], u8:encode(value), 255)
                save()
                helper_msg('Гос. строка '..edit_dialog_a..' обновлена.')
            elseif edit_dialog_mode == 'rpgos' and edit_dialog_a >= 1 and edit_dialog_a <= 4 and edit_dialog_b >= 1 and edit_dialog_b <= 3 then
                ffi.copy(rpgos_lines[edit_dialog_a][edit_dialog_b], u8:encode(value), 255)
                save()
                helper_msg('РП госка #'..edit_dialog_a..' строка '..edit_dialog_b..' обновлена.')
            elseif edit_dialog_mode == 'ruktext' then
                ffi.copy(ruk_radio_text, u8:encode(value), 127)
                save()
                helper_msg('Текст вызова в /r обновлен.')
            end
        end
        edit_dialog_mode = nil
        return false
    end
end

local function get_cooldown() local left = (cfg.gos.cooldown_until or 0) - os.time(); return left > 0 and left or 0 end

local function send_gnews(count, ignore_cooldown)
    if not ignore_cooldown and get_cooldown() > 0 then helper_msg('Подождите, КД гос. новостей еще активно.'); return end
    lua_thread.create(function()
        local lines = active_gos_lines()
        for i = 1, count do
            local text = u8:decode(ffi.string(lines[i]))
            if text and #text > 0 then sampSendChat('/gnews ' .. text) end
            wait(1250)
        end
        if not ignore_cooldown then
            cfg.gos.cooldown_until = os.time() + (count == 3 and 360 or 120)
            save()
        else
            helper_msg('Гос. новости отправлены в РП режиме без запуска КД.')
        end
    end)
end

local function send_gnews_single(ignore_cooldown)
    if not ignore_cooldown and get_cooldown() > 0 then helper_msg('Подождите, КД гос. новостей еще активно.'); return end
    lua_thread.create(function()
        local text = u8:decode(ffi.string(active_gos_single_line()))
        if text and #text > 0 then
            sampSendChat('/gnews ' .. text)
        else
            helper_msg('Отдельная 1 строка гос. новости пустая.')
            return
        end
        if not ignore_cooldown then
            cfg.gos.cooldown_until = os.time() + 120
            save()
        else
            helper_msg('Отдельная гос. новость отправлена без запуска КД.')
        end
    end)
end

local function send_rp_gnews_set(set, count)
    set = tonumber(set) or 1
    if set < 1 or set > 4 then set = 1 end
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    if count > 3 then count = 3 end
    lua_thread.create(function()
        for i = 1, count do
            local text = u8:decode(ffi.string(rpgos_lines[set][i]))
            if text and #text > 0 then sampSendChat('/gnews ' .. text) end
            wait(1250)
        end
        helper_msg('РП госка #' .. set .. ' отправлена без КД.')
    end)
end

-- Постоянные буферы для checkbox в /ms.
-- Важно: не создаём imgui.new.bool() каждый кадр внутри отрисовки,
-- потому что на некоторых сборках mimgui это приводит к крашу при открытии /ms.
local main_toggle_buffers = {}
for _, __ms_key in ipairs({'hide_smi_ads', 'female'}) do
    main_toggle_buffers[__ms_key] = imgui.new.bool(cfg.main and cfg.main[__ms_key] == true)
end

local function toggle(label, key)
    cfg.main = cfg.main or {}
    if cfg.main[key] == nil then cfg.main[key] = false end
    if not main_toggle_buffers[key] then
        main_toggle_buffers[key] = imgui.new.bool(cfg.main[key] == true)
    end
    local v = main_toggle_buffers[key]
    if v[0] ~= (cfg.main[key] == true) then v[0] = (cfg.main[key] == true) end
    if imgui.Checkbox(label, v) then
        cfg.main[key] = v[0]
        save()
    end
end

local function button_cmd(label, cmd)
    if imgui.Button(label, imgui.ImVec2(145, 28)) then chat(cmd) end
end

local function center_next_window(width, height)
    local display = imgui.GetIO().DisplaySize
    -- Размер фиксируем, но позицию ставим только при первом появлении окна.
    -- Поэтому Invite / Uninvite / Rang можно свободно двигать мышкой за верхнюю панель.
    imgui.SetNextWindowSize(imgui.ImVec2(width, height), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2((display.x - width) / 2, (display.y - height) / 2), imgui.Cond.Once)
end

local function reset_interview_ui_state()
    -- После собеседования полностью чистим состояние мини-окон.
    -- На некоторых сборках SAMP/mimgui повторное открытие /ms после закрытого окна
    -- могло крашить игру, если старое окно собеседования еще висело в состоянии ImGui.
    patient_window[0] = false
    interview_window[0] = false
    interview_action_busy = false
    interview_step = 1
    interview_player_nick = ''
    if interview_player_id then interview_player_id[0] = 0 end
end

local function request_main_menu_toggle()
    -- Не переключаем главное окно прямо из chat command.
    -- Делаем это в основном цикле после wait(0), чтобы не трогать mimgui из обработчика чата.
    pending_main_window_toggle = true
end

local online_text

local function action_is_female()
    return cfg and cfg.main and cfg.main.female == true
end

local action_c60_player_name, action_c60_time_text

local function action_split_lines(text)
    local lines = {}
    text = tostring(text or ''):gsub('\\n', '|'):gsub('\n', '|')
    for part in text:gmatch('([^|]+)') do
        part = trim(part)
        -- Строка '-' означает пропустить эту RP-строку.
        if part ~= '' and part ~= '-' then table.insert(lines, part) end
    end
    return lines
end

local function action_custom_lines(key, cmd)
    local rp = cfg.rptexts and cfg.rptexts[key] or ''
    if action_rp_buffers and action_rp_buffers[key] then
        rp = ffi.string(action_rp_buffers[key])
    end
    rp = trim(rp)
    if rp == '' then return nil end

    if key == 'c60' then
        -- Убираем ник из старых сохраненных шаблонов /c 60.
        rp = rp:gsub('%s*%(%s*{nick}%s*%)', '')
        rp = rp:gsub('{nick}', '')
        rp = rp:gsub('{time}', action_c60_time_text())
    end
    local lines = action_split_lines(rp)
    return lines
end

local function action_player_name_from_command(cmd)
    local id = tostring(cmd or ''):match('^/changeskin%s+(%d+)')
    id = tonumber(id)
    if not id then return nil, nil end
    local nick = safe_nick(id)
    if not nick or nick == '' then return id, nil end
    return id, nick:gsub('_', ' ')
end

action_c60_player_name = function()
    if type(sampGetPlayerIdByCharHandle) == 'function' and type(sampGetPlayerNickname) == 'function' then
        local ok, id = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
        id = tonumber(id) or -1
        if ok and id >= 0 then
            local ok_nick, nick = pcall(sampGetPlayerNickname, id)
            if ok_nick and nick and tostring(nick) ~= '' and tostring(nick) ~= 'nil' then
                return tostring(nick)
            end
        end
    end
    local manual = cfg and cfg.main and tostring(cfg.main.doctor_name or '') or ''
    manual = trim(manual)
    if manual ~= '' and manual:lower() ~= 'auto' then
        return manual:gsub(' ', '_')
    end
    return 'Врач'
end

action_c60_time_text = function()
    return os.date('%H ч. %M мин.')
end

local function action_default_lines(key, cmd)
    local female = action_is_female()

    if key == 'lock' then
        return { string.format("/me %s ключи от транспорта, после чего %s на кнопку 'open/close'.", female and 'достала' or 'достал', female and 'нажала' or 'нажал') }
    end

    if key == 'healme' then
        return { string.format('/me %s шприц с адреналином, %s колпачок, %s себе в ногу.', female and 'достала' or 'достал', female and 'сняла' or 'снял', female and 'вколола' or 'вколол') }
    end

    if key == 'find' then
        -- В MS Helper нет надежного определения военного статуса, поэтому используем нейтральный вариант "сотрудников".
        return { string.format('/me %s КПК из кармана и %s список сотрудников.', female and 'достала' or 'достал', female and 'открыла' or 'открыл') }
    end

    if key == 'mask' then
        return { string.format('/me %s медицинскую маску и аккуратно %s её на лицо.', female and 'достала' or 'достал', female and 'надела' or 'надел') }
    end

    if key == 'c60' then
        return {
            '/me движением руки закатал рукав затем посмотрел на часы.',
            '/do На часах: ' .. action_c60_time_text()
        }
    end

    if key == 'changeskin' then
        return {
            '/do В руках заранее подготовленный комплект с формой.',
            '/me передает пакет с формой сотруднику'
        }
    end

    return {}
end

local function action_preset_text(key)
    local female = action_is_female()

    if key == 'lock' then
        return string.format("/me %s ключи от транспорта, после чего %s на кнопку 'open/close'.", female and 'достала' or 'достал', female and 'нажала' or 'нажал')
    end
    if key == 'healme' then
        return string.format('/me %s шприц с адреналином, %s колпачок, %s себе в ногу.', female and 'достала' or 'достал', female and 'сняла' or 'снял', female and 'вколола' or 'вколол')
    end
    if key == 'find' then
        return string.format('/me %s КПК из кармана и %s список сотрудников.', female and 'достала' or 'достал', female and 'открыла' or 'открыл')
    end
    if key == 'mask' then
        return string.format('/me %s медицинскую маску и аккуратно %s её на лицо.', female and 'достала' or 'достал', female and 'надела' or 'надел')
    end
    if key == 'c60' then
        return '/me движением руки закатал рукав затем посмотрел на часы. | /do На часах: {time}'
    end
    if key == 'changeskin' then
        return '/do В руках заранее подготовленный комплект с формой. | /me передает пакет с формой сотруднику'
    end
    return ''
end

local function action_send_rp_lines(lines, delay_ms)
    delay_ms = tonumber(delay_ms) or 550
    for _, line in ipairs(lines or {}) do
        line = trim(line)
        if line ~= '' then
            chat(line)
            wait(delay_ms)
        end
    end
end

local function action_lines_for(key, cmd)
    local custom = action_custom_lines(key, cmd)
    if custom and #custom > 0 then return custom end
    return action_default_lines(key, cmd)
end

action_rp = function(key, cmd)
    if _G.MSHelper_ActionBusy then
        helper_msg('Подождите, предыдущая кнопка еще выполняется.')
        return
    end

    cmd = tostring(cmd or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if cmd == '' then return end

    if key == 'changeskin' then
        local id = tonumber(cmd:match('^/changeskin%s+(%d+)'))
        if not id then
            helper_msg('Используйте: /changeskin id')
            return
        end
        if not ms_safe_player_connected(id) then
            helper_msg('Игрок с данным ID не подключен к серверу.')
            return
        end
    end

    _G.MSHelper_ActionBusy = true
    lua_thread.create(function()
        local rp_enabled = action_enabled[key] and action_enabled[key][0]
        local lines = rp_enabled and action_lines_for(key, cmd) or {}

        if key == 'c60' then
            action_send_rp_lines(lines, 650)
            script_action_guard = true
            sampSendChat(cmd)
            wait(350)
            script_action_guard = false
        elseif key == 'lock' then
            action_send_rp_lines(lines, 222)
            script_action_guard = true
            sampSendChat(cmd)
            wait(350)
            script_action_guard = false
        elseif key == 'changeskin' then
            if lines[1] then action_send_rp_lines({lines[1]}, 777) end
            if lines[2] then action_send_rp_lines({lines[2]}, 444) end
            for i = 3, #lines do action_send_rp_lines({lines[i]}, 444) end
            script_action_guard = true
            sampSendChat(cmd)
            wait(350)
            script_action_guard = false
        else
            script_action_guard = true
            sampSendChat(cmd)
            wait(300)
            script_action_guard = false
            action_send_rp_lines(lines, 444)
        end

        _G.MSHelper_ActionBusy = false
    end)
end

local function draw_action_button(label, key, cmd)
    if imgui.Button(label, imgui.ImVec2(145, 28)) then
        selected_action_edit = key
        action_rp(key, cmd)
    end
    imgui.SameLine()
    if action_enabled[key] then
        if imgui.Checkbox('##act_'..key, action_enabled[key]) then save() end
    else
        imgui.TextDisabled('нет RP')
    end
end

local function draw_action_rp_editor()
    if not selected_action_edit or not action_rp_buffers[selected_action_edit] then
        selected_action_edit = 'mask'
    end

    imgui.Separator()
    imgui.TextColored(MSHelper_AccentColor(), 'Настройка RP для команды')
    imgui.Text('Выбрана команда: ' .. (action_labels[selected_action_edit] or selected_action_edit))

    imgui.PushItemWidth(-1)
    if imgui.InputText('RP текст##action_rp_text', action_rp_buffers[selected_action_edit], 256) then
        cfg.rptexts[selected_action_edit] = ffi.string(action_rp_buffers[selected_action_edit])
        save()
    end
    imgui.PopItemWidth()

    if imgui.Button('Сохранить RP', imgui.ImVec2(130, 28)) then
        cfg.rptexts[selected_action_edit] = ffi.string(action_rp_buffers[selected_action_edit])
        save()
        helper_msg('RP для '..(action_labels[selected_action_edit] or selected_action_edit)..' сохранено.')
    end
    imgui.SameLine()
    if imgui.Button('Подставить RP', imgui.ImVec2(170, 28)) then
        local preset = action_preset_text(selected_action_edit)
        ffi.copy(action_rp_buffers[selected_action_edit], preset, 255)
        cfg.rptexts[selected_action_edit] = ffi.string(action_rp_buffers[selected_action_edit])
        save()
        helper_msg('Для '..(action_labels[selected_action_edit] or selected_action_edit)..' подставлен RP-шаблон.')
    end
end

local function send_where_radio(id)
    id = tonumber(id) or -1
    if id < 0 or not ms_safe_player_connected(id) then helper_msg('Укажите ID сотрудника.'); return end
    local nick = (safe_nick(id) or ('ID '..id)):gsub('_', ' ')
    local text = ffi.string(ruk_radio_text)
    lua_thread.create(function()
        -- /mwhere теперь сразу пишет вызов сотруднику в /r.
        _G.MSHelper_SendCommandPrepared('/r ' .. nick .. ', ' .. u8:decode(text))
    end)
end

online_text = function()
    local online = os.time() - script_started_at
    local afk = math.max(0, os.time() - last_activity_at)
    local base = string.format('Онлайн скрипта: %02d:%02d:%02d | AFK примерно: %02d:%02d', math.floor(online/3600), math.floor((online%3600)/60), online%60, math.floor(afk/60), afk%60)
    if MSHelper_TimeStatsText then
        return base .. ' | ' .. MSHelper_TimeStatsText(true)
    end
    return base
end

-- Делаем функцию доступной для блока обновления /c 60, который объявлен выше.
-- Без этого Lua ищет global online_text и получает nil.
_G.online_text = online_text

local function split_lines(text)
    local lines = {}
    text = text or ''
    text = text:gsub('\\n', '|')
    for part in string.gmatch(text, '([^|]+)') do
        part = part:gsub('^%s+', ''):gsub('%s+$', '')
        -- Знак '-' можно поставить вместо строки, чтобы она не отправлялась.
        if #part > 0 and part ~= '-' then
            table.insert(lines, part)
        end
    end
    return lines
end

send_binder_slot = function(slot)
    slot = tonumber(slot) or 0
    if not binder[slot] then return end
    if _G.MSHelper_BinderBusy then
        helper_msg('Подождите, предыдущий бинд ещё выполняется.')
        return
    end

    local text = ffi.string(binder[slot])
    if text == nil or trim(text) == '' then
        helper_msg('Слот №' .. slot .. ' пустой.')
        return
    end

    local delay = binder_delay[slot] and binder_delay[slot][0] or 1000
    if delay < 0 then delay = 0 end

    lua_thread.create(function()
        _G.MSHelper_BinderBusy = true
        for _, line in ipairs(split_lines(text)) do
            script_binder_guard = true
            sampSendChat(u8:decode(line))
            wait(120)
            script_binder_guard = false
            wait(delay)
        end
        _G.MSHelper_BinderBusy = false
    end)
end

find_binder_slot_by_command = function(command)
    local cmd = tostring(command or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    local name = cmd:match('^/(%S+)')
    if not name then return nil end
    name = normalize_binder_command(name, 1):lower()

    for i = 1, 22 do
        local saved = normalize_binder_command(ffi.string(binder_command[i]), i):lower()
        if saved == name then
            return i
        end
    end

    return nil
end

local function samp_text_input_active()
    -- ВАЖНО: не используем pcall/анонимные функции в игровом цикле.
    -- На некоторых сборках MoonLoader это может давать ошибку
    -- "cannot resume non-suspended coroutine" и убивать скрипт.
    if type(sampIsChatInputActive) == 'function' and sampIsChatInputActive() then
        return true
    end

    if type(sampIsDialogActive) == 'function' and sampIsDialogActive() then
        return true
    end

    if type(isSampfuncsConsoleActive) == 'function' and isSampfuncsConsoleActive() then
        return true
    end

    return false
end

local function process_binder_hotkeys()
    for i = 1, 22 do
        local vk = binder_key[i] and tonumber(binder_key[i][0]) or 0
        if vk > 0 and not is_forbidden_binder_key(vk) and wasKeyPressed and wasKeyPressed(vk) then
            send_binder_slot(i)
            return true
        end
    end

    return false
end

function MSHelper_CleanRpName(name)
    name = tostring(name or '')
    name = name:gsub('%[%d+%]', '')
    name = name:gsub('_', ' ')
    name = trim(name)
    if name == '' then return 'Врач' end
    return name
end

local function local_rp_name()
    -- Если имя прописано вручную через /msname Имя Фамилия или в ms_helper.ini, используем его.
    -- По умолчанию doctor_name пустой, поэтому у каждого игрока скрипт пробует взять именно его ник.
    local manual = trim(tostring(cfg.main and cfg.main.doctor_name or ''))
    if manual ~= '' and manual:lower() ~= 'auto' then
        return MSHelper_CleanRpName(manual)
    end

    -- Автоник: берем ID своего персонажа и ник из SAMP.
    -- На некоторых сборках sampIsPlayerConnected(id) для своего ID может вернуть false,
    -- хотя sampGetPlayerNickname(id) уже отдаёт правильный ник. Поэтому проверку connected здесь не используем.
    -- ID 0 специально не берём в авто-режиме: на твоей сборке он уже ошибочно подтягивал чужой ник.
    if type(sampGetPlayerIdByCharHandle) == 'function' and type(sampGetPlayerNickname) == 'function' then
        local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        id = tonumber(id) or -1

        if id > 0 then
            local nick = sampGetPlayerNickname(id)
            if nick and tostring(nick) ~= '' and tostring(nick) ~= 'nil' then
                return MSHelper_CleanRpName(nick)
            end
        end
    end

    -- Если сборка вообще не отдала ник, не подставляем чужой ник и не Makar Maslow.
    -- Игрок может прописать свое имя командой /msname Имя Фамилия.
    return 'Врач'
end

local function local_player_id()
    if type(sampGetPlayerIdByCharHandle) == 'function' then
        local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        id = tonumber(id) or -1
        if id >= 0 then return id end
    end
    return -1
end

local function local_player_nick_raw()
    local id = local_player_id and local_player_id() or -1
    if id >= 0 and type(sampGetPlayerNickname) == 'function' then
        local ok, nick = pcall(sampGetPlayerNickname, id)
        if ok and nick and tostring(nick) ~= '' and tostring(nick) ~= 'nil' then
            return tostring(nick)
        end
    end
    return ''
end

function MSHelper_TrySendMedhelpGoodbye(raw_text)
    if (MSH_MEDHELP_GOODBYE_UNTIL or 0) < os.clock() then return false end
    raw_text = tostring(raw_text or '')
    local low = raw_text:lower()
    local p_course = cp1251 and cp1251('курс лечения'):lower() or 'курс лечения'
    local p_done1 = cp1251 and cp1251('провёл'):lower() or 'провёл'
    local p_done2 = cp1251 and cp1251('провел'):lower() or 'провел'
    if not low:find(p_course, 1, true) then return false end
    if not (low:find(p_done1, 1, true) or low:find(p_done2, 1, true)) then return false end

    local nick = tostring(MSH_MEDHELP_GOODBYE_NICK or '')
    if nick ~= '' and raw_text:find(nick, 1, true) == nil then
        return false
    end

    MSH_MEDHELP_GOODBYE_UNTIL = 0
    MSH_MEDHELP_GOODBYE_NICK = nil
    lua_thread.create(function()
        wait(550)
        chat('Всего доброго, не болейте.')
    end)
    return true
end

local function target_player_id()
    local result, ped = getCharPlayerIsTargeting(PLAYER_HANDLE)
    if result and ped ~= 0 then
        local ok, id = sampGetPlayerIdByCharHandle(ped)
        if ok then return id end
    end
    return -1
end

local function send_treatment(pid, illness_index)
    if pid == nil or pid < 0 then helper_msg('Наведитесь на пациента и нажмите ПКМ+G.'); return end

    -- Сразу скрываем меню после выбора лечения.
    -- RP-сценарий и /medhelp продолжат выполняться в отдельном потоке ниже.
    if patient_window then patient_window[0] = false end

    local data = illnesses[illness_index] or illnesses[1]
    local med = data[2]
    local cost, org, why = get_patient_price(pid)
    lua_thread.create(function()
        chat('/me внимательно осмотрев пациента, поставил диагноз.')
        wait(1100)
        chat('/do У ' .. local_rp_name() .. ' через плечо надета мед.сумка с лекарствами.')
        wait(1100)
        chat('/todo Открыв сумку*Вам будет выписан ' .. med .. ', его цена: ' .. cost .. '$.')
        wait(1100)
        chat('/me достал лекарство и передал человеку напротив.')
        wait(900)
        pending_bed_hint_until = os.time() + 8
        MSH_MEDHELP_GOODBYE_UNTIL = os.clock() + 12
        MSH_MEDHELP_GOODBYE_NICK = local_player_nick_raw and local_player_nick_raw() or ''
        sampSendChat('/medhelp ' .. pid .. ' ' .. cost)
        if MSHelper_ReportAdd then MSHelper_ReportAdd('heal_hospital', 'Лечение в больнице: ID ' .. tostring(pid) .. ', цена ' .. tostring(cost) .. '$') end
        if cfg.main.show_heal_debug then
            -- Скрыто: техническая отладка лечения больше не выводится игроку.
        end
        patient_window[0] = false
    end)
end



local function safe_player_connected(pid)
    return ms_safe_player_connected(pid)
end

local function start_interview(pid)
    pid = tonumber(pid) or -1
    if pid < 0 or not safe_player_connected(pid) then
        helper_msg('Наведитесь на игрока и нажмите ПКМ+G, затем выберите "Собеседование".')
        return false
    end

    interview_player_id[0] = pid
    interview_step = 1
    interview_action_busy = false

    local nick = safe_nick(pid)
    interview_player_nick = nick and nick:gsub('_', ' ') or ('ID ' .. tostring(pid))

    -- Закрываем меню пациента, чтобы не держать два окна и не дергать SAMP-функции каждый кадр.
    patient_window[0] = false
    interview_window[0] = true
    return true
end

local function interview_target_valid()
    local pid = tonumber(interview_player_id[0]) or -1
    if pid < 0 or not safe_player_connected(pid) then
        helper_msg('Кандидат не найден или вышел с сервера.')
        interview_action_busy = false
        return false
    end
    return true
end

local function send_interview_invite(pid)
    pid = tonumber(pid) or -1
    if pid < 0 or not safe_player_connected(pid) then
        helper_msg('Кандидат не найден или вышел с сервера.')
        return false
    end

    if _G.MSHelper_InviteBusy then
        helper_msg('Подождите, приглашение уже выполняется.')
        return false
    end

    -- В собеседовании выполняем /invite в этой же корутине, без вложенного lua_thread.
    -- Дополнительно оборачиваем в pcall, чтобы ошибка в /invite не роняла весь скрипт.
    local nick = interview_player_nick ~= '' and interview_player_nick or nick_or_id(pid)
    -- Не используем pcall вокруг функции с wait(), чтобы не ловить нестабильность в MoonLoader/SA-MP.
    local ok = run_invite_sequence_inline(pid, nick, { interview_no_invite_fallback = true })
    script_invite_guard = false
    _G.MSHelper_InviteBusy = false
    return ok == true
end

local function send_interview_step(step)
    if interview_action_busy then
        helper_msg('Подождите, предыдущее действие собеседования еще выполняется.')
        return
    end
    if not interview_target_valid() then return end

    local pid = tonumber(interview_player_id[0]) or -1
    interview_action_busy = true

    lua_thread.create(function()
        if step == 1 then
            chat('Здравствуйте, вы на собеседование?')
            interview_step = 2
            wait(350)
        elseif step == 2 then
            chat('Представьтесь и сколько вам лет?')
            interview_step = 3
            wait(350)
        elseif step == 3 then
            chat('Опыт в Министерстве Здравоохранения имеется?')
            interview_step = 4
            wait(350)
        elseif step == 4 then
            local my_id = local_player_id()
            chat('Хорошо, предоставьте мне документы, а именно: паспорт, лицензии, мед.карту и личное дело.')
            wait(850)
            if my_id >= 0 then
                chat('/n Передайте документы командами: /pass ' .. my_id .. ', /lic ' .. my_id .. ', /med ' .. my_id .. ', /show ' .. my_id .. '.')
            else
                chat('/n Передайте документы командами: /pass мой ID, /lic мой ID, /med мой ID, /show мой ID.')
            end
            interview_step = 5
            wait(350)
        elseif step == 5 then
            chat('Хорошо, поздравляю, вы нам подходите.')
            wait(900)
            if interview_target_valid() then
                send_interview_invite(pid)
                interview_step = 6
                reset_interview_ui_state()
            end
        end

        interview_action_busy = false
    end)
end

local function draw_binder_tab()
    imgui.TextColored(MSHelper_AccentColor(), 'Биндер')
    imgui.TextWrapped('Здесь можно создать свои текстовые бинды. Каждый слот запускается командой, например /b1, или назначенной клавишей.')
    imgui.TextWrapped('Для нескольких строк используйте символ | или \\n. Скрипт отправит строки по очереди с указанной задержкой.')
    imgui.Separator()

    imgui.BeginChild('binder_slots_list', imgui.ImVec2(160, 0), true)
    for i = 1, 22 do
        local preview = ffi.string(binder[i] or '')
        if #preview > 18 then preview = preview:sub(1, 18) .. '...' end
        local label = string.format('%02d  %s', i, binder_command_label(i))
        if binder_key[i] and binder_key[i][0] ~= 0 then
            label = label .. ' [' .. vk_name(binder_key[i][0]) .. ']'
        end
        if preview ~= '' then label = label .. '  *' end

        if imgui.Selectable(label .. '##binder_slot_' .. i, selected_binder_slot == i, 0, imgui.ImVec2(135, 26)) then
            selected_binder_slot = i
        end
    end
    imgui.EndChild()

    imgui.SameLine()
    imgui.BeginChild('binder_slot_editor', imgui.ImVec2(0, 0), false)

    local slot = selected_binder_slot
    if slot < 1 or slot > 22 then slot = 1; selected_binder_slot = 1 end

    imgui.TextColored(MSHelper_AccentColor(), 'Слот №' .. slot)
    imgui.Text('Команда запуска: ' .. binder_command_label(slot))

    imgui.PushItemWidth(180)
    if imgui.InputText('Команда без /##binder_command', binder_command[slot], 32) then
        local normalized_cmd = normalize_binder_command(ffi.string(binder_command[slot]), slot)
        ffi.copy(binder_command[slot], normalized_cmd, 31)
        save()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Сбросить команду##binder_reset_command', imgui.ImVec2(160, 28)) then
        local default_cmd = 'b' .. tostring(slot)
        ffi.copy(binder_command[slot], default_cmd, 31)
        save()
    end

    imgui.Text('Клавиша: ' .. vk_name(binder_key[slot][0]))

    imgui.SameLine()
    if imgui.Button('Назначить клавишу##binder_set_key', imgui.ImVec2(160, 28)) then
        binder_wait_key_slot = slot
        helper_msg('Нажмите нужную клавишу для слота №' .. slot .. '.')
    end

    imgui.SameLine()
    if imgui.Button('Убрать клавишу##binder_clear_key', imgui.ImVec2(140, 28)) then
        binder_key[slot][0] = 0
        if binder_wait_key_slot == slot then binder_wait_key_slot = 0 end
        save()
    end

    if binder_wait_key_slot == slot then
        imgui.TextColored(MSHelper_AccentColor(), 'Ожидание клавиши... ESC отменяет.')
        local pressed_vk = get_pressed_binder_key()
        if pressed_vk then
            if pressed_vk == 0x1B then
                binder_wait_key_slot = 0
                helper_msg('Назначение клавиши отменено.')
            elseif is_forbidden_binder_key(pressed_vk) then
                helper_msg('Эта клавиша запрещена для биндера. Используйте F2-F12, Num-клавиши или обычные буквы/цифры.')
                binder_wait_key_slot = 0
            else
                binder_key[slot][0] = pressed_vk
                binder_wait_key_slot = 0
                save()
                helper_msg('Слот №' .. slot .. ' назначен на клавишу ' .. vk_name(pressed_vk) .. '.')
            end
        end
    end

    imgui.PushItemWidth(140)
    if imgui.InputInt('Задержка между строками, мс##binder_delay', binder_delay[slot], 0, 0) then
        if binder_delay[slot][0] < 0 then binder_delay[slot][0] = 0 end
        save()
    end
    imgui.PopItemWidth()

    imgui.Separator()
    imgui.Text('Текст слота:')
    local binder_text_changed = false
    if imgui.InputTextMultiline then
        binder_text_changed = imgui.InputTextMultiline('##binder_text', binder[slot], 512, imgui.ImVec2(-1, 150))
    else
        imgui.PushItemWidth(-1)
        binder_text_changed = imgui.InputText('##binder_text', binder[slot], 512)
        imgui.PopItemWidth()
    end
    if binder_text_changed then
        save()
    end

    if imgui.Button('Отправить слот сейчас##binder_send', imgui.ImVec2(190, 32)) then
        send_binder_slot(slot)
    end
    imgui.SameLine()
    if imgui.Button('Очистить текст##binder_clear_text', imgui.ImVec2(145, 32)) then
        ffi.copy(binder[slot], '')
        save()
    end
    imgui.SameLine()
    if imgui.Button('Сохранить##binder_save', imgui.ImVec2(120, 32)) then
        save()
        helper_msg('Биндер слот №' .. slot .. ' сохранен.')
    end

    imgui.Separator()
    imgui.TextWrapped('Формат: строки разделяются символом |, знак - пропускает строку. Пример: /me достал аптечку|/do Аптечка в руках.|Здравствуйте.')
    imgui.TextWrapped('Запуск: команда ' .. binder_command_label(slot) .. ' или выбранная клавиша, если она назначена.')

    imgui.EndChild()
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    MSHelper_ApplyTheme()
end)

local function draw_prices()
    imgui.TextColored(MSHelper_AccentColor(), 'Ценовая политика')

    local rows = {
        {'В карете', 'ambulance'}, {'Гражданский', 'civil'}, {'Банды', 'gangs'}, {'Yakuza', 'yakuza'},
        {'СМИ', 'smi'}, {'МО', 'mo'}, {'ЛКН', 'lkn'},
        {'Право', 'pravo'}, {'МЗ', 'mz'}, {'РМ', 'rm'},
        {'МВД', 'mvd'}
    }

    for i, r in ipairs(rows) do
        local label, key = r[1], r[2]
        imgui.PushItemWidth(90)
        if imgui.InputInt(label..'##price_'..key, price[key], 0, 0) then
            if price[key][0] < 0 then price[key][0] = 0 end
            save()
        end
        imgui.PopItemWidth()
        if i % 3 ~= 0 then imgui.SameLine(220 * (i % 3)) end
    end


end


-- Интегрированный мониторинг склада медикаментов.
-- Логика перенесена из отдельного MonitorSclada, но меню сделано в стиле MS Helper.
MS_Sklad = MS_Sklad or {
    -- Авто-режим: включается сам, когда видит 3D-текст склада на втором этаже,
    -- и выключается, когда игрок выходит из зоны прорисовки склада.
    enabled = false,
    auto = true,
    inZone = false,
    current = 0,
    max = 50000,
    oneBox = 200,
    lastUpdate = 0,
    lastSeen = 0,
    timeout = 15000,
    lostTimeout = 4500,
    scanInterval = 1000,
    nextScan = 0,
    workerStarted = false,
    lastError = ''
}
MS_Sklad.auto = true
if MS_Sklad.lostTimeout == nil then MS_Sklad.lostTimeout = 4500 end
if MS_Sklad.scanInterval == nil or MS_Sklad.scanInterval < 700 then MS_Sklad.scanInterval = 1000 end
if MS_Sklad.inZone == nil then MS_Sklad.inZone = false end
if MS_Sklad.lastSeen == nil then MS_Sklad.lastSeen = 0 end
if MS_Sklad.workerStarted == nil then MS_Sklad.workerStarted = false end

function MS_SkladNow()
    -- SAFE: не используем getGameTimer/os.clock в основном цикле.
    -- На некоторых сборках MoonLoader вызов игровых таймеров внутри обработки склада
    -- давал ошибку "cannot resume non-suspended coroutine".
    return os.time() * 1000
end

function MS_SkladFormat(num)
    local str = tostring(tonumber(num) or 0)
    while true do
        local newStr, k = str:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        str = newStr
        if k == 0 then break end
    end
    return str
end

function MS_SkladResetOldData()
    local now = MS_SkladNow()

    if (MS_Sklad.lastSeen or 0) > 0 and now - (MS_Sklad.lastSeen or 0) > (MS_Sklad.lostTimeout or 4500) then
        MS_Sklad.enabled = false
        MS_Sklad.inZone = false
        MS_Sklad.current = 0
        MS_Sklad.max = 50000
        MS_Sklad.lastUpdate = 0
        return
    end

    if MS_Sklad.lastUpdate and MS_Sklad.lastUpdate > 0 then
        if now - MS_Sklad.lastUpdate > MS_Sklad.timeout then
            MS_Sklad.current = 0
            MS_Sklad.max = 50000
            MS_Sklad.lastUpdate = 0
            MS_Sklad.enabled = false
            MS_Sklad.inZone = false
        end
    end
end

function MS_SkladFindCurrent()
    if type(sampIs3dTextDefined) ~= 'function' or type(sampGet3dTextInfoById) ~= 'function' then
        return false
    end

    for id = 0, 2048 do
        local okDefined, defined = pcall(sampIs3dTextDefined, id)
        if okDefined and defined then
            local okInfo, text = pcall(sampGet3dTextInfoById, id)
            if okInfo and text then
                text = tostring(text):gsub('{%x%x%x%x%x%x}', '')

                -- Поддержка обоих вариантов: 49004 / 50000 и 49.004 / 50.000.
                local amount, maxValue = text:match('([%d%.]+)%s*/%s*([%d%.]+)')
                if amount and maxValue then
                    amount = tostring(amount):gsub('%.', '')
                    maxValue = tostring(maxValue):gsub('%.', '')
                    local a = tonumber(amount)
                    local m = tonumber(maxValue)

                    if a and m and m >= a and m == 50000 then
                        return true, a, m
                    end
                end
            end
        end
    end

    return false
end

function MS_SkladApplyScanResult(found, current, maxValue)
    local now = MS_SkladNow()

    if found then
        MS_Sklad.enabled = true
        MS_Sklad.inZone = true
        MS_Sklad.current = current or 0
        MS_Sklad.max = maxValue or 50000
        MS_Sklad.lastUpdate = now
        MS_Sklad.lastSeen = now
        return true
    end

    -- Если 3D-текст склада пропал, значит игрок ушёл со второго этажа/из зоны прорисовки.
    if (MS_Sklad.lastSeen or 0) > 0 and now - (MS_Sklad.lastSeen or 0) > (MS_Sklad.lostTimeout or 4500) then
        MS_Sklad.enabled = false
        MS_Sklad.inZone = false
        MS_Sklad.current = 0
        MS_Sklad.max = 50000
        MS_Sklad.lastUpdate = 0
    end

    return false
end

function MS_SkladScan()
    local found, current, maxValue = MS_SkladFindCurrent()
    return MS_SkladApplyScanResult(found, current, maxValue)
end

function MS_SkladProcess()
    if not MS_Sklad.auto then return end
    if MS_Sklad._busy then return end

    local now = MS_SkladNow()
    if now < (MS_Sklad.nextScan or 0) then return end
    MS_Sklad.nextScan = now + (MS_Sklad.scanInterval or 1000)

    MS_Sklad._busy = true
    local ok, err = pcall(function()
        MS_SkladScan()
        MS_SkladResetOldData()
    end)
    MS_Sklad._busy = false

    if not ok then
        MS_Sklad.enabled = false
        MS_Sklad.inZone = false
        MS_Sklad.lastUpdate = 0
        MS_Sklad.lastError = tostring(err or '')
        MS_Sklad.nextScan = MS_SkladNow() + 3000
    end
end

function MS_SkladStartAutoWorker()
    if MS_Sklad.workerStarted then return end
    MS_Sklad.workerStarted = true

    lua_thread.create(function()
        wait(1500)
        while true do
            local ok, err = pcall(MS_SkladProcess)
            if not ok then
                MS_Sklad.enabled = false
                MS_Sklad.inZone = false
                MS_Sklad.lastUpdate = 0
                MS_Sklad.lastError = tostring(err or '')
                wait(3000)
            else
                wait(MS_Sklad.scanInterval or 1000)
            end
        end
    end)
end

function MS_SkladIsAvailable()
    if not MS_Sklad.enabled then return false end
    if (MS_Sklad.current or 0) <= 0 or (MS_Sklad.lastUpdate or 0) <= 0 then return false end
    if MS_SkladNow() - MS_Sklad.lastUpdate > (MS_Sklad.timeout or 15000) then return false end
    return true
end

function MS_SkladNeed()
    local need = (MS_Sklad.max or 50000) - (MS_Sklad.current or 0)
    if need < 0 then need = 0 end
    return need
end

function MS_SkladBoxes()
    local need = MS_SkladNeed()
    if need < (MS_Sklad.oneBox or 200) then return 0 end
    return math.floor(need / (MS_Sklad.oneBox or 200))
end

function MS_SkladShowInfo()
    if not MS_SkladIsAvailable() then
        helper_msg('Склад: проверить склад нельзя. Подойдите на второй этаж.')
        return
    end

    helper_msg('Склад: сейчас ' .. MS_SkladFormat(MS_Sklad.current) .. '/' .. MS_SkladFormat(MS_Sklad.max) .. '.')
    helper_msg('Склад: не хватает ' .. MS_SkladFormat(MS_SkladNeed()) .. '. Нужно ящиков: ' .. tostring(MS_SkladBoxes()) .. '.')
end

function MS_SkladSendRadio()
    if not MS_SkladIsAvailable() then
        helper_msg('Склад: проверить склад нельзя. Подойдите на второй этаж.')
        return
    end

    local boxes = MS_SkladBoxes()
    if boxes <= 0 then
        helper_msg('Склад: нужно ящиков: 0. В рацию не отправляю.')
        return
    end

    sampSendChat(u8:decode(string.format(
        '/rn На складе находится %s/%s. Не хватает %s.',
        MS_SkladFormat(MS_Sklad.current),
        MS_SkladFormat(MS_Sklad.max),
        MS_SkladFormat(MS_SkladNeed())
    )))

    lua_thread.create(function()
        wait(700)
        sampSendChat(u8:decode(string.format('/rn Необходимо привезти %d ящиков медикаментов.', boxes)))
    end)
end

function MS_SkladOpenTab()
    active_tab = 5
    main_window[0] = true
end

function MS_DrawSkladTab()
    imgui.TextColored(MSHelper_AccentColor(), 'Мониторинг склада')
    imgui.TextWrapped('Скрипт считывает 3D-текст склада формата 49970 / 50000. Чтобы данные появились, подойдите к складу на второй этаж.')
    imgui.Separator()

    imgui.TextWrapped('Авто-режим включен: скрипт сам включает мониторинг, когда видит 3D-текст склада, и сам выключает его, когда вы уходите.')
    if MS_Sklad.enabled then
        imgui.TextColored(imgui.ImVec4(0.25,0.95,0.45,1), 'Мониторинг: включен автоматически, вы рядом со складом')
    else
        imgui.TextColored(imgui.ImVec4(0.95,0.35,0.35,1), 'Мониторинг: ожидает склад на втором этаже')
    end

    imgui.Spacing()
    local available = MS_SkladIsAvailable()
    if available then
        imgui.TextColored(imgui.ImVec4(0.25,0.95,0.45,1), 'Статус: данные склада найдены')
    else
        imgui.TextColored(imgui.ImVec4(0.95,0.35,0.35,1), 'Статус: данных нет или они устарели')
    end

    local percent = 0
    if (MS_Sklad.max or 0) > 0 then
        percent = (MS_Sklad.current or 0) / (MS_Sklad.max or 50000)
        if percent < 0 then percent = 0 end
        if percent > 1 then percent = 1 end
    end

    imgui.Text('Сейчас: ' .. MS_SkladFormat(MS_Sklad.current) .. ' / ' .. MS_SkladFormat(MS_Sklad.max))
    if imgui.ProgressBar then
        imgui.ProgressBar(percent, imgui.ImVec2(-1, 22), tostring(math.floor(percent * 100)) .. '%')
    end

    imgui.Text('Не хватает: ' .. MS_SkladFormat(MS_SkladNeed()))
    imgui.Text('Ящиков нужно: ' .. tostring(MS_SkladBoxes()) .. '   |   1 ящик = ' .. tostring(MS_Sklad.oneBox or 200) .. ' медикаментов')

    if (MS_Sklad.lastUpdate or 0) > 0 then
        local ago = math.floor((MS_SkladNow() - MS_Sklad.lastUpdate) / 1000)
        if ago < 0 then ago = 0 end
        imgui.Text('Последнее обновление: ' .. tostring(ago) .. ' сек. назад')
    else
        imgui.Text('Последнее обновление: нет')
    end

    imgui.Spacing()
    if imgui.Button('Обновить сейчас', imgui.ImVec2(180, 32)) then
        local ok_sklad_manual, err_sklad_manual = pcall(function()
            MS_SkladScan()
            MS_SkladResetOldData()
        end)
        if not ok_sklad_manual then
            MS_Sklad.enabled = false
            helper_msg('Склад: авто/ручное сканирование отключено из-за ошибки MoonLoader. Остальной скрипт работает.')
        end
    end
    imgui.SameLine()
    if imgui.Button('Показать в чат', imgui.ImVec2(180, 32)) then
        MS_SkladShowInfo()
    end
    imgui.SameLine()
    if imgui.Button('Отправить в /rn', imgui.ImVec2(180, 32)) then
        MS_SkladSendRadio()
    end

    imgui.Separator()
    imgui.TextColored(MSHelper_AccentColor(), 'Команды')
    imgui.Text('/medinfo — показать склад в чат')
    imgui.Text('/medrn — отправить склад в рацию /rn')
    imgui.TextWrapped('Когда вы уходите со второго этажа и 3D-текст склада пропадает, мониторинг выключается примерно через 4-5 секунд.')
end



-- Вкладка шпаргалок удалена по просьбе пользователя.



-- ===== MS Helper | Шпаргалки ЕЦП / Устав с online update =====
-- Данные обновляются из GitHub raw/txt. Форум напрямую не грузим, чтобы не крашить MoonLoader.
MS_ShporaTab = MS_ShporaTab or 1
MS_SHPORA_STATUS = MS_SHPORA_STATUS or 'Шпаргалки готовы. Для обновления используйте /shupdate.'
MS_SHPORA_DOWNLOADING = MS_SHPORA_DOWNLOADING or false

MS_ECP_DEFAULT_RAW_URL = 'https://raw.githubusercontent.com/MakarMaslow/mshelper-data/main/ecp.txt'
MS_USTAV_DEFAULT_RAW_URL = 'https://raw.githubusercontent.com/MakarMaslow/mshelper-data/main/ustav.txt'
MS_ECP_DEFAULT_API_URL = 'https://api.github.com/repos/MakarMaslow/mshelper-data/contents/ecp.txt?ref=main'
MS_USTAV_DEFAULT_API_URL = 'https://api.github.com/repos/MakarMaslow/mshelper-data/contents/ustav.txt?ref=main'

MS_USTAV_TEXT = MS_USTAV_TEXT or [====[
version=18.06.2026

[1. Права сотрудников Министерства здравоохранения]

1.1 Сотрудники Министерства здравоохранения имеют право использовать служебный транспорт, средства связи, специализированное оборудование и иные ресурсы Министерства исключительно в рамках исполнения своих должностных обязанностей, строго в пределах предоставленных полномочий и с соблюдением установленных внутренних регламентов.

1.2 Сотрудники имеют право на получение должностных надбавок, премиальных выплат, а также иных форм материального и нематериального поощрения. Указанные меры применяются при наличии соответствующих оснований и оформляются в установленном порядке, включая внесение записей в личное дело сотрудника.

1.3 Сотрудники вправе обращаться к руководству Министерства для защиты своих законных прав, интересов и профессиональной репутации. Данное право распространяется на случаи возникновения конфликтных ситуаций, а также при неправомерных действиях со стороны граждан, сотрудников иных организаций или должностных лиц.

1.4 Сотрудники имеют право на профессиональное развитие и карьерный рост, включая прохождение обучения, повышение квалификации, участие в профильных мероприятиях, освоение новых компетенций и возможность продвижения по службе при соблюдении требований, установленных внутренними нормативными актами и действующим законодательством.

1.5 Сотрудники имеют право на получение полной, достоверной и актуальной информации, необходимой для надлежащего исполнения служебных обязанностей. К такой информации относятся приказы, распоряжения, инструкции, регламенты, графики работы и иные внутренние нормативные документы.

1.6 Сотрудникам гарантируется право на безопасные условия труда. Это включает обеспечение средствами индивидуальной защиты, необходимыми медицинскими материалами, а также соблюдение санитарных и иных обязательных норм, направленных на предотвращение угроз жизни и здоровью сотрудников.

1.7 Сотрудники имеют право на уважительное и корректное отношение со стороны граждан, коллег и представителей других организаций. Также им гарантируется защита от оскорблений, дискриминации, угроз и любых форм неправомерного давления при исполнении служебных обязанностей.

1.8 Сотрудники вправе запрашивать содействие и помощь со стороны руководства, старшего состава или коллег в случаях, когда выполнение должностных обязанностей требует дополнительных ресурсов, участия других специалистов, повышенной квалификации или организационной поддержки.

1.9 Сотрудники имеют право вносить предложения, направленные на улучшение деятельности Министерства, оптимизацию рабочих процессов, совершенствование внутренних регламентов и повышение качества оказания медицинской помощи. Такие предложения подаются в установленном порядке через руководство подразделения или Министерства.

1.10 Сотрудники имеют право на объективную и беспристрастную оценку своей служебной деятельности. В случае применения дисциплинарных мер сотруднику должны быть разъяснены причины их применения, а также предоставлена возможность дать письменные или устные объяснения до принятия окончательного решения.

[2. Обязанности сотрудников Министерства здравоохранения]

2.1 Сотрудник Министерства здравоохранения обязан добросовестно, своевременно и качественно выполнять возложенные на него должностные обязанности, действуя строго в рамках своей компетенции, соблюдая внутренние регламенты Министерства и нормы действующего законодательства Синей Федерации.

2.2 Сотрудник обязан соблюдать нормы профессиональной этики и служебного поведения, проявлять уважение, тактичность и корректность в общении с гражданами, независимо от их социального статуса, должности, возраста, пола, национальности, вероисповедания и иных характеристик.

2.3 Сотрудник обязан исполнять законные приказы, распоряжения и поручения руководства при условии, что такие указания не выходят за пределы полномочий руководителя, не противоречат внутренним нормативным актам Министерства и не нарушают действующее законодательство.

2.4 Сотрудник обязан поддерживать и повышать уровень своей профессиональной квалификации, регулярно изучать действующие регламенты, стандарты оказания медицинской помощи, порядок работы подразделения, а также совершенствовать практические навыки, необходимые для выполнения служебных задач.

2.5 Сотрудник несёт персональную ответственность за свои действия, принятые решения и бездействие в рамках служебной деятельности, включая их последствия, которые могут повлиять на здоровье граждан, репутацию Министерства, уровень дисциплины и безопасность сотрудников.

2.6 Сотрудники медицинских учреждений обязаны обеспечивать своевременное снабжение медикаментами и медицинскими средствами организаций, находящихся в зоне ответственности, в установленном порядке — на основании запросов, распоряжений руководства либо при возникновении чрезвычайных ситуаций.

2.7 Сотрудник обязан соблюдать трудовую дисциплину, установленный график работы, требования к внешнему виду (дресс-код), а также правила эксплуатации служебного транспорта, средств связи и медицинского оборудования.

2.8 Сотрудник обязан соблюдать служебную и медицинскую тайну, обеспечивать конфиденциальность информации о пациентах, внутренней деятельности Министерства и иных данных, полученных в ходе выполнения служебных обязанностей, за исключением случаев, предусмотренных законодательством или санкционированных руководством.

2.9 Сотрудник обязан выстраивать корректное и профессиональное взаимодействие с представителями других государственных органов и организаций, действуя в рамках установленного порядка и поддерживая деловую репутацию Министерства здравоохранения.

2.10 Сотрудник обязан бережно относиться к государственному имуществу, включая служебный транспорт, медицинское оборудование, медикаменты, документацию и иные материальные ценности, не допуская их порчи, утраты или нецелевого использования.

2.11 Сотрудник обязан соблюдать служебную субординацию, поддерживать уважительные и профессиональные отношения с коллегами и руководством, а возникающие спорные или конфликтные ситуации разрешать в установленном порядке через официальные каналы, способствуя поддержанию дисциплины и стабильной рабочей обстановки.

[3. Сотрудникам Министерства здравоохранения запрещается]

3.1 Принимать денежные средства, подарки, услуги, льготы, скидки и иные материальные или нематериальные выгоды от физических и юридических лиц, если это может повлиять на объективность решений сотрудника, привести к возникновению конфликта интересов или предоставить кому-либо незаконные преимущества.

3.2 Разглашать служебную, медицинскую или иную конфиденциальную информацию, полученную при исполнении должностных обязанностей, без законных оснований либо соответствующего разрешения руководства.

3.3 Использовать служебное положение, полномочия, авторитет должности, а также ресурсы Министерства (включая транспорт, оборудование, медикаменты, документы и средства связи) в личных целях или для получения выгоды.

3.4 Допускать любые формы дискриминации, оскорблений, унижения достоинства, предвзятого отношения или ограничения прав граждан и сотрудников по любым признакам.

3.5 Самостоятельно изменять стоимость медицинских услуг, установленную Единой ценовой политикой Министерства, за исключением случаев, прямо предусмотренных внутренними нормативными актами и подтверждённых официальными решениями руководства.

3.6 Проявлять некорректное поведение, включая использование нецензурной лексики, грубости, оскорблений, провокаций или иных форм неуважительного общения при исполнении служебных обязанностей.

3.7 Игнорировать, нарушать или саботировать законные приказы и распоряжения руководства, если они соответствуют уставу и действующему законодательству.

3.8 Допускать порчу, утрату или нецелевое использование имущества Министерства, включая служебный транспорт, оборудование, медикаменты, документацию, средства связи и иные материальные ценности.

3.9 Иметь при себе оружие в открытом виде, демонстрировать его, использовать для давления или устрашения, а также хранить его в служебных помещениях, за исключением случаев, прямо предусмотренных законодательством.

3.10 Подделывать, изменять, уничтожать или искажать официальные документы, а также вносить заведомо ложные сведения в отчёты, приказы, личные дела и иные документы с целью обмана, сокрытия нарушений или получения выгоды.

3.11 Совершать действия, наносящие ущерб чести, достоинству и деловой репутации Министерства, включая распространение недостоверной информации, провокационное поведение и демонстративное нарушение установленных норм.

3.12 Препятствовать работе других сотрудников, создавать помехи при оказании медицинской помощи, а также умышленно затягивать процессы лечения, осмотра или предоставления услуг.

3.13 Злоупотреблять должностными полномочиями, включая оказание давления на граждан, принуждение к действиям, не предусмотренным нормативными актами, а также использование служебного положения в личных интересах.

[4. Рабочий график и порядок несения службы]

4.1 В Министерстве здравоохранения Синей Федерации установлен единый график рабочего времени, обязательный для всех сотрудников вне зависимости от подразделения. Изменение графика допускается только на основании официального распоряжения Министра здравоохранения, Главного врача либо при возникновении чрезвычайных обстоятельств.

4.2 Рабочее время устанавливается следующим образом:
— Понедельник – пятница: с 10:00 до 21:00;
— Перерыв: с 15:00 до 16:00;
— Суббота: с 12:00 до 21:00;
— Перерыв: с 15:00 до 16:00;
— Воскресенье: выходной день.

4.3 В период рабочего времени сотрудник обязан находиться на рабочем месте, поддерживать постоянную связь по служебным каналам и быть готовым к выполнению своих обязанностей, включая приём пациентов, реагирование на вызовы, выполнение поручений руководства и участие в мероприятиях Министерства.

4.4 В государственные праздничные дни режим работы может быть изменён отдельным приказом руководства либо осуществляется в соответствии с установленным порядком работы в такие дни. К государственным праздникам относятся:
— 31 декабря – 5 января — новогодние каникулы;
— 25 января — профессиональный праздник работников органов государственной власти;
— 15 февраля — День независимости Синей Федерации;
— 23 февраля — День защитника Отечества и Федерации;
— 8 марта — Международный женский день;
— 10 марта — профессиональный праздник работников МВД;
— 5 апреля — профессиональный праздник журналистов;
— 8–9 мая — День Победы в Европе;
— 4 июня — День Конституции Синей Федерации;
— 10 июля — профессиональный праздник военнослужащих;
— 7 октября — День всенародной памяти;
— 31 октября – 1 ноября — День всех святых;
— 8 декабря — профессиональный праздник работников здравоохранения.

4.5 Сотруднику допускается временно покидать рабочее место в рабочее время только при наличии служебной необходимости, в том числе:
— при реагировании на чрезвычайные ситуации;
— при выездах по вызовам и оказании помощи пациентам;
— при доставке медикаментов и медицинских средств;
— при участии в официальных мероприятиях;
— при проведении учений и тренировок по распоряжению руководства;
— при выполнении иных служебных поручений, санкционированных руководящим составом.

4.6 Самовольное отсутствие на рабочем месте в течение рабочего дня запрещено и рассматривается как нарушение трудовой дисциплины. Исключения допускаются только в случаях, предусмотренных пунктом 4.5, и при наличии соответствующего распоряжения руководства.

4.7 Сотрудник вправе по собственной инициативе выполнять служебные задачи вне установленного рабочего времени, включая участие в мероприятиях, обучение, работу с документацией и оказание медицинской помощи, при условии соблюдения требований законодательства и внутренних регламентов.

[5. Служебный транспорт]

5.1 Сотрудникам Министерства здравоохранения разрешается использовать карету скорой помощи, начиная с 3-ей должности, а транспортный фургон для перевозки медикаментов, начиная с 1-ой должности, исключительно при выполнении служебных обязанностей и в соответствии с установленными инструкциями.

5.2 Использование вертолёта допускается сотрудниками, занимающими должности с 7-ой и выше, при условии соблюдения всех требований эксплуатации и норм безопасности.

5.3 Иной служебный транспорт, находящийся на территории Министерства, может использоваться сотрудниками с 7-ой должности и выше только при наличии разрешения Министра здравоохранения или его заместителя. При отсутствии руководства решение принимается в соответствии с установленной внутренней процедурой.

5.4 Использование специальных сигналов (сирены и проблесковых маячков) допускается исключительно при срочной транспортировке пациентов или в условиях чрезвычайных ситуаций, связанных с угрозой жизни и здоровью граждан.

5.5 Сотрудники обязаны бережно относиться к служебному транспорту, использовать его строго по назначению, соблюдать правила эксплуатации, техники безопасности и внутреннего порядка, а также не оставлять транспортные средства в непредусмотренных местах.

5.6 Использование служебного транспорта в личных целях категорически запрещено. Любые поездки, не связанные с выполнением должностных обязанностей, рассматриваются как нарушение дисциплины и влекут применение мер ответственности в соответствии с уставом Министерства здравоохранения.

[6. Лечение пациентов]

6.1 Медицинский работник Министерства здравоохранения обязан оказывать квалифицированную и всестороннюю медицинскую помощь всем гражданам, нуждающимся в лечении, в соответствии со своей профессиональной подготовкой, установленными стандартами и внутренними регламентами. Помощь должна предоставляться с соблюдением норм медицинской этики, безопасности и уважительного отношения к пациенту.

6.2 Оказание лечения допускается только после установления точного и обоснованного диагноза. Сотрудник обязан применять разрешённые методы диагностики и фиксировать результаты в установленном порядке. По запросу пациента ему должна быть предоставлена информация о диагнозе и назначенном лечении в корректной и доступной форме.

6.3 К проведению лечения допускаются сотрудники, занимающие должности с 3-й и выше, при наличии необходимой квалификации, полномочий и допуска к выполнению медицинских процедур.

6.4 Медицинский работник не вправе отказывать пациенту в оказании помощи, за исключением случаев, прямо предусмотренных внутренними нормативными актами или законодательством. Необоснованный отказ рассматривается как нарушение дисциплины и влечёт ответственность.

6.5 Запрещается требовать или принимать оплату, вознаграждение либо иные выгоды за оказание медицинских услуг, входящих в установленный перечень бесплатного или регламентированного обслуживания, включая оформление документов, проведение процедур и назначение лечения.

6.6 Министр здравоохранения вправе временно изменять стоимость медицинских услуг при наличии обоснованных причин (в том числе при чрезвычайных или военных обстоятельствах, а также в рамках разовых акций).

6.7 Медицинский работник вправе самостоятельно снижать стоимость медицинских услуг либо оказывать их бесплатно в индивидуальном порядке при наличии уважительных причин, связанных с финансовым положением пациента.

6.8 Актуальная информация о стоимости медицинских услуг закрепляется в Единой ценовой политике Министерства и является обязательной для соблюдения всеми сотрудниками.

6.9 Медицинский работник обязан при необходимости обеспечить транспортировку пациента в медицинское учреждение, если это требуется для сохранения жизни или здоровья, используя служебный транспорт и действуя в соответствии с установленными инструкциями.

6.10 Проведение медицинских операций и сложных процедур допускается только при участии ассистентов. Исключение составляют случаи их фактического отсутствия. Все манипуляции должны выполняться с соблюдением санитарных норм, правил асептики и антисептики, а также профессиональных стандартов.

6.11 Оказание медицинской помощи должно осуществляться в пределах закреплённого за сотрудником медицинского учреждения. Выезд в другие учреждения допускается только при чрезвычайных или экстренных ситуациях.

6.12 При проведении медицинских процедур сотрудник обязан использовать средства индивидуальной защиты (маски, перчатки, спецодежду и иные СИЗ) в соответствии с установленными требованиями.

6.13 В случае возникновения нестандартных или чрезвычайных ситуаций, включая осложнения, ошибки или сложные клинические случаи, сотрудник обязан незамедлительно уведомить руководство и действовать в соответствии с полученными указаниями.

6.14 Запрещается самостоятельно назначать лечение, препараты или процедуры, не предусмотренные внутренними регламентами, клиническими протоколами или распоряжениями руководства. Нарушение данного требования влечёт дисциплинарную ответственность.

6.15 Сотрудник вправе по собственной инициативе оказывать медицинскую помощь или участвовать в служебной деятельности вне рабочего времени при условии соблюдения всех установленных норм и требований законодательства.

6.16 При взаимодействии с пациентами сотрудники обязаны соблюдать высокие профессиональные и этические стандарты, обеспечивать безопасность и конфиденциальность, проявлять уважительное отношение и предоставлять достоверную информацию в рамках своей компетенции.

6.17 Выписка пациентов из медицинского учреждения должна производиться исключительно у регистратуры медицинского учреждения с обязательным соблюдением установленного порядка оформления документов.

[7. Служебная рация]

7.1 В Министерстве здравоохранения предусмотрены два канала служебной связи для оперативного взаимодействия сотрудников:
7.1.1 Внутрибольничная волна (( /r )) — используется для связи между сотрудниками одного подразделения.
7.1.2 Министерская волна (( /f )) — предназначена для взаимодействия всех сотрудников Министерства здравоохранения.

7.2 Право использования министерской волны (( /f )) предоставляется сотрудникам, начиная с 1-й должности. Данный канал используется исключительно в служебных целях: для оповещения о чрезвычайных ситуациях, передачи информации о вызовах, координации действий медицинских бригад, а также для официального взаимодействия с руководством, включая Министра здравоохранения.

7.3 Использование служебной радиосвязи допускается только в рамках выполнения должностных обязанностей и должно быть направлено на обеспечение эффективного и оперативного взаимодействия между сотрудниками.

7.4 Запрещается использование рации в личных целях, включая обсуждение личных вопросов, посторонних тем, развлечений или информации, не связанной со служебной деятельностью.

7.5 Сотрудники обязаны контролировать радиосвязь в рабочее время, не игнорировать входящие сообщения и своевременно реагировать на поступающую информацию.

7.6 При ведении радиопереговоров запрещается использовать второстепенные обозначения, должностные теги и иные элементы, не относящиеся к служебной необходимости. Общение должно быть кратким, корректным и по существу.

[8. Дресс-код сотрудников]

8.1 Дресс-код сотрудников устанавливается Министром здравоохранения или его заместителем и является обязательным для всех работников независимо от занимаемой должности. Изменения допускаются только на основании официальных распоряжений руководства.

8.2 Сотрудники обязаны строго соблюдать установленные требования к форме одежды в рабочее время и поддерживать профессиональный внешний вид на территории медицинских учреждений. Любые отклонения от утверждённого дресс-кода запрещены.

8.3 Министр здравоохранения, его заместители, а также руководители медицинских подразделений и их заместители вправе использовать деловой стиль одежды при выполнении административных функций. При этом при проведении медицинских процедур они обязаны соблюдать установленную медицинскую форму.

8.4 Обязательными элементами экипировки медицинского работника являются медицинская маска и нитриловые перчатки. Использование посторонних аксессуаров запрещено, за исключением предметов, предусмотренных внутренними регламентами (очки для зрения, медицинская шапочка, специализированные принадлежности и иные допустимые элементы).

8.5 Запрещается ношение неподобающей одежды, включая вульгарную, чрезмерно открытую или не соответствующую профессиональному статусу медицинского работника, в рабочее время и на территории, связанной с деятельностью учреждения.

8.6 При нахождении вне территории медицинского учреждения и прилегающих служебных зон сотрудник обязан сменить рабочую форму на повседневную или деловую одежду, соответствующую нормам профессионального поведения.

8.7 Сотрудники обязаны поддерживать аккуратный внешний вид: одежда должна быть чистой и исправной, обувь — надлежащего состояния, а средства индивидуальной защиты — соответствовать установленным санитарным требованиям.

8.8 Нарушение требований дресс-кода рассматривается как дисциплинарное нарушение и влечёт применение мер ответственности в соответствии с внутренними нормативными актами Министерства.

8.9 Руководство имеет право осуществлять контроль за соблюдением дресс-кода, проводить проверки внешнего вида сотрудников и требовать устранения выявленных нарушений в установленном порядке.
1-2 Белая рубашка[М] 3-5 Зеленая рубашка[М] 6-7 Синия рубашка[М] 8-10 Белный халат[М] 1-2 Синий костюм[Ж] 3-10 Зеленая рубашка[Ж]

[9. Причины увольнения]

9.1 Увольнение за нарушение устава Министерства здравоохранения (НУМЗ) применяется в случаях систематического или грубого несоблюдения правил и внутренних регламентов: невыполнение должностных обязанностей, игнорирование распоряжений руководства, нарушение трудовой дисциплины, несоблюдение дресс-кода, неправомерное использование служебного транспорта и рации, действия, порочащие честь и авторитет Министерства.

9.2 Увольнение за нарушение Единой ценовой политики применяется к сотрудникам, допустившим отклонения от утверждённых цен, необоснованные скидки, изменение стоимости медицинских услуг без приказа Министра или его заместителей, а также иные действия, противоречащие установленной ценовой политике.

9.3 Увольнение по причине профессиональной непригодности производится при систематической неспособности сотрудника качественно выполнять обязанности, низкой квалификации, частых ошибках, нарушении стандартов медицинской помощи или невозможности пройти обучение и повышение квалификации.

9.4 Увольнение по причине перевода осуществляется при официальном перемещении сотрудника в другое подразделение, медицинское учреждение или организацию Министерства по распоряжению руководства с соблюдением процедур, уведомлением сотрудника и передачей документации.

9.5 Увольнение по причине отпуска применяется при предоставлении сотруднику официального отпуска. В этот период сотрудник освобождается от обязанностей, при этом сохраняются все права и гарантии. После окончания отпуска сотрудник возвращается к исполнению своих обязанностей, если иное не установлено распоряжением руководства.

9.6 Увольнение по собственному желанию осуществляется по инициативе сотрудника с обязательным уведомлением руководства, соблюдением сроков предупреждения и передачей всех служебных материалов, документов и инвентаря Министерства.

9.7 Во всех случаях увольнения сотрудник заранее уведомляется о причинах и основаниях. Уведомление фиксируется через межведомственную рацию и в системе учёта персонала. Сотрудник имеет право ознакомиться с основаниями и представить свои объяснения или возражения.

[10. Основные правила для сотрудников старшего состава]

10.1 Сотрудник старшего состава обязан добросовестно, качественно и в полном объёме выполнять свои обязанности, строго соблюдая нормы законодательства Синей Федерации, внутренние регламенты Министерства и настоящий устав.

10.2 Сотрудник старшего состава обеспечивает системную и оперативную поддержку главного врача подразделения, включая организацию мероприятий, контроль распределения обязанностей, выполнение планов работы и соблюдение дисциплины в подразделении.

10.3 Старший состав контролирует работу младшего персонала, обеспечивает обучение и повышение квалификации, проводит инструктажи, практические и теоретические занятия, выявляет нарушения и докладывает о них руководству.

10.4 Сотрудник обязан строго соблюдать внутренние правила, инструкции и нормативные документы Министерства, включая работу с документацией, учёт пациентов, дресс-код, использование служебного транспорта и средств связи, а также нормы дисциплины и профессиональной этики.

10.5 Старший состав отвечает за подбор персонала: оценку кандидатов, проверку квалификации, законопослушности и наличия действующей медицинской карты, проведение собеседований, фиксацию результатов и информирование руководства о решениях.

10.6 Все действия старшего состава должны быть прозрачными и документально зафиксированными в системе учёта Министерства или в личных делах сотрудников.

10.7 Сотрудник старшего состава поддерживает корпоративную дисциплину, демонстрирует высокий уровень профессиональной этики и является примером для младшего персонала.

10.8 Старший состав контролирует соблюдение всех норм безопасности при оказании медицинской помощи, использовании транспорта и оборудования, предотвращает аварии и нарушения санитарных правил.

10.9 Ответственность старшего состава включает правильность и своевременность отчётности о работе подразделения, обучении персонала, кадровых мероприятиях и использовании ресурсов.
10.10 Старший состав способствует формированию профессиональной и этичной рабочей атмосферы, предотвращает конфликты и решает спорные ситуации внутри подразделения, взаимодействуя с другими отделами Министерства.

10.11 Требования к кандидатам на трудоустройство в медицинское учреждение:
• Проживание в штате не менее 3 лет;
• Положительная характеристика по критерию законопослушности;
• Наличие базовых прав и действующей медицинской карты;

[11. Правила увольнения сотрудников]

11.1 Увольнение сотрудников Министерства здравоохранения осуществляется строго в соответствии с законодательством Синей Федерации, настоящим Уставом, внутренними регламентами и приказами руководства. Все процедуры должны быть официально оформлены, прозрачны и зафиксированы в системе учёта персонала. Сотрудник обязателен уведомляется заранее о причинах увольнения и имеет право ознакомиться с основаниями, а также представить свои пояснения или возражения.

11.2 Увольнение может происходить по инициативе сотрудника, работодателя или по взаимному соглашению сторон. Все действия при этом должны соответствовать установленной процедуре: фиксация причины увольнения, оформление приказа, возврат служебного инвентаря, оборудования и документов.

11.3 Сотрудник, подлежащий увольнению, обязан сдать все служебные материалы, документацию, медицинское оборудование, инвентарь, ключи и иные предметы, принадлежащие Министерству здравоохранения, а также обеспечить передачу текущих дел и обязанностей. Факт сдачи имущества фиксируется официально.

11.4 Увольнение сотрудников с руководящих должностей (старший состав) осуществляется исключительно Главным Врачом подразделения или Министром здравоохранения, за исключением случаев официального перевода в другое подразделение, который оформляется отдельным распоряжением.

11.5 При увольнении по инициативе работодателя, включая несоответствие должностным обязанностям, сотрудник должен быть заранее предупреждён о причинах, иметь доступ к документам и материалам, отражающим его работу, и иметь возможность представить свои пояснения. Все действия фиксируются в системе учёта и, при необходимости, в личном деле сотрудника.

11.6 Внесение сотрудника в Чёрный список Министерства здравоохранения в случае чрезвычайной ситуации или серьёзных нарушений осуществляется исключительно Министром здравоохранения. Все действия фиксируются письменно и документально, включая запись в личное дело сотрудника.

11.7 Все увольнения, включая инициированные работодателем, сопровождаются официальным уведомлением через межведомственную рацию Министерства здравоохранения с обязательной фиксацией факта уведомления. Это обеспечивает прозрачность процедуры и соблюдение прав сотрудника.

11.8 Сотрудник, уволенный за нарушение устава или законодательства Синей Федерации, не может повторно трудоустроиться в Министерство здравоохранения в течение 10 дней с момента увольнения.

[12. Правила повышения сотрудников]

12.1 Повышение сотрудников младшего состава Министерства здравоохранения осуществляется по решению Министра здравоохранения, Главного врача подразделения или его заместителя, в строгом соответствии с установленными системами, внутренними регламентами и процедурами Министерства.

12.2 Повышение сотрудников проводится по следующим системам:
• Отчётная система — оценка выполнения служебных обязанностей, эффективности работы, дисциплинарной ответственности и соблюдения внутренних правил;
• Альтернативная система — выполнение специальных заданий, кейсов или проектов, результаты которых оцениваются руководством;
• Онлайн-собеседование — применяется при повышении на руководящие должности или переходе в старший состав.

12.3 Повышение сотрудников старшего состава осуществляется исключительно Главным врачом подразделения или Министром здравоохранения с обязательной фиксацией решения в системе учёта и личном деле сотрудника.

12.4 Подача электронного заявления на повышение до 4-й порядковой должности с целью получения должности строго запрещена в день увольнения. Между увольнением и подачей заявления на 4-ю порядковую должность должен пройти не менее одного рабочего дня, что обеспечивает корректность кадровой процедуры.

12.5 Любое косвенное или прямое давление, требования или попытки ускоренного повышения со стороны сотрудника или третьих лиц категорически запрещены.

12.6 Фальсификация отчётных данных или иного рода манипуляции с документами и результатами работы сотрудника с целью повышения или получения личной выгоды строго запрещены и влекут дисциплинарную ответственность.

12.7 Повышение сотрудников может проводиться также в форме премирования по решению Министра здравоохранения, в качестве поощрения за успешное выполнение задач, инициативность, высокую эффективность работы и строгое соблюдение внутренних правил и регламентов Министерства.

12.8 Максимальный срок хранения доказательств, которые будут использованы для подачи электронного отчёта сотрудника, составляет 7 дней с момента выполнения соответствующей работы.

[13. Испытательные сроки]

13.1 На новой должности сотрудник обязан пройти испытательный срок перед возможностью перевода, увольнения или ухода в отпуск. Данное правило строго распространяется на сотрудников старшего состава, включая должности с 7-й по 9-ю порядковую.

Испытательные сроки по должностям:
• 1-я порядковая должность — 0 дней;
• 2-я порядковая должность — 0 дней;
• 3-я порядковая должность — 1 дней;
• 4-я порядковая должность — 1 день;
• 5-я порядковая должность — 2 день;
• 6-я порядковая должность — 3 дня;
• 7-я порядковая должность — 4 дня;
• 8-я порядковая должность — 5 дней;
• 9-я порядковая должность — 7 дней.

Испытательный срок обеспечивает проверку соответствия сотрудника должностным обязанностям, профессиональной подготовке и соблюдению внутренних регламентов Министерства.

[14. Лимиты сотрудников старшего состава]

14.1 Установлены ограничения по количеству сотрудников старшего состава в каждой из высших должностей:
• 9-я порядковая должность — 4 человека;
• 8-я порядковая должность — 6 человек;
• 7-я порядковая должность — 8 человек.

14.2 В случае, если заместитель занимает должность ВрИО (Временно исполняющий обязанности), место на 9-й должности и выше закрепляется за ним и не может быть занято другим сотрудником до окончания временного назначения.

14.3 Лимиты сотрудников обеспечивают рациональное распределение кадров, контроль за компетенцией старшего состава и поддержание эффективной работы подразделений Министерства здравоохранения.

[15. Правила внесения записей в личное дело (( /NOTE /SHOW ))]

15.1 Любые записи в личное дело сотрудника могут вноситься заместителем только при наличии официального разрешения вышестоящего руководства.

15.2 Записи о занесении сотрудника в Чёрный Список Министерства здравоохранения может осуществлять исключительно Министр здравоохранения.

15.3 Занесение в Чёрный Список применяется только при наличии веской и обоснованной причины (( исключительно по Решению руководства, с обязательной РП причиной )), являясь крайней мерой дисциплинарного воздействия.

15.4 Все выговоры и записи о занесении в ЧС должны быть официально задокументированы и продублированы в соответствующих разделах электронного портала Федерации для прозрачного учёта.

15.5 Намеренное повреждение, изменение или удаление записей в личном деле (( общение посредством /note )) строго запрещено и рассматривается как дисциплинарное нарушение.

15.6 Нарушение правил внесения записей может повлечь дисциплинарные меры и санкции в отношении руководителя подразделения, допустившего нарушение.

[16. Правила для заместителей директора]

16.1 Заместителям директора запрещается провоцировать конфликтные ситуации между сотрудниками. Любые доказанные случаи намеренной провокации будут рассматриваться как дисциплинарное нарушение и могут повлечь увольнение с занесением в Чёрный Список.

16.2 Заместителям директора строго запрещено распространять клевету или подставлять сотрудников перед руководством. Нарушение данного положения влечёт серьёзные дисциплинарные меры, включая увольнение и занесение в Чёрный Список.

16.3 Заместители директора обязаны контролировать и проверять поступающие заявления, отчёты сотрудников, проводить собеседования и актуализировать списки приёма в подразделение. Эти обязанности являются прямой служебной обязанностью заместителя.

16.4 В отсутствие директора больницы заместитель директора полностью отвечает за организацию и работу подразделения, обеспечивая выполнение всех функций и задач учреждения.

16.5 Сотрудникам, занимающим 9-ю порядковую должность, запрещается спать в рабочее время. Исключение составляют выходные дни или окончание рабочего дня. Нарушение данного правила рассматривается как дисциплинарное нарушение и подлежит соответствующему наказанию.
]====]

MS_ECP_DISPLAY = MS_ECP_DISPLAY or {}

function MS_ShporaMkdir(path)
    path = tostring(path or '')
    if path == '' then return false end

    if type(doesDirectoryExist) == 'function' and doesDirectoryExist(path) then
        return true
    end

    if type(createDirectory) == 'function' then
        createDirectory(path)
        if type(doesDirectoryExist) ~= 'function' or doesDirectoryExist(path) then return true end
    end

    -- Без os.execute: создаём папку через WinAPI, чтобы GTA/MoonLoader не сворачивало и не мусорило в корне.
    if ffi then
        if not _G.MSHelper_CreateDirCdefReady then
            pcall(ffi.cdef, [[
                typedef int BOOL;
                typedef const char* LPCSTR;
                typedef void* LPSECURITY_ATTRIBUTES;
                BOOL __stdcall CreateDirectoryA(LPCSTR lpPathName, LPSECURITY_ATTRIBUTES lpSecurityAttributes);
            ]])
            _G.MSHelper_CreateDirCdefReady = true
        end
        local ok, k32 = pcall(ffi.load, 'kernel32')
        if ok and k32 then pcall(k32.CreateDirectoryA, path, nil) end
    end

    if type(doesDirectoryExist) == 'function' then
        return doesDirectoryExist(path)
    end
    return true
end

function MS_ShporaBaseDir()
    local dir = '.'
    if type(getWorkingDirectory) == 'function' then dir = getWorkingDirectory() end

    local base = tostring(dir) .. '\\MSHelper'
    local temp = base .. '\\temp'

    MS_ShporaMkdir(base)
    MS_ShporaMkdir(temp)

    return temp
end

function MS_ShporaPath(name)
    return MS_ShporaBaseDir() .. '\\' .. tostring(name)
end


function MS_ShporaRuLower(s)
    s = tostring(s or ''):lower()
    s = s:gsub('Ё','ё'):gsub('А','а'):gsub('Б','б'):gsub('В','в'):gsub('Г','г'):gsub('Д','д'):gsub('Е','е'):gsub('Ж','ж'):gsub('З','з'):gsub('И','и'):gsub('Й','й'):gsub('К','к'):gsub('Л','л'):gsub('М','м'):gsub('Н','н'):gsub('О','о'):gsub('П','п'):gsub('Р','р'):gsub('С','с'):gsub('Т','т'):gsub('У','у'):gsub('Ф','ф'):gsub('Х','х'):gsub('Ц','ц'):gsub('Ч','ч'):gsub('Ш','ш'):gsub('Щ','щ'):gsub('Ъ','ъ'):gsub('Ы','ы'):gsub('Ь','ь'):gsub('Э','э'):gsub('Ю','ю'):gsub('Я','я')
    return s
end

-- Серверные профили шпаргалок. У каждого сервера свой кэш ЕЦП/Устава.
MS_SHPORA_SERVERS = {
    {'red', 'Red'},
    {'green', 'Green'},
    {'blue', 'Blue'},
    {'lime', 'Lime'},
    {'chocolate', 'Chocolate'}
}
MS_SHPORA_SERVER_LABELS = {
    red='Red',
    green='Green',
    blue='Blue',
    lime='Lime',
    chocolate='Chocolate'
}
MS_SHPORA_ACTIVE_SERVER = MS_SHPORA_ACTIVE_SERVER or 'green'

function MS_ShporaNormalizeServerKey(key)
    key = MS_ShporaRuLower(key)
    key = key:gsub('ё', 'е')
    key = key:gsub('advance%s*', ''):gsub('server%s*', ''):gsub('[%[%]%(%)|]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    MS_SHPORA_TMP_ALIASES = {
        ['red']='red', ['красный']='red', ['крас']='red',
        ['green']='green', ['грин']='green', ['зеленый']='green', ['зел']='green', ['x2 exp']='green', ['x2']='green',
        ['blue']='blue', ['блу']='blue', ['синий']='blue', ['син']='blue',
        ['lime']='lime', ['лайм']='lime',
        ['choco']='chocolate', ['chocolate']='chocolate', ['шоколад']='chocolate', ['шоколадный']='chocolate'
    }
    if MS_SHPORA_TMP_ALIASES[key] then return MS_SHPORA_TMP_ALIASES[key] end
    for _, MS_SHPORA_TMP_ROW in ipairs(MS_SHPORA_SERVERS) do
        if key:find(MS_SHPORA_TMP_ROW[1], 1, true) then return MS_SHPORA_TMP_ROW[1] end
    end
    return nil
end

function MS_ShporaServerNameRaw()
    MS_SHPORA_TMP_NAME = ''
    if type(sampGetCurrentServerName) == 'function' then
        MS_SHPORA_TMP_OK, MS_SHPORA_TMP_RESULT = pcall(sampGetCurrentServerName)
        if MS_SHPORA_TMP_OK and MS_SHPORA_TMP_RESULT then MS_SHPORA_TMP_NAME = tostring(MS_SHPORA_TMP_RESULT) end
    end
    if MS_SHPORA_TMP_NAME == '' and type(sampGetCurrentServerAddress) == 'function' then
        MS_SHPORA_TMP_OK, MS_SHPORA_TMP_IP, MS_SHPORA_TMP_PORT = pcall(sampGetCurrentServerAddress)
        if MS_SHPORA_TMP_OK and MS_SHPORA_TMP_IP then MS_SHPORA_TMP_NAME = tostring(MS_SHPORA_TMP_IP) .. ':' .. tostring(MS_SHPORA_TMP_PORT or '') end
    end
    return MS_SHPORA_TMP_NAME
end

function MS_ShporaDetectServerKey()
    MS_SHPORA_TMP_NAME = MS_ShporaRuLower(MS_ShporaServerNameRaw()):gsub('ё', 'е')
    if MS_SHPORA_TMP_NAME == '' then return nil end

    -- Автоопределение по IP из лаунчера Advance:
    -- Red 185.169.134.237, Green 185.169.134.238, Blue 185.169.134.239,
    -- Lime 185.169.134.156, Chocolate 185.169.134.157.
    if MS_SHPORA_TMP_NAME:find('185%.169%.134%.237', 1, false) then return 'red' end
    if MS_SHPORA_TMP_NAME:find('185%.169%.134%.238', 1, false) then return 'green' end
    if MS_SHPORA_TMP_NAME:find('185%.169%.134%.239', 1, false) then return 'blue' end
    if MS_SHPORA_TMP_NAME:find('185%.169%.134%.156', 1, false) then return 'lime' end
    if MS_SHPORA_TMP_NAME:find('185%.169%.134%.157', 1, false) then return 'chocolate' end

    for _, MS_SHPORA_TMP_ROW in ipairs(MS_SHPORA_SERVERS) do
        if MS_SHPORA_TMP_NAME:find(MS_SHPORA_TMP_ROW[1], 1, true) then return MS_SHPORA_TMP_ROW[1] end
    end
    if MS_SHPORA_TMP_NAME:find('грин', 1, true) or MS_SHPORA_TMP_NAME:find('зел', 1, true) then return 'green' end
    if MS_SHPORA_TMP_NAME:find('син', 1, true) then return 'blue' end
    if MS_SHPORA_TMP_NAME:find('крас', 1, true) then return 'red' end
    if MS_SHPORA_TMP_NAME:find('лайм', 1, true) then return 'lime' end
    if MS_SHPORA_TMP_NAME:find('шоколад', 1, true) then return 'chocolate' end
    return nil
end

function MS_ShporaCurrentServerKey()
    cfg.shpora = cfg.shpora or {}
    if tostring(cfg.shpora.server_mode or 'auto') == 'manual' then
        return MS_ShporaNormalizeServerKey(cfg.shpora.manual_server) or 'green'
    end
    return MS_ShporaDetectServerKey() or MS_ShporaNormalizeServerKey(cfg.shpora.manual_server) or 'green'
end

function MS_ShporaServerLabel(key)
    key = MS_ShporaNormalizeServerKey(key) or 'green'
    return MS_SHPORA_SERVER_LABELS[key] or key
end

function MS_ShporaModeText()
    if cfg and cfg.shpora and tostring(cfg.shpora.server_mode or 'auto') == 'manual' then
        return 'ручной'
    end
    return 'авто'
end

function MS_ShporaUpdateServerFiles()
    MS_SHPORA_ACTIVE_SERVER = MS_ShporaCurrentServerKey()
    MS_ECP_CACHE_FILE = MS_ShporaPath('ecp_cache_' .. MS_SHPORA_ACTIVE_SERVER .. '.txt')
    MS_USTAV_CACHE_FILE = MS_ShporaPath('ustav_cache_' .. MS_SHPORA_ACTIVE_SERVER .. '.txt')
end


function MS_ShporaGithubFolder(key)
    key = MS_ShporaNormalizeServerKey(key) or MS_ShporaCurrentServerKey() or 'green'
    if key == 'choco' then return 'chocolate' end
    return key
end

function MS_ShporaServerRawUrl(kind)
    MS_SHPORA_ACTIVE_SERVER = MS_ShporaCurrentServerKey()
    MS_SHPORA_GITHUB_FOLDER = MS_ShporaGithubFolder(MS_SHPORA_ACTIVE_SERVER)
    return 'https://raw.githubusercontent.com/MakarMaslow/mshelper-data/main/' .. MS_SHPORA_GITHUB_FOLDER .. '/' .. tostring(kind) .. '.txt'
end

function MS_ShporaServerApiUrl(kind)
    MS_SHPORA_ACTIVE_SERVER = MS_ShporaCurrentServerKey()
    MS_SHPORA_GITHUB_FOLDER = MS_ShporaGithubFolder(MS_SHPORA_ACTIVE_SERVER)
    return 'https://api.github.com/repos/MakarMaslow/mshelper-data/contents/' .. MS_SHPORA_GITHUB_FOLDER .. '/' .. tostring(kind) .. '.txt?ref=main'
end

function MS_ShporaSetServerMode(mode, key)
    cfg.shpora = cfg.shpora or {}
    mode = tostring(mode or 'auto'):lower()
    if mode ~= 'manual' then mode = 'auto' end
    if key then cfg.shpora.manual_server = MS_ShporaNormalizeServerKey(key) or cfg.shpora.manual_server or 'green' end
    cfg.shpora.server_mode = mode
    save()
    MS_ShporaUpdateServerFiles()
    MS_ShporaLoadCache()
    MS_SHPORA_LAST_APPLIED_SERVER = MS_ShporaCurrentServerKey()
    MS_SHPORA_STATUS = 'Выбран сервер шпаргалок: ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ' (' .. MS_ShporaModeText() .. '). ЕЦП применена для выбранного сервера.'
end

function MS_ShporaCmdServer(arg)
    arg = tostring(arg or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if arg == '' then
        helper_msg('Сервер шпаргалок: ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ' (' .. MS_ShporaModeText() .. '). Команда: /shserver auto')
        return
    end
    if arg:lower() == 'auto' or arg:lower() == 'авто' then
        MS_ShporaSetServerMode('auto')
        helper_msg(MS_SHPORA_STATUS)
        return
    end
    MS_SHPORA_TMP_KEY = MS_ShporaNormalizeServerKey(arg)
    if not MS_SHPORA_TMP_KEY then
        helper_msg('Не понял сервер. Доступно: auto, red, green, blue, lime, chocolate.')
        return
    end
    MS_ShporaSetServerMode('manual', MS_SHPORA_TMP_KEY)
    helper_msg(MS_SHPORA_STATUS)
end


-- Все временные/скачанные файлы шпаргалок теперь лежат в:
-- moonloader\MSHelper\temp\
-- а не в корне moonloader.
MS_ShporaUpdateServerFiles()

function MS_ShporaCleanupOldRootFiles()
    local dir = '.'
    if type(getWorkingDirectory) == 'function' then dir = getWorkingDirectory() end
    local old = {
        'MSHelper_online_ecp.txt', 'MSHelper_online_ecp.txt.api', 'MSHelper_online_ecp.txt.raw',
        'MSHelper_online_ustav.txt', 'MSHelper_online_ustav.txt.api', 'MSHelper_online_ustav.txt.raw',
        'ecp_cache.txt', 'ecp_cache.txt.api', 'ecp_cache.txt.raw',
        'ustav_cache.txt', 'ustav_cache.txt.api', 'ustav_cache.txt.raw'
    }
    for _, name in ipairs(old) do
        os.remove(tostring(dir) .. '\\' .. name)
    end
end

MS_ShporaCleanupOldRootFiles()

function MS_ShporaReadFile(path)
    local f = io.open(tostring(path or ''), 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    if not data then return nil end
    data = data:gsub('^\239\187\191', '')
    return data
end

function MS_ShporaFormatNumber(num)
    num = tonumber(num) or 0
    local s = tostring(math.floor(num))
    local out = s
    while true do
        local changed
        out, changed = out:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
        if changed == 0 then break end
    end
    return out
end

function MS_ShporaPriceText(num)
    return MS_ShporaFormatNumber(num) .. '$'
end

function MS_ShporaParsePrice(raw)
    raw = tostring(raw or '')
    local digits = raw:gsub('[^%d]', '')
    local num = tonumber(digits)
    return num
end

MS_ECP_SERVER_FALLBACKS = MS_ECP_SERVER_FALLBACKS or {
    blue = { mvd = 1, pravo = 3000, mz = 3000, mo = 3000, smi = 3000, civil = 800, private = 3000, lkn = 3000, yakuza = 3000, rm = 3000, gangs = 2500, surgery = 50000, gender = 5000, heal = 300, ambulance = 300 },
    green = { mvd = 1000, pravo = 1000, mz = 1000, mo = 1000, smi = 1000, civil = 1000, private = 2000, lkn = 2000, yakuza = 2000, rm = 2000, gangs = 2000, surgery = 2000, gender = 50000, heal = 300, ambulance = 300 },
    red = { mvd = 250, pravo = 250, mz = 0, mo = 250, smi = 250, civil = 250, private = 250, lkn = 250, yakuza = 250, rm = 250, gangs = 250, surgery = 2000, gender = 10000, heal = 300, ambulance = 300 },
    lime = { mvd = 250, pravo = 250, mz = 250, mo = 250, smi = 250, civil = 250, private = 250, lkn = 250, yakuza = 250, rm = 250, gangs = 250, surgery = 5000, gender = 10000, heal = 300, ambulance = 300 },
    chocolate = { mvd = 1000, pravo = 1000, mz = 500, mo = 1000, smi = 1500, civil = 500, private = 2000, lkn = 2000, yakuza = 2000, rm = 2000, gangs = 2000, surgery = 5000, gender = 10000, heal = 300, ambulance = 300 }
}

function MS_ECPApplyServerFallbackPrices(key)
    cfg.prices = cfg.prices or {}
    key = MS_ShporaNormalizeServerKey(key or (MS_ShporaCurrentServerKey and MS_ShporaCurrentServerKey()) or 'green') or 'green'
    MS_ECP_FALLBACK_TMP = MS_ECP_SERVER_FALLBACKS[key] or MS_ECP_SERVER_FALLBACKS.green
    for MS_ECP_FALLBACK_K, MS_ECP_FALLBACK_V in pairs(MS_ECP_FALLBACK_TMP) do
        cfg.prices[MS_ECP_FALLBACK_K] = MS_ECP_FALLBACK_V
        if price and price[MS_ECP_FALLBACK_K] then price[MS_ECP_FALLBACK_K][0] = tonumber(MS_ECP_FALLBACK_V) or 0 end
    end
    cfg.prices.heal = 300
    cfg.prices.ambulance = 300
    if price then
        if price.heal then price.heal[0] = 300 end
        if price.ambulance then price.ambulance[0] = 300 end
        if price.lkn and cfg.prices.lkn then price.lkn[0] = cfg.prices.lkn end
        if price.yakuza and cfg.prices.yakuza then price.yakuza[0] = cfg.prices.yakuza end
        if price.rm and cfg.prices.rm then price.rm[0] = cfg.prices.rm end
    end
    if MS_ShporaRefreshECPDisplay then MS_ShporaRefreshECPDisplay() end
    return true
end

-- Старое имя оставлено для совместимости, но теперь это только серверный fallback.
-- GitHub/кэш всё равно имеют приоритет и накладываются поверх него.
function MS_ECPForceServerPrices()
    return MS_ECPApplyServerFallbackPrices(MS_ShporaCurrentServerKey and MS_ShporaCurrentServerKey() or 'green')
end

function MS_ShporaRefreshECPDisplay()
    cfg.prices = cfg.prices or {}
    -- Важно: цены организаций берём из GitHub/кэша.
    -- Старый MS_ECPForceServerPrices() больше не вызываем, чтобы он не перебивал mo/mvd/smi и другие значения.
    -- Лечение в карете на Advance всегда 300$ для всех.
    cfg.prices.ambulance = 300
    cfg.prices.heal = 300
    if price then
        if price.ambulance then price.ambulance[0] = 300 end
        if price.heal then price.heal[0] = 300 end
    end

    MS_ECP_DISPLAY.mvd = tonumber(cfg.prices.mvd) or 1
    MS_ECP_DISPLAY.pravo = tonumber(cfg.prices.pravo) or 3000
    MS_ECP_DISPLAY.mz = tonumber(cfg.prices.mz) or 3000
    MS_ECP_DISPLAY.mo = tonumber(cfg.prices.mo) or 3000
    MS_ECP_DISPLAY.smi = tonumber(cfg.prices.smi) or 3000
    MS_ECP_DISPLAY.civil = tonumber(cfg.prices.civil) or 800
    MS_ECP_DISPLAY.ambulance = 300
    MS_ECP_DISPLAY.private = tonumber(cfg.prices.private) or tonumber(cfg.prices.lkn) or 3000
    MS_ECP_DISPLAY.gangs = tonumber(cfg.prices.gangs) or 2500
    MS_ECP_DISPLAY.surgery = tonumber(cfg.prices.surgery) or 50000
    MS_ECP_DISPLAY.gender = tonumber(cfg.prices.gender) or 5000
    MS_ECP_DISPLAY.heal = 300
end

function MS_ShporaSetPriceKey(key, num)
    key = tostring(key or ''):lower()
    num = tonumber(num)
    if not num then return false end
    cfg.prices = cfg.prices or {}

    if key == 'private' then
        cfg.prices.private = num
        cfg.prices.lkn = num
        cfg.prices.yakuza = num
        cfg.prices.rm = num
        if price.lkn then price.lkn[0] = num end
        if price.yakuza then price.yakuza[0] = num end
        if price.rm then price.rm[0] = num end
    elseif key == 'heal' or key == 'ambulance' then
        -- Эти ключи не берём из ЕЦП: лечение в карете фиксированно 300$.
        cfg.prices[key] = 300
        if price[key] then price[key][0] = 300 end
        num = 300
    elseif key == 'lkn' or key == 'yakuza' or key == 'rm' or key == 'mvd' or key == 'pravo' or key == 'mz' or key == 'mo' or key == 'smi' or key == 'civil' or key == 'gangs' then
        cfg.prices[key] = num
        if price[key] then price[key][0] = num end
    elseif key == 'surgery' or key == 'gender' then
        cfg.prices[key] = num
    else
        return false
    end

    MS_ECP_DISPLAY[key] = num
    return true
end

function MS_ShporaNormalizeECPKey(key)
    key = MS_ShporaRuLower(key)
    key = key:gsub('ё', 'е')
    key = key:gsub('^%s+', ''):gsub('%s+$', '')
    key = key:gsub('^%d+%.%d+%.%s*', ''):gsub('^%d+%.%s*', '')
    key = key:gsub('^[•%-—]%s*', '')
    key = key:gsub('_', ' '):gsub('%-', ' '):gsub('—', ' '):gsub('–', ' ')
    key = key:gsub('[,%;%.]+%s*$', '')
    key = key:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')

    local aliases = {
        ['mvd']='mvd', ['мвд']='mvd', ['министерство внутренних дел']='mvd',
        ['pravo']='pravo', ['право']='pravo', ['правительство']='pravo',
        ['mz']='mz', ['мз']='mz', ['министерство здравоохранения']='mz',
        ['mo']='mo', ['мо']='mo', ['министерство обороны']='mo',
        ['smi']='smi', ['сми']='smi', ['средства массовой информации']='smi', ['средство массовой информации']='smi',
        ['civil']='civil', ['граждане']='civil', ['нетрудоустроенные граждане']='civil', ['нетрудоустроенные граждане штата']='civil', ['безработные граждане штата']='civil',
        ['private']='private', ['частные компании']='private', ['мафии']='private',
        ['lkn']='lkn', ['лкн']='lkn', ['la cosa nostra']='lkn',
        ['yakuza']='yakuza', ['якудза']='yakuza',
        ['rm']='rm', ['рм']='rm', ['russian mafia']='rm',
        ['gangs']='gangs', ['банды']='gangs', ['спортивные клубы']='gangs',
        ['surgery']='surgery', ['хирургические вмешательства']='surgery', ['операция любого вида']='surgery', ['другие операции']='surgery', ['остальные операции']='surgery',
        ['gender']='gender', ['смена пола']='gender', ['операция по смене пола']='gender', ['операция по смене гендерной принадлежности']='gender',
        ['heal']='heal', ['скорая']='heal', ['лечение']='heal',
        ['ambulance']='ambulance', ['в карете']='ambulance', ['лечение в карете']='ambulance', ['оказание медицинской помощи в карете скорой помощи']='ambulance'
    }
    if aliases[key] then return aliases[key] end

    if key:find('внутренних дел', 1, true) then return 'mvd' end
    if key:find('правитель', 1, true) then return 'pravo' end
    if key:find('здравоохран', 1, true) then return 'mz' end
    if key:find('обороны', 1, true) then return 'mo' end
    if key:find('массовой информации', 1, true) or key:find('сми', 1, true) then return 'smi' end
    if key:find('нетрудоустро', 1, true) or key:find('безработ', 1, true) then return 'civil' end
    if key:find('частн', 1, true) or key:find('la cosa', 1, true) or key:find('yakuza', 1, true) or key:find('russian mafia', 1, true) then return 'private' end
    if key:find('спортив', 1, true) or key:find('vagos', 1, true) or key:find('ballas', 1, true) or key:find('aztec', 1, true) or key:find('rifa', 1, true) or key:find('groove', 1, true) then return 'gangs' end

    if key:find('карет', 1, true) then return 'ambulance' end
    if key:find('смен', 1, true) and key:find('пол', 1, true) then return 'gender' end
    if key:find('операц', 1, true) then return 'surgery' end
    if key:find('все жители', 1, true) or key:find('всех граждан', 1, true) or key:find('граждан штата', 1, true) then return 'civil' end
    if key:find('лечение', 1, true) then return 'heal' end

    return nil
end

function MS_ShporaExtractECPPair(line)
    line = tostring(line or ''):gsub(string.char(13), '')
    line = line:gsub('^%s+', ''):gsub('%s+$', '')
    if line == '' then return nil, nil end

    local key, value = line:match('^%s*[•%-—]?%s*(.-)%s*[=:]%s*([%d%.%s]+)%s*%$?')
    if key and value then return key, value end

    key, value = line:match('^%s*[•%-—]?%s*(.-)%s*[%-—–]%s*([%d%.%s]+)%s*%$?')
    if key and value then return key, value end

    return nil, nil
end

function MS_ShporaApplyECPText(text)
    local source = tostring(text or '')
    local count = 0
    for line in (source:gsub(string.char(13), '') .. '\n'):gmatch('([^\n]*)\n') do
        MS_SHPORA_TMP_KEY, MS_SHPORA_TMP_VALUE = MS_ShporaExtractECPPair(line)
        if MS_SHPORA_TMP_KEY and MS_SHPORA_TMP_VALUE then
            MS_SHPORA_TMP_NUM = MS_ShporaParsePrice(MS_SHPORA_TMP_VALUE)
            MS_SHPORA_TMP_LOW = MS_ShporaRuLower(MS_SHPORA_TMP_KEY):gsub('ё', 'е')
            MS_SHPORA_TMP_SKIP = MS_SHPORA_TMP_LOW:find('воскресенье', 1, true) or MS_SHPORA_TMP_LOW:find('день здоровья', 1, true) or MS_SHPORA_TMP_LOW:find('выходн', 1, true)

            if MS_SHPORA_TMP_NUM and not MS_SHPORA_TMP_SKIP then
                MS_SHPORA_TMP_NORM = MS_ShporaNormalizeECPKey(MS_SHPORA_TMP_KEY)
                if MS_SHPORA_TMP_NORM and MS_ShporaSetPriceKey(MS_SHPORA_TMP_NORM, MS_SHPORA_TMP_NUM) then
                    count = count + 1
                end

                if MS_SHPORA_TMP_LOW:find('стандартное лечение', 1, true) or MS_SHPORA_TMP_LOW:find('все жители', 1, true) or MS_SHPORA_TMP_LOW:find('всех граждан', 1, true) then
                    if MS_ShporaSetPriceKey('civil', MS_SHPORA_TMP_NUM) then count = count + 1 end
                    -- heal/ambulance не меняем из ЕЦП: лечение в карете фиксированно 300$.
                end
                if MS_SHPORA_TMP_LOW:find('карет', 1, true) then
                    if MS_ShporaSetPriceKey('ambulance', MS_SHPORA_TMP_NUM) then count = count + 1 end
                end
            end
        end
    end

    MS_ShporaRefreshECPDisplay()
    if count > 0 then save() end
    return count
end

function MS_ShporaUpdateUstavText(text)
    text = tostring(text or ''):gsub('^\239\187\191', '')
    if #text < 50 then return false end
    if not text:find('%[1%.') and not text:find('1%.%s') and not text:find('ГЛАВА') and not text:find('Глава') then return false end
    MS_USTAV_TEXT = text
    return true
end

function MS_ShporaLoadCache()
    MS_ShporaUpdateServerFiles()
    if MS_ECPApplyServerFallbackPrices then
        MS_ECPApplyServerFallbackPrices(MS_ShporaCurrentServerKey())
    end
    local ecp = MS_ShporaReadFile(MS_ECP_CACHE_FILE)
    if ecp and #ecp > 5 then
        MS_ShporaApplyECPText(ecp)
    else
        MS_ShporaRefreshECPDisplay()
    end
    local ustav = MS_ShporaReadFile(MS_USTAV_CACHE_FILE)
    if ustav and #ustav > 50 then
        MS_ShporaUpdateUstavText(ustav)
    end
end

MS_ShporaRefreshECPDisplay()
MS_ShporaLoadCache()
MS_SHPORA_LAST_APPLIED_SERVER = MS_ShporaCurrentServerKey()

function MS_ShporaEnsureServerCache()
    MS_SHPORA_TMP_CURRENT = MS_ShporaCurrentServerKey()
    if tostring(MS_SHPORA_TMP_CURRENT or '') ~= tostring(MS_SHPORA_LAST_APPLIED_SERVER or '') then
        MS_SHPORA_LAST_APPLIED_SERVER = MS_SHPORA_TMP_CURRENT
        MS_ShporaLoadCache()
    end
end

function MS_ShporaProcessDownloadedText(kind, data)
    data = tostring(data or ''):gsub('^\239\187\191', '')
    if kind == 'ustav' then
        if MS_ShporaUpdateUstavText(data) then
            MS_SHPORA_STATUS = 'Устав ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ' обновлён. Последнее обновление: ' .. os.date('%d.%m.%Y %H:%M:%S')
            helper_msg(MS_SHPORA_STATUS)
            return true
        end
        MS_SHPORA_STATUS = 'Ошибка: ustav.txt имеет неверный формат.'
        helper_msg(MS_SHPORA_STATUS)
        return false
    end

    local count = MS_ShporaApplyECPText(data)
    if count > 0 then
        MS_SHPORA_STATUS = 'ЕЦП ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ' обновлена. Цен обновлено: ' .. tostring(count) .. '. Последнее обновление: ' .. os.date('%d.%m.%Y %H:%M:%S')
        helper_msg(MS_SHPORA_STATUS)
        return true
    end

    MS_SHPORA_STATUS = 'Ошибка: ecp.txt не содержит цен формата ключ=цена.'
    helper_msg(MS_SHPORA_STATUS)
    return false
end


function MS_ShporaBase64Decode(data)
    data = tostring(data or ''):gsub('%s+', '')
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local out = {}
    local buffer = 0
    local bits = 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c == '=' then break end
        local p = chars:find(c, 1, true)
        if p then
            buffer = buffer * 64 + (p - 1)
            bits = bits + 6
            while bits >= 8 do
                bits = bits - 8
                local byte = math.floor(buffer / (2 ^ bits)) % 256
                table.insert(out, string.char(byte))
                buffer = buffer % (2 ^ bits)
            end
        end
    end
    return table.concat(out)
end

function MS_ShporaExtractGitHubApiContent(data)
    data = tostring(data or '')
    if not data:find('"content"', 1, true) then return nil end
    if not data:find('"encoding"', 1, true) then return nil end
    local content = data:match('"content"%s*:%s*"([^"]+)"')
    if not content or content == '' then return nil end
    content = content:gsub('\\n', ''):gsub('\\r', ''):gsub('%s+', '')
    local decoded = MS_ShporaBase64Decode(content)
    if decoded and #decoded > 5 then return decoded end
    return nil
end

function MS_ShporaWriteFile(path, data)
    local f = io.open(tostring(path or ''), 'wb')
    if not f then return false end
    f:write(tostring(data or ''))
    f:close()
    return true
end

function MS_ShporaDownloadText(url, path, min_len)
    url = tostring(url or '')
    path = tostring(path or '')
    min_len = tonumber(min_len) or 5
    local last_status = -1
    MS_ShporaBaseDir()
    os.remove(path)
    downloadUrlToFile(url, path, function(id, status)
        last_status = status
    end)

    local data = nil
    local last_size = -1
    local stable_ticks = 0
    for i = 1, 120 do
        wait(250)
        data = MS_ShporaReadFile(path)
        local size = data and #data or 0
        if size > min_len then
            if size == last_size then
                stable_ticks = stable_ticks + 1
            else
                stable_ticks = 0
                last_size = size
            end
            if stable_ticks >= 2 then break end
        end
    end
    data = MS_ShporaReadFile(path)
    return data, last_status
end

function MS_ShporaTryDownloadKind(kind, api_url, raw_url, path, title)
    local api_path = path .. '.api'
    local raw_path = path .. '.raw'

    MS_SHPORA_STATUS = 'Загружаю ' .. title .. ' для ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. '...'
    helper_msg(MS_SHPORA_STATUS)

    local api_dl = tostring(api_url or '') .. '&nocache=' .. tostring(os.time()) .. tostring(math.random(10000, 99999))
    local api_data, api_status = MS_ShporaDownloadText(api_dl, api_path, 20)
    local decoded = MS_ShporaExtractGitHubApiContent(api_data)

    if decoded and #decoded > 5 then
        MS_ShporaWriteFile(path, decoded)
        return MS_ShporaProcessDownloadedText(kind, decoded)
    end

    MS_SHPORA_STATUS = 'GitHub API не отдал текст, пробую Raw...'
    helper_msg(MS_SHPORA_STATUS)

    local raw_dl = tostring(raw_url or '') .. '?nocache=' .. tostring(os.time()) .. tostring(math.random(10000, 99999))
    local raw_data, raw_status = MS_ShporaDownloadText(raw_dl, raw_path, 5)

    if raw_data and #raw_data > 5 then
        MS_ShporaWriteFile(path, raw_data)
        return MS_ShporaProcessDownloadedText(kind, raw_data)
    end

    MS_SHPORA_LAST_API_STATUS = api_status
    MS_SHPORA_LAST_RAW_STATUS = raw_status
    return false
end

function MS_ShporaDoDownload(kind)
    MS_ShporaUpdateServerFiles()
    local path = (kind == 'ustav') and MS_USTAV_CACHE_FILE or MS_ECP_CACHE_FILE
    local title = (kind == 'ustav') and 'Устав' or 'ЕЦП'

    -- Берём строго серверный файл из GitHub:
    -- main/red|green|blue|lime|chocolate/ecp.txt или ustav.txt.
    if MS_ShporaTryDownloadKind(kind, MS_ShporaServerApiUrl(kind), MS_ShporaServerRawUrl(kind), path, title) then
        return true
    end

    MS_SHPORA_STATUS = 'Ошибка загрузки ' .. title .. ' для ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ': проверьте файл ' .. MS_ShporaGithubFolder(MS_ShporaCurrentServerKey()) .. '/' .. tostring(kind) .. '.txt в GitHub. API код ' .. tostring(MS_SHPORA_LAST_API_STATUS) .. ', Raw код ' .. tostring(MS_SHPORA_LAST_RAW_STATUS)
    helper_msg(MS_SHPORA_STATUS)
    return false
end

function MS_ShporaDownloadOne(kind)
    if MS_SHPORA_DOWNLOADING then helper_msg('Обновление уже выполняется.'); return end
    MS_SHPORA_DOWNLOADING = true
    lua_thread.create(function()
        MS_ShporaDoDownload(kind)
        MS_SHPORA_DOWNLOADING = false
    end)
end

function MS_ShporaUpdateAll()
    if MS_SHPORA_DOWNLOADING then helper_msg('Обновление уже выполняется.'); return end
    MS_SHPORA_DOWNLOADING = true
    lua_thread.create(function()
        MS_ShporaDoDownload('ecp')
        wait(700)
        MS_ShporaDoDownload('ustav')
        MS_SHPORA_DOWNLOADING = false
    end)
end

function MS_ShporaOpenTab()
    MS_ShporaTab = 1
    active_tab = 6
    main_window[0] = true
end

function MS_ECPOpenTab()
    MS_ShporaTab = 1
    active_tab = 6
    main_window[0] = true
end

function MS_UstavOpenTab()
    MS_ShporaTab = 2
    active_tab = 6
    main_window[0] = true
end

function MS_ECPShowChat()
    helper_msg('ЕЦП: МВД ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.mvd) .. ', Правительство ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.pravo) .. ', МЗ ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.mz) .. ', СМИ ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.smi) .. '.')
    helper_msg('Граждане ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.civil) .. ', частные компании ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.private) .. ', спортклубы ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.gangs) .. ', карета ' .. MS_ShporaPriceText(MS_ECP_DISPLAY.ambulance) .. '.')
end

function MS_UstavShowChat()
    helper_msg('Устав МЗ загружен в шпаргалку. Откройте /ustav или вкладку Шпаргалки → Устав.')
end

function MS_DrawECPQuickPrices()
    if MS_ShporaEnsureServerCache then MS_ShporaEnsureServerCache() end
    MS_ShporaRefreshECPDisplay()
    imgui.TextColored(MSHelper_AccentColor(), 'ЕЦП — цены для игроков | ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()))
    imgui.TextWrapped('Данные берутся из GitHub и применяются к ценам лечения MSHelper.')
    imgui.Separator()

    local rows = {
        {'Министерство внутренних дел', MS_ECP_DISPLAY.mvd},
        {'Правительство', MS_ECP_DISPLAY.pravo},
        {'Министерство здравоохранения', MS_ECP_DISPLAY.mz},
        {'Министерство обороны', MS_ECP_DISPLAY.mo},
        {'Средства массовой информации', MS_ECP_DISPLAY.smi},
        {'Нетрудоустроенные граждане', MS_ECP_DISPLAY.civil},
        {'Частные компании: La Cosa Nostra, Yakuza, Russian Mafia', MS_ECP_DISPLAY.private},
        {'Спортивные клубы: Vagos, Ballas, Aztec, Rifa, Groove', MS_ECP_DISPLAY.gangs}
    }
    imgui.TextColored(MSHelper_AccentColor(), 'Цены по организациям')
    for _, row in ipairs(rows) do
        imgui.BulletText(row[1])
        imgui.SameLine(520)
        imgui.TextColored(imgui.ImVec4(0.25,0.95,0.45,1), MS_ShporaPriceText(row[2]))
    end

    imgui.Separator()
    imgui.TextColored(MSHelper_AccentColor(), 'Дополнительные услуги')
    local services = {
        {'Лечение в карете', MS_ECP_DISPLAY.ambulance},
        {'Хирургические вмешательства', MS_ECP_DISPLAY.surgery},
        {'Операция по смене гендерной принадлежности', MS_ECP_DISPLAY.gender}
    }
    for _, row in ipairs(services) do
        imgui.BulletText(row[1])
        imgui.SameLine(520)
        imgui.TextColored(imgui.ImVec4(0.25,0.95,0.45,1), MS_ShporaPriceText(row[2]))
    end

    imgui.Spacing()
    if imgui.Button('Вывести ЕЦП в чат', imgui.ImVec2(190, 32)) then MS_ECPShowChat() end
    imgui.SameLine()
    if imgui.Button('Открыть цены MSHelper', imgui.ImVec2(210, 32)) then active_tab = 1 end
    imgui.SameLine()
    if imgui.Button('Обновить ЕЦП онлайн', imgui.ImVec2(210, 32)) then MS_ShporaDownloadOne('ecp') end
end

function MS_DrawUstavQuickRules()
    imgui.TextColored(MSHelper_AccentColor(), 'Устав МЗ | ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()))
    imgui.TextWrapped('Полный устав из ustav.txt. Разделы читаются в формате [1. Название] и пункты ниже.')
    imgui.Separator()

    for line in (tostring(MS_USTAV_TEXT or ''):gsub('\r', '') .. '\n'):gmatch('([^\n]*)\n') do
        local s = tostring(line or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then
            if s:sub(1,1) == '[' and s:sub(-1) == ']' then
                imgui.Spacing()
                imgui.TextColored(MSHelper_AccentColor(), s:sub(2, -2))
            elseif s:find('^version=') then
                imgui.TextDisabled('Версия: ' .. s:gsub('^version=', ''))
            else
                imgui.TextWrapped(s)
            end
        end
    end

    imgui.Separator()
    if imgui.Button('Вывести кратко в чат', imgui.ImVec2(190, 32)) then MS_UstavShowChat() end
    imgui.SameLine()
    if imgui.Button('Обновить Устав онлайн', imgui.ImVec2(220, 32)) then MS_ShporaDownloadOne('ustav') end
end

function MS_ShporaDrawServerSelector()
    imgui.TextColored(MSHelper_AccentColor(), 'Сервер шпаргалок')
    imgui.TextWrapped('Авто выбирает ЕЦП/Устав по текущему серверу. При смене сервера цены сразу переключаются на кэш/резерв выбранного сервера. Если авто не сработало — выберите сервер вручную.')
    imgui.TextWrapped('Определено: ' .. tostring(MS_ShporaServerNameRaw() ~= '' and MS_ShporaServerNameRaw() or 'неизвестно') .. ' | используется: ' .. MS_ShporaServerLabel(MS_ShporaCurrentServerKey()) .. ' (' .. MS_ShporaModeText() .. ')')

    if imgui.Selectable('Авто по серверу##shpora_server_auto', tostring(cfg.shpora and cfg.shpora.server_mode or 'auto') ~= 'manual', 0, imgui.ImVec2(170, 28)) then
        MS_ShporaSetServerMode('auto')
    end
    imgui.SameLine()
    if imgui.Selectable('Ручной выбор##shpora_server_manual', tostring(cfg.shpora and cfg.shpora.server_mode or 'auto') == 'manual', 0, imgui.ImVec2(170, 28)) then
        MS_ShporaSetServerMode('manual', MS_ShporaCurrentServerKey())
    end

    for MS_SHPORA_TMP_I, MS_SHPORA_TMP_ROW in ipairs(MS_SHPORA_SERVERS) do
        if MS_SHPORA_TMP_I > 1 and ((MS_SHPORA_TMP_I - 1) % 5) ~= 0 then imgui.SameLine() end
        if imgui.Selectable(MS_SHPORA_TMP_ROW[2] .. '##shpora_server_' .. MS_SHPORA_TMP_ROW[1], MS_ShporaCurrentServerKey() == MS_SHPORA_TMP_ROW[1], 0, imgui.ImVec2(115, 26)) then
            MS_ShporaSetServerMode('manual', MS_SHPORA_TMP_ROW[1])
        end
    end
    imgui.Separator()
end

function MS_DrawShporaTab()
    if MS_ShporaEnsureServerCache then MS_ShporaEnsureServerCache() end
    imgui.TextColored(MSHelper_AccentColor(), 'Шпаргалки МЗ')
    imgui.TextWrapped('ЕЦП и полный Устав под каждый сервер Advance.')
    imgui.Separator()

    MS_ShporaDrawServerSelector()

    if imgui.Selectable('ЕЦП', MS_ShporaTab == 1, 0, imgui.ImVec2(120, 30)) then MS_ShporaTab = 1 end
    imgui.SameLine()
    if imgui.Selectable('Устав', MS_ShporaTab == 2, 0, imgui.ImVec2(120, 30)) then MS_ShporaTab = 2 end
    imgui.SameLine()
    if imgui.Button('Обновить онлайн', imgui.ImVec2(170, 30)) then MS_ShporaUpdateAll() end

    imgui.TextWrapped('Статус: ' .. tostring(MS_SHPORA_STATUS or 'нет данных'))
    imgui.TextWrapped('Кэш этого сервера: moonloader\\MSHelper\\temp\\ecp_cache_' .. MS_ShporaCurrentServerKey() .. '.txt / ustav_cache_' .. MS_ShporaCurrentServerKey() .. '.txt')
    imgui.TextColored(imgui.ImVec4(0.95,0.75,0.25,1), 'Для обновления текущего сервера: /shupdate. Выбор сервера: /shserver auto.')
    imgui.Separator()
    imgui.BeginChild('##shpora_scroll', imgui.ImVec2(0, 0), false)
    if MS_ShporaTab == 1 then MS_DrawECPQuickPrices() else MS_DrawUstavQuickRules() end
    imgui.EndChild()
end

local function draw_commands_tab()
    imgui.TextColored(MSHelper_AccentColor(), 'Команды скрипта')
    imgui.TextWrapped('Здесь собраны команды MS Helper и краткое описание того, что они делают.')
    imgui.Separator()

    local function section(title)
        imgui.Spacing()
        imgui.TextColored(MSHelper_AccentColor(), title)
    end

    local function cmd(name, desc)
        imgui.BulletText(name)
        imgui.SameLine(170)
        imgui.TextWrapped(desc)
    end

    imgui.BeginChild('commands_list', imgui.ImVec2(0, 0), false)

    section('Основное')
    cmd('/ms', 'Открыть или закрыть главное меню MSHelper.')
    cmd('/mgos', 'Меню для госновостей для Лидеров.')
    cmd('/drone', 'Включит свободную камеру -+ Скорость передвежение w/a/s/d shift - вниз')
	cmd('/mshome id ', 'Вводите id Дома для вызова метка стандартная из GTA')
	cmd('/mshome off ', 'Выключить метку на дом поле как вызов закончили или просто через карту убрать.')

    section('Реконнект')
    cmd('/rec [сек]', 'Ручной реконнект. Пример: /rec 5 или просто /rec')
	
    section('Склад')
    cmd('/medinfo', 'Показать текущее состояние склада в чат.')
    cmd('/medrn', 'Отправить состояние склада и нужное количество ящиков в /rn.')

    section('Шпаргалки')
    cmd('/shupdate', 'Обновить ЕЦП и Устав для выбранного сервера.')
    cmd('/shserver auto', 'Автоопределение или ручной сервер шпаргалок.')

    section('Работа с пациентами и организациями')
    cmd('ПКМ + G', 'Открыть мини-меню взаимодействия с пациентом, если вы навелись на игрока.')
    cmd('/heal id [цена]', 'Лечение в карете.+RP')
    cmd('/to id', 'Принять вызов.+RP')
	
    section('Техническое')
	    cmd('/msname auto','Если Скрипт указывает не ваш ник: данная команда поможет использувать ваш для Начало лечение "Привествие"' )
	
    section('Руководство и сотрудники')
    cmd('/mfind', 'Открыть кастомный /find сотрудников, если функция включена в Основном.')
    cmd('/mwhere id', 'Сразу отправить сотруднику вызов в /r.')
    cmd('/ok id', 'Принять доклад сотрудника в /r. R-тег добавится автоматически, если включен.')
    cmd('/invite', 'Открывается меню, где можно указать ID и принять сотрудника с RP и оповещением в /r.')
    cmd('/uni', 'Открываеться меню где можете указать id и выбрать причину.')
	cmd('/sobes id ', 'Открывается меню собеседования: паспорт, лицензии, мед.карту и личное дело /show.')
    cmd('/rang', 'Открываеться меню где можете указать id и выбрать понижать или повышать.')
    cmd('/drive', 'Респ Организационный Т/c -1200$. С оповещением в /r')
    cmd('/drive 1', 'Респ Организационный Т/c -1200$. Без оповещения в /r')
	
    imgui.EndChild()
end


-- ===== MS Helper | Кастомный TAB =====
function MSHelper_CustomTabEnabled()
    return false
end

function MSHelper_CustomTabCanUse()
    if not MSHelper_CustomTabEnabled() then return false end
    if samp_text_input_active and samp_text_input_active() then return false end
    if main_window and main_window[0] then return false end
    if gos_window and gos_window[0] then return false end
    if patient_window and patient_window[0] then return false end
    if invite_window and invite_window[0] then return false end
    if uninvite_window and uninvite_window[0] then return false end
    if rang_window and rang_window[0] then return false end
    if interview_window and interview_window[0] then return false end
    return true
end

function MSHelper_CustomTabToggle()
    if not MSH_CUSTOM_TAB_WINDOW then return false end
    local now = os.clock()
    if (MSH_CUSTOM_TAB_LAST_TOGGLE or 0) + 0.18 > now then return false end
    MSH_CUSTOM_TAB_LAST_TOGGLE = now
    MSH_CUSTOM_TAB_WINDOW[0] = not MSH_CUSTOM_TAB_WINDOW[0]
    return true
end

function MSHelper_CustomTabOpen()
    if MSH_CUSTOM_TAB_WINDOW then MSH_CUSTOM_TAB_WINDOW[0] = true end
end

function MSHelper_CustomTabClose()
end

function MSHelper_CustomTabGetLevel(pid)
    if type(sampGetPlayerScore) ~= 'function' then return 0 end
    local ok, score = pcall(sampGetPlayerScore, pid)
    return (ok and tonumber(score)) or 0
end

function MSHelper_CustomTabGetPing(pid)
    if type(sampGetPlayerPing) ~= 'function' then return 0 end
    local ok, ping = pcall(sampGetPlayerPing, pid)
    return (ok and tonumber(ping)) or 0
end


function MSHelper_CustomTabGetPlayerColor(pid)
    -- Цвет берём напрямую из SA-MP TAB: у Advance он обычно приходит как 0xAARRGGBB.
    -- Поэтому используем младшие 24 бита как RR GG BB, как и в автоопределении организаций.
    local default_color = imgui.ImVec4(1.0, 1.0, 1.0, 1.0)
    if type(sampGetPlayerColor) ~= 'function' then return default_color end
    local ok, color = pcall(sampGetPlayerColor, pid)
    if not ok or color == nil then return default_color end
    color = tonumber(color) or 0

    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)

    -- Если вдруг сборка отдаёт цвет в другом формате и вышел почти чёрный цвет,
    -- оставляем белый, чтобы строка не пропадала на тёмной теме.
    if r == 0 and g == 0 and b == 0 then return default_color end

    return imgui.ImVec4(r / 255.0, g / 255.0, b / 255.0, 1.0)
end

function MSHelper_CustomTabMatch(pid, nick, search)
    search = trim(tostring(search or '')):lower()
    if search == '' then return true end
    if tostring(pid):find(search, 1, true) then return true end
    nick = tostring(nick or ''):lower()
    return nick:find(search, 1, true) ~= nil
end


function MSHelper_CustomTabRawNick(pid)
    pid = tonumber(pid)
    if not pid then return nil end
    if type(sampGetPlayerNickname) == 'function' then
        local ok, nick = pcall(sampGetPlayerNickname, pid)
        if ok and nick ~= nil then
            nick = tostring(nick or '')
            if nick ~= '' and nick ~= 'None' and nick ~= 'nil' then return nick end
        end
    end
    return nil
end

function MSHelper_CustomTabGetNick(pid)
    pid = tonumber(pid)
    local nick = MSHelper_CustomTabRawNick(pid)
    if nick then return nick end

    -- Для своей строки даём запасной ник из /msname, если сборка не отдаёт локальный ник через TAB.
    -- Для чужих игроков этот запасной вариант не используем.
    local self_cached = tonumber(MSH_CUSTOM_TAB_SELF_ID)
    if self_cached and pid == self_cached then
        local manual = trim(tostring(cfg and cfg.main and cfg.main.doctor_name or ''))
        if manual ~= '' and manual:lower() ~= 'auto' and manual ~= 'Врач' then
            return manual:gsub(' ', '_')
        end
    end

    return 'Player_' .. tostring(pid)
end

function MSHelper_CustomTabGetSelfId()
    local function valid_id(id)
        id = tonumber(id)
        if not id then return nil end
        if id < 0 or id > 1000 then return nil end
        return id
    end

    -- Основной способ для локального игрока. На разных сборках функция может возвращать:
    --   true, id
    --   id
    --   false, id
    -- Поэтому проверяем оба возвращаемых значения, но не принимаем false, 0 как свой ID.
    if type(sampGetPlayerIdByCharHandle) == 'function' and PLAYER_PED then
        local ok, a, b = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
        if ok then
            local id = nil
            if type(a) == 'boolean' then
                if a == true then
                    id = valid_id(b)
                elseif valid_id(b) and tonumber(b) ~= 0 then
                    -- Некоторые сборки для локального игрока возвращают false, id.
                    id = valid_id(b)
                end
            else
                id = valid_id(a) or valid_id(b)
            end
            if id then
                MSH_CUSTOM_TAB_SELF_ID = id
                return id
            end
        end
    end

    -- Запасные функции, если они есть в сборке.
    for _, fn_name in ipairs({'sampGetLocalPlayerId', 'sampGetPlayerId'}) do
        local fn = _G[fn_name]
        if type(fn) == 'function' then
            local ok, a, b = pcall(fn)
            if ok then
                local id = valid_id(a) or valid_id(b)
                if id then
                    MSH_CUSTOM_TAB_SELF_ID = id
                    return id
                end
            end
        end
    end

    -- Поиск по char-handle. Не используем sampIsPlayerConnected для своего ID,
    -- потому что на части сборок локальный игрок не считается подключённым в remote-пуле.
    if type(sampGetCharHandleBySampPlayerId) == 'function' and PLAYER_PED then
        for pid = 0, 1000 do
            local ok, result, ped = pcall(sampGetCharHandleBySampPlayerId, pid)
            if ok then
                local handle = nil
                if type(result) == 'boolean' then
                    if result == true then handle = ped end
                else
                    handle = result
                end
                if handle and tonumber(handle) == tonumber(PLAYER_PED) then
                    MSH_CUSTOM_TAB_SELF_ID = pid
                    return pid
                end
            end
        end
    end

    -- Если уже определяли ID раньше, используем кэш.
    local cached = valid_id(MSH_CUSTOM_TAB_SELF_ID)
    if cached then return cached end

    -- Последний вариант: /msname Nick_Name. Ищем этот ник в TAB.
    local manual = trim(tostring(cfg and cfg.main and cfg.main.doctor_name or ''))
    if manual ~= '' and manual:lower() ~= 'auto' and manual ~= 'Врач' then
        manual = manual:gsub(' ', '_'):lower()
        for pid = 0, 1000 do
            local nick = MSHelper_CustomTabRawNick(pid)
            if nick and tostring(nick):lower() == manual then
                MSH_CUSTOM_TAB_SELF_ID = pid
                return pid
            end
        end
    end

    return nil
end


function MSHelper_CustomTabDrawPlayerRow(pid)
    local nick = MSHelper_CustomTabGetNick and MSHelper_CustomTabGetNick(pid) or (safe_nick(pid) or ('Player_' .. tostring(pid)))
    local lvl = MSHelper_CustomTabGetLevel(pid)
    local ping = MSHelper_CustomTabGetPing(pid)
    local row_color = MSHelper_CustomTabGetPlayerColor(pid)

    -- Координаты совпадают с заголовками ниже.
    imgui.TextColored(row_color, tostring(pid))
    imgui.SameLine(58)
    imgui.TextColored(row_color, tostring(nick))
    imgui.SameLine(420)
    imgui.TextColored(row_color, tostring(lvl))
    imgui.SameLine(520)
    imgui.TextColored(row_color, tostring(ping))
end

function MSHelper_CustomTabCountOnline()
    local total = 0
    local self_id = MSHelper_CustomTabGetSelfId and MSHelper_CustomTabGetSelfId() or nil
    local self_counted = false

    for pid = 0, 1000 do
        if ms_safe_player_connected(pid) then
            total = total + 1
            if self_id and pid == self_id then self_counted = true end
        end
    end

    -- На некоторых сборках локальный игрок не проходит sampIsPlayerConnected,
    -- поэтому добавляем его отдельно, если ID уже определён и он не попал в общий счётчик.
    if self_id and not self_counted then
        total = total + 1
    end

    return total
end

function MSHelper_CustomTabDraw()
    imgui.SetNextWindowSize(imgui.ImVec2(720, 510), imgui.Cond.FirstUseEver)
    imgui.Begin('MS HELPER | Custom TAB', MSH_CUSTOM_TAB_WINDOW, imgui.WindowFlags.NoCollapse)

    imgui.TextColored(MSHelper_AccentColor(), 'Кастомный TAB')
    imgui.SameLine()
    imgui.TextDisabled('TAB или ESC — закрыть')
    imgui.SameLine(500)
    local online_total = MSHelper_CustomTabCountOnline and MSHelper_CustomTabCountOnline() or 0
    imgui.TextColored(MSHelper_AccentColor(), 'Онлайн сервера: ' .. tostring(online_total))

    imgui.PushItemWidth(-120)
    imgui.InputText('##msh_custom_tab_search', MSH_CUSTOM_TAB_SEARCH_BUFFER, 64)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Очистить', imgui.ImVec2(100, 26)) then
        ffi.fill(MSH_CUSTOM_TAB_SEARCH_BUFFER, 64, 0)
    end
    imgui.TextDisabled('Поиск работает по ID или Nick_Name. Цвет строк берётся из обычного SA-MP TAB.')
    imgui.Separator()

    local header_color = MSHelper_AccentColor()
    imgui.TextColored(header_color, 'ID')
    imgui.SameLine(58)
    imgui.TextColored(header_color, 'Nick_Name')
    imgui.SameLine(420)
    imgui.TextColored(header_color, 'LVL')
    imgui.SameLine(520)
    imgui.TextColored(header_color, 'Ping')
    imgui.Separator()

    local search = ''
    if MSH_CUSTOM_TAB_SEARCH_BUFFER then search = ffi.string(MSH_CUSTOM_TAB_SEARCH_BUFFER) end
    local count = 0
    local self_id = MSHelper_CustomTabGetSelfId and MSHelper_CustomTabGetSelfId() or nil

    imgui.BeginChild('##msh_custom_tab_list', imgui.ImVec2(0, 0), true)
    -- Сначала показываем самого игрока. Локальный игрок на некоторых сборках не проходит
    -- sampIsPlayerConnected, поэтому здесь намеренно не проверяем connected.
    if self_id then
        local self_nick = (MSHelper_CustomTabGetNick and MSHelper_CustomTabGetNick(self_id)) or ('Player_' .. tostring(self_id))
        if MSHelper_CustomTabMatch(self_id, self_nick, search) then
            MSHelper_CustomTabDrawPlayerRow(self_id)
            count = count + 1
            imgui.Separator()
        end
    end

    for pid = 0, 1000 do
        if pid ~= self_id and ms_safe_player_connected(pid) then
            local nick = (MSHelper_CustomTabGetNick and MSHelper_CustomTabGetNick(pid)) or (safe_nick(pid) or ('Player_' .. tostring(pid)))
            if MSHelper_CustomTabMatch(pid, nick, search) then
                count = count + 1
                MSHelper_CustomTabDrawPlayerRow(pid)
            end
        end
    end
    if count == 0 then
        imgui.TextDisabled('Игроки не найдены по этому поиску.')
    end
    imgui.EndChild()

    imgui.End()
end


-- ===== MS Helper | Кастомный /find сотрудников =====
function MSHelper_FindCleanText(s)
    s = tostring(s or '')
    s = s:gsub('{%x%x%x%x%x%x}', '')
    s = s:gsub('\r', '')
    return s
end

function MSHelper_FindToUtf8(s)
    s = tostring(s or '')
    if s == '' then return '' end
    if u8 and u8.encode then
        local ok, out = pcall(function() return u8:encode(s) end)
        if ok and out then return out end
    end
    return s
end

function MSHelper_FindContains(raw, needle_utf8)
    raw = MSHelper_FindCleanText(raw):lower()
    needle_utf8 = tostring(needle_utf8 or '')
    local needle = needle_utf8
    if u8 and u8.decode then
        local ok, cp = pcall(function() return u8:decode(needle_utf8) end)
        if ok and cp then needle = cp end
    end
    return raw:find(tostring(needle):lower(), 1, true) ~= nil
end

function MSHelper_IsStaffFindDialog(title, text)
    local raw = MSHelper_FindCleanText(tostring(title or '') .. '\n' .. tostring(text or ''))
    return MSHelper_FindContains(raw, 'В подразделении')
        and MSHelper_FindContains(raw, 'Ранг и должность')
        and MSHelper_FindContains(raw, 'Телефон')
end

function MSHelper_SplitTabLine(line)
    local parts = {}
    line = tostring(line or '')
    for part in (line .. '\t'):gmatch('(.-)\t') do
        table.insert(parts, part)
    end
    return parts
end

function MSHelper_ParseFindStaff(title, text)
    -- Серверный /find приходит в CP1251, а mimgui рисует UTF-8.
    -- Поэтому парсим уже UTF-8-копию, иначе должности отображаются знаками вопроса.
    local raw = MSHelper_FindToUtf8(MSHelper_FindCleanText(tostring(title or '') .. '\n' .. tostring(text or '')))
    local total = raw:match('В подразделении%s+(%d+)%s+чел') or raw:match('В подразделении%s+(%d+)') or '?'
    local online = raw:match('%(онлайн%s+(%d+)%)') or '?'
    local rows = {}

    for line in raw:gmatch('[^\n]+') do
        local clean = line:gsub('^%s+', ''):gsub('%s+$', '')
        local nick, id = clean:match('^%d+%.%s*([^%[%]%s]+)%[(%d+)%]')
        if nick and id then
            local parts = MSHelper_SplitTabLine(clean)
            local first = parts[1] or clean
            local rank = parts[2] or ''
            local phone = parts[3] or ''
            local extra = parts[4] or ''
            -- Если диалог пришёл без табов, пытаемся аккуратно убрать имя из начала.
            if rank == '' then
                rank = clean:gsub('^%d+%.%s*' .. nick:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1') .. '%[' .. id .. '%]%s*', '')
            end
            table.insert(rows, {
                id = tonumber(id) or -1,
                nick = tostring(nick or ''),
                rank = tostring(rank or ''),
                phone = tostring(phone or ''),
                extra = tostring(extra or '')
            })
        end
    end

    return rows, { total = total, online = online }
end

function MSHelper_FindMatch(row, filter)
    filter = tostring(filter or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if filter == '' then return true end
    local hay = table.concat({ tostring(row.id or ''), tostring(row.nick or ''), tostring(row.rank or ''), tostring(row.phone or ''), tostring(row.extra or '') }, ' '):lower()
    return hay:find(filter, 1, true) ~= nil
end

function MSHelper_FindOneLine(s)
    s = tostring(s or '')
    s = s:gsub('\r', ' '):gsub('\n', ' '):gsub('\t', ' ')
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

function MSHelper_FindOpenFromDialog(title, text)
    local rows, meta = MSHelper_ParseFindStaff(title, text)
    if not rows or #rows == 0 then return false end
    MSH_FIND_ROWS = rows
    MSH_FIND_META = meta or { total = '?', online = '?' }
    MSH_FIND_AUTO_REFRESH_NEXT = os.clock() + 15
    if MSH_FIND_STAFF_WINDOW then MSH_FIND_STAFF_WINDOW[0] = true end
    return true
end

function MSHelper_FindCallEmployee(row)
    row = row or MSH_FIND_SELECTED or {}
    local id = tonumber(row.id or -1) or -1
    if id < 0 then if helper_msg then helper_msg('ID сотрудника не найден.') end; return false end
    -- Используем внутреннюю логику /mwhere из MS Helper, чтобы не открывать лишние серверные окна.
    if send_where_radio then
        send_where_radio(id)
    else
        sampSendChat('/mwhere ' .. tostring(id))
    end
    if helper_msg then helper_msg('Вызов сотрудника отправлен: ' .. tostring(row.nick or ('ID ' .. id)) .. ' [' .. tostring(id) .. '].') end
    return true
end

function MSHelper_FindOkReport(row)
    row = row or MSH_FIND_SELECTED or {}
    local id = tonumber(row.id or -1) or -1
    if id < 0 then if helper_msg then helper_msg('ID сотрудника не найден.') end; return false end
    if _G.MSHelper_SendOkReport then
        _G.MSHelper_SendOkReport(tostring(id))
    else
        sampSendChat('/ok ' .. tostring(id))
    end
    return true
end

function MSHelper_FindSelectRow(row)
    MSH_FIND_SELECTED = {
        id = tonumber(row.id or -1) or -1,
        nick = tostring(row.nick or ''),
        rank = tostring(row.rank or ''),
        phone = tostring(row.phone or ''),
        extra = tostring(row.extra or '')
    }
    if MSH_FIND_ACTION_WINDOW then MSH_FIND_ACTION_WINDOW[0] = true end
end

function MSHelper_FindAutoRefreshTick()
    if not (MSH_CUSTOM_FIND_ENABLED and MSH_CUSTOM_FIND_ENABLED[0]) then return end
    if not (MSH_FIND_STAFF_WINDOW and MSH_FIND_STAFF_WINDOW[0]) then return end
    if MSH_FIND_AUTO_REFRESH_BUSY == true then return end
    if (tonumber(MSH_FIND_AUTO_REFRESH_NEXT) or 0) > os.clock() then return end

    MSH_FIND_AUTO_REFRESH_BUSY = true
    MSH_FIND_AUTO_REFRESH_NEXT = os.clock() + 15
    lua_thread.create(function()
        MSH_FIND_EXPECT_UNTIL = os.clock() + 6
        sampSendChat('/find')
        wait(1200)
        MSH_FIND_AUTO_REFRESH_BUSY = false
    end)
end

function MSHelper_DrawFindStaffWindow()
    if MSHelper_FindAutoRefreshTick then MSHelper_FindAutoRefreshTick() end
    imgui.SetNextWindowSize(imgui.ImVec2(760, 500), imgui.Cond.FirstUseEver)
    imgui.Begin('MS Helper | Сотрудники /find', MSH_FIND_STAFF_WINDOW, imgui.WindowFlags.NoCollapse)

    imgui.TextColored(MSHelper_AccentColor(), 'Онлайн: ' .. tostring(MSH_FIND_META.online or '?'))
    imgui.Separator()

    local filter = ''
    imgui.BeginChild('##msh_find_staff_list', imgui.ImVec2(0, -42), true)
    imgui.Columns(4, 'msh_find_staff_columns', false)
    imgui.SetColumnWidth(0, 230)
    imgui.SetColumnWidth(1, 285)
    imgui.SetColumnWidth(2, 90)
    imgui.SetColumnWidth(3, 140)
    imgui.TextColored(MSHelper_AccentColor(), 'Имя')
    imgui.NextColumn(); imgui.TextColored(MSHelper_AccentColor(), 'Ранг и должность')
    imgui.NextColumn(); imgui.TextColored(MSHelper_AccentColor(), 'Телефон')
    imgui.NextColumn(); imgui.TextColored(MSHelper_AccentColor(), 'Дополнительно')
    imgui.NextColumn(); imgui.Separator()

    local shown = 0
    for _, row in ipairs(MSH_FIND_ROWS or {}) do
        if MSHelper_FindMatch(row, filter) then
            shown = shown + 1
            local label = tostring(row.nick or 'Player') .. '[' .. tostring(row.id or '?') .. ']##msh_find_row_' .. tostring(row.id or shown)
            if imgui.Selectable(label, false) then MSHelper_FindSelectRow(row) end
            imgui.NextColumn()
            imgui.TextWrapped(tostring(row.rank or ''))
            imgui.NextColumn()
            imgui.Text(tostring(row.phone or ''))
            imgui.NextColumn()
            imgui.Text(MSHelper_FindOneLine(row.extra or ''))
            imgui.NextColumn()
        end
    end
    imgui.Columns(1)
    if shown == 0 then imgui.TextDisabled('Сотрудники не найдены по этому поиску.') end
    imgui.EndChild()

    imgui.TextDisabled('Автообновление: раз в 15 секунд, пока окно /find открыто.')
    imgui.SameLine()
    if imgui.Button('Закрыть', imgui.ImVec2(110, 30)) then
        MSH_FIND_STAFF_WINDOW[0] = false
        MSH_FIND_AUTO_REFRESH_NEXT = 0
        MSH_FIND_AUTO_REFRESH_BUSY = false
    end

    imgui.End()
end

function MSHelper_DrawFindActionWindow()
    imgui.SetNextWindowSize(imgui.ImVec2(360, 245), imgui.Cond.FirstUseEver)
    imgui.Begin('MS Helper | Действия сотрудника', MSH_FIND_ACTION_WINDOW, imgui.WindowFlags.NoCollapse)
    local row = MSH_FIND_SELECTED or {}
    local title = tostring(row.nick or 'Сотрудник') .. ' [' .. tostring(row.id or '?') .. ']'
    imgui.TextColored(MSHelper_AccentColor(), title)
    imgui.TextWrapped(tostring(row.rank or ''))
    if tostring(row.phone or '') ~= '' then imgui.Text('Телефон: ' .. tostring(row.phone)) end
    if tostring(row.extra or '') ~= '' then imgui.Text('Дополнительно: ' .. MSHelper_FindOneLine(row.extra)) end
    imgui.Separator()

    if imgui.Button('Позвать игрока', imgui.ImVec2(160, 32)) then
        MSHelper_FindCallEmployee(row)
        MSH_FIND_ACTION_WINDOW[0] = false
    end
    imgui.SameLine()
    if imgui.Button('Принять доклад', imgui.ImVec2(160, 32)) then
        MSHelper_FindOkReport(row)
        MSH_FIND_ACTION_WINDOW[0] = false
    end

    if imgui.Button('Скопировать ник', imgui.ImVec2(160, 30)) then
        if type(setClipboardText) == 'function' then setClipboardText(tostring(row.nick or '')) end
        if helper_msg then helper_msg('Ник скопирован: ' .. tostring(row.nick or '')) end
    end
    imgui.SameLine()
    if imgui.Button('Скопировать ID', imgui.ImVec2(160, 30)) then
        if type(setClipboardText) == 'function' then setClipboardText(tostring(row.id or '')) end
        if helper_msg then helper_msg('ID скопирован: ' .. tostring(row.id or '')) end
    end

    if imgui.Button('Закрыть', imgui.ImVec2(-1, 30)) then MSH_FIND_ACTION_WINDOW[0] = false end
    imgui.End()
end

imgui.OnFrame(function() return MSH_FIND_STAFF_WINDOW and MSH_FIND_STAFF_WINDOW[0] end, function()
    MSHelper_DrawFindStaffWindow()
end)

imgui.OnFrame(function() return MSH_FIND_ACTION_WINDOW and MSH_FIND_ACTION_WINDOW[0] end, function()
    MSHelper_DrawFindActionWindow()
end)

-- Custom TAB убран: окно не регистрируем.

imgui.OnFrame(function() return main_window[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(940, 580), imgui.Cond.FirstUseEver)
    imgui.Begin('MS HELPER', main_window, imgui.WindowFlags.NoCollapse)
    imgui.BeginChild('left', imgui.ImVec2(160, 0), true)
    imgui.TextColored(MSHelper_AccentColor(), 'MS\nHELPER')
    imgui.Separator()
    -- Вкладка 'Прочее' убрана: меню взаимодействия теперь открывается только мини-окном ПКМ+G.
    local tabs = {
        { title = 'Основное', id = 1 },
        { title = 'Руководство', id = 3 },
        { title = 'Биндер', id = 2 },
        { title = 'Склад', id = 5 },
        { title = 'Шпаргалки', id = 6 },
        { title = 'Журнал', id = 7 },
        { title = 'Команды', id = 4 }
    }
    for _, tab in ipairs(tabs) do
        if imgui.Selectable(tab.title, active_tab == tab.id, 0, imgui.ImVec2(135, 42)) then
            active_tab = tab.id
        end
    end
    imgui.SetCursorPosY(imgui.GetWindowHeight() - 55)
    if imgui.Button('Закрыть', imgui.ImVec2(135, 32)) then
        if save_phone_settings then save_phone_settings(false) end
        main_window[0] = false
    end
    imgui.EndChild(); imgui.SameLine()
    imgui.BeginChild('content', imgui.ImVec2(0, 0), true)

    local __ms_menu_ok, __ms_menu_err = pcall(function()
        if active_tab == 1 then
            imgui.TextColored(MSHelper_AccentColor(), 'Основное')
            if MSHelper_DrawThemeSettings then MSHelper_DrawThemeSettings() end
            imgui.Separator()
            imgui.Separator()
            imgui.TextColored(MSHelper_AccentColor(), 'Кастомный /find')
            if MSH_CUSTOM_FIND_ENABLED and imgui.Checkbox('Включить кастомный /find сотрудников##msh_custom_find_on', MSH_CUSTOM_FIND_ENABLED) then save() end
            imgui.TextWrapped('Когда включено: обычный /find будет открывать удобный список сотрудников MS Helper. По сотруднику можно нажать и выбрать: Позвать игрока или Принять доклад.')
            imgui.Separator()
            toggle('Скрывать объявления СМИ', 'hide_smi_ads')
            toggle('Женский персонаж для RP-отыгровок', 'female')
            if _G.MSHelper_DrawRadioTagSettings then _G.MSHelper_DrawRadioTagSettings() end

            imgui.Separator()
            imgui.TextColored(MSHelper_AccentColor(), 'Телефон /p')
            imgui.TextWrapped('Скрипт ловит системное сообщение входящего звонка и отправляет приветствие только после подтверждения сервера, что трубка взята. Кнопку P лаунчера не дублирует.')
            if MSH_PHONE_GREET_ENABLED and imgui.Checkbox('Авто-приветствие после /p##phone_greet_enabled', MSH_PHONE_GREET_ENABLED) then
                save_phone_settings(false)
            end
            if MSH_PHONE_GREET_BUFFER then
                imgui.PushItemWidth(-1)
                if imgui.InputText('Приветствие для /p##phone_greet_text', MSH_PHONE_GREET_BUFFER, 512) then
                    save_phone_settings(false)
                end
                imgui.PopItemWidth()
                if imgui.Button('Сохранить приветствие /p', imgui.ImVec2(230, 27)) then
                    save_phone_settings(true)
                end
                imgui.SameLine()
                imgui.TextDisabled('Сохраняется в moonloader/config/ms_helper.ini')
                imgui.TextDisabled('Запасной способ сохранения: /msphone ваш текст или /msp ваш текст')
            end

            imgui.Separator()
            imgui.TextColored(MSHelper_AccentColor(), 'RolePlay отыгровки / команды')
            imgui.TextDisabled('Формат: пустое поле = стандартный RP, | = следующая строка, - = пропустить строку.')
            -- Команда управления воротами полностью убрана из списка RP-команд.
            draw_action_button('/mask', 'mask', '/mask')
            imgui.SameLine(220); draw_action_button('/find', 'find', '/find')

            draw_action_button('/lock', 'lock', '/lock')
            imgui.SameLine(220); draw_action_button('/healme', 'healme', '/healme')

            draw_action_button('/changeskin', 'changeskin', '/changeskin')
            imgui.SameLine(220); draw_action_button('/c 60', 'c60', '/c 60')

            draw_action_rp_editor()

            imgui.Separator()
            draw_prices()
        elseif active_tab == 2 then
            draw_binder_tab()
        elseif active_tab == 3 then
            imgui.TextColored(MSHelper_AccentColor(), 'Руководство')

            imgui.TextColored(MSHelper_AccentColor(), 'Вызов сотрудника')
            imgui.PushItemWidth(110)
            if imgui.InputInt('ID сотрудника##rukid', ruk_staff_id, 0, 0) then
                if ruk_staff_id[0] < 0 then ruk_staff_id[0] = 0 end
                save()
            end
            imgui.PopItemWidth()

            imgui.PushItemWidth(-1)
            if imgui.InputText('Текст в /r##ruktext', ruk_radio_text, 128) then save() end
            imgui.PopItemWidth()

            if imgui.Button('/mwhere', imgui.ImVec2(260, 32)) then
                send_where_radio(ruk_staff_id[0])
            end

            if _G.MSHelper_DrawOkReportBlock then _G.MSHelper_DrawOkReportBlock() end

            imgui.Separator()
            imgui.TextColored(MSHelper_AccentColor(), 'Государственные новости')
            local cd = get_cooldown()
            imgui.Text('Обычное КД скрипта: ' .. (cd > 0 and (math.floor(cd/60)..' мин. '..(cd%60)..' сек.') or 'нет'))

            imgui.Text('Выберите вкладку гос. новости:')
            for idx, h in ipairs(gos_hospitals) do
                if imgui.Selectable(h.title, selected_gos_hospital == h.key, 0, imgui.ImVec2(70, 26)) then
                    selected_gos_hospital = h.key
                end
                if idx < #gos_hospitals then imgui.SameLine() end
            end

            local lines = active_gos_lines()
            for i = 1, 3 do
                imgui.PushItemWidth(-1)
                if imgui.InputText('Строка '..i..'##gosline'..selected_gos_hospital..'_'..i, lines[i], 256) then save() end
                imgui.PopItemWidth()
            end

            imgui.Separator()
            imgui.TextColored(MSHelper_AccentColor(), 'Отдельная гос. новость на 1 строку')
            imgui.PushItemWidth(-1)
            if imgui.InputText('1 строка отдельно##gossingle'..selected_gos_hospital, active_gos_single_line(), 256) then save() end
            imgui.PopItemWidth()

            imgui.TextColored(MSHelper_AccentColor(), 'Стандартная отправка (с КД):')
            if imgui.Button('Отправить отдельную 1 строку', imgui.ImVec2(230, 30)) then send_gnews_single(false) end
            imgui.SameLine()
            if imgui.Button('Отправить 3 строки', imgui.ImVec2(180, 30)) then send_gnews(3, false) end
            imgui.SameLine()
            if imgui.Button('Открыть /mgos', imgui.ImVec2(140, 30)) then gos_window[0] = true end

            imgui.Spacing()
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.91,0.35,0.35,1), 'РП Госка без КД — 4 шаблона')

            for set = 1, 4 do
                if imgui.Selectable('Шаблон '..set, rpgos_tab == set, 0, imgui.ImVec2(120, 28)) then
                    rpgos_tab = set
                end
                if set < 4 then imgui.SameLine() end
            end

            imgui.Spacing()
            for i = 1, 3 do
                imgui.PushItemWidth(-1)
                if imgui.InputText('РП '..rpgos_tab..' / строка '..i..'##rpgosline'..rpgos_tab..'_'..i, rpgos_lines[rpgos_tab][i], 256) then
                    save()
                end
                imgui.PopItemWidth()
            end

            if imgui.Button('РП Госка #'..rpgos_tab..' — 1 строка', imgui.ImVec2(210, 32)) then
                send_rp_gnews_set(rpgos_tab, 1)
            end
            imgui.SameLine()
            if imgui.Button('РП Госка #'..rpgos_tab..' — 3 строки', imgui.ImVec2(210, 32)) then
                send_rp_gnews_set(rpgos_tab, 3)
            end
        elseif active_tab == 5 then
            if MS_DrawSkladTab then MS_DrawSkladTab() end
        elseif active_tab == 6 then
            if MS_DrawShporaTab then MS_DrawShporaTab() end
        elseif active_tab == 7 then
            if MSHelper_DrawJournalTab then MSHelper_DrawJournalTab() end
        elseif active_tab == 4 then
            draw_commands_tab()
        end
    end)

    if not __ms_menu_ok then
        active_tab = 4
        imgui.TextColored(imgui.ImVec4(1.0, 0.35, 0.35, 1.0), 'Ошибка отрисовки вкладки. Скрипт не выключен.')
        imgui.TextWrapped(tostring(__ms_menu_err))
        if helper_msg and (_G.MSHelper_LastMenuErrorText ~= tostring(__ms_menu_err)) then
            _G.MSHelper_LastMenuErrorText = tostring(__ms_menu_err)
            helper_msg('Ошибка /ms: ' .. tostring(__ms_menu_err) .. '. Открыта безопасная вкладка Команды.')
        end
    end

    imgui.EndChild(); imgui.End()
end)

imgui.OnFrame(function() return gos_window[0] end, function()
    if MSHelper_IsLeader and not MSHelper_IsLeader() then gos_window[0] = false; return end
    imgui.SetNextWindowSize(imgui.ImVec2(680, 560), imgui.Cond.FirstUseEver)
    imgui.Begin('Гос. новости /mgos', gos_window, imgui.WindowFlags.NoCollapse)
    local cd = get_cooldown()
    imgui.TextColored(MSHelper_AccentColor(), 'КД: ' .. (cd > 0 and (math.floor(cd/60)..' мин. '..(cd%60)..' сек.') or 'нет'))

    imgui.BeginChild('##mgos_scroll', imgui.ImVec2(0, 0), false)
    imgui.TextColored(MSHelper_AccentColor(), 'Обычные гос. новости')
        imgui.Text('Выберите вкладку гос. новости:')
        for idx, h in ipairs(gos_hospitals) do
            if imgui.Selectable(h.title, selected_gos_hospital == h.key, 0, imgui.ImVec2(70, 26)) then
                selected_gos_hospital = h.key
            end
            if idx < #gos_hospitals then imgui.SameLine() end
        end
        local lines = active_gos_lines()
        for i = 1, 3 do
            imgui.PushItemWidth(-1)
            if imgui.InputText('Строка '..i..'##mgosline'..selected_gos_hospital..'_'..i, lines[i], 256) then save() end
            imgui.PopItemWidth()
        end
        imgui.Separator()
        imgui.TextColored(MSHelper_AccentColor(), 'Отдельная гос. новость на 1 строку')
        imgui.PushItemWidth(-1)
        if imgui.InputText('1 строка отдельно##mgossingle'..selected_gos_hospital, active_gos_single_line(), 256) then save() end
        imgui.PopItemWidth()
        if imgui.Button('Кинуть отдельную 1 строку', imgui.ImVec2(230, 35)) then send_gnews_single(false) end
        imgui.SameLine()
        if imgui.Button('Кинуть 3 строки', imgui.ImVec2(170, 35)) then send_gnews(3, false) end

        imgui.Spacing()
        imgui.Separator()
        imgui.TextColored(imgui.ImVec4(0.91,0.35,0.35,1), 'РП госки без КД')
        imgui.TextWrapped('Эти строки отправляются через /gnews без запуска КД скрипта. Можно настроить 4 шаблона и отправить 1 или 3 строки.')

        for set = 1, 4 do
            if imgui.Selectable('Шаблон '..set, rpgos_tab == set, 0, imgui.ImVec2(120, 28)) then
                rpgos_tab = set
            end
            if set < 4 then imgui.SameLine() end
        end

        imgui.Spacing()
        for i = 1, 3 do
            imgui.PushItemWidth(-1)
            if imgui.InputText('РП '..rpgos_tab..' / строка '..i..'##mgos_rpgosline'..rpgos_tab..'_'..i, rpgos_lines[rpgos_tab][i], 256) then
                save()
            end
            imgui.PopItemWidth()
        end

        if imgui.Button('Кинуть РП госку #'..rpgos_tab..' — 1 строка', imgui.ImVec2(250, 35)) then
            send_rp_gnews_set(rpgos_tab, 1)
        end
        imgui.SameLine()
        if imgui.Button('Кинуть РП госку #'..rpgos_tab..' — 3 строки', imgui.ImVec2(250, 35)) then
            send_rp_gnews_set(rpgos_tab, 3)
        end
    imgui.EndChild()
    imgui.End()
end)

imgui.OnFrame(function() return patient_window[0] end, function()
    -- Мини-меню пациента теперь открывается выше и его можно перетаскивать мышкой за заголовок.
    local display = imgui.GetIO().DisplaySize
    imgui.SetNextWindowSize(imgui.ImVec2(340, 510), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(display.x - 360, display.y - 520), imgui.Cond.FirstUseEver)
    imgui.Begin('Взаимодействие с пациентом', patient_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    local pinfo = 'не выбрана'
    if selected_patient >= 0 then
        local cst, org, why = get_patient_price(selected_patient)
        pinfo = 'ID '..selected_patient..' | '..(org_names[org] or org)..' | '..cst..'$'
    end
    imgui.TextColored(MSHelper_AccentColor(), 'Цель: ' .. pinfo)
    if selected_patient >= 0 then
        imgui.TextDisabled('Организация определяется автоматически по цвету TAB.')
    end
    imgui.Separator()
    if imgui.Button('Представиться', imgui.ImVec2(-1, 27)) then
        chat('Здравствуйте, я ваш лечащий врач '..local_rp_name()..'. Вас что-то беспокоит?')
    end
    if imgui.Button('Собеседование', imgui.ImVec2(-1, 27)) then
        start_interview(selected_patient)
    end
    if imgui.Button('Выдать мед.карту', imgui.ImVec2(-1, 27)) then
        patient_window[0] = false
        if send_givemed_sequence then send_givemed_sequence(selected_patient) else sampSendChat('/givemed ' .. selected_patient) end
    end
    if imgui.Button('Показать паспорт', imgui.ImVec2(-1, 27)) then sampSendChat('/pass ' .. selected_patient) end
    if imgui.Button('Показать мед.карту', imgui.ImVec2(-1, 27)) then sampSendChat('/med ' .. selected_patient) end
    if imgui.Button('Послать на анализы', imgui.ImVec2(-1, 27)) then
        patient_window[0] = false
        analysis_command_until = os.time() + 15
        sampSendChat('/analysis ' .. selected_patient)
    end
    if imgui.Button('Послать на процедуру', imgui.ImVec2(-1, 27)) then
        if selected_patient >= 0 then
            patient_window[0] = false
            dis_command_until = os.time() + 15
            sampSendChat('/dis ' .. selected_patient)
        else
            helper_msg('Пациент не выбран.')
        end
    end
    imgui.Separator()
    imgui.TextColored(MSHelper_AccentColor(), 'Лечение болезней')
    for i, v in ipairs(illnesses) do
        if imgui.Button(v[1], imgui.ImVec2(-1, 25)) then selected_illness = i; send_treatment(selected_patient, i) end
    end
    imgui.Separator()
    if imgui.Button('Закрыть окно', imgui.ImVec2(-1, 28)) then patient_window[0] = false end
    imgui.End()
end)




imgui.OnFrame(function() return interview_window[0] end, function()
    center_next_window(420, 375)
    imgui.Begin('MS Helper | Собеседование', interview_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)

    local pid = tonumber(interview_player_id[0]) or -1
    local nick = interview_player_nick ~= '' and interview_player_nick or ('ID ' .. tostring(pid))
    imgui.TextColored(MSHelper_AccentColor(), 'Кандидат: ID ' .. tostring(pid) .. ' | ' .. nick)
    imgui.TextWrapped('Нажимайте кнопки по очереди после ответа кандидата или после получения документов.')
    if interview_action_busy then
        imgui.TextColored(imgui.ImVec4(1.0,0.75,0.25,1), 'Выполняется действие, подождите...')
    end
    imgui.Separator()

    if imgui.Button('1. Поздороваться и спросить про собеседование', imgui.ImVec2(-1, 32)) then
        send_interview_step(1)
    end

    if interview_step >= 2 then
        if imgui.Button('2. Представьтесь и сколько вам лет?', imgui.ImVec2(-1, 32)) then
            send_interview_step(2)
        end
    else
        imgui.TextDisabled('2. Представьтесь и сколько вам лет?')
    end

    if interview_step >= 3 then
        if imgui.Button('3. Спросить про опыт в МЗ', imgui.ImVec2(-1, 32)) then
            send_interview_step(3)
        end
    else
        imgui.TextDisabled('3. Спросить про опыт в МЗ')
    end

    if interview_step >= 4 then
        if imgui.Button('4. Запросить паспорт, лицензии, мед.карту и личное дело', imgui.ImVec2(-1, 32)) then
            send_interview_step(4)
        end
    else
        imgui.TextDisabled('4. Запросить документы и личное дело')
    end

    if interview_step >= 5 then
        if imgui.Button('5. Подходит — /invite или передать руководству', imgui.ImVec2(-1, 34)) then
            send_interview_step(5)
        end
    else
        imgui.TextDisabled('5. Подходит — /invite или передать руководству')
    end

    imgui.Separator()
    if imgui.Button('Сбросить этапы', imgui.ImVec2(190, 30)) then
        interview_step = 1
        interview_action_busy = false
    end
    imgui.SameLine()
    if imgui.Button('Закрыть', imgui.ImVec2(190, 30)) then
        reset_interview_ui_state()
    end

    imgui.End()
end)

imgui.OnFrame(function() return invite_window[0] end, function()
    center_next_window(330, 150)
    imgui.Begin('MS Helper | Invite', invite_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    imgui.TextColored(MSHelper_AccentColor(), 'Принять сотрудника')
    imgui.Text('Введите ID игрока:')
    imgui.PushItemWidth(-1)
    imgui.InputInt('##invite_id_input', invite_player_id, 0, 0)
    imgui.PopItemWidth()

    if imgui.Button('Принять', imgui.ImVec2(145, 32)) then
        local id = invite_player_id[0]
        if id >= 0 and ms_safe_player_connected(id) then
            invite_window[0] = false
            send_invite_sequence(id)
        else
            helper_msg('Игрок ID '..tostring(id)..' не подключен.')
        end
    end
    imgui.SameLine()
    if imgui.Button('Отмена', imgui.ImVec2(145, 32)) then
        invite_window[0] = false
    end
    imgui.End()
end)

imgui.OnFrame(function() return uninvite_window[0] end, function()
    center_next_window(520, 335)
    imgui.Begin('MS Helper | Uninvite', uninvite_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    imgui.TextColored(imgui.ImVec4(0.91,0.35,0.35,1), 'Увольнение / перевод / отпуск')
    imgui.Text('ID игрока:')
    imgui.PushItemWidth(-1)
    imgui.InputInt('##uninvite_id_input', uninvite_player_id, 0, 0)
    imgui.PopItemWidth()

    local function run_uninvite_reason(reason, reason_type)
        local id = uninvite_player_id[0]
        if id < 0 or not ms_safe_player_connected(id) then
            helper_msg('Игрок ID '..tostring(id)..' не подключен.')
            return
        end
        uninvite_window[0] = false
        send_uninvite_sequence(id, reason, true, reason_type)
    end

    imgui.Text('Выберите причину:')
    if imgui.Button('ПСЖ', imgui.ImVec2(150, 32)) then
        run_uninvite_reason('ПСЖ', 'fire')
    end
    imgui.SameLine()
    if imgui.Button('НУМЗ', imgui.ImVec2(150, 32)) then
        run_uninvite_reason('НУМЗ', 'fire')
    end
    imgui.SameLine()
    if imgui.Button('Нарушение ЕЦП', imgui.ImVec2(170, 32)) then
        run_uninvite_reason('Нарушение ЕЦП', 'fire')
    end

    if imgui.Button('Проф.непригоден', imgui.ImVec2(150, 32)) then
        run_uninvite_reason('Проф. Непригоден', 'fire')
    end
    imgui.SameLine()
    if imgui.Button('Перевод', imgui.ImVec2(150, 32)) then
        run_uninvite_reason('Перевод', 'transfer')
    end
    imgui.SameLine()
    if imgui.Button('Отпуск', imgui.ImVec2(170, 32)) then
        run_uninvite_reason('Отпуск', 'vacation')
    end

    imgui.Separator()
    imgui.Text('Своя причина:')
    imgui.PushItemWidth(-1)
    imgui.InputText('##uninvite_reason_input', uninvite_reason_buffer, 128)
    imgui.PopItemWidth()

    if imgui.Button('Уволить со своей причиной', imgui.ImVec2(320, 32)) then
        local id = uninvite_player_id[0]
        local reason = trim(ffi.string(uninvite_reason_buffer))
        if id < 0 or not ms_safe_player_connected(id) then
            helper_msg('Игрок ID '..tostring(id)..' не подключен.')
        elseif reason == '' then
            helper_msg('Введите причину увольнения или выберите кнопку.')
        else
            uninvite_window[0] = false
            send_uninvite_sequence(id, reason, true, 'fire')
        end
    end
    imgui.SameLine()
    if imgui.Button('Отмена', imgui.ImVec2(150, 32)) then
        uninvite_window[0] = false
    end
    imgui.End()
end)



imgui.OnFrame(function() return rang_window[0] end, function()
    center_next_window(330, 165)
    imgui.Begin('MS Helper | Rang', rang_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    imgui.TextColored(MSHelper_AccentColor(), 'Изменение ранга сотрудника')
    imgui.Text('Введите ID игрока:')
    imgui.PushItemWidth(-1)
    imgui.InputInt('##rang_id_input', rang_player_id, 0, 0)
    imgui.PopItemWidth()

    local function run_rang(sign)
        local id = rang_player_id[0]
        if id < 0 or not ms_safe_player_connected(id) then
            helper_msg('Игрок ID '..tostring(id)..' не подключен.')
            return
        end
        rang_window[0] = false
        send_rang_sequence(id, sign)
    end

    if imgui.Button('- Понизить', imgui.ImVec2(145, 32)) then
        run_rang('-')
    end
    imgui.SameLine()
    if imgui.Button('+ Повысить', imgui.ImVec2(145, 32)) then
        run_rang('+')
    end

    if imgui.Button('Отмена', imgui.ImVec2(-1, 30)) then
        rang_window[0] = false
    end
    imgui.End()
end)



function is_any_ms_window_open()
    return (main_window and main_window[0]) or (gos_window and gos_window[0]) or (patient_window and patient_window[0]) or (interview_window and interview_window[0]) or (invite_window and invite_window[0]) or (uninvite_window and uninvite_window[0]) or (rang_window and rang_window[0])
end


function close_all_ms_windows()
    -- Закрываем все окна MS Helper, когда игрок открывает стандартное меню GTA через ESC.
    pending_main_window_toggle = false
    binder_wait_key_slot = 0
    main_window[0] = false
    gos_window[0] = false
    patient_window[0] = false
    invite_window[0] = false
    uninvite_window[0] = false
    rang_window[0] = false
    reset_interview_ui_state()
end

function gta_pause_menu_active()
    -- На разных сборках MoonLoader/SAMP функция может называться по-разному.
    -- Если функции нет, всё равно закрываем окна по самому нажатию ESC в основном цикле.
    if type(isPauseMenuActive) == 'function' and isPauseMenuActive() then return true end
    if type(isGamePaused) == 'function' and isGamePaused() then return true end
    if type(isMenuActive) == 'function' and isMenuActive() then return true end
    return false
end

-- Важно: вызываем через _G внутри main(), чтобы не превысить лимит LuaJIT/MoonLoader в 60 upvalues.
_G.MSHelper_CloseAllWindows = close_all_ms_windows
_G.MSHelper_GtaPauseMenuActive = gta_pause_menu_active

function imgui_wants_keyboard()
    -- В этой версии не обращаемся к imgui.GetIO() в main loop:
    -- на некоторых сборках mimgui это вызывает ошибку coroutine.
    -- Блокировки по открытым окнам достаточно, чтобы бинды не срабатывали при редактировании.
    return false
end



-- Свободная камера /drone: медленная, с управлением мышкой
drone_enabled = false
drone_thread_running = false
drone_x, drone_y, drone_z = 0.0, 0.0, 0.0
drone_yaw, drone_pitch = 0.0, 0.0

-- Сделал скорость намного медленнее. Меняется клавишами - и +.
drone_speed = 0.06
drone_speed_min = 0.01
drone_speed_max = 0.75
drone_speed_step = 0.01
drone_mouse_sens = 0.0025

ffi.cdef[[
    typedef struct { long x; long y; } POINT;
    int GetCursorPos(POINT* lpPoint);
    int SetCursorPos(int X, int Y);
]]

function drone_speed_text()
    return string.format('%.2f', drone_speed)
end

function drone_change_speed(delta)
    drone_speed = drone_speed + delta
    if drone_speed < drone_speed_min then drone_speed = drone_speed_min end
    if drone_speed > drone_speed_max then drone_speed = drone_speed_max end
    helper_msg('Скорость свободной камеры: '..drone_speed_text())
end

function drone_lock_player(state)
    if freezeCharPosition then pcall(freezeCharPosition, PLAYER_PED, state) end
    if setPlayerControl then pcall(setPlayerControl, PLAYER_HANDLE, not state) end
end

function drone_restore_camera()
    if restoreCameraJumpcut then
        pcall(restoreCameraJumpcut)
    elseif restoreCamera then
        pcall(restoreCamera)
    end
    if setCameraBehindPlayer then pcall(setCameraBehindPlayer) end
    drone_lock_player(false)
end

function drone_apply_camera()
    local dist = 8.0
    local cp = math.cos(drone_pitch)
    local tx = drone_x + math.cos(drone_yaw) * cp * dist
    local ty = drone_y + math.sin(drone_yaw) * cp * dist
    local tz = drone_z + math.sin(drone_pitch) * dist

    if setFixedCameraPosition then
        pcall(setFixedCameraPosition, drone_x, drone_y, drone_z, 0.0, 0.0, 0.0)
    end
    if pointCameraAtPoint then
        pcall(pointCameraAtPoint, tx, ty, tz, 2)
    end
end

function drone_get_screen_center()
    -- Не используем imgui.GetIO() здесь: /drone вызывается из chat command,
    -- а на некоторых сборках mimgui доступ к GetIO вне OnFrame крашит/роняет coroutine.
    local sx, sy = 800, 600
    if getScreenResolution then
        local ok, w, h = pcall(getScreenResolution)
        if ok and tonumber(w) and tonumber(h) and tonumber(w) > 0 and tonumber(h) > 0 then
            sx, sy = tonumber(w), tonumber(h)
        end
    end
    return math.floor(sx / 2), math.floor(sy / 2)
end

function drone_start()
    if drone_enabled then return end

    if not PLAYER_PED or not doesCharExist or not doesCharExist(PLAYER_PED) then
        helper_msg('Свободная камера: персонаж еще не загружен.')
        return
    end

    local ok_pos, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if not ok_pos or not x or not y or not z then
        helper_msg('Свободная камера: не удалось получить координаты игрока.')
        return
    end

    drone_x, drone_y, drone_z = x, y, z + 2.0
    local heading = 0.0
    if getCharHeading then
        local ok, h = pcall(getCharHeading, PLAYER_PED)
        if ok and h then heading = h end
    end
    drone_yaw = math.rad(90.0 - heading)
    drone_pitch = 0.0
    drone_enabled = true
    drone_lock_player(true)

    local cx, cy = drone_get_screen_center()
    pcall(ffi.C.SetCursorPos, cx, cy)

    helper_msg('Свободная камера включена. Мышь — направление, W — лететь туда, куда смотришь, S назад, A/D в стороны')
    helper_msg('SPACE/SHIFT вверх-вниз, - медленнее, + быстрее, CTRL ускорение, ESC или /drone выключить. Скорость: '..drone_speed_text())
    if drone_thread_running then return end
    drone_thread_running = true
    lua_thread.create(function()
        -- Важно: не оборачиваем цикл с wait(0) в pcall/xpcall.
        -- В Lua 5.1/MoonLoader yield внутри pcall на части сборок иногда приводит
        -- к "cannot resume non-suspended coroutine".
        local ok_pt, pt = pcall(ffi.new, 'POINT[1]')
        if not ok_pt or not pt then
            drone_enabled = false
            drone_restore_camera()
            drone_thread_running = false
            helper_msg('Свободная камера выключена: не удалось создать POINT.')
            return
        end

        while drone_enabled do
            wait(0)

            if wasKeyPressed and wasKeyPressed(0x1B) then -- ESC
                drone_enabled = false
                break
            end

            -- - / + регулируют базовую скорость. Поддерживаются верхний ряд и NumPad.
            if wasKeyPressed and (wasKeyPressed(0xBD) or wasKeyPressed(0x6D)) then -- - / Num-
                drone_change_speed(-drone_speed_step)
            end
            if wasKeyPressed and (wasKeyPressed(0xBB) or wasKeyPressed(0x6B)) then -- + / Num+
                drone_change_speed(drone_speed_step)
            end

            -- Поворот камеры мышкой: курсор каждый кадр возвращается в центр экрана.
            local center_x, center_y = drone_get_screen_center()
            if ffi.C.GetCursorPos(pt) ~= 0 then
                local dx = tonumber(pt[0].x - center_x)
                local dy = tonumber(pt[0].y - center_y)
                -- мышь влево = камера влево, мышь вправо = камера вправо
                drone_yaw = drone_yaw - dx * drone_mouse_sens
                -- мышь вниз = камера вниз, мышь вверх = камера вверх
                drone_pitch = drone_pitch - dy * drone_mouse_sens
                pcall(ffi.C.SetCursorPos, center_x, center_y)
            end

            if drone_pitch > 1.35 then drone_pitch = 1.35 end
            if drone_pitch < -1.35 then drone_pitch = -1.35 end

            local speed = drone_speed
            if isKeyDown(0x11) then speed = speed * 3.0 end -- CTRL временное ускорение

            -- Вперёд/назад летит именно туда, куда смотрит камера, включая высоту.
            local cp = math.cos(drone_pitch)
            local fx = math.cos(drone_yaw) * cp
            local fy = math.sin(drone_yaw) * cp
            local fz = math.sin(drone_pitch)

            -- Стрейф влево/вправо оставлен горизонтальным, чтобы камера не кренилась.
            local rx = math.cos(drone_yaw + math.pi / 2)
            local ry = math.sin(drone_yaw + math.pi / 2)

            if isKeyDown(0x57) then drone_x = drone_x + fx * speed; drone_y = drone_y + fy * speed; drone_z = drone_z + fz * speed end -- W
            if isKeyDown(0x53) then drone_x = drone_x - fx * speed; drone_y = drone_y - fy * speed; drone_z = drone_z - fz * speed end -- S
            if isKeyDown(0x41) then drone_x = drone_x + rx * speed; drone_y = drone_y + ry * speed end -- A: влево
            if isKeyDown(0x44) then drone_x = drone_x - rx * speed; drone_y = drone_y - ry * speed end -- D: вправо
            if isKeyDown(0x20) then drone_z = drone_z + speed end -- SPACE
            if isKeyDown(0x10) then drone_z = drone_z - speed end -- SHIFT

            drone_apply_camera()
        end

        drone_enabled = false
        drone_restore_camera()
        drone_thread_running = false
        helper_msg('Свободная камера выключена.')
    end)
end

function drone_toggle()
    if drone_enabled then
        drone_enabled = false
    else
        drone_start()
    end
end


-- Команды вынесены из main(), чтобы MoonLoader/Lua не упирался в лимит upvalues.
function MSHelper_CmdOpenMain()
    request_main_menu_toggle()
end

function MSHelper_CmdToggleGos()
    gos_window[0] = not gos_window[0]
end

function MSHelper_CmdColor(arg)
    local pid = tonumber(arg) or target_player_id()
    if pid < 0 then helper_msg('Наведитесь на игрока или введите /mscolor id'); return end
    if not ms_safe_player_connected(pid) then helper_msg('Игрок ID '..pid..' не подключен.'); return end

    local nick = safe_nick(pid) or 'unknown'
    local ok_color, color = pcall(sampGetPlayerColor, pid)
    if not ok_color or not color then helper_msg('Не удалось получить цвет игрока.'); return end
    local raw = color_to_hex(color)

    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)
    local rgb_hex = string.format('%02X%02X%02X', r, g, b)

    local r_alt = bit.band(bit.rshift(color, 24), 0xFF)
    local g_alt = bit.band(bit.rshift(color, 16), 0xFF)
    local b_alt = bit.band(bit.rshift(color, 8), 0xFF)
    local rgb_alt_hex = string.format('%02X%02X%02X', r_alt, g_alt, b_alt)

    local detected_direct, why_direct = classify_tab_rgb(r, g, b)
    local detected_alt, why_alt = classify_tab_rgb(r_alt, g_alt, b_alt)
    local cost, org, why = get_patient_price(pid)

    helper_msg('DEBUG ID '..pid..' | '..nick)
    helper_msg('RAW: 0x'..raw..' | RGB: '..r..','..g..','..b..' | HEX RGB: '..rgb_hex)
    helper_msg('ALT: '..r_alt..','..g_alt..','..b_alt..' | HEX ALT: '..rgb_alt_hex)
    helper_msg('DIRECT: '..(org_names[detected_direct] or detected_direct or 'nil')..' | '..tostring(why_direct))
    helper_msg('ALT: '..(org_names[detected_alt] or detected_alt or 'nil')..' | '..tostring(why_alt))
    helper_msg('ИТОГ: '..(org_names[org] or org)..' | цена '..cost..'$ | '..why)
end

function MSHelper_CmdOrg(arg)
    local pid = tonumber(arg) or target_player_id()
    if pid < 0 then helper_msg('Наведитесь на игрока или введите /msorg id'); return end
    local cost, org, why = get_patient_price(pid)
    helper_msg('ID '..pid..' → '..(org_names[org] or org)..', цена '..cost..'$, Метод: '..why)
end

function MSHelper_CmdSetOrg(arg)
    local id, org_raw = tostring(arg or ''):match('^(%d+)%s+(.+)$')
    local pid = tonumber(id)
    local org = map_org_name(org_raw) or org_raw
    if not pid or not org_names[org] then
        helper_msg('Используйте: /mssetorg id org. Орг: civil gangs yakuza smi mo lkn pravo mz rm mvd')
        return
    end
    local nick = save_org_for_player(pid, org)
    if nick then helper_msg('Запомнил '..nick..' как '..org_names[org]..' в players.ini') else helper_msg('Не удалось сохранить: игрок не найден') end
end

function MSHelper_CmdDelOrg(arg)
    local pid = tonumber(arg) or target_player_id()
    if pid < 0 then helper_msg('Наведитесь на игрока или /msdelorg id'); return end
    local nick = delete_org_for_player(pid)
    helper_msg('Удалил из players.ini: '..(nick or ('ID '..pid)))
end

function MSHelper_CmdWhere(arg)
    local id = tonumber(arg)
    if not id then helper_msg('Используйте: /mwhere id'); return end
    send_where_radio(id)
end

function MSHelper_CmdOk(arg)
    _G.MSHelper_SendOkReport(arg)
end


function MSHelper_CmdJobChat()
    cfg.main.hide_job_chat = false
    save()
    helper_msg('Скрытие рабочего чата /j и /jn убрано из MS Helper. Используйте серверную настройку.')
end

function MSHelper_CmdName(arg)
    arg = trim(tostring(arg or ''))
    if arg == '' then
        helper_msg('Текущее имя врача: '..local_rp_name()..'. Автоник: /msname auto.')
        return
    end
    if arg:lower() == 'auto' then
        cfg.main.doctor_name = ''
        save()
        helper_msg('Имя врача переведено в авто-режим. Сейчас определяется как: '..local_rp_name())
        return
    end
    cfg.main.doctor_name = MSHelper_CleanRpName(arg)
    save()
    helper_msg('Имя врача установлено: '..cfg.main.doctor_name)
end

function MSHelper_CmdMyId()
    local id = local_player_id()
    local nick = 'nil'
    if id and id >= 0 then
        if type(sampGetPlayerNickname) == 'function' then
            nick = sampGetPlayerNickname(id) or safe_nick(id) or 'nil'
        else
            nick = safe_nick(id) or 'nil'
        end
    end
    helper_msg('Мой ID по скрипту: '..tostring(id)..' | ник: '..tostring(nick)..' | имя для RP: '..local_rp_name())
end

function MSHelper_CmdInvite(arg)
    local id = tonumber(arg)
    if not id then helper_msg('Используйте: /minvite id'); return end
    send_invite_sequence(id)
end

function MSHelper_CmdSobes(arg)
    local id = tonumber(arg) or target_player_id()
    if not id or id < 0 then helper_msg('Используйте: /sobes id или наведитесь на игрока.'); return end
    start_interview(id)
end

function MSHelper_CmdUninvite(arg)
    local id, reason = tostring(arg or ''):match('^(%d+)%s+(.+)$')
    if not id or not reason then helper_msg('Используйте: /muninvite id причина'); return end
    send_uninvite_sequence(tonumber(id), reason)
end

function MSHelper_CmdRang(arg)
    local id, sign = tostring(arg or ''):match('^(%d+)%s+([%+%-])%s*$')
    if id and sign then
        send_rang_sequence(tonumber(id), sign)
        return
    end
    local only_id = tostring(arg or ''):match('^(%d+)%s*$')
    if only_id then rang_player_id[0] = tonumber(only_id) end
    rang_window[0] = true
end

function MSHelper_CmdDrive()
    send_drive_sequence()
end

function MSHelper_CmdDrone()
    -- Возвращён старый MSHelper /drone: медленная свободная камера с мышью.
    drone_toggle()
end

function MSHelper_CmdReconnect(arg)
    reconnect_start(tonumber(arg) or rc.delay[0], 'manual')
end

function MSHelper_CmdAutoReconnect(arg)
    reconnect_toggle_auto(arg)
end

function MSHelper_CmdFastConnect()
    reconnect_start(1, 'manual')
end

function MSHelper_CmdSaveConnect()
    reconnect_save_current_server()
    reconnect_status()
end

function MSHelper_CmdRp(arg)
    local key, rp = tostring(arg or ''):match('^(%S+)%s+(.+)$')
    if not key or not rp or not action_rp_buffers[key] then
        helper_msg('Используйте: /msrp key текст. key: mask find lock healme changeskin')
        return
    end
    ffi.copy(action_rp_buffers[key], u8:encode(rp), 255)
    cfg.rptexts[key] = ffi.string(action_rp_buffers[key])
    save()
    helper_msg('RP для '..(action_labels[key] or key)..' обновлено.')
end

function MSHelper_CmdPrice(arg)
    local org, amount = tostring(arg or ''):match('^(%S+)%s+(%d+)$')
    amount = tonumber(amount)
    if not org or not amount or not price[org] then
        helper_msg('Используйте: /msprice org сумма. Орг: ambulance civil gangs yakuza smi mo lkn pravo mz rm mvd')
        return
    end
    price[org][0] = amount
    save()
    helper_msg('Цена '..(org_names[org] or org)..' = '..amount..'$')
end

function MSHelper_CmdRuk(arg)
    local id = tonumber(arg)
    if not id then helper_msg('Используйте: /msruk id'); return end
    ruk_staff_id[0] = id
    save()
    helper_msg('ID сотрудника для вызова: '..id)
end

function MSHelper_CmdRukText(arg)
    if tostring(arg or '') == '' then helper_msg('Используйте: /msruktext текст'); return end
    ffi.copy(ruk_radio_text, u8:encode(arg), 127)
    save()
    helper_msg('Текст вызова в /r обновлен.')
end

function MSHelper_CmdMsgos(arg)
    arg = tostring(arg or '')
    local hospital, line, text = arg:match('^(%S+)%s+(%d+)%s+(.+)$')
    hospital = normalize_gos_hospital(hospital)
    if hospital then
        selected_gos_hospital = hospital
    else
        line, text = arg:match('^(%d+)%s+(.+)$')
        hospital = selected_gos_hospital
    end
    line = tonumber(line)
    if not line or line < 1 or line > 3 or not text then helper_msg('Используйте: /msgos [sf/ls/lv/mz] 1-3 текст'); return end
    ffi.copy(gos_lines[hospital][line], u8:encode(text), 255)
    save()
    helper_msg('Гос. строка '..line..' для '..hospital:upper()..' обновлена.')
end

function MSHelper_CmdMsgos1(arg)
    arg = tostring(arg or '')
    local hospital, text = arg:match('^(%S+)%s+(.+)$')
    hospital = normalize_gos_hospital(hospital)
    if hospital then
        selected_gos_hospital = hospital
    else
        hospital = selected_gos_hospital
        text = arg
    end
    if not text or trim(text) == '' then helper_msg('Используйте: /msgos1 [sf/ls/lv/mz] текст'); return end
    ffi.copy(gos_single_lines[hospital], u8:encode(text), 255)
    save()
    helper_msg('Отдельная 1 строка гос. новости для '..hospital:upper()..' обновлена.')
end

function MSHelper_CmdRpGos(arg)
    local set, line, text = tostring(arg or ''):match('^(%d+)%s+(%d+)%s+(.+)$')
    set, line = tonumber(set), tonumber(line)
    if not set or set < 1 or set > 4 or not line or line < 1 or line > 3 or not text then helper_msg('Используйте: /msrpgos шаблон1-4 строка1-3 текст'); return end
    ffi.copy(rpgos_lines[set][line], u8:encode(text), 255)
    save()
    helper_msg('РП госка #'..set..' строка '..line..' обновлена.')
end

function MSHelper_CmdBind(arg)
    local slot, bind_text = tostring(arg or ''):match('^(%d+)%s+(.+)$')
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > 22 or not bind_text then
        helper_msg('Используйте: /msbind слот текст. Например: /msbind 1 /me достал аптечку|/do Аптечка в руках.')
        return
    end
    ffi.copy(binder[slot], u8:encode(bind_text), 511)
    save()
    helper_msg('Текст биндера для слота №' .. slot .. ' обновлен.')
end

function MSHelper_CmdBindCmd(arg)
    local slot, cmd_name = tostring(arg or ''):match('^(%d+)%s+(%S+)%s*$')
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > 22 or not cmd_name then
        helper_msg('Используйте: /msbindcmd слот команда. Например: /msbindcmd 1 аптечка')
        return
    end
    cmd_name = normalize_binder_command(cmd_name, slot)
    ffi.copy(binder_command[slot], cmd_name, 31)
    save()
    helper_msg('Команда слота №' .. slot .. ': /' .. cmd_name)
end

function MSHelper_CmdBindKey(arg)
    local slot, vk = tostring(arg or ''):match('^(%d+)%s+(%d+)%s*$')
    slot, vk = tonumber(slot), tonumber(vk)
    if not slot or slot < 1 or slot > 22 or vk == nil then
        helper_msg('Используйте: /msbindkey слот VK. Например: /msbindkey 1 113 для F2. Ноль убирает клавишу.')
        return
    end
    binder_key[slot][0] = vk
    if binder_key[slot][0] < 0 then binder_key[slot][0] = 0 end
    sanitize_binder_key_obj(binder_key[slot])
    save()
    helper_msg('Клавиша слота №' .. slot .. ': ' .. vk_name(binder_key[slot][0]) .. '.')
end

function MSHelper_CmdCustomTab(arg)
    helper_msg('Кастомный TAB убран из этой версии, чтобы не ломался ввод в /ms.')
end

function MSHelper_CmdFindStaff(arg)
    if MSH_CUSTOM_FIND_ENABLED and MSH_CUSTOM_FIND_ENABLED[0] then
        MSH_FIND_EXPECT_UNTIL = os.clock() + 6
    end
    sampSendChat('/find')
end

function MSHelper_RegisterCommands()
    -- Оставлены только команды, которые указаны во вкладке «Команды».
    -- Остальные действия (/heal, /to, /invite, /uni, /rang, /drive) ловятся через onSendCommand,
    -- поэтому отдельная регистрация им не нужна.
    local function reg_medic(name, fn)
        sampRegisterChatCommand(name, function(arg) fn(arg) end)
    end
    local function reg_leader(name, fn)
        sampRegisterChatCommand(name, function(arg) fn(arg) end)
    end

    reg_medic('ms', MSHelper_CmdOpenMain)
    reg_leader('mgos', MSHelper_CmdToggleGos)
    reg_medic('medinfo', MS_SkladShowInfo)
    reg_medic('medrn', MS_SkladSendRadio)
    reg_medic('shupdate', MS_ShporaUpdateAll)
    reg_medic('shserver', MS_ShporaCmdServer)
    reg_medic('msname', MSHelper_CmdName)
    reg_medic('msphone', MSHelper_CmdPhoneGreeting)
    reg_medic('msp', MSHelper_CmdPhoneGreeting)
    reg_medic('mfind', MSHelper_CmdFindStaff)
    reg_medic('msfind', MSHelper_CmdFindStaff)
    reg_medic('mwhere', MSHelper_CmdWhere)
    reg_medic('ok', MSHelper_CmdOk)
    reg_medic('sobes', MSHelper_CmdSobes)
    reg_medic('drone', MSHelper_CmdDrone)
    reg_medic('rec', MSHelper_CmdReconnect)
end

function MSHelper_MainTick()
    -- Склад сканируется отдельным безопасным потоком MS_SkladStartAutoWorker(), не каждый кадр.
    if pending_main_window_toggle then
        pending_main_window_toggle = false
        if _G.MSHelper_GtaPauseMenuActive and _G.MSHelper_GtaPauseMenuActive() then
            if _G.MSHelper_CloseAllWindows then _G.MSHelper_CloseAllWindows() end
        else
            reset_interview_ui_state()
            invite_window[0] = false
            uninvite_window[0] = false
            rang_window[0] = false
            patient_window[0] = false
            if active_tab ~= 1 and active_tab ~= 2 and active_tab ~= 3 and active_tab ~= 4 and active_tab ~= 5 and active_tab ~= 6 and active_tab ~= 7 then
                active_tab = 4
            end
            main_window[0] = not main_window[0]
        end
    end

    if is_any_ms_window_open() and ((wasKeyPressed and wasKeyPressed(0x1B)) or (_G.MSHelper_GtaPauseMenuActive and _G.MSHelper_GtaPauseMenuActive())) then
        if _G.MSHelper_CloseAllWindows then _G.MSHelper_CloseAllWindows() end
    end
    for _, k in ipairs({0x57,0x41,0x53,0x44,0x20,0x01,0x02,0x0D}) do if isKeyDown(k) then last_activity_at = os.time(); break end end
    if not is_any_ms_window_open() and not samp_text_input_active() then
        if not process_binder_hotkeys() then
            if isKeyDown(VK_RBUTTON) and wasKeyPressed(cfg.main.interaction_key or 71) then
                selected_patient = target_player_id()
                if selected_patient >= 0 then
                    patient_window[0] = true
                else
                    patient_window[0] = false
                    helper_msg('Меню открывается только при наведении на пациента: ПКМ+G.')
                end
            end
        end
    end

    -- На части сборок это стабильнее, чем оставлять обработку окон полностью на предикатах OnFrame.
    if imgui then imgui.Process = is_any_ms_window_open() end
end


function onWindowMessage(msg, wparam, lparam)
    -- Custom TAB убран: клавиши не перехватываем, чтобы поля ввода в /ms работали нормально.
end

function main()
    repeat wait(0) until isSampAvailable()
    MSHelper_RegisterCommands()
    MS_SkladStartAutoWorker()
    MSHelper_ReconnectStartWorker()
    helper_msg('Загружен /ms Меню BETA 1.0.')
    while true do
        wait(0)
        MSHelper_MainTick()
    end
end

-- =========================================================
-- MS Helper addon: home marker, embedded Advance RP house DB
-- /mshome ID       - поставить GPS/блип метку на дом по ID Advance
-- /mshome off      - убрать метку
-- /mshome update   - перечитать пользовательский house.ini из config
-- База домов вшита в скрипт. Для новых/исправленных домов используется
-- moonloader\config\house.ini, который создаёт /mshomeadd.
-- =========================================================

-- v17: addon wrapped into a function so top-level Lua chunk does not exceed 200 local variables.
function MSHelper_HomeAddonStart_V17()
__ms_home_u8 = nil
pcall(function()
    local encoding = require 'encoding'
    encoding.default = 'CP1251'
    __ms_home_u8 = encoding.UTF8
end)

function __ms_home_text(s)
    if __ms_home_u8 then
        local ok, result = pcall(function() return __ms_home_u8:decode(tostring(s or '')) end)
        if ok and result then return result end
    end
    return tostring(s or '')
end

function __ms_home_msg(s, color)
    if type(sampAddChatMessage) == 'function' then
        pcall(sampAddChatMessage, __ms_home_text(s), color or 0x66CCFFFF)
    end
end

__ms_home_embedded_db = [====[
[0]
y = -1682.890137
x = 1984.562012
z = 15.968750

[1]
y = -1629.829468
x = 2015.527466
z = 13.546875

[2]
y = -1628.856323
x = 2070.883789
z = 13.546875

[3]
y = -1703.331543
x = 2068.206543
z = 14.148438

[4]
y = -1639.923340
x = 2240.414307
z = 15.575047

[5]
y = -1646.350708
x = 2256.950439
z = 15.499722

[6]
y = -1644.351074
x = 2281.594727
z = 15.246120

[7]
y = -1676.282959
x = 2307.149658
z = 13.846556

[8]
y = -1681.174438
x = 2330.114502
z = 14.425596

[9]
y = -1646.161133
x = 2362.913086
z = 13.533920

[10]
y = -1671.378418
x = 2365.475098
z = 13.546875

[11]
y = -1672.676880
x = 2384.851563
z = 14.680487

[12]
y = -1648.591064
x = 2393.823975
z = 13.541663

[13]
y = -1671.411987
x = 2409.352295
z = 13.577196

[14]
y = -1649.629272
x = 2413.944580
z = 13.537546

[15]
y = -1644.295410
x = 2451.920410
z = 13.457876

[16]
y = -1688.759644
x = 2459.576416
z = 13.533511

[17]
y = -1687.342285
x = 2495.323242
z = 13.515532

[18]
y = -1678.566406
x = 2518.975098
z = 14.592714

[19]
y = -1661.292847
x = 2520.312500
z = 14.429855

[20]
y = -1652.620483
x = 2510.741211
z = 13.790663

[21]
y = -1644.432739
x = 2498.232422
z = 13.782610

[22]
y = -1647.724976
x = 2486.551514
z = 14.070313

[23]
y = -1916.117065
x = 1853.905762
z = 15.256798

[24]
y = -1913.742188
x = 1872.111694
z = 15.256798

[25]
y = -1916.141113
x = 1892.861450
z = 15.256798

[26]
y = -1913.889282
x = 1914.487427
z = 15.256798

[27]
y = -1917.660522
x = 1928.911743
z = 15.256798

[28]
y = -1911.851685
x = 1936.843872
z = 15.256798

[29]
y = -1673.768311
x = 2168.269531
z = 15.083082

[30]
y = -1665.386108
x = 2146.031982
z = 15.085938

[31]
y = -1607.298340
x = 2141.844727
z = 14.216815

[32]
y = -1586.432617
x = 2149.698242
z = 14.343750

[33]
y = -1795.877563
x = 2397.877930
z = 13.546875

[34]
y = -1785.388916
x = 2377.280029
z = 13.546875

[35]
y = -1795.847290
x = 2325.433350
z = 13.546875

[36]
y = -1795.859253
x = 2292.453857
z = 13.546875

[37]
y = -1795.778931
x = 2249.836670
z = 13.546875

[38]
y = -2136.597900
x = 1894.224976
z = 15.162292

[39]
y = -2135.869629
x = 1872.524170
z = 15.162647

[40]
y = -2137.292725
x = 1850.811768
z = 15.166531

[41]
y = -2067.459229
x = 1851.889282
z = 15.021821

[42]
y = -2067.483887
x = 1873.536133
z = 15.021832

[43]
y = -2066.131836
x = 1895.265625
z = 15.025702

[44]
y = -1999.150146
x = 2464.539795
z = 13.546875

[45]
y = -1998.876831
x = 2483.878174
z = 13.834324

[46]
y = -2001.373657
x = 2508.704346
z = 13.546875

[47]
y = -2000.292603
x = 2522.832275
z = 13.782611

[48]
y = -2017.450928
x = 2520.672363
z = 13.546875

[49]
y = -2018.511353
x = 2508.084473
z = 13.546875

[50]
y = -2017.833252
x = 2485.900879
z = 13.546875

[51]
y = -2017.777710
x = 2465.692871
z = 13.546875

[52]
y = -2018.210205
x = 2437.872314
z = 13.546875

[53]
y = -2017.040039
x = 2695.278320
z = 13.535845

[54]
y = -2015.823486
x = 2674.327148
z = 13.554415

[55]
y = -2021.929443
x = 2647.882324
z = 13.546875

[56]
y = -2011.481567
x = 2637.626953
z = 13.813861

[57]
y = -1993.199707
x = 2638.884033
z = 13.993547

[58]
y = -1992.295898
x = 2653.348877
z = 13.554781

[59]
y = -1992.001465
x = 2675.255371
z = 13.993547

[60]
y = -1993.382568
x = 2695.926514
z = 13.554688

[61]
y = -1884.587769
x = 2241.819824
z = 13.546875

[62]
y = -1884.705933
x = 2269.251709
z = 13.546875

[63]
y = -1884.779663
x = 2296.565430
z = 13.596452

[64]
y = -1906.167114
x = 2233.513916
z = 13.844491

[65]
y = -1906.083130
x = 2257.003418
z = 13.982710

[66]
y = -1906.039063
x = 2280.365234
z = 14.041756

[67]
y = -1714.983032
x = 2386.147217
z = 13.609709

[68]
y = -1717.351074
x = 2310.206055
z = 14.328125

[69]
y = -1366.143433
x = 2854.737793
z = 14.164063

[70]
y = -1334.957520
x = 2844.930420
z = 13.217712

[71]
y = -1188.298462
x = 2807.988281
z = 25.353823

[72]
y = -1178.320190
x = 2808.364014
z = 25.365505

[73]
y = -955.201477
x = 2583.344727
z = 81.378288

[74]
y = -958.092529
x = 2554.918457
z = 82.687294

[75]
y = -949.199402
x = 2499.244141
z = 82.267265

[76]
y = -964.198792
x = 2471.890869
z = 80.137169

[77]
y = -1090.080688
x = 2570.992920
z = 66.720993

[78]
y = -1027.990601
x = 2510.472900
z = 70.085938

[79]
y = -1013.637695
x = 2462.006348
z = 59.773438

[80]
y = -1054.346313
x = 2455.193115
z = 59.742188

[81]
y = -1056.111816
x = 2437.026611
z = 54.513874

[82]
y = -1116.599976
x = 1886.706055
z = 25.273438

[83]
y = -1115.125854
x = 1905.755493
z = 25.983864

[84]
y = -1117.279541
x = 1939.215820
z = 26.453125

[85]
y = -1116.691406
x = 2000.152100
z = 26.781250

[86]
y = -1123.525879
x = 2091.733643
z = 27.137428

[87]
y = -1145.371826
x = 2093.070557
z = 25.819138

[88]
y = -1166.318604
x = 2089.787598
z = 25.695076

[89]
y = -1185.260742
x = 2089.086670
z = 26.345697

[90]
y = -1232.529297
x = 2090.236816
z = 24.712194

[91]
y = -1242.008789
x = 2111.037109
z = 25.664116

[92]
y = -1230.785400
x = 2136.358887
z = 23.976563

[93]
y = -1240.825928
x = 2153.883057
z = 25.089220

[94]
y = -1282.178345
x = 2132.278564
z = 25.742849

[95]
y = -1281.000244
x = 2110.970459
z = 25.687500

[96]
y = -1280.832642
x = 2091.659424
z = 25.686659

[97]
y = -1319.352051
x = 2101.041992
z = 25.742796

[98]
y = -1318.403320
x = 2126.758301
z = 26.014166

[99]
y = -1317.699829
x = 2148.739502
z = 25.743345

[100]
y = 187.301605
x = 2361.527100
z = 28.230867

[101]
y = 166.036499
x = 2361.954102
z = 28.445313

[102]
y = 162.216797
x = 2326.620850
z = 28.075809

[103]
y = 142.090195
x = 2361.390869
z = 28.161427

[104]
y = 136.373703
x = 2326.536621
z = 28.118742

[105]
y = 116.126900
x = 2361.388916
z = 28.160431

[106]
y = 116.192001
x = 2326.206787
z = 28.286869

[107]
y = 108.925797
x = 2398.411621
z = 28.043835

[108]
y = 71.100899
x = 2376.160156
z = 28.310637

[109]
y = 42.281601
x = 2376.538818
z = 28.117622

[110]
y = 21.936199
x = 2376.223877
z = 28.278156

[111]
y = 17.903799
x = 2413.980957
z = 26.882187

[112]
y = -3.257500
x = 2410.555908
z = 26.889629

[113]
y = -8.655000
x = 2376.659668
z = 28.056023

[114]
y = -62.563801
x = 2365.393311
z = 27.721706

[115]
y = -45.652500
x = 2367.222656
z = 27.816662

[116]
y = -51.574200
x = 2391.971191
z = 27.869835

[117]
y = -49.253502
x = 2415.794678
z = 28.098230

[118]
y = -51.288502
x = 2438.420898
z = 27.696943

[119]
y = -25.987301
x = 2484.552979
z = 28.258368

[120]
y = 9.164500
x = 2488.453857
z = 28.165508

[121]
y = 8.683800
x = 2509.566895
z = 27.790663

[122]
y = -25.662800
x = 2513.366211
z = 28.092960

[123]
y = -2.751400
x = 2550.577637
z = 26.756153

[124]
y = 22.928200
x = 2548.544922
z = 27.675648

[125]
y = 354.643494
x = 1427.654175
z = 18.843750

[126]
y = 57.430801
x = 2548.911621
z = 27.675646

[127]
y = 323.331512
x = 1414.402466
z = 18.843750

[128]
y = 340.610504
x = 1462.148804
z = 18.843750

[129]
y = 92.388000
x = 2547.653076
z = 27.675648

[130]
y = 359.923492
x = 1486.323120
z = 19.404951

[131]
y = 128.383698
x = 2533.846924
z = 26.881168

[132]
y = 125.942398
x = 2518.152100
z = 27.675646

[133]
y = 126.262901
x = 2484.040039
z = 27.675648

[134]
y = 91.073502
x = 2510.288818
z = 26.931919

[135]
y = 373.366791
x = 1450.585815
z = 19.090599

[136]
y = 92.176498
x = 2446.406250
z = 28.185196

[137]
y = 66.581802
x = 2480.658203
z = 26.938601

[138]
y = 59.325802
x = 2413.639648
z = 28.247730

[139]
y = -121.896301
x = 2322.461182
z = 28.075886

[140]
y = -121.387901
x = 2293.962158
z = 27.759613

[141]
y = -116.333199
x = 2272.184082
z = 28.156250

[142]
y = -118.754997
x = 2245.501465
z = 27.774334

[143]
y = -89.471100
x = 2206.918457
z = 27.601347

[144]
y = -60.443001
x = 2200.821777
z = 27.775185

[145]
y = -37.883099
x = 2203.406494
z = 27.825956

[146]
y = -5.204000
x = 2245.133545
z = 27.771832

[147]
y = -10.910100
x = 2270.454834
z = 27.856579

[148]
y = 108.854698
x = 2269.410156
z = 27.823061

[149]
y = 108.710899
x = 2249.358154
z = 27.928553

[150]
y = 62.174400
x = 2206.819336
z = 27.811768

[151]
y = 106.155800
x = 2207.494629
z = 27.673994

[152]
y = 164.442795
x = 2257.897705
z = 27.545883

[153]
y = 158.682693
x = 2285.989502
z = 27.784557

[154]
y = 191.650101
x = 1301.440918
z = 20.460938

[155]
y = 171.980103
x = 1293.469116
z = 20.460938

[156]
y = 158.899994
x = 1285.730469
z = 20.462719

[157]
y = 142.149002
x = 1299.223022
z = 20.414677

[158]
y = 171.608902
x = 1312.691040
z = 20.460938

[159]
y = -33.049301
x = 246.683197
z = 1.578125

[160]
y = -51.115398
x = 271.570404
z = 2.035622

[161]
y = -55.206501
x = 292.628998
z = 1.946589

[162]
y = -92.450996
x = 314.877289
z = 3.484857

[163]
y = -121.305702
x = 315.358185
z = 3.239730

[164]
y = -121.259499
x = 250.705704
z = 3.471401

[165]
y = -92.238701
x = 250.307693
z = 3.268524

[166]
y = -109.433800
x = 206.635803
z = 4.896471

[167]
y = -273.643188
x = 254.837204
z = 1.583575

[168]
y = -301.444214
x = 258.720703
z = 1.578125

[169]
y = -303.587402
x = 228.866699
z = 1.926183

[170]
y = -590.283630
x = 743.764893
z = 18.012922

[171]
y = -554.506714
x = 744.615112
z = 18.012926

[172]
y = -554.665771
x = 766.643921
z = 18.012924

[173]
y = -511.340515
x = 818.755981
z = 18.012922

[174]
y = -508.221191
x = 794.452393
z = 18.012922

[175]
y = -505.728088
x = 768.618286
z = 18.012926

[176]
y = -511.339813
x = 743.432800
z = 18.012922

[177]
y = -299.428497
x = 1104.384644
z = 74.390625

[178]
y = -1400.612671
x = 2148.811768
z = 25.798033

[179]
y = -1419.001831
x = 2148.407715
z = 25.715298

[180]
y = -1433.647705
x = 2147.371094
z = 25.539063

[181]
y = -1446.417969
x = 2149.975830
z = 25.774595

[182]
y = -1484.807129
x = 2146.219238
z = 25.862787

[183]
y = -1470.478027
x = 2192.487793
z = 25.779961

[184]
y = -1456.059082
x = 2193.277588
z = 25.539063

[185]
y = -1419.112671
x = 2190.618408
z = 25.984953

[186]
y = -1282.271729
x = 2250.191406
z = 25.367188

[187]
y = -1282.658325
x = 2229.714111
z = 25.367188

[188]
y = -1278.309570
x = 2191.706787
z = 24.785187

[189]
y = -1236.596069
x = 2249.793213
z = 25.722002

[190]
y = -1237.410522
x = 2191.808594
z = 23.976563

[191]
y = -1240.562866
x = 2472.459717
z = 31.949903

[192]
y = -1240.970581
x = 2492.464355
z = 37.136921

[193]
y = -1235.818970
x = 2550.904297
z = 49.001362

[194]
y = -1195.945068
x = 2520.697021
z = 56.441933

[195]
y = -1195.276733
x = 2550.069580
z = 60.751026

[196]
y = -1339.006958
x = 2441.540039
z = 24.000000

[197]
y = -1303.070557
x = 2436.078369
z = 24.699257

[198]
y = -1274.842529
x = 2435.932861
z = 24.324863

[199]
y = -1295.920776
x = 2468.446289
z = 29.926687

[200]
y = -1055.290527
x = 2022.896118
z = 25.100996

[201]
y = -1061.402100
x = 2036.022095
z = 25.334686

[202]
y = -1068.015991
x = 2050.610840
z = 25.301126

[203]
y = -997.521790
x = 2184.216309
z = 65.701775

[204]
y = -1020.768372
x = 2261.005859
z = 59.279964

[205]
y = -1040.349121
x = 2355.698242
z = 54.148438

[206]
y = -884.549011
x = 1421.756592
z = 50.624660

[207]
y = -904.316406
x = 1468.459595
z = 54.835938

[208]
y = -883.911682
x = 1537.375000
z = 57.657482

[209]
y = -851.265381
x = 1538.399536
z = 64.336060

[210]
y = -800.121216
x = 1533.128906
z = 72.558334

[211]
y = -774.109070
x = 1526.351196
z = 79.897408

[212]
y = -689.793030
x = 1496.998413
z = 94.820488

[213]
y = -630.535400
x = 1442.465088
z = 95.718567

[214]
y = -631.472717
x = 1331.315430
z = 109.134903

[215]
y = -800.289124
x = 1298.511841
z = 84.140625

[216]
y = -804.682983
x = 1093.790527
z = 107.417801

[217]
y = -811.097290
x = 1034.139282
z = 101.851563

[218]
y = -769.773804
x = 977.434082
z = 112.202629

[219]
y = -761.806274
x = 1016.959717
z = 112.563019

[220]
y = -829.007813
x = 987.350830
z = 95.468575

[221]
y = -846.545288
x = 936.633301
z = 93.864807

[222]
y = -860.170105
x = 828.598572
z = 69.921875

[223]
y = -893.222900
x = 836.993225
z = 68.768898

[224]
y = -997.798279
x = 725.580017
z = 52.734375

[225]
y = -1059.395508
x = 698.814270
z = 49.421692

[226]
y = -1117.961914
x = 644.388672
z = 44.207039

[227]
y = -1155.590210
x = 415.918793
z = 76.687614

[228]
y = -1196.378906
x = 351.006012
z = 76.515625

[229]
y = -1156.074951
x = 298.609985
z = 80.914063

[230]
y = -741.898987
x = 1110.519531
z = 100.132927

[231]
y = -645.658630
x = 1095.128540
z = 113.600716

[232]
y = -640.988586
x = 1044.612061
z = 120.117188

[233]
y = -675.604370
x = 979.233398
z = 121.976257

[234]
y = -678.303589
x = 899.433228
z = 116.890442

[235]
y = -708.830078
x = 945.303772
z = 122.210938

[236]
y = -715.788025
x = 868.189697
z = 105.679688

[237]
y = -744.375183
x = 849.371521
z = 94.969269

[238]
y = -758.942322
x = 809.998230
z = 76.531364

[239]
y = -1251.502808
x = 431.220215
z = 51.580940

[240]
y = -1270.018555
x = 399.757507
z = 50.019791

[241]
y = -1337.117432
x = 297.707794
z = 53.441513

[242]
y = -1366.142090
x = 255.696594
z = 53.109375

[243]
y = -1308.163818
x = 191.872894
z = 70.296860

[244]
y = -1404.122559
x = 228.638794
z = 51.609795

[245]
y = -1251.957520
x = 220.781799
z = 78.304413

[246]
y = -1221.783691
x = 252.467499
z = 75.367897

[247]
y = -1468.920532
x = 144.442001
z = 25.210938

[248]
y = -1714.109497
x = 651.945007
z = 14.483046

[249]
y = -1693.966187
x = 650.701782
z = 14.657353

[250]
y = -1652.468018
x = 654.660400
z = 14.597724

[251]
y = -1619.912842
x = 651.278625
z = 15.000000

[252]
y = -1600.517212
x = 693.176880
z = 14.308498

[253]
y = -1605.977417
x = 764.569214
z = 13.419926

[254]
y = -1655.601074
x = 765.758911
z = 4.822579

[255]
y = -1696.674927
x = 767.543213
z = 4.846974

[256]
y = -1745.972412
x = 766.912598
z = 12.532471

[257]
y = -1755.301025
x = 791.786621
z = 13.410003

[258]
y = -1729.147339
x = 799.149719
z = 13.546875

[259]
y = -1707.433716
x = 795.949585
z = 13.546875

[260]
y = -1691.046021
x = 797.303711
z = 13.827294

[261]
y = -1662.784058
x = 790.987122
z = 13.485004

[262]
y = -1638.103760
x = 893.701172
z = 14.948078

[263]
y = -1635.877686
x = 865.919006
z = 14.929688

[264]
y = -1094.201904
x = 1101.208984
z = 28.370615

[265]
y = -1067.767944
x = 1100.363403
z = 31.337341

[266]
y = -1081.332520
x = 1071.320190
z = 27.073992

[267]
y = -1057.029785
x = 1051.076782
z = 34.796875

[268]
y = -1056.072388
x = 993.675903
z = 33.576809

[269]
y = -1070.747559
x = 974.375122
z = 26.418390

[270]
y = -1023.671082
x = 1118.047363
z = 34.992188

[271]
y = -1024.158447
x = 1127.965088
z = 34.992188

[272]
y = -974.053772
x = 1111.370117
z = 42.765625

[273]
y = -1068.366943
x = 1144.229492
z = 31.546803

[274]
y = -1094.690674
x = 1143.890381
z = 28.146297

[275]
y = -1100.511353
x = 1180.182617
z = 27.577995

[276]
y = -1074.405029
x = 1180.718018
z = 31.276983

[277]
y = -1074.724365
x = 1244.635864
z = 31.194912

[278]
y = -1101.159180
x = 1245.478638
z = 27.053202

[279]
y = -1705.708496
x = 695.343079
z = 3.424378

[280]
y = -1689.638672
x = 697.227783
z = 3.722885

[281]
y = -1646.015381
x = 695.737183
z = 3.568195

[282]
y = -1626.851929
x = 699.560303
z = 3.425211

[283]
y = -1516.864990
x = 901.913513
z = 13.562899

[284]
y = -1520.214722
x = 851.680481
z = 13.554688

[285]
y = -1502.981934
x = 822.528503
z = 13.593750

[286]
y = -1475.161011
x = 898.618408
z = 13.548472

[287]
y = -1473.364380
x = 841.107971
z = 13.601570

[288]
y = -1456.470337
x = 811.882324
z = 13.546278

[289]
y = -1422.118286
x = 880.173584
z = 14.478306

[290]
y = -1420.891602
x = 852.283875
z = 13.343791

[291]
y = -1421.841187
x = 824.544678
z = 14.488877

[292]
y = -1091.844727
x = 1283.292480
z = 28.257813

[293]
y = -1065.730713
x = 1283.335327
z = 31.671875

[294]
y = -1066.055664
x = 1327.960449
z = 31.553154

[295]
y = -1092.341064
x = 1327.595337
z = 27.976563

[296]
y = -1088.803589
x = 1379.133789
z = 27.170919

[297]
y = -922.720703
x = 1409.036255
z = 38.151672

[298]
y = -1092.593750
x = 497.867889
z = 82.358147

[299]
y = -1074.396606
x = 558.132324
z = 72.921989

[300]
y = -927.668030
x = 1438.746338
z = 39.640625

[301]
y = -1832.312622
x = 982.259583
z = 12.734879

[302]
y = -1829.150391
x = 970.933411
z = 12.867951

[303]
y = -1820.878296
x = 924.920776
z = 12.740897

[304]
y = -1819.497314
x = 913.320679
z = 12.756691

[305]
y = -1771.486084
x = 315.787292
z = 4.683291

[306]
y = -1766.183228
x = 295.385101
z = 4.545435

[307]
y = -1769.173096
x = 280.882385
z = 4.501231

[308]
y = -1590.433960
x = -91.610199
z = 2.617188

[309]
y = -1563.575195
x = -87.390404
z = 2.779498

[310]
y = -1547.502563
x = -67.538803
z = 2.617188

[311]
y = -2401.294922
x = -2218.666504
z = 32.496620

[312]
y = -2425.531006
x = -2237.066895
z = 32.299934

[313]
y = -2449.898926
x = -2203.448242
z = 31.060598

[314]
y = -2480.736084
x = -2226.074463
z = 31.816273

[315]
y = -2510.970703
x = -2198.326904
z = 31.101570

[316]
y = -2480.486328
x = -2176.265381
z = 30.926224

[317]
y = -2529.960449
x = -2179.730713
z = 31.358063

[318]
y = -2545.638184
x = -2160.150635
z = 31.305916

[319]
y = -2505.385254
x = -2133.446533
z = 31.307610

[320]
y = -2511.778320
x = -2088.813965
z = 31.066807

[321]
y = -2504.258545
x = -2059.977783
z = 30.841997

[322]
y = -2537.996094
x = -2068.855713
z = 30.625000

[323]
y = -2559.649414
x = -2043.643677
z = 30.625000

[324]
y = -181.038101
x = -2791.138184
z = 9.158486

[325]
y = -162.890198
x = -2791.902588
z = 9.152683

[326]
y = -145.970993
x = -2793.592529
z = 7.187500

[327]
y = -111.017097
x = -2792.997803
z = 7.187500

[328]
y = -96.807800
x = -2791.926270
z = 9.413418

[329]
y = -52.371399
x = -2791.079102
z = 9.197904

[330]
y = -35.757900
x = -2793.580811
z = 7.187500

[331]
y = -17.728300
x = -2794.208740
z = 7.187500

[332]
y = 0.525800
x = -2789.154297
z = 8.886574

[333]
y = 63.006401
x = -2788.654053
z = 9.217571

[334]
y = 92.167099
x = -2793.854736
z = 7.187500

[335]
y = 105.965401
x = -2791.830078
z = 9.179279

[336]
y = 120.162804
x = -2788.990723
z = 8.996758

[337]
y = 140.507599
x = -2791.896484
z = 8.920559

[338]
y = 184.116104
x = -2790.590332
z = 9.534413

[339]
y = 213.941193
x = -2791.923096
z = 9.185331

[340]
y = 130.363602
x = -2686.613770
z = 6.143887

[341]
y = 115.713402
x = -2688.695801
z = 6.348785

[342]
y = 93.503098
x = -2689.524902
z = 6.034745

[343]
y = 76.494598
x = -2689.395752
z = 6.584293

[344]
y = 54.806499
x = -2689.533203
z = 6.395794

[345]
y = 24.147100
x = -2723.058594
z = 6.421518

[346]
y = 2.194900
x = -2723.154541
z = 6.382502

[347]
y = -14.751000
x = -2723.057861
z = 6.200013

[348]
y = -36.774700
x = -2724.265137
z = 6.598969

[349]
y = -58.168301
x = -2722.738281
z = 4.335938

[350]
y = -92.806396
x = -2723.525391
z = 6.126784

[351]
y = -110.205200
x = -2723.037109
z = 5.791803

[352]
y = -127.913002
x = -2721.267090
z = 4.335938

[353]
y = -156.086899
x = -2726.248047
z = 6.348399

[354]
y = -184.466797
x = -2726.162354
z = 6.290074

[355]
y = -187.867706
x = -2689.048096
z = 6.124667

[356]
y = -152.712296
x = -2691.361328
z = 4.335938

[357]
y = -124.770203
x = -2686.564941
z = 6.186805

[358]
y = -89.405296
x = -2689.646729
z = 4.335938

[359]
y = -99.704201
x = -2621.389893
z = 6.250084

[360]
y = -117.972801
x = -2620.719727
z = 6.423328

[361]
y = -134.748398
x = -2619.304443
z = 4.335938

[362]
y = -162.824707
x = -2623.963867
z = 6.369110

[363]
y = -191.367004
x = -2624.228027
z = 6.547096

[364]
y = 682.595215
x = -2862.798828
z = 23.411922

[365]
y = 737.015930
x = -2881.605225
z = 29.413490

[366]
y = 790.113525
x = -2878.881104
z = 35.489437

[367]
y = 834.706787
x = -2858.535400
z = 40.081047

[368]
y = 877.369202
x = -2838.372559
z = 44.061825

[369]
y = 914.700317
x = -2841.947266
z = 44.054688

[370]
y = 957.679321
x = -2856.238037
z = 44.051315

[371]
y = 990.642273
x = -2879.358887
z = 40.722214

[372]
y = 1034.334961
x = -2899.439453
z = 36.648220

[373]
y = 1073.812622
x = -2898.959961
z = 32.132813

[374]
y = 1111.669434
x = -2903.187256
z = 27.058102

[375]
y = 1164.924805
x = -2903.405029
z = 13.664063

[376]
y = 1147.369141
x = -2563.705566
z = 55.726563

[377]
y = 1141.797119
x = -2534.893311
z = 55.726563

[378]
y = 1140.588623
x = -2506.529785
z = 55.726563

[379]
y = 1139.221924
x = -2478.921875
z = 55.726563

[380]
y = 1139.780640
x = -2451.263428
z = 55.733276

[381]
y = 1137.014893
x = -2424.435303
z = 55.726563

[382]
y = 1131.225342
x = -2396.956787
z = 55.733276

[383]
y = 1120.522827
x = -2370.061279
z = 55.733276

[384]
y = 898.890686
x = -2099.571777
z = 76.710938

[385]
y = 891.819519
x = -2059.041504
z = 61.858627

[386]
y = 1088.913818
x = -2279.815674
z = 80.081184

[387]
y = 1070.275024
x = -2280.648438
z = 81.527519

[388]
y = 1046.617676
x = -2280.406982
z = 83.948997

[389]
y = 1023.072083
x = -2280.531982
z = 83.951820

[390]
y = 1037.593384
x = -2241.790771
z = 83.843750

[391]
y = 1054.081299
x = -2242.295654
z = 83.066872

[392]
y = 1070.689087
x = -2241.890625
z = 81.161446

[393]
y = 1105.930054
x = -2228.035400
z = 80.007813

[394]
y = 1106.130981
x = -2208.158447
z = 80.007813

[395]
y = 1106.038818
x = -2188.187744
z = 80.007813

[396]
y = 1105.664551
x = -2168.229736
z = 80.007813

[397]
y = 1081.945313
x = -2172.945313
z = 80.007813

[398]
y = 1082.032349
x = -2191.295654
z = 80.007813

[399]
y = 1081.802490
x = -2209.652344
z = 80.007813

[400]
y = 1081.656250
x = -2227.949219
z = 80.007813

[401]
y = 1188.291016
x = -2139.885742
z = 55.726563

[402]
y = 1188.318359
x = -1982.467651
z = 45.445313

[403]
y = 1066.989014
x = -2158.173828
z = 80.007813

[404]
y = 1048.536377
x = -2158.103027
z = 80.007813

[405]
y = 1087.625610
x = -2128.195068
z = 80.007813

[406]
y = 1069.229248
x = -2128.018799
z = 80.007813

[407]
y = 1050.943481
x = -2128.316162
z = 80.007813

[408]
y = 1032.639648
x = -2128.035645
z = 80.007813

[409]
y = 1014.287903
x = -2128.174805
z = 80.007813

[410]
y = 996.301697
x = -2128.072266
z = 80.007813

[411]
y = 978.612793
x = -2128.128174
z = 80.007813

[412]
y = 942.674805
x = -2131.863037
z = 80.000000

[413]
y = 947.051392
x = -2158.140869
z = 80.000000

[414]
y = 965.398315
x = -2158.243652
z = 80.000000

[415]
y = 983.604614
x = -2158.549072
z = 80.000000

[416]
y = 1001.982422
x = -2158.361572
z = 80.000000

[417]
y = 1026.032593
x = -2169.580322
z = 80.007813

[418]
y = 916.492676
x = -2280.850830
z = 66.648438

[419]
y = 888.815002
x = -2236.435791
z = 66.654396

[420]
y = 870.466980
x = -2236.666016
z = 66.645073

[421]
y = 786.244873
x = -2242.004883
z = 49.400818

[422]
y = 742.274780
x = -2223.891846
z = 49.442696

[423]
y = 753.510620
x = -2156.840576
z = 69.553383

[424]
y = 786.252502
x = -2156.838623
z = 69.553413

[425]
y = 830.637512
x = -2157.171387
z = 69.556068

[426]
y = 797.971680
x = -2112.572510
z = 69.562500

[427]
y = 798.072327
x = -2094.355957
z = 69.562500

[428]
y = 821.115417
x = -2094.138672
z = 69.562500

[429]
y = 820.797607
x = -2112.409424
z = 69.562500

[430]
y = 755.535217
x = -2128.775879
z = 69.562500

[431]
y = 773.709717
x = -2128.508301
z = 69.562500

[432]
y = 253.103699
x = -2632.937256
z = 6.263279

[433]
y = 200.556702
x = -2658.484619
z = 6.120248

[434]
y = 188.005798
x = -2654.065186
z = 4.328125

[435]
y = 186.961807
x = -2663.115234
z = 4.328125

[436]
y = 186.843994
x = -2692.954590
z = 6.299313

[437]
y = 131.324005
x = -2621.406006
z = 6.245198

[438]
y = 96.782600
x = -2617.932617
z = 4.335938

[439]
y = 78.414001
x = -2623.677002
z = 6.164571

[440]
y = -189.322205
x = -2512.938965
z = 25.322277

[441]
y = -171.035004
x = -2512.970459
z = 25.318756

[442]
y = -153.999893
x = -2512.566162
z = 25.363955

[443]
y = -43.234501
x = -2027.697144
z = 38.804688

[444]
y = 643.902527
x = -2374.586670
z = 35.171875

[445]
y = 711.821716
x = -2371.260498
z = 35.170193

[446]
y = 818.806091
x = -2447.470215
z = 35.179688

[447]
y = 730.473816
x = -2637.229004
z = 30.070313

[448]
y = 719.827881
x = -2665.498779
z = 27.936325

[449]
y = 721.220093
x = -2731.548584
z = 41.273438

[450]
y = 771.661072
x = -2740.298584
z = 54.382813

[451]
y = 797.724915
x = -2740.919434
z = 53.112282

[452]
y = 818.629700
x = -2700.363037
z = 49.984375

[453]
y = 805.071106
x = -2709.749023
z = 49.976563

[454]
y = 805.599792
x = -2677.277100
z = 49.984375

[455]
y = 805.200195
x = -2670.508057
z = 49.984375

[456]
y = 805.362915
x = -2645.530029
z = 49.984375

[457]
y = 818.132080
x = -2641.970703
z = 49.984375

[458]
y = 818.190125
x = -2667.040039
z = 49.984375

[459]
y = 920.789673
x = -2721.989258
z = 67.593750

[460]
y = 867.570618
x = -2706.519775
z = 70.703125

[461]
y = 929.933899
x = -2671.353271
z = 79.703125

[462]
y = 879.186584
x = -2662.080811
z = 79.773796

[463]
y = 933.609192
x = -2641.226563
z = 71.953125

[464]
y = 969.956177
x = -2711.836670
z = 54.460938

[465]
y = 986.630188
x = -2658.959229
z = 64.984375

[466]
y = 1000.628296
x = -2514.187012
z = 78.343750

[467]
y = 987.872681
x = -2514.447998
z = 78.343750

[468]
y = 987.794800
x = -2538.940918
z = 78.289063

[469]
y = 942.865173
x = -2513.899658
z = 65.229164

[470]
y = 919.516174
x = -2502.984375
z = 65.045959

[471]
y = 897.902283
x = -2502.907959
z = 64.971397

[472]
y = 897.372620
x = -2471.822021
z = 63.159069

[473]
y = 919.123718
x = -2471.921387
z = 63.164085

[474]
y = 930.604126
x = -2400.042480
z = 45.445313

[475]
y = 897.258423
x = -2413.056641
z = 45.564251

[476]
y = 830.829895
x = -2515.822266
z = 49.998150

[477]
y = 733.176086
x = -2538.098633
z = 28.900503

[478]
y = 932.453308
x = -2229.253418
z = 66.648438

[479]
y = 897.487671
x = -2014.335938
z = 45.445313

[480]
y = 1274.852051
x = -1970.569946
z = 7.187500

[481]
y = 1263.645508
x = -2043.790039
z = 8.955893

[482]
y = 2447.697754
x = -2479.489014
z = 17.323023

[483]
y = 2449.593018
x = -2472.064941
z = 17.323023

[484]
y = 2447.197266
x = -2424.771484
z = 13.204474

[485]
y = 2445.460693
x = -2387.264648
z = 10.169355

[486]
y = 2442.825684
x = -2379.966309
z = 10.169355

[487]
y = 2421.503906
x = -2349.727295
z = 7.266051

[488]
y = 2411.793945
x = -2397.037109
z = 8.896343

[489]
y = 2408.711670
x = -2420.296143
z = 13.160889

[490]
y = 2403.309570
x = -2632.839111
z = 11.339975

[491]
y = 2377.453857
x = -2631.127197
z = 9.062681

[492]
y = 2357.878906
x = -2625.264893
z = 8.820223

[493]
y = 2351.813477
x = -2633.744873
z = 8.529648

[494]
y = 2318.661133
x = -2624.693848
z = 8.291161

[495]
y = 2309.922119
x = -2624.937500
z = 8.293125

[496]
y = 2291.945313
x = -2625.245850
z = 8.295609

[497]
y = 2283.375000
x = -2625.429199
z = 8.297087

[498]
y = 2357.236572
x = -2599.796387
z = 9.882996

[499]
y = 2364.560303
x = -2599.401123
z = 9.882996

[500]
y = 2241.054932
x = -2522.677002
z = 5.124314

[501]
y = 2268.836426
x = -2550.991943
z = 5.271583

[502]
y = 2300.340576
x = -2580.893799
z = 7.002886

[503]
y = 2308.092529
x = -2581.495361
z = 7.002886

[504]
y = 2352.489014
x = -2436.904053
z = 4.968750

[505]
y = 2493.326904
x = -2422.260010
z = 13.158347

[506]
y = 2515.454346
x = -2446.530273
z = 15.250000

[507]
y = 2493.070313
x = -2446.132568
z = 15.320313

[508]
y = 2490.409912
x = -2465.503662
z = 16.854977

[509]
y = 2507.861572
x = -2479.000488
z = 17.799484

[510]
y = 2485.801514
x = -2479.034180
z = 17.781250

[511]
y = 2683.608398
x = -1491.474609
z = 55.835938

[512]
y = 2701.500977
x = -1478.445068
z = 55.835938

[513]
y = 2690.715088
x = -1466.765259
z = 55.835938

[514]
y = 2688.287354
x = -1450.980469
z = 55.951374

[515]
y = 2656.395996
x = -1444.148804
z = 55.835938

[516]
y = 2635.905273
x = -1442.421631
z = 55.835938

[517]
y = 2653.374512
x = -1457.414795
z = 55.835938

[518]
y = 2693.492920
x = -1511.855347
z = 55.835938

[519]
y = 2686.111328
x = -1527.913574
z = 55.835938

[520]
y = 2697.114502
x = -1551.271484
z = 55.835938

[521]
y = 2712.037109
x = -1562.888916
z = 55.835938

[522]
y = 2689.769287
x = -1601.406372
z = 55.114525

[523]
y = 2654.635986
x = -1534.202515
z = 56.281361

[524]
y = 2643.781006
x = -1513.232666
z = 55.835938

[525]
y = 1560.545654
x = -882.119690
z = 25.914063

[526]
y = 1554.786865
x = -884.314026
z = 25.914063

[527]
y = 1536.691650
x = -884.259216
z = 25.914063

[528]
y = 1533.482544
x = -881.689819
z = 25.914063

[529]
y = 1515.723267
x = -886.262207
z = 25.914063

[530]
y = 1517.029785
x = -905.728577
z = 26.316807

[531]
y = 1526.605103
x = -904.968079
z = 25.914063

[532]
y = 1544.950439
x = -905.554871
z = 25.914063

[533]
y = 1590.412598
x = -828.909302
z = 27.034626

[534]
y = 1615.764038
x = -766.099670
z = 27.117188

[535]
y = 1430.505615
x = -743.052917
z = 15.949762

[536]
y = 1435.741211
x = -716.244019
z = 18.476563

[537]
y = 1448.370972
x = -688.833313
z = 17.494930

[538]
y = 1446.968140
x = -656.463318
z = 13.617188

[539]
y = 1450.644775
x = -652.640015
z = 13.617188

[540]
y = 1443.904297
x = -635.557617
z = 13.617188

[541]
y = 1113.080811
x = 10.484300
z = 20.939867

[542]
y = 1115.068848
x = -20.758301
z = 20.100124

[543]
y = 1122.716431
x = -43.979000
z = 20.198132

[544]
y = 1078.494873
x = 1.132000
z = 20.128025

[545]
y = 1074.081543
x = -37.379799
z = 20.216791

[546]
y = 1079.038452
x = -147.400101
z = 19.742188

[547]
y = 1038.090210
x = -34.747398
z = 20.939867

[548]
y = 1174.632324
x = 98.861603
z = 20.940155

[549]
y = 1162.331543
x = 81.356102
z = 20.940155

[550]
y = 1176.689697
x = -251.251801
z = 20.205742

[551]
y = 1153.628540
x = -258.840698
z = 20.087292

[552]
y = 1122.535278
x = -260.818909
z = 20.939867

[553]
y = 1174.388794
x = -290.333313
z = 20.939867

[554]
y = 1172.684204
x = -332.585693
z = 20.178394

[555]
y = 1167.684204
x = -367.733398
z = 20.271875

[556]
y = 1139.233643
x = -360.269409
z = 20.939867

[557]
y = 1108.097412
x = -362.307587
z = 20.079964

[558]
y = 1126.490601
x = -321.185913
z = 20.220007

[559]
y = 1115.022705
x = -300.944000
z = 20.043533

[560]
y = 1083.592041
x = -255.905594
z = 20.939867

[561]
y = 1051.594482
x = -251.289093
z = 20.212004

[562]
y = 1003.627319
x = -276.308502
z = 20.939867

[563]
y = 1001.653015
x = -245.395599
z = 20.118456

[564]
y = 1229.298584
x = -86.337097
z = 22.440262

[565]
y = 1218.524658
x = -68.547897
z = 22.440262

[566]
y = 772.521484
x = 2013.904297
z = 11.460938

[567]
y = 773.379211
x = 2043.190918
z = 11.453125

[568]
y = 774.036316
x = 2071.769287
z = 11.453125

[569]
y = 772.739685
x = 2094.091064
z = 11.453125

[570]
y = 773.595825
x = 2123.281006
z = 11.445313

[571]
y = 734.263916
x = 2122.614746
z = 11.460938

[572]
y = 732.828674
x = 2093.443359
z = 11.453125

[573]
y = 732.392517
x = 2064.962891
z = 11.460938

[574]
y = 733.654297
x = 2042.610962
z = 11.460938

[575]
y = 732.727783
x = 2013.194214
z = 11.453125

[576]
y = 692.398682
x = 2011.431519
z = 11.460938

[577]
y = 693.695374
x = 2040.652832
z = 11.453125

[578]
y = 694.049011
x = 2069.136230
z = 11.460938

[579]
y = 692.433105
x = 2091.166016
z = 11.460938

[580]
y = 693.797913
x = 2120.332031
z = 11.453125

[581]
y = 654.148804
x = 2123.319824
z = 11.460938

[582]
y = 652.958130
x = 2094.131104
z = 11.460938

[583]
y = 652.524292
x = 2065.719971
z = 11.460938

[584]
y = 654.143677
x = 2043.531372
z = 11.460938

[585]
y = 652.714478
x = 2014.259155
z = 11.460938

[586]
y = 772.284485
x = 2166.833252
z = 11.460938

[587]
y = 733.719116
x = 2177.503906
z = 11.460938

[588]
y = 734.169617
x = 2206.058838
z = 11.460938

[589]
y = 732.837708
x = 2228.307617
z = 11.460938

[590]
y = 733.691223
x = 2257.469238
z = 11.460938

[591]
y = 692.928772
x = 2256.831299
z = 11.453125

[592]
y = 692.630127
x = 2228.575684
z = 11.453125

[593]
y = 693.717773
x = 2206.452148
z = 11.460938

[594]
y = 693.275879
x = 2177.348633
z = 11.460938

[595]
y = 653.423279
x = 2177.937256
z = 11.460938

[596]
y = 654.089722
x = 2206.538330
z = 11.460938

[597]
y = 652.457581
x = 2228.733643
z = 11.460938

[598]
y = 653.381470
x = 2258.136963
z = 11.453125

[599]
y = 734.091187
x = 2346.469971
z = 11.460938

[600]
y = 741.161072
x = 1847.569092
z = 11.460938

[601]
y = 718.823792
x = 1846.243896
z = 11.460938

[602]
y = 690.277771
x = 1847.088135
z = 11.453125

[603]
y = 661.195190
x = 1848.314209
z = 11.460938

[604]
y = 732.816589
x = 2369.117676
z = 11.460938

[605]
y = 733.692871
x = 2398.333740
z = 11.460938

[606]
y = 692.668213
x = 2396.703125
z = 11.453125

[607]
y = 692.410828
x = 2368.436768
z = 11.453125

[608]
y = 694.270630
x = 2346.495361
z = 11.460938

[609]
y = 692.952393
x = 2317.241455
z = 11.460938

[610]
y = 653.338501
x = 2317.746826
z = 11.453125

[611]
y = 654.246887
x = 2346.334961
z = 11.453125

[612]
y = 652.669617
x = 2368.327393
z = 11.460938

[613]
y = 653.757813
x = 2397.441406
z = 11.460938

[614]
y = 662.513489
x = 2447.915527
z = 11.460938

[615]
y = 689.798218
x = 2446.542236
z = 11.460938

[616]
y = 714.393127
x = 2448.135254
z = 11.460938

[617]
y = 742.546204
x = 2447.745361
z = 11.460938

[618]
y = 2123.296387
x = 1686.749878
z = 11.460938

[619]
y = 2093.662842
x = 1687.515747
z = 11.460938

[620]
y = 2066.837891
x = 1680.279419
z = 11.359375

[621]
y = 2046.538818
x = 1686.891479
z = 11.468750

[622]
y = 2044.809814
x = 1639.513794
z = 11.312500

[623]
y = 2075.766113
x = 1637.879272
z = 11.312500

[624]
y = 2102.889160
x = 1637.959839
z = 11.312500

[625]
y = 2129.924805
x = 1645.601929
z = 11.203125

[626]
y = 2149.698242
x = 1638.636841
z = 11.312500

[627]
y = 2147.205566
x = 1598.837891
z = 11.460938

[628]
y = 2123.330078
x = 1597.804565
z = 11.460938

[629]
y = 2086.423584
x = 1595.094971
z = 11.312500

[630]
y = 2071.070068
x = 1597.453369
z = 11.312500

[631]
y = 2038.197754
x = 1597.297852
z = 11.468750

[632]
y = 2076.227051
x = 1554.405273
z = 11.359375

[633]
y = 2096.412842
x = 1547.927856
z = 11.460938

[634]
y = 2027.836792
x = 1367.872559
z = 11.460938

[635]
y = 2003.790283
x = 1366.812500
z = 11.460938

[636]
y = 1974.152588
x = 1367.534668
z = 11.460938

[637]
y = 1976.204224
x = 1317.819092
z = 11.468750

[638]
y = 2005.810547
x = 1316.652222
z = 11.460938

[639]
y = 2027.909668
x = 1317.984131
z = 11.460938

[640]
y = 1930.134399
x = 1316.470825
z = 11.460938

[641]
y = 1933.594238
x = 1336.554932
z = 11.460938

[642]
y = 1931.729858
x = 1366.540039
z = 11.460938

[643]
y = 1896.749023
x = 1367.093750
z = 11.468750

[644]
y = 1897.005127
x = 1408.751831
z = 11.460938

[645]
y = 1953.721680
x = 1412.743652
z = 11.453125

[646]
y = 1953.396118
x = 1439.901123
z = 11.460938

[647]
y = 1952.012329
x = 1462.314087
z = 11.460938

[648]
y = 1920.099487
x = 1467.033325
z = 11.460938

[649]
y = 1895.065308
x = 1466.860229
z = 11.460938

[650]
y = 1847.867310
x = 1028.296631
z = 11.460938

[651]
y = 1876.486816
x = 1028.226196
z = 11.468750

[652]
y = 1905.914185
x = 1026.901978
z = 11.460938

[653]
y = 1928.006958
x = 1028.488525
z = 11.460938

[654]
y = 1879.102905
x = 986.471375
z = 11.460938

[655]
y = 1901.148438
x = 987.905579
z = 11.460938

[656]
y = 1930.551880
x = 986.976807
z = 11.468750

[657]
y = 1928.017700
x = 928.001587
z = 11.460938

[658]
y = 1976.681763
x = 1086.728027
z = 11.468750

[659]
y = 1993.569336
x = 1084.045776
z = 11.460938

[660]
y = 2031.945190
x = 1086.315918
z = 11.460938

[661]
y = 2027.847534
x = 1028.388184
z = 11.460938

[662]
y = 2005.633911
x = 1027.026001
z = 11.460938

[663]
y = 1976.108643
x = 1028.141357
z = 11.468750

[664]
y = 1978.545410
x = 986.372620
z = 11.460938

[665]
y = 1980.450195
x = 887.820374
z = 11.460938

[666]
y = 2006.462524
x = 927.119202
z = 11.460938

[667]
y = 2027.747803
x = 928.500916
z = 11.460938

[668]
y = 2046.977173
x = 887.543091
z = 11.460938

[669]
y = 2584.635010
x = 1227.915771
z = 10.820313

[670]
y = 2616.880371
x = 1225.385376
z = 10.820313

[671]
y = 2607.694580
x = 1265.479736
z = 10.820313

[672]
y = 2608.502686
x = 1284.862915
z = 10.820313

[673]
y = 2607.759766
x = 1313.779785
z = 10.820313

[674]
y = 2608.348389
x = 1344.685425
z = 10.820313

[675]
y = 2522.395996
x = 1276.909180
z = 10.820313

[676]
y = 2554.516846
x = 1271.818604
z = 10.820313

[677]
y = 2564.295654
x = 1274.161987
z = 10.820313

[678]
y = 2524.506104
x = 1313.566406
z = 10.820313

[679]
y = 2569.751221
x = 1325.807739
z = 10.820313

[680]
y = 2569.771484
x = 1349.858765
z = 10.820313

[681]
y = 2567.895996
x = 1359.623413
z = 10.820313

[682]
y = 2525.451416
x = 1364.406738
z = 10.820313

[683]
y = 2524.505127
x = 1405.895630
z = 10.820313

[684]
y = 2570.290527
x = 1418.007446
z = 10.820313

[685]
y = 2569.762695
x = 1441.833862
z = 10.820313

[686]
y = 2567.925537
x = 1451.332397
z = 10.820313

[687]
y = 2525.470703
x = 1456.178955
z = 10.820313

[688]
y = 2535.485840
x = 1498.611816
z = 10.820313

[689]
y = 2569.875244
x = 1503.461914
z = 10.820313

[690]
y = 2567.741943
x = 1513.256226
z = 10.820313

[691]
y = 2569.713623
x = 1551.606201
z = 10.820313

[692]
y = 2567.742432
x = 1564.514160
z = 10.820313

[693]
y = 2569.710205
x = 1596.720337
z = 10.820313

[694]
y = 2569.849121
x = 1623.537354
z = 10.820313

[695]
y = 2571.776367
x = 1646.425415
z = 10.820313

[696]
y = 2571.744141
x = 1665.597656
z = 10.820313

[697]
y = 2607.829590
x = 1515.935303
z = 10.820313

[698]
y = 2607.811035
x = 1535.012695
z = 10.820313

[699]
y = 2608.452148
x = 1554.453003
z = 10.820313

[700]
y = 2607.740479
x = 1600.326050
z = 10.820313

[701]
y = 2607.522705
x = 1618.697144
z = 10.820313

[702]
y = 2608.227783
x = 1638.043579
z = 10.820313

[703]
y = 2608.347412
x = 1667.001831
z = 10.820313

[704]
y = 2648.139648
x = 1609.524170
z = 10.820313

[705]
y = 2679.403320
x = 1605.251099
z = 10.820313

[706]
y = 2659.855713
x = 1573.067383
z = 10.820313

[707]
y = 2660.790771
x = 1556.039551
z = 10.820313

[708]
y = 2713.448242
x = 1570.420166
z = 10.820313

[709]
y = 2711.368896
x = 1580.106201
z = 10.820313

[710]
y = 2711.113037
x = 1601.142212
z = 10.820313

[711]
y = 2713.329590
x = 1627.251221
z = 10.820313

[712]
y = 2711.494629
x = 1652.423462
z = 10.820313

[713]
y = 2751.817383
x = 1663.148193
z = 10.820313

[714]
y = 2750.985596
x = 1643.706177
z = 10.820313

[715]
y = 2751.581299
x = 1626.751587
z = 10.820313

[716]
y = 2751.696533
x = 1608.503662
z = 10.820313

[717]
y = 2755.127686
x = 1599.594238
z = 10.820313

[718]
y = 2757.147949
x = 1563.116211
z = 10.820313

[719]
y = 2776.604004
x = 1562.546021
z = 10.820313

[720]
y = 2793.695801
x = 1562.994019
z = 10.820313

[721]
y = 2799.803955
x = 1588.468872
z = 10.820313

[722]
y = 2803.073730
x = 1618.411011
z = 10.820313

[723]
y = 2803.975830
x = 1637.874390
z = 10.820313

[724]
y = 2803.264893
x = 1654.858643
z = 10.820313

[725]
y = 2803.275146
x = 1673.053223
z = 10.820313

[726]
y = 2843.792236
x = 1664.788574
z = 10.820313

[727]
y = 2841.739502
x = 1632.614258
z = 10.820313

[728]
y = 2843.783936
x = 1622.843994
z = 10.820313

[729]
y = 2843.738037
x = 1601.877441
z = 10.820313

[730]
y = 2841.468750
x = 1575.803101
z = 10.820313

[731]
y = 2843.796631
x = 1550.619263
z = 10.820313

[732]
y = 2693.059326
x = 1678.490967
z = 10.820313

[733]
y = 2691.489258
x = 1703.684814
z = 10.820313

[734]
y = 2693.562256
x = 1735.764282
z = 10.820313

[735]
y = 2774.467773
x = 1927.381470
z = 10.820313

[736]
y = 2764.343506
x = 1967.396851
z = 10.820313

[737]
y = 2762.440430
x = 1992.621826
z = 10.820313

[738]
y = 2764.144775
x = 2018.629395
z = 10.820313

[739]
y = 2764.185059
x = 2039.671021
z = 10.820313

[740]
y = 2761.664795
x = 2049.378174
z = 10.820313

[741]
y = 2723.730225
x = 2066.046143
z = 10.820313

[742]
y = 2722.449463
x = 2037.328979
z = 11.054918

[743]
y = 2724.071045
x = 2018.153687
z = 10.820313

[744]
y = 2723.768555
x = 1998.805176
z = 10.820313

[745]
y = 2723.468994
x = 1969.913696
z = 10.820313

[746]
y = 2724.131348
x = 1950.778442
z = 10.820313

[747]
y = 2723.935791
x = 1931.365479
z = 10.820313

[748]
y = 2662.844727
x = 1921.643066
z = 10.820313

[749]
y = 2663.114014
x = 1950.581543
z = 10.820313

[750]
y = 2661.995117
x = 1969.664795
z = 10.820313

[751]
y = 2663.073730
x = 1989.082275
z = 10.820313

[752]
y = 2662.722656
x = 2017.927368
z = 10.820313

[753]
y = 2662.081055
x = 2037.018921
z = 10.820313

[754]
y = 2662.884033
x = 2056.437744
z = 10.820313

[755]
y = -2120.784668
x = 1804.159668
z = 13.546875

[756]
y = -2121.884766
x = 1782.242432
z = 13.546875

[757]
y = -2121.549316
x = 1761.179321
z = 13.546875

[758]
y = -2127.909180
x = 1734.894897
z = 13.546875

[759]
y = -2121.375977
x = 1715.131470
z = 13.546875

[760]
y = -2122.289551
x = 1695.469482
z = 13.546875

[761]
y = -2120.101807
x = 1676.107422
z = 13.546875

[762]
y = -2110.243408
x = 1667.437500
z = 13.546875

[763]
y = -2101.137451
x = 1684.851440
z = 13.834324

[764]
y = -2104.577393
x = 1711.557495
z = 13.546875

[765]
y = -2101.493652
x = 1734.046509
z = 13.546875

[766]
y = -2105.654297
x = 1762.371582
z = 13.546875

[767]
y = -2104.360352
x = 1781.424927
z = 13.546875

[768]
y = -2103.351563
x = 1801.868408
z = 13.546875

[769]
y = 939.572815
x = -689.099487
z = 13.632813

[770]
y = 939.629395
x = -686.974915
z = 13.632813

[771]
y = 1425.305786
x = -936.354492
z = 30.106777

[772]
y = 1551.461182
x = -1047.760132
z = 33.437611

[773]
y = 1963.478516
x = -1499.563843
z = 48.421875

[774]
y = 2486.491699
x = -1665.199463
z = 87.141296

[775]
y = 2543.953125
x = -1670.267700
z = 85.462311

[776]
y = 2600.156494
x = -1669.636719
z = 81.320663

[777]
y = 2038.274170
x = -1825.421265
z = 8.450703

[778]
y = 2036.708740
x = -1806.294067
z = 9.243753

[779]
y = 1216.991943
x = 13.332500
z = 22.503162

[780]
y = 1008.355774
x = 65.070900
z = 13.665104

[781]
y = 970.886475
x = 70.325203
z = 16.164619

[782]
y = 970.950623
x = 22.962700
z = 19.744648

[783]
y = 949.587830
x = 16.813200
z = 19.935083

[784]
y = 924.342102
x = 33.634800
z = 23.585108

[785]
y = 911.120300
x = 17.604900
z = 23.833450

[786]
y = 974.789185
x = -10.594100
z = 19.805540

[787]
y = 953.910278
x = -3.987600
z = 19.655630

[788]
y = 971.629272
x = -68.905800
z = 19.905596

[789]
y = 972.490906
x = -92.570801
z = 19.912687

[790]
y = 974.443481
x = -124.699501
z = 19.840126

[791]
y = 2206.730957
x = -381.844696
z = 42.398773

[792]
y = 2217.727539
x = -385.246704
z = 42.429688

[793]
y = 2231.261963
x = -387.855408
z = 42.400146

[794]
y = 2250.029785
x = -391.032196
z = 42.333527

[795]
y = 2230.563965
x = -418.113007
z = 42.429688

[796]
y = 2237.280762
x = -431.543091
z = 42.429688

[797]
y = 2260.551514
x = -379.253113
z = 42.484375

[798]
y = 2234.675293
x = -358.643585
z = 42.484375

[799]
y = 1140.807617
x = 303.343292
z = 8.585938

[800]
y = 1161.193115
x = 398.100189
z = 7.914237

[801]
y = 1118.507080
x = 510.891510
z = 14.946717

[802]
y = 1119.542236
x = 501.814697
z = 14.735641

[803]
y = 1194.507568
x = 712.857910
z = 13.390625

[804]
y = 1207.057007
x = 714.640991
z = 13.390625

[805]
y = -1036.078003
x = 2579.453857
z = 69.582596

[806]
y = -1034.372681
x = 2558.702148
z = 69.570313

[807]
y = -1034.805542
x = 2550.710205
z = 69.581352

[808]
y = -1036.537842
x = 2526.732666
z = 69.579971

[809]
y = -1060.204346
x = 2533.734863
z = 69.568596

[810]
y = -1057.628418
x = 2529.129883
z = 69.578125

[811]
y = -1062.311157
x = 2497.892822
z = 70.132813

[812]
y = -1060.683472
x = 2478.004883
z = 66.835938

[813]
y = -1012.612183
x = 2488.336182
z = 65.398438

[814]
y = -1039.438477
x = 2391.702393
z = 53.601563

[815]
y = -1043.847290
x = 2335.190918
z = 52.351563

[816]
y = -1049.429199
x = 2288.084717
z = 49.515625

[817]
y = -1055.508423
x = 2301.228760
z = 49.542625

[818]
y = -1057.595825
x = 2247.355957
z = 54.450287

[819]
y = -1070.011963
x = 2573.336426
z = 69.297554

[820]
y = -1111.361938
x = 2521.478516
z = 56.220375

[821]
y = -1101.337402
x = 2469.815186
z = 44.131248

[822]
y = -1099.243286
x = 2457.072266
z = 43.546513

[823]
y = -1102.399048
x = 2438.583008
z = 42.582874

[824]
y = -1103.693970
x = 2407.889893
z = 39.734127

[825]
y = -1130.163208
x = 2505.927002
z = 39.521709

[826]
y = -1138.595093
x = 2487.895020
z = 38.686378

[827]
y = -1138.251465
x = 2425.514893
z = 34.155918

[828]
y = -1136.344360
x = 2394.834961
z = 30.306585

[829]
y = -1141.940918
x = 2373.924316
z = 28.432404

[830]
y = -1284.651489
x = 2207.747314
z = 24.528845

[831]
y = -1367.348999
x = 2202.582520
z = 25.677282

[832]
y = -1367.536499
x = 2185.030273
z = 25.584959

[833]
y = -1472.570801
x = 2232.610107
z = 23.844727

[834]
y = -1472.464966
x = 2247.609131
z = 23.528059

[835]
y = -1472.085205
x = 2263.828857
z = 23.292500

[836]
y = -1393.993774
x = 2256.549072
z = 24.003798

[837]
y = -1393.968384
x = 2243.604980
z = 24.003721

[838]
y = -1393.945190
x = 2230.556152
z = 24.003651

[839]
y = 300.315399
x = 716.456177
z = 20.234375

[840]
y = 288.778198
x = 705.600586
z = 20.409519

[841]
y = 305.834900
x = 750.254883
z = 20.234375

[842]
y = 266.514587
x = 723.238770
z = 22.367188

[843]
y = 260.023987
x = 747.455383
z = 27.085938

[844]
y = 279.063385
x = 749.977783
z = 27.350550

[845]
y = 60.359699
x = 340.403687
z = 3.761291

[846]
y = 55.994499
x = 315.847809
z = 3.146111

[847]
y = 41.849499
x = 310.595490
z = 2.814378

[848]
y = 44.740799
x = 284.970612
z = 2.533167

[849]
y = 14.576700
x = 317.457611
z = 4.550907

[850]
y = 35.941799
x = 343.021698
z = 6.460651

[851]
y = 21.971300
x = 266.335388
z = 2.429815

[852]
y = -27.095501
x = 869.389526
z = 63.615837

[853]
y = -355.906189
x = 1110.809082
z = 73.992188

[854]
y = -359.532410
x = 1103.693115
z = 73.992188

[855]
y = -1574.229980
x = -104.791901
z = 2.617188

[856]
y = -1554.484375
x = -58.084999
z = 2.617188

[857]
y = -2310.727539
x = -2078.506592
z = 30.731251

[858]
y = -2292.088867
x = -2221.551025
z = 31.141584

[859]
y = -2524.813721
x = -2043.390015
z = 30.625000

[860]
y = -2535.938965
x = -2028.155762
z = 30.625000

[861]
y = -2546.600830
x = -2055.460693
z = 30.625000

[862]
y = -2563.754883
x = -2071.445068
z = 30.625000

[863]
y = -2546.494629
x = -2080.378662
z = 30.625000

[864]
y = -2534.969971
x = -2104.450195
z = 30.625000

[865]
y = -2497.211670
x = -2071.772949
z = 30.625000

[866]
y = 2544.745117
x = -1475.359863
z = 55.835938

[867]
y = 2565.452148
x = -1445.501465
z = 55.835938

[868]
y = 2627.590088
x = -1568.049805
z = 55.835938

[869]
y = 2650.946045
x = -1559.249878
z = 55.835938

[870]
y = 2649.768555
x = -1590.480347
z = 55.835938

[871]
y = 2051.524414
x = -1372.773193
z = 52.515625

[872]
y = 2365.896973
x = 540.979126
z = 30.843679

[873]
y = 2006.018921
x = 772.062622
z = 5.691518

[874]
y = 1989.149780
x = 794.889893
z = 5.404900

[875]
y = 1973.798828
x = 785.182617
z = 5.335938

[876]
y = 1988.613037
x = 769.233093
z = 5.335938

[877]
y = 1972.247803
x = 757.208130
z = 5.335938

[878]
y = 1955.277588
x = 754.961182
z = 5.335938

[879]
y = 1952.617920
x = 787.645203
z = 5.335938

[880]
y = 1940.412842
x = 778.371704
z = 5.447459

[881]
y = -1643.788330
x = 2070.115234
z = 13.546875

[882]
y = -1656.557251
x = 2069.167480
z = 13.546875

[883]
y = -1641.640991
x = 2013.392700
z = 13.546875

[884]
y = -1656.385620
x = 2010.854370
z = 13.546875

[885]
y = -1703.201050
x = 2015.142944
z = 13.698026

[886]
y = -1716.867920
x = 2013.699463
z = 13.546875

[887]
y = -1732.669678
x = 2012.715210
z = 13.893585

[888]
y = -1606.430786
x = 1988.126099
z = 13.525304

[889]
y = -1561.959106
x = 1960.225830
z = 13.600812

[890]
y = -1561.472900
x = 1974.532227
z = 13.636953

[891]
y = -1596.141113
x = 2013.210205
z = 13.576441

[892]
y = -1595.590820
x = 2003.944702
z = 13.575218

[893]
y = -1609.113892
x = 2188.384766
z = 14.355144

[894]
y = -1718.390381
x = 2402.590332
z = 13.625413

[895]
y = -1648.777222
x = 2469.441406
z = 13.471758

[896]
y = -1205.607422
x = 2748.156006
z = 67.484375

[897]
y = -1221.877441
x = 2748.158691
z = 64.601563

[898]
y = -1238.844360
x = 2748.098633
z = 61.531250

[899]
y = -1276.298828
x = 731.393188
z = 13.566649

[900]
y = -1437.315552
x = 725.352783
z = 13.539063

[901]
y = -1936.265137
x = 2805.955811
z = 13.546875

[902]
y = -1967.501587
x = 2806.841064
z = 13.371759

[903]
y = -1952.554443
x = 2733.128662
z = 13.546875

[904]
y = -1933.415649
x = 2732.087891
z = 13.546875

[905]
y = -1404.492065
x = 2866.191895
z = 10.986352

[906]
y = -1249.346069
x = 2799.126709
z = 46.960358

[907]
y = -1249.424561
x = 2776.154297
z = 49.113430

[908]
y = -1239.300659
x = 2539.874756
z = 43.656250

[909]
y = -1194.737427
x = 2466.842041
z = 37.349701

[910]
y = -1287.954102
x = 2439.013916
z = 24.330107

[911]
y = -1321.194946
x = 2437.901855
z = 24.510426

[912]
y = -1357.060791
x = 2442.799316
z = 24.000000

[913]
y = -1276.382568
x = 2383.064209
z = 24.173668

[914]
y = -1326.847412
x = 2383.232910
z = 24.259232

[915]
y = -1346.753052
x = 2385.209229
z = 24.384434

[916]
y = -1366.381714
x = 2379.084717
z = 23.992207

[917]
y = -1284.466187
x = 2324.141113
z = 27.981327

[918]
y = -1262.290527
x = 2334.805908
z = 27.976563

[919]
y = -1253.157715
x = 2322.846924
z = 27.976563

[920]
y = -1232.159912
x = 2332.600098
z = 27.976563

[921]
y = -1222.113281
x = 2323.209717
z = 27.976563

[922]
y = -1202.168701
x = 2331.799072
z = 27.976563

[923]
y = -1232.850098
x = 2208.293457
z = 23.961231

[924]
y = -1411.019775
x = 2199.453613
z = 25.539063

[925]
y = -1478.202271
x = 2142.654297
z = 25.539063

[926]
y = -1369.375488
x = 2147.539551
z = 25.539063

[927]
y = -1365.296997
x = 2129.814697
z = 25.539063

[928]
y = -1291.552490
x = 2150.400391
z = 23.977467

[929]
y = -1732.114746
x = 2072.367920
z = 13.546875

[930]
y = -1717.056519
x = 2069.793213
z = 13.546875

[931]
y = -1882.908813
x = 2326.952393
z = 13.618725

[932]
y = -1943.890625
x = 2327.362549
z = 13.585938

[933]
y = -1719.780396
x = 2324.340088
z = 13.546875

[934]
y = -1416.761841
x = 685.530823
z = 13.732947

[935]
y = -1489.636719
x = 644.864014
z = 14.776446

[936]
y = -1536.763428
x = 644.897400
z = 15.276295

[937]
y = -1268.251099
x = 251.857498
z = 73.437691

[938]
y = -1168.436035
x = 472.329102
z = 65.889488

[939]
y = -1081.465576
x = 615.022705
z = 58.826656

[940]
y = -1063.059570
x = 645.182373
z = 52.565765

[941]
y = -1025.275146
x = 670.968872
z = 55.620689

[942]
y = -829.952698
x = 781.725098
z = 70.201111

[943]
y = -780.674377
x = 890.346130
z = 101.286072

[944]
y = -2038.021362
x = 1872.319092
z = 13.546875

[945]
y = -2020.827271
x = 1875.197876
z = 13.546875

[946]
y = -2021.649414
x = 1891.022339
z = 13.546875

[947]
y = -2037.913818
x = 1894.055054
z = 13.546875

[948]
y = -2009.455933
x = 1817.685791
z = 13.546875

[949]
y = -1998.007202
x = 1826.684448
z = 13.546875

[950]
y = -1426.569336
x = -378.764587
z = 25.726563

[951]
y = -1050.663574
x = -348.263214
z = 59.309807

[952]
y = 165.903595
x = 1947.137939
z = 37.281250

[953]
y = 173.686707
x = 1927.048950
z = 37.281250

[954]
y = 163.289307
x = 2237.561035
z = 27.383856

[955]
y = 129.326599
x = 2462.779297
z = 26.779041

[956]
y = -7.048000
x = 2440.093994
z = 26.881662

[957]
y = 15.666000
x = 2447.358887
z = 26.595091

[958]
y = 58.658699
x = 2443.306641
z = 27.781082

[959]
y = 191.008698
x = 2326.468018
z = 28.153711

[960]
y = 1166.729736
x = -2172.802979
z = 55.726563

[961]
y = 1166.720703
x = -2189.435059
z = 55.726563

[962]
y = 1166.666382
x = -2205.722900
z = 55.726563

[963]
y = 1166.789795
x = -2222.375000
z = 55.726563

[964]
y = 1252.853760
x = -2152.586914
z = 25.577433

[965]
y = 1112.527954
x = -1732.348389
z = 45.445313

[966]
y = 1112.739136
x = -1776.097046
z = 45.445313

[967]
y = 1112.799316
x = -1842.535645
z = 45.445313

[968]
y = 1112.606567
x = -1860.765381
z = 45.445313

[969]
y = 1125.358398
x = -1874.827026
z = 45.445313

[970]
y = 1146.429688
x = -1875.264648
z = 45.445313

[971]
y = 1187.475952
x = -1915.418579
z = 45.445313

[972]
y = 1187.737427
x = -1929.766724
z = 45.445313

[973]
y = 863.418396
x = -2014.288208
z = 45.445313

[974]
y = 849.139221
x = -2014.188477
z = 45.445313

[975]
y = 833.352295
x = -2014.245605
z = 45.445313

[976]
y = 970.153198
x = -2013.371094
z = 45.561783

[977]
y = 1177.161743
x = -1742.692261
z = 25.125000

[978]
y = 1177.405762
x = -1761.079468
z = 25.125000

[979]
y = 1280.110474
x = -2024.189453
z = 7.187500

[980]
y = 1280.639648
x = -2028.558960
z = 7.197403

[981]
y = 787.971802
x = -2275.740723
z = 49.445313

[982]
y = 767.869324
x = -2275.648193
z = 49.445313

[983]
y = 747.681030
x = -2275.553711
z = 49.445313

[984]
y = 799.659424
x = -2223.778809
z = 49.445313

[985]
y = 815.935486
x = -2223.784668
z = 49.445313

[986]
y = 799.260010
x = -2550.646729
z = 49.984375

[987]
y = 799.385925
x = -2569.110352
z = 49.984375

[988]
y = 800.182922
x = -2586.055664
z = 49.984375

[989]
y = 714.734619
x = -2581.394531
z = 27.961128

[990]
y = 574.609924
x = -2240.685059
z = 35.171875

[991]
y = 574.670227
x = -2217.082275
z = 35.171875

[992]
y = 2683.945068
x = -1577.659180
z = 55.835938

[993]
y = 2562.353027
x = -1472.119385
z = 55.835938

[994]
y = 2564.184326
x = -1538.765991
z = 55.835938

[995]
y = 2557.759277
x = -1507.412720
z = 55.835938

[996]
y = 1498.556885
x = -814.149780
z = 20.164248

[997]
y = 1485.663330
x = -777.586670
z = 23.998386

[998]
y = 1551.289917
x = -814.718201
z = 27.117188

[999]
y = 858.345276
x = -126.875702
z = 18.290333

[1000]
y = 875.653625
x = -126.651497
z = 18.626942

[1001]
y = 881.587097
x = -148.772797
z = 18.519989

[1002]
y = 905.692078
x = -147.570694
z = 18.916182

[1003]
y = 933.165894
x = -145.990906
z = 19.490589

[1004]
y = 916.318970
x = -126.482002
z = 19.738974

[1005]
y = 883.358276
x = -95.504303
z = 20.871559

[1006]
y = 915.674988
x = -90.757401
z = 20.984970

[1007]
y = 929.129700
x = -83.051598
z = 20.662153

[1008]
y = 894.844788
x = -58.692600
z = 21.992188

[1009]
y = 919.464600
x = -58.365700
z = 21.945313

[1010]
y = 936.095215
x = -60.995201
z = 20.820313

[1011]
y = 933.375488
x = -10.429700
z = 21.022928

[1012]
y = 967.082703
x = -36.758801
z = 19.757027

[1013]
y = 743.114319
x = 2655.878174
z = 12.215790

[1014]
y = 745.167786
x = 2656.406738
z = 10.820313

[1015]
y = 722.691223
x = 2652.932861
z = 13.138569

[1016]
y = 724.415588
x = 2655.234375
z = 10.820313

[1017]
y = 723.144775
x = 2614.024902
z = 12.795419

[1018]
y = 724.314026
x = 2616.180908
z = 10.820313

[1019]
y = 749.651794
x = 2535.824219
z = 12.890177

[1020]
y = 746.600586
x = 2536.596436
z = 10.820313

[1021]
y = 722.554382
x = 2532.982178
z = 13.242100

[1022]
y = 724.688477
x = 2537.957031
z = 10.820313

[1023]
y = 722.568726
x = 2572.041260
z = 13.231249

[1024]
y = 723.884521
x = 2575.959473
z = 10.820313

[1025]
y = 2691.356689
x = -150.237106
z = 62.081474

[1026]
y = 2707.299072
x = -172.278000
z = 62.568459

[1027]
y = 2728.089355
x = -158.396393
z = 62.114819

[1028]
y = 2756.732910
x = -157.342896
z = 62.667221

[1029]
y = 2768.348633
x = -161.939102
z = 62.687500

[1030]
y = 2775.192139
x = -201.788696
z = 62.012482

[1031]
y = 2763.861572
x = -219.678696
z = 62.687500

[1032]
y = 2807.603271
x = -235.404999
z = 61.672340

[1033]
y = 2779.303223
x = -258.113800
z = 62.687500

[1034]
y = 2769.524414
x = -272.506409
z = 61.925522

[1035]
y = 2764.077637
x = -286.573303
z = 62.129471

[1036]
y = 2735.480957
x = -271.089111
z = 62.537758

[1037]
y = 2725.333008
x = -279.459106
z = 62.441235

[1038]
y = 2726.712402
x = -307.941986
z = 62.586433

[1039]
y = 2708.937744
x = -208.240601
z = 62.687500

[1040]
y = 2708.554199
x = -243.210999
z = 62.687500

[1041]
y = 2694.620605
x = -271.599091
z = 62.687500

[1042]
y = 2694.517090
x = -288.919312
z = 62.687500

[1043]
y = 2679.197510
x = -322.722992
z = 62.665741

[1044]
y = 2658.165039
x = -284.608185
z = 62.674400

[1045]
y = -1076.284424
x = -607.646179
z = 23.542740

[1046]
y = -1068.578735
x = -601.082825
z = 23.441681

[1047]
y = -1059.371216
x = -594.742188
z = 23.371511

[1048]
y = -1051.309082
x = -588.729309
z = 23.349354

[1049]
y = -1043.197510
x = -582.632324
z = 23.602791

[1050]
y = -1034.253296
x = -576.751404
z = 23.814589

[1051]
y = 2274.827637
x = 989.605225
z = 11.460938

[1052]
y = 2274.150879
x = 952.893677
z = 11.468750

[1053]
y = 2312.552490
x = 1036.463989
z = 11.468292

[1054]
y = 2311.685059
x = 988.896912
z = 11.460938

[1055]
y = 2348.188477
x = 988.364929
z = 11.468750

[1056]
y = 2898.543945
x = 261.665588
z = 9.155102

[1057]
y = 2689.274658
x = -909.732971
z = 42.370262

[1058]
y = 2708.361328
x = -671.686218
z = 70.794586

[1059]
y = 2710.159912
x = -626.887573
z = 72.375000

[1060]
y = 2711.917725
x = -605.098816
z = 72.375000

[1061]
y = 2712.679199
x = -584.899475
z = 71.784729

[1062]
y = 187.958099
x = 1302.556030
z = 20.460938

[1063]
y = 179.701401
x = 1317.929932
z = 20.436565

[1064]
y = 152.460999
x = 1309.615967
z = 20.347454

[1065]
y = 156.904007
x = 1292.063599
z = 20.460938

[1066]
y = 375.039398
x = 1476.126709
z = 19.627283

[1067]
y = 350.707214
x = 1467.958252
z = 18.882013

[1068]
y = 366.004395
x = 1466.690186
z = 19.303982

[1069]
y = 363.835205
x = 1448.496826
z = 18.943861

[1070]
y = 333.599213
x = 1437.780151
z = 18.841671

[1071]
y = 392.642609
x = 1420.755859
z = 19.285721

[1072]
y = 362.240204
x = 1415.088623
z = 19.133223

[1073]
y = 343.244812
x = 1410.349365
z = 18.843750

[1074]
y = 332.704590
x = 1401.064087
z = 18.843750

[1075]
y = -2523.364014
x = -2070.396484
z = 30.625000

[1076]
y = -2186.842529
x = -2409.298096
z = 33.289063

[1077]
y = -500.566589
x = -924.428772
z = 25.960938

[1078]
y = -488.876587
x = -944.914001
z = 25.960938

[1079]
y = -528.766113
x = -917.032593
z = 25.960938

[1080]
y = -516.066711
x = -927.166321
z = 25.960938

[1081]
y = -520.460022
x = -939.506897
z = 25.960938

[1082]
y = -503.333191
x = -959.300720
z = 25.960938

[1083]
y = -534.095398
x = -925.445129
z = 25.960938

[1084]
y = -532.986023
x = -939.334412
z = 25.960938

[1085]
y = -527.814392
x = -950.654724
z = 25.960938

[1086]
y = -1994.415527
x = 1866.009521
z = 13.546875

[1087]
y = -1983.942749
x = 1828.044067
z = 13.546875

[1088]
y = -1989.584473
x = 1867.502930
z = 13.546875

[1089]
y = -1988.920654
x = 1900.057373
z = 13.546875

[1090]
y = -2021.557495
x = 1909.903564
z = 13.546875

[1091]
y = -1993.408447
x = 1910.734253
z = 13.546875

[1092]
y = -1401.987915
x = 2754.353516
z = 39.371693

[1093]
y = -1352.139038
x = 2743.247803
z = 44.575451

[1094]
y = -1305.086670
x = 2753.876465
z = 53.093750

[1095]
y = -1276.344360
x = 2750.629395
z = 58.710938

[1096]
y = -1281.255981
x = 2805.326416
z = 43.961033

[1097]
y = -1281.392212
x = 2787.449219
z = 43.914333

[1098]
y = -1303.135620
x = 2805.284424
z = 38.835335

[1099]
y = -1306.113403
x = 2787.355225
z = 38.107960

[1100]
y = -1325.038452
x = 2805.548096
z = 33.616547

[1101]
y = -1333.799194
x = 2787.474854
z = 31.576254

[1102]
y = -1354.276367
x = 2802.602051
z = 26.625044

[1103]
y = -1369.617432
x = 2803.600342
z = 22.982346

[1104]
y = -1358.421509
x = 2788.075439
z = 25.635565

[1105]
y = -1309.397339
x = 2851.430908
z = 14.535452

[1106]
y = -1068.993896
x = 2632.062744
z = 69.625000

[1107]
y = -1082.439575
x = 2631.430420
z = 69.620255

[1108]
y = -1098.168701
x = 2631.056396
z = 69.420242

[1109]
y = -1114.094971
x = 2630.296387
z = 67.785431

[1110]
y = -1224.659668
x = 2511.735596
z = 39.015625

[1111]
y = -1278.074585
x = 2466.447998
z = 29.612665

[1112]
y = -1103.816162
x = 2204.045898
z = 29.110847

[1113]
y = -1084.007202
x = 2192.234619
z = 40.850250

[1114]
y = -1087.649902
x = 2143.818848
z = 24.701279

[1115]
y = -1069.390381
x = 2152.018066
z = 38.070507

[1116]
y = -1058.514282
x = 2103.347900
z = 27.165417

[1117]
y = -1054.040405
x = 2097.990479
z = 28.393024

[1118]
y = -1049.462158
x = 2092.459961
z = 29.650806

[1119]
y = -1042.095215
x = 2081.487061
z = 31.826620

[1120]
y = -1088.199707
x = 2081.410400
z = 25.046671

[1121]
y = -1077.928955
x = 2059.973389
z = 24.890793

[1122]
y = -1075.138184
x = 2214.167480
z = 36.776726

[1123]
y = -972.134216
x = 2124.268311
z = 57.765625

[1124]
y = -977.036499
x = 2130.201660
z = 59.335938

[1125]
y = -979.585571
x = 2145.146240
z = 60.929688

[1126]
y = -982.478821
x = 2152.441162
z = 62.843750

[1127]
y = -1005.948608
x = 2140.565430
z = 61.759804

[1128]
y = -1001.347717
x = 2112.511719
z = 58.776775

[1129]
y = -993.093506
x = 2090.334473
z = 52.539974

[1130]
y = -975.378784
x = 2090.217285
z = 51.877716

[1131]
y = -969.089172
x = 2072.539795
z = 48.775246

[1132]
y = -960.128906
x = 2050.135498
z = 48.005505

[1133]
y = -980.901184
x = 2017.266968
z = 36.484993

[1134]
y = -987.047302
x = 2009.217529
z = 33.910965

[1135]
y = -1080.036865
x = 1955.626953
z = 24.789063

[1136]
y = -1076.890259
x = 1935.264893
z = 24.421034

[1137]
y = -1074.953369
x = 1914.659058
z = 24.268284

[1138]
y = -1075.283813
x = 1893.871826
z = 23.937500

[1139]
y = -1701.558716
x = 2140.064453
z = 15.085938

[1140]
y = -1705.019531
x = 2157.076904
z = 15.085938

[1141]
y = -1593.725830
x = 2070.568115
z = 13.498857

[1142]
y = -1557.033081
x = 2076.249512
z = 13.404706

[1143]
y = -1708.073853
x = 1969.051636
z = 15.968750

[1144]
y = -1673.602051
x = 1974.833496
z = 15.968750

[1145]
y = -1657.854980
x = 1973.218140
z = 15.968750

[1146]
y = -1637.335327
x = 1972.073730
z = 15.968750

[1147]
y = -1601.821045
x = 1863.939087
z = 13.543804

[1148]
y = -1601.873779
x = 1910.016479
z = 13.547318

[1149]
y = -1771.378540
x = 206.834900
z = 4.252840

[1150]
y = -1771.622070
x = 192.843994
z = 4.167520

[1151]
y = -1771.526733
x = 168.106903
z = 4.380805

[1152]
y = -1636.956299
x = 652.108215
z = 15.024088

[1153]
y = -1574.608765
x = 572.903625
z = 16.179688

[1154]
y = -1436.309326
x = 788.924683
z = 13.554688

[1155]
y = -1465.017944
x = 786.935608
z = 13.546040

[1156]
y = -1512.182495
x = 776.611328
z = 13.554688

[1157]
y = -1564.432983
x = 765.562317
z = 13.546875

[1158]
y = -890.060913
x = 1289.651245
z = 42.882813

[1159]
y = -881.371216
x = 1282.156982
z = 42.882813

[1160]
y = -895.590820
x = 1251.518188
z = 42.882813

[1161]
y = -884.826416
x = 1243.471802
z = 42.882813

[1162]
y = -816.090881
x = 913.408081
z = 103.126030

[1163]
y = -826.654602
x = 853.615173
z = 89.501671

[1164]
y = -1161.083496
x = 553.007324
z = 54.429688

[1165]
y = -1111.525024
x = 564.735901
z = 62.806358

[1166]
y = -1456.502075
x = 164.275208
z = 32.844982

[1167]
y = -1024.618042
x = 1190.439819
z = 32.546875

[1168]
y = -1023.423828
x = 1228.617798
z = 32.601563

[1169]
y = -1015.843872
x = 1382.966064
z = 26.814568

[1170]
y = 372.711609
x = 805.224609
z = 19.613092

[1171]
y = 359.330414
x = 800.908875
z = 19.389380

[1172]
y = 380.536285
x = 784.405212
z = 21.210938

[1173]
y = 355.038208
x = 783.574890
z = 19.562378

[1174]
y = 344.195007
x = 772.902283
z = 19.824816

[1175]
y = 377.802887
x = 756.892578
z = 23.170147

[1176]
y = 377.936615
x = 752.870972
z = 23.190979

[1177]
y = 348.395691
x = 750.238586
z = 20.416475

[1178]
y = -75.801804
x = 342.095306
z = 1.440298

[1179]
y = -79.653702
x = 374.564911
z = 1.382813

[1180]
y = -44.550400
x = 330.664001
z = 1.495072

[1181]
y = -306.244507
x = 235.113205
z = 1.578125

[1182]
y = -295.071991
x = 242.146301
z = 1.578125

[1183]
y = -289.622314
x = 235.690094
z = 1.578125

[1184]
y = -289.969299
x = 250.566299
z = 1.578125

[1185]
y = -288.469299
x = 262.176910
z = 1.578125

[1186]
y = -271.815399
x = 259.731903
z = 1.578125

[1187]
y = 1074.889893
x = -137.575500
z = 19.742188

[1188]
y = 1119.231567
x = -204.207306
z = 19.742188

[1189]
y = 2232.145752
x = -453.762512
z = 42.495171

[1190]
y = 2222.320801
x = -365.037415
z = 42.484375

[1191]
y = 2241.178467
x = -381.825806
z = 42.230701

[1192]
y = 1427.404663
x = -816.069092
z = 13.789063

[1193]
y = 1427.916870
x = -802.058472
z = 13.789063

[1194]
y = 1428.094116
x = -788.872314
z = 13.789063

[1195]
y = 1427.554565
x = -775.614685
z = 13.789063

[1196]
y = 1444.590698
x = -775.755127
z = 13.789063

[1197]
y = 1445.214722
x = -787.849304
z = 13.789063

[1198]
y = 1445.561279
x = -801.996216
z = 13.789063

[1199]
y = 1445.601440
x = -815.649475
z = 13.789063

[1200]
y = 127.855103
x = -2713.952148
z = 4.335938

[1201]
y = 185.014694
x = -2672.183838
z = 4.328125

[1202]
y = 182.639206
x = -2682.882813
z = 4.343616

[1203]
y = 165.141602
x = -2643.682861
z = 4.328125

[1204]
y = 164.419693
x = -2627.870117
z = 4.328125

[1205]
y = 575.812500
x = -2356.838379
z = 24.890625

[1206]
y = 576.131470
x = -2338.385498
z = 27.903418

[1207]
y = 576.124512
x = -2319.971436
z = 31.234863

[1208]
y = 575.616272
x = -2301.792725
z = 34.516991

[1209]
y = 907.930786
x = -1581.347534
z = 7.695313

[1210]
y = -27.539301
x = -2428.191162
z = 35.320313

[1211]
y = -4.884000
x = -2427.668945
z = 35.320313

[1212]
y = -186.030899
x = -2593.829834
z = 4.210630

[1213]
y = -158.523697
x = -2593.604736
z = 4.218660

[1214]
y = -105.976700
x = -2594.015137
z = 4.206133

[1215]
y = -95.652496
x = -2593.574951
z = 4.214314

[1216]
y = 847.189880
x = -2377.038086
z = 40.103775

[1217]
y = -1756.483398
x = -414.869812
z = 6.224959

[1218]
y = -1119.637695
x = 1922.619019
z = 26.099548

[1219]
y = -1120.138062
x = 1955.927856
z = 26.841816
]====]

-- Проверенная точная база домов Advance RP.
-- ID секции = реальный ID дома на Advance.
-- Эта база вшита в скрипт, поэтому отдельный MSHelper_house.ini не нужен.
__ms_home_embedded_verified_db = [====[
[0]
x = 1983.416992
y = -1719.023804
z = 16.076399

[1]
x = 1982.401489
y = -1682.722900
z = 17.053593

[2]
x = 2017.182861
y = -1629.918945
z = 13.546875

[3]
x = 2069.356201
y = -1629.004639
z = 13.876158

[4]
x = 2065.552490
y = -1703.506592
z = 14.148438

[5]
x = 2243.555908
y = -1639.778809
z = 15.907408

[6]
x = 2257.700928
y = -1644.877319
z = 15.517007

[7]
x = 2282.472412
y = -1642.125122
z = 15.627917

[8]
x = 2307.133301
y = -1677.832642
z = 14.001158

[9]
x = 2362.709229
y = -1643.989502
z = 13.531879

[10]
x = 2363.302979
y = -1643.975586
z = 13.537825

[11]
x = 2368.005615
y = -1674.523438
z = 13.906295

[12]
x = 2384.442139
y = -1674.716309
z = 14.731529

[13]
x = 2393.279541
y = -1647.228149
z = 13.536005

[14]
x = 2408.831787
y = -1674.181152
z = 13.605250

[15]
x = 2413.880371
y = -1646.904297
z = 14.011916

[16]
x = 2452.011475
y = -1642.154663
z = 13.735735

[17]
x = 2459.319824
y = -1690.803467
z = 13.547185

[18]
x = 2495.438477
y = -1690.667236
z = 14.765625

[19]
x = 2523.014648
y = -1679.343750
z = 15.497000

[20]
x = 2523.410400
y = -1658.696289
z = 15.493547

[21]
x = 2524.437500
y = -1658.527954
z = 15.493547

[22]
x = 2498.981201
y = -1643.286743
z = 13.782610

[23]
x = 2498.136719
y = -1643.237183
z = 13.782610

[24]
x = 1854.177002
y = -1915.816650
z = 15.256798

[25]
x = 1871.858032
y = -1913.202148
z = 15.256798

[26]
x = 1892.136230
y = -1915.023926
z = 15.256798

[27]
x = 1913.375732
y = -1912.774170
z = 15.256798

[28]
x = 1928.799561
y = -1916.546265
z = 15.256798

[29]
x = 1937.734131
y = -1911.788818
z = 15.256798

[30]
x = 2166.431152
y = -1672.224731
z = 15.074650

[31]
x = 2144.779297
y = -1664.700928
z = 15.085938

[32]
x = 2142.826172
y = -1605.523193
z = 14.351563

[33]
x = 2150.480225
y = -1584.803101
z = 14.343750

[34]
x = 2395.287842
y = -1795.942017
z = 13.546875

[35]
x = 2380.332764
y = -1785.664185
z = 13.546875

[36]
x = 2321.959717
y = -1795.216797
z = 13.546875

[37]
x = 2291.056885
y = -1795.975342
z = 13.546875

[38]
x = 2248.165527
y = -1795.595825
z = 13.546875

[39]
x = 1894.003662
y = -2133.589600
z = 15.466327

[40]
x = 1872.560181
y = -2133.290527
z = 15.481952

[41]
x = 1851.565430
y = -2135.259766
z = 15.388202

[42]
x = 1851.587524
y = -2069.712646
z = 15.481237

[43]
x = 1873.203003
y = -2070.607178
z = 15.497087

[44]
x = 1895.270996
y = -2068.721924
z = 15.668894

[45]
x = 2465.486084
y = -1996.704712
z = 13.688861

[46]
x = 2483.655273
y = -1996.330200
z = 13.834324

[47]
x = 2508.344482
y = -1998.788696
z = 13.902541

[48]
x = 2523.516602
y = -1998.868774
z = 13.782611

[49]
x = 2522.504395
y = -2018.607910
z = 14.074416

[50]
x = 2508.037354
y = -2020.174438
z = 13.948230

[51]
x = 2486.288818
y = -2020.858643
z = 13.736976

[52]
x = 2465.374268
y = -2019.586060
z = 13.862292

[53]
x = 2695.237061
y = -2020.456787
z = 14.022285

[54]
x = 2695.170654
y = -2020.403076
z = 14.022285

[55]
x = 2673.351074
y = -2019.441040
z = 13.906295

[56]
x = 2649.890137
y = -2021.521118
z = 14.176628

[57]
x = 2635.646484
y = -2012.292480
z = 13.813861

[58]
x = 2637.520508
y = -1992.413330
z = 13.993547

[59]
x = 2652.827148
y = -1989.933838
z = 13.998847

[60]
x = 2672.408936
y = -1989.934326
z = 13.993547

[61]
x = 2696.160645
y = -1991.349854
z = 13.960982

[62]
x = 2241.921631
y = -1883.626099
z = 14.173780

[63]
x = 2269.499023
y = -1883.234863
z = 14.234375

[64]
x = 2295.966064
y = -1883.269165
z = 14.234375

[65]
x = 2237.821289
y = -1905.612427
z = 14.937500

[66]
x = 2261.404785
y = -1905.564087
z = 14.937500

[67]
x = 2284.786621
y = -1905.239502
z = 14.929688

[68]
x = 2385.408447
y = -1712.650879
z = 14.229556

[69]
x = 2308.883301
y = -1715.403564
z = 14.649595

[895]
x = 2402.585205
y = -1715.812744
z = 14.057112

[896]
x = 2469.752197
y = -1646.863525
z = 13.780097

[932]
x = 2333.492188
y = -1882.071777
z = 15.000000

[933]
x = 2333.807129
y = -1944.325684
z = 14.968750

[934]
x = 2326.514648
y = -1716.702393
z = 14.237879

[1142]
x = 2069.364502
y = -1588.992798
z = 13.491903

[1143]
x = 2071.968262
y = -1557.751953
z = 13.412887

[1221]
x = 877.450378
y = -1515.853882
z = 13.862916

[1222]
x = 901.605896
y = -1447.398682
z = 13.774590

[1223]
x = 2044.976440
y = -965.956787
z = 44.355991

[1224]
x = 2049.095947
y = -986.562439
z = 44.535995

[1225]
x = 2288.595215
y = -1106.099121
z = 37.976563

[1226]
x = 2351.882324
y = -1168.530396
z = 27.970264

[1227]
x = 2580.381348
y = -969.789795
z = 81.362968

[1228]
x = 2518.731934
y = -965.567200
z = 82.330482

[1229]
x = 2491.001465
y = -965.380127
z = 82.238579

[1230]
x = 2459.094727
y = -949.816711
z = 80.081177

[1231]
x = 2454.862793
y = -964.914673
z = 80.068848

[1232]
x = 2370.698242
y = -1035.674316
z = 54.410557

[1233]
x = 1052.060181
y = -345.471619
z = 73.992188

[1234]
x = 1072.695801
y = -344.467194
z = 73.992188

[1235]
x = 253.259125
y = -22.498089
z = 1.620707

[1236]
x = -36.135410
y = 2349.587158
z = 24.302555

[1237]
x = -309.594696
y = 1303.674927
z = 53.664345

[1238]
x = 613.769043
y = 1549.481567
z = 4.852962

[1239]
x = 986.465454
y = 2000.336426
z = 11.460938

[1240]
x = 985.491699
y = 2030.476440
z = 11.468750

[1241]
x = 1408.166504
y = 1920.233765
z = 11.468750

[1242]
x = 25.383417
y = 1174.251587
z = 19.396870

[1243]
x = 25.692110
y = 1175.061279
z = 19.381248

[1244]
x = 1414.255859
y = 2003.911743
z = 14.739589

[1245]
x = 1421.765015
y = 2026.824829
z = 14.739589

[1246]
x = 1460.456299
y = 2026.952026
z = 14.739589

[1247]
x = 1502.930298
y = 2026.885132
z = 14.739589

[1248]
x = 1542.271118
y = 2026.655762
z = 14.739589

[1249]
x = 1541.845825
y = 1996.520752
z = 14.739589

[1250]
x = 1548.140869
y = 2125.784912
z = 11.460938

[1251]
x = 2818.764404
y = 2141.597168
z = 14.661465

[1252]
x = 2794.538330
y = 2229.253174
z = 14.661464

[1253]
x = 2794.646729
y = 2268.226563
z = 14.661464

[1254]
x = 2823.846191
y = 2267.659180
z = 14.661464

[1255]
x = 2581.102051
y = 1061.267456
z = 11.526609

[1256]
x = -5.338308
y = -2649.709717
z = 80.464203

[1257]
x = -315.282959
y = 1773.624634
z = 43.640625

[1258]
x = 354.864960
y = -1280.322021
z = 53.703640

[1259]
x = 903.571960
y = -1816.126465
z = 13.300085

[1260]
x = 960.830200
y = -1824.510620
z = 13.323335

[1261]
x = 986.529907
y = -1624.374878
z = 14.929688

[1262]
x = 986.266174
y = -1704.189819
z = 14.929688

[1263]
x = 335.388733
y = -1303.448120
z = 50.759045

[1264]
x = -2658.478271
y = 268.872925
z = 47.195301

[1265]
x = -2657.432129
y = 849.562927
z = 64.007813

[1266]
x = -2369.956055
y = 740.200684
z = 35.079628

[1267]
x = -2368.817871
y = 763.268311
z = 35.151756

[1268]
x = -2373.208984
y = 783.481140
z = 35.004868

[1269]
x = -2240.037354
y = 962.054749
z = 66.652184

[1270]
x = -2573.584961
y = 993.242554
z = 78.273438

[1271]
x = -2596.982178
y = 986.241333
z = 78.273438

[1272]
x = -2036.635254
y = 1196.164795
z = 46.239510

[1273]
x = 1180.831665
y = -1261.146118
z = 18.898438

[1274]
x = 1185.954102
y = -1227.220703
z = 22.140625

[1275]
x = -2630.211914
y = 2427.706787
z = 14.232674

[1276]
x = -1353.245972
y = 2057.276855
z = 53.117188

[1277]
x = -1426.571533
y = 2170.527588
z = 50.625000

[1278]
x = -1589.820923
y = 2705.782227
z = 56.176182

[1279]
x = -1471.841431
y = 2592.908203
z = 55.835938

[1280]
x = -791.092590
y = 1613.343994
z = 27.117188

[1281]
x = -801.449524
y = 1596.498535
z = 27.034002

[1282]
x = -799.548767
y = 1499.714111
z = 21.667444

[1283]
x = -814.726196
y = 2765.396240
z = 46.000000

[1284]
x = -826.920471
y = 2764.830322
z = 46.000000

[1285]
x = -838.477356
y = 2762.354004
z = 46.000000

[1286]
x = -851.892761
y = 2760.217285
z = 46.000000

[1287]
x = -867.238525
y = 2761.315430
z = 46.000000

[1288]
x = -880.742004
y = 2760.612305
z = 46.000000

[1289]
x = -880.084167
y = 2748.972412
z = 46.000000

[1290]
x = -866.545227
y = 2749.386475
z = 45.995499

[1291]
x = -825.850525
y = 2752.265381
z = 46.000000

[1292]
x = -814.372009
y = 2753.290771
z = 46.000000

[1293]
x = 2795.099609
y = 2261.462646
z = 10.820313

[1294]
x = 2787.207520
y = 2222.121826
z = 14.661464

[1295]
x = 2787.761963
y = 2222.355957
z = 10.820313

[1296]
x = 2794.479980
y = 2222.606445
z = 10.820313

[1297]
x = 2819.303467
y = 2141.576172
z = 10.820313

[1298]
x = 2612.876953
y = 2051.447510
z = 10.820313

[1299]
x = 2613.238770
y = 2060.470947
z = 10.812986

[1300]
x = 2624.241211
y = 2067.353027
z = 10.820313

[1301]
x = 2624.354736
y = 2048.417236
z = 10.812986

[1302]
x = 2638.600830
y = 2029.906006
z = 10.820313

[1303]
x = 2650.144775
y = 1979.492310
z = 10.820313

[1304]
x = 2642.472412
y = 1979.807983
z = 10.820313

[1305]
x = 2633.313477
y = 1979.538452
z = 10.820313

[1306]
x = 2620.735352
y = 719.790039
z = 10.820313

[1307]
x = 1566.254761
y = 23.259977
z = 24.164063

[1308]
x = 1546.728394
y = 32.413715
z = 24.140625

[1309]
x = 715.602417
y = -471.648163
z = 16.343704

[1310]
x = 349.972748
y = -127.826164
z = 2.090685

[1311]
x = -427.821472
y = -392.161621
z = 16.580153

[1312]
x = -396.647705
y = -425.736603
z = 16.203125

[1313]
x = -2791.720459
y = -43.432724
z = 9.684302

[1314]
x = -2791.586670
y = 77.023361
z = 10.054688

[1315]
x = -2792.629883
y = 130.702576
z = 7.766860

[1316]
x = -2791.840332
y = 193.192108
z = 9.840440

[1317]
x = -2792.131592
y = 200.678818
z = 7.859375

[1318]
x = -2792.256836
y = 218.476959
z = 7.859375

[1319]
x = 1196.279297
y = -1017.044128
z = 32.546875

[1320]
x = 1234.596558
y = -1017.460754
z = 32.606651

[1321]
x = 1227.670044
y = -1017.357483
z = 32.601563

[1322]
x = 1189.344604
y = -1018.085083
z = 32.546875

[1323]
x = 2046.125977
y = -1116.090576
z = 26.361748
]====]

__ms_home = {
    cache_path = 'moonloader\\config\\MSHelper_house.ini',
    user_path = 'moonloader\\config\\house.ini',
    local_path = 'moonloader\\house.ini',
    radius = 3.0,
    -- v25: база домов вшита в скрипт. Проверенная база и house.ini используют точные ID Advance.
    -- Старая встроенная база оставлена только как запасной legacy fallback для старых ID.
    -- Основная метка теперь ставится как обычная цель GTA через placeWaypoint/setTargetBlipCoordinates.
    -- Blip-крест оставлен как запасной визуальный слой.
    dark_color = 8,
    edge_color = 0,
    sprite_color = 0,
    blip_scale = 6,
    blip_display = 4,
    cross_offset = 28.0,
    house_sprite = 31,
    waypoint_enabled = true,
    reapply_ms = 3000,
    max_server_id = 1323,
    -- Проверенная встроенная база и внешний house.ini: ID = ID Advance.
    -- Legacy-смещение используется только для старой запасной базы, если точной записи нет.
    prefer_zero_based = true,
    legacy_zero_based_cutoff_db_id = 1220,
    houses = {},
    sources = {},
    min_id = nil,
    max_id = nil,
    count = 0,
    db_source = nil,
    x = nil,
    y = nil,
    z = nil,
    house_id = nil,
    blip = nil,
    blip2 = nil,
    checkpoint = nil,
    marker_mode = nil
}

function __ms_home_trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

function __ms_home_file_exists(path)
    local ok, f = pcall(io.open, path, 'rb')
    if ok and f then
        f:close()
        return true
    end
    return false
end

function __ms_home_read_file(path)
    local ok, f = pcall(io.open, path, 'rb')
    if not ok or not f then return nil end
    local ok_read, data = pcall(function() return f:read('*a') end)
    pcall(function() f:close() end)
    if ok_read then return data end
    return nil
end

function __ms_home_write_file(path, data)
    local ok, f = pcall(io.open, path, 'wb')
    if not ok or not f then return false end
    local ok_write = pcall(function() f:write(tostring(data or '')) end)
    pcall(function() f:close() end)
    return ok_write
end

function __ms_home_prepare_dirs()
    -- Без os.execute, чтобы игра не сворачивалась при запуске скрипта.
    -- Если папки нет, её лучше создать вручную: moonloader\config.
    if type(createDirectory) == 'function' then
        pcall(createDirectory, 'moonloader\\config')
    end
    if type(doesDirectoryExist) == 'function' then
        local ok, exists = pcall(doesDirectoryExist, 'moonloader\\config')
        if ok and exists then return true end
    end
    return true
end

function __ms_home_remember(id, x, y, z, source)
    id, x, y, z = tonumber(id), tonumber(x), tonumber(y), tonumber(z)
    if id == nil or x == nil or y == nil or z == nil then return end
    id = math.floor(id)
    local is_new = (__ms_home.houses[id] == nil)
    __ms_home.houses[id] = { x = x, y = y, z = z }
    __ms_home.sources[id] = source or 'base'
    if is_new then __ms_home.count = __ms_home.count + 1 end
    if __ms_home.min_id == nil or id < __ms_home.min_id then __ms_home.min_id = id end
    if __ms_home.max_id == nil or id > __ms_home.max_id then __ms_home.max_id = id end
end

function __ms_home_parse_db(data, reset, source)
    if reset ~= false then
        __ms_home.houses = {}
        __ms_home.sources = {}
        __ms_home.min_id, __ms_home.max_id, __ms_home.count = nil, nil, 0
    end
    source = source or 'base'
    local before = __ms_home.count or 0

    local current_id, x, y, z = nil, nil, nil, nil
    local function flush()
        if current_id ~= nil and x ~= nil and y ~= nil and z ~= nil then
            __ms_home_remember(current_id, x, y, z, source)
        end
    end

    for raw in (tostring(data or ''):gsub('\r', '') .. '\n'):gmatch('(.-)\n') do
        local line = __ms_home_trim(raw)
        if line ~= '' and not line:match('^;') and not line:match('^#') then
            local sid = line:match('^%[(%-?%d+)%]')
            if sid then
                flush()
                current_id = tonumber(sid)
                x, y, z = nil, nil, nil
            else
                local key, value = line:match('^([xyzXYZ])%s*=%s*([%-+]?%d+%.?%d*)')
                if key and value then
                    key = key:lower()
                    value = tonumber(value)
                    if key == 'x' then x = value elseif key == 'y' then y = value elseif key == 'z' then z = value end
                else
                    -- запасной формат: id x y z или id=x,y,z
                    local nums = {}
                    for n in line:gmatch('[%-+]?%d+%.?%d*') do nums[#nums + 1] = tonumber(n) end
                    if #nums >= 4 then
                        __ms_home_remember(nums[1], nums[2], nums[3], nums[4], source)
                    end
                end
            end
        end
    end
    flush()
    return (__ms_home.count or 0) > before
end

function __ms_home_is_legacy_zero_based()
    return (__ms_home.prefer_zero_based ~= false) and (((__ms_home.sources or {})[0] == 'base') or ((__ms_home.min_id or 0) == 0))
end

function __ms_home_legacy_cutoff_db_id()
    return tonumber(__ms_home.legacy_zero_based_cutoff_db_id or 1220) or 1220
end

function __ms_home_display_range()
    if __ms_home.count <= 0 then return nil, nil end
    return 0, tonumber(__ms_home.max_server_id or __ms_home.max_id or 0) or 0
end

function __ms_home_visible_max_id()
    return tonumber(__ms_home.max_server_id or __ms_home.max_id or 0) or 0
end

function __ms_home_db_id_for_save(server_id)
    server_id = tonumber(server_id)
    if server_id == nil then return nil, nil end
    server_id = math.floor(server_id)
    return server_id, 'exact'
end

function __ms_home_load_db(silent)
    __ms_home_prepare_dirs()

    -- База грузится слоями без создания лишнего MSHelper_house.ini:
    -- 1) старая встроенная база MSHelper как legacy fallback;
    -- 2) проверенная вшитая база Advance по точным ID;
    -- 3) moonloader\config\house.ini как пользовательские исправления/новые дома.
    local ok = __ms_home_parse_db(__ms_home_embedded_db, true, 'base')
    local sources = { 'embedded legacy base' }

    if __ms_home_embedded_verified_db and #tostring(__ms_home_embedded_verified_db) > 10 then
        __ms_home_parse_db(__ms_home_embedded_verified_db, false, 'verified')
        table.insert(sources, 'embedded verified Advance DB')
    end

    if __ms_home_file_exists(__ms_home.user_path) then
        local user_data = __ms_home_read_file(__ms_home.user_path)
        if user_data and #tostring(user_data) > 0 then
            __ms_home_parse_db(user_data, false, 'user')
            table.insert(sources, tostring(__ms_home.user_path))
        end
    end

    __ms_home.db_source = table.concat(sources, ' + ')

    if (__ms_home.count or 0) <= 0 then
        __ms_home_parse_db(__ms_home_embedded_verified_db or __ms_home_embedded_db, true, 'verified')
        __ms_home.db_source = 'embedded verified Advance DB'
        ok = (__ms_home.count or 0) > 0
    end

    if not silent then
        if ok then
            local min_show, max_show = __ms_home_display_range()
            __ms_home_msg(string.format('[MS Home] База домов загружена: %d записей. ID Advance: %s-%s.', __ms_home.count, tostring(min_show), tostring(max_show)), 0x66CCFFFF)
            __ms_home_msg('[MS Home] Основная база вшита в скрипт. house.ini нужен только для /mshomeadd и исправлений.', 0x66CCFFFF)
        else
            __ms_home_msg('[MS Home] Не удалось прочитать базу домов.', 0xFFFF4040)
        end
    end
    return (__ms_home.count or 0) > 0
end

function __ms_home_remove_one_blip(blip)
    if blip == nil then return end
    if type(removeBlip) == 'function' then pcall(removeBlip, blip) end
    if type(deleteBlip) == 'function' then pcall(deleteBlip, blip) end
    if type(removeBlipForCoord) == 'function' then pcall(removeBlipForCoord, blip) end
end

function __ms_home_remove_marker()
    -- Убираем стандартную цель GTA, если она была поставлена через placeWaypoint.
    if type(removeWaypoint) == 'function' then pcall(removeWaypoint) end
    if type(clearGpsMultiRoute) == 'function' then pcall(clearGpsMultiRoute) end

    if type(__ms_home.blips) == 'table' then
        for _, blip in ipairs(__ms_home.blips) do
            __ms_home_remove_one_blip(blip)
        end
    end
    __ms_home_remove_one_blip(__ms_home.blip)
    __ms_home_remove_one_blip(__ms_home.blip2)
    __ms_home_remove_one_blip(__ms_home.blip3)
    __ms_home_remove_one_blip(__ms_home.blip4)
    __ms_home_remove_one_blip(__ms_home.blip5)
    __ms_home.blips = {}
    __ms_home.blip = nil
    __ms_home.blip2 = nil
    __ms_home.blip3 = nil
    __ms_home.blip4 = nil
    __ms_home.blip5 = nil
    __ms_home.checkpoint = nil
    __ms_home.marker_mode = nil
    __ms_home.last_waypoint_at = 0
end

function __ms_home_try_call(name, ...)
    local fn = _G and _G[name]
    if type(fn) ~= 'function' then return false, nil end
    local ok, result = pcall(fn, ...)
    if ok then return true, result end
    return false, nil
end

function __ms_home_setup_blip(blip, color, scale)
    if blip == nil then return end
    color = tonumber(color) or 0
    scale = tonumber(scale) or 4

    -- Показываем на большой карте и на радаре. Никаких checkpoint/route-вызовов тут нет.
    if type(changeBlipColour) == 'function' then pcall(changeBlipColour, blip, color) end
    if type(changeBlipScale) == 'function' then pcall(changeBlipScale, blip, scale) end
    if type(changeBlipDisplay) == 'function' then pcall(changeBlipDisplay, blip, 4) end
    if type(setBlipDisplay) == 'function' then pcall(setBlipDisplay, blip, 4) end
    if type(setBlipAsShortRange) == 'function' then pcall(setBlipAsShortRange, blip, false) end
    if type(showBlipOnAllLevels) == 'function' then pcall(showBlipOnAllLevels, blip, true) end
end

function __ms_home_add_coord_blip(x, y, z, color, scale)
    if type(addBlipForCoord) ~= 'function' then return nil end
    local ok, blip = pcall(addBlipForCoord, x, y, z)
    if ok and blip ~= nil then
        __ms_home_setup_blip(blip, color, scale)
        table.insert(__ms_home.blips, blip)
        return blip
    end
    return nil
end

function __ms_home_try_sprite_blip(x, y, z)
    -- Дополнительная иконка дома, если сборка MoonLoader её поддерживает.
    -- Если не поддерживает — просто пропускаем, без ошибок в чат.
    if type(addSpriteBlipForCoord) ~= 'function' then return nil end
    local sprite = tonumber(__ms_home.house_sprite or 31) or 31
    local ok, blip = pcall(addSpriteBlipForCoord, x, y, z, sprite)
    if ok and blip ~= nil then
        __ms_home_setup_blip(blip, __ms_home.sprite_color or 0, __ms_home.sprite_scale or 4)
        table.insert(__ms_home.blips, blip)
        return blip
    end
    return nil
end

function __ms_home_try_waypoint(x, y, z)
    -- Самая заметная метка на большой карте GTA/SA:MP — это стандартная цель/waypoint.
    -- На некоторых сборках работает placeWaypoint, на других setTargetBlipCoordinates.
    -- Вызываем через pcall, чтобы не крашить игру, если функция есть, но сигнатура другая.
    local ok_any = false

    if type(placeWaypoint) == 'function' then
        local ok = pcall(placeWaypoint, x, y, z)
        if not ok then ok = pcall(placeWaypoint, x, y) end
        if ok then ok_any = true end
    end

    if type(setTargetBlipCoordinates) == 'function' then
        local ok = pcall(setTargetBlipCoordinates, x, y, z)
        if not ok then ok = pcall(setTargetBlipCoordinates, x, y) end
        if ok then ok_any = true end
    end

    -- Если есть GPS route-функция, пробуем включить маршрут, но без обязательной зависимости.
    if type(addPointToGpsMultiRoute) == 'function' and type(setGpsMultiRouteRender) == 'function' then
        pcall(clearGpsMultiRoute)
        pcall(addPointToGpsMultiRoute, x, y, z)
        pcall(setGpsMultiRouteRender, true)
        ok_any = true
    end

    if ok_any then
        __ms_home.last_waypoint_at = os.clock()
    end
    return ok_any
end

function __ms_home_set_marker(x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return false end

    __ms_home_remove_marker()
    __ms_home.blips = {}

    -- v22: сначала ставим стандартную цель GTA. Именно она лучше всего видна на большой карте.
    local waypoint_ok = false
    if __ms_home.waypoint_enabled ~= false then
        waypoint_ok = __ms_home_try_waypoint(x, y, z)
    end

    -- Дополнительно ставим крупный blip-крест. Если карта Advance скрывает обычные blip'ы,
    -- waypoint всё равно должен остаться видимым.
    local dark = tonumber(__ms_home.dark_color or 8) or 8
    local edge = tonumber(__ms_home.edge_color or 0) or 0
    local off = tonumber(__ms_home.cross_offset or 28.0) or 28.0
    local scale = tonumber(__ms_home.blip_scale or 6) or 6

    __ms_home.blip = __ms_home_add_coord_blip(x, y, z, dark, scale + 1)
    __ms_home.blip2 = __ms_home_add_coord_blip(x + off, y, z, edge, scale)
    __ms_home.blip3 = __ms_home_add_coord_blip(x - off, y, z, edge, scale)
    __ms_home.blip4 = __ms_home_add_coord_blip(x, y + off, z, edge, scale)
    __ms_home.blip5 = __ms_home_add_coord_blip(x, y - off, z, edge, scale)
    __ms_home_try_sprite_blip(x, y, z)

    if waypoint_ok or #__ms_home.blips > 0 then
        if waypoint_ok and #__ms_home.blips > 0 then
            __ms_home.marker_mode = 'waypoint_dark_cross'
        elseif waypoint_ok then
            __ms_home.marker_mode = 'waypoint'
        else
            __ms_home.marker_mode = 'dark_cross_blip'
        end
        return true
    end

    __ms_home_msg('[MS Home] В этой сборке не удалось поставить ни waypoint, ни blip.', 0xFFFF4040)
    return false
end

function __ms_home_disable(silent)
    __ms_home.x, __ms_home.y, __ms_home.z = nil, nil, nil
    __ms_home.house_id = nil
    __ms_home_remove_marker()
    if not silent then
        __ms_home_msg('[MS Home] Метка дома убрана.', 0x66CCFFFF)
    end
end

function __ms_home_get_house_for_server_id(id, raw_mode)
    id = tonumber(id)
    if id == nil then return nil, nil, nil end
    id = math.floor(id)

    -- raw нужен только для отладки: /mshome ID raw ставит метку прямо на секцию базы.
    if raw_mode then
        return __ms_home.houses[id], id, 'raw'
    end

    -- Проверенная встроенная база, user house.ini и любые будущие добавления работают точно по ID Advance.
    local src = __ms_home.sources and __ms_home.sources[id]
    if src and src ~= 'base' and __ms_home.houses[id] then
        return __ms_home.houses[id], id, tostring(src)
    end

    -- Дом 0 на Advance существует и должен искаться строго как [0].
    if id == 0 and __ms_home.houses[0] then
        return __ms_home.houses[0], 0, 'exact_zero'
    end

    -- Старый полный MSHelper fallback был собран со смещением: Advance ID 1 -> [0].
    -- Используем его только если точной проверенной записи нет.
    if __ms_home_is_legacy_zero_based() and id >= 1 and id <= __ms_home_legacy_cutoff_db_id() + 1 then
        local shifted_id = id - 1
        local shifted_src = __ms_home.sources and __ms_home.sources[shifted_id]
        if __ms_home.houses[shifted_id] and shifted_src == 'base' then
            return __ms_home.houses[shifted_id], shifted_id, 'legacy_shift'
        end
    end

    return __ms_home.houses[id], id, src or 'exact'
end

function __ms_home_mark_by_id(id, raw_mode)
    id = tonumber(id)
    if id == nil then return false end
    id = math.floor(id)

    if __ms_home.count <= 0 then
        __ms_home_load_db(true)
    end

    local house, db_id, id_mode = __ms_home_get_house_for_server_id(id, raw_mode)
    if not house then
        __ms_home_msg(string.format('[MS Home] Дом Advance ID %d не найден в базе.', id), 0xFFFF4040)
        if id > (__ms_home_visible_max_id() or 0) then
            __ms_home_msg(string.format('[MS Home] Сейчас в базе MSHelper только до Advance ID %d. Добавьте дом через /mshomeadd %d или обновите house.ini.', __ms_home_visible_max_id() or 0, id), 0xFFFFC040)
        end
        return false
    end

    if __ms_home_set_marker(house.x, house.y, house.z) then
        __ms_home.house_id = id
        __ms_home.db_id = db_id
        __ms_home.id_mode = id_mode
        __ms_home.x, __ms_home.y, __ms_home.z = house.x, house.y, house.z
        if raw_mode then
            __ms_home_msg(string.format('[MS Home] Метка на базовую секцию [%d] поставлена. Режим: %s.', db_id, tostring(__ms_home.marker_mode or 'unknown')), 0x66CCFFFF)
        else
            __ms_home_msg(string.format('[MS Home] Метка на дом Advance ID %d поставлена. Режим: %s.', id, tostring(__ms_home.marker_mode or 'unknown')), 0x66CCFFFF)
        end
        return true
    end
    return false
end

function __ms_home_usage()
    __ms_home_msg('[MS Home] /mshome ID - метка на дом по ID Advance, включая 0.', 0x66CCFFFF)
    __ms_home_msg('[MS Home] /mshomeadd ID - сохранить текущую позицию как дом ID.', 0x66CCFFFF)
    __ms_home_msg('[MS Home] /mshome off - убрать метку.', 0x66CCFFFF)
    __ms_home_msg('[MS Home] /mshome update - перечитать house.ini.', 0x66CCFFFF)
    -- Скрытая команда: /mshome ID raw (для отладки секции house.ini, в подсказке не показываем)
end

function __ms_home_command(arg)
    arg = __ms_home_trim(arg)
    if arg == '' then
        __ms_home_usage()
        return
    end

    local low = arg:lower()
    if low == 'off' or low == 'del' or low == 'clear' then
        __ms_home_disable(false)
        return
    end
    if low == 'update' or low == 'upd' then
        __ms_home_load_db(false)
        return
    end

    local id = tonumber(arg:match('^(%d+)'))
    local raw_mode = arg:lower():find('%sraw%s*$') ~= nil or arg:lower():find('%sbase%s*$') ~= nil
    if id == nil then
        __ms_home_usage()
        return
    end
    id = math.floor(id)

    if id < 0 or id > __ms_home.max_server_id then
        __ms_home_msg(string.format('[MS Home] Неверный ID дома. Доступно: 0-%d.', __ms_home.max_server_id), 0xFFFF4040)
        return
    end

    __ms_home_mark_by_id(id, raw_mode)
end

function __ms_home_get_player_position()
    if type(getCharCoordinates) ~= 'function' then return nil, nil, nil end
    local ped = PLAYER_PED or playerPed
    if ped == nil then return nil, nil, nil end
    local ok, x, y, z = pcall(getCharCoordinates, ped)
    if ok and tonumber(x) and tonumber(y) and tonumber(z) then
        return tonumber(x), tonumber(y), tonumber(z)
    end
    return nil, nil, nil
end

function __ms_home_source_data_for_user_file()
    -- user house.ini хранит только добавленные/исправленные дома.
    -- Полная встроенная база подмешивается отдельно в __ms_home_load_db().
    local data = ''
    if __ms_home_file_exists(__ms_home.user_path) then
        data = __ms_home_read_file(__ms_home.user_path) or ''
    end
    return tostring(data or '')
end

function __ms_home_save_house_from_position(server_id, x, y, z)
    server_id, x, y, z = tonumber(server_id), tonumber(x), tonumber(y), tonumber(z)
    if server_id == nil or x == nil or y == nil or z == nil then return false, nil end
    server_id = math.floor(server_id)

    if __ms_home.count <= 0 then __ms_home_load_db(true) end
    local db_id, save_mode = __ms_home_db_id_for_save(server_id)
    if db_id == nil then return false, nil end

    local data = __ms_home_source_data_for_user_file()
    local block = string.format('\n\n[%d]\nx = %.6f\ny = %.6f\nz = %.6f\n', db_id, x, y, z)
    local ok = __ms_home_write_file(__ms_home.user_path, data .. block)
    if ok then
        __ms_home_load_db(true)
    end
    return ok, db_id, save_mode
end

function __ms_home_add_command(arg)
    arg = __ms_home_trim(arg)
    local id = tonumber(arg:match('^(%d+)'))
    if id == nil then
        __ms_home_msg('[MS Home] Использование: /mshomeadd ID. Встаньте у входа дома и введите ID Advance, можно 0.', 0xFFFFC040)
        return
    end
    id = math.floor(id)
    if id < 0 or id > __ms_home.max_server_id then
        __ms_home_msg(string.format('[MS Home] Неверный ID дома. Доступно: 0-%d.', __ms_home.max_server_id), 0xFFFF4040)
        return
    end

    local x, y, z = __ms_home_get_player_position()
    if not x then
        __ms_home_msg('[MS Home] Не удалось получить координаты игрока. Выйдите из режима просмотра дома и встаньте у входа.', 0xFFFF4040)
        return
    end

    local ok, db_id = __ms_home_save_house_from_position(id, x, y, z)
    if not ok then
        __ms_home_msg('[MS Home] Не удалось записать house.ini. Проверьте папку moonloader\\config.', 0xFFFF4040)
        return
    end

    __ms_home_msg(string.format('[MS Home] Дом Advance ID %d сохранён в house.ini. Координаты: %.3f %.3f %.3f.', id, x, y, z), 0x66CCFFFF)
    __ms_home_mark_by_id(id, false)
end

lua_thread.create(function()
    repeat wait(0) until type(isSampAvailable) == 'function' and isSampAvailable()

    __ms_home_prepare_dirs()
    __ms_home_load_db(true)

    if type(sampRegisterChatCommand) == 'function' then
        sampRegisterChatCommand('mshome', __ms_home_command)
        sampRegisterChatCommand('mshomeadd', __ms_home_add_command)
    end

    while true do
        -- v22: некоторые сборки/карты могут сбрасывать target waypoint после открытия карты.
        -- Поэтому аккуратно переустанавливаем только waypoint раз в несколько секунд.
        wait(tonumber(__ms_home.reapply_ms or 3000) or 3000)
        if __ms_home.x and __ms_home.y and __ms_home.z and __ms_home.waypoint_enabled ~= false then
            __ms_home_try_waypoint(__ms_home.x, __ms_home.y, __ms_home.z)
        end
    end
end)



-- =========================================================
-- MSHelper v16 source visible marker
-- Global sampShowDialog hook disabled to avoid native SA:MP crashes.
-- =========================================================


end
MSHelper_HomeAddonStart_V17()
MSHelper_HomeAddonStart_V17 = nil

-- =========================================================
-- MSHelper v17 source visible marker + local limit fix
-- Global sampShowDialog hook disabled to avoid native SA:MP crashes.
-- =========================================================

-- =========================================================
-- MSHelper no-update version
-- GitHub update commands and auto-update checks removed.
-- =========================================================

-- MSHelper v21: /mshome uses GTA waypoint + dark cross blips for better visibility.




-- =========================================================

-- Информер урона полностью удалён из этой сборки: нет хуков урона, потоков отрисовки и пунктов меню.

-- =========================================================
-- MS Helper | GitHub one-file updater like HorAssist
-- /msupdate      - check and install update from GitHub
-- /msupdate force - force download and reload
-- =========================================================
MSH_UPDATER_VERSION = MSH_UPDATER_VERSION or '1.0.2'
MSH_UPDATER_JSON_URL = MSH_UPDATER_JSON_URL or 'https://raw.githubusercontent.com/MakarMaslow/mshelper-data/main/update/update.json'
MSH_UPDATER_BUSY = MSH_UPDATER_BUSY or false

function MSHelper_UpdateReadFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

function MSHelper_UpdateWriteFile(path, data)
    local f = io.open(path, 'wb')
    if not f then return false end
    f:write(data or '')
    f:close()
    return true
end

function MSHelper_UpdateCopyFile(src, dst)
    local data = MSHelper_UpdateReadFile(src)
    if not data or #data < 1 then return false end
    return MSHelper_UpdateWriteFile(dst, data)
end

function MSHelper_UpdateJsonValue(raw, key)
    raw = tostring(raw or '')
    key = tostring(key or '')
    local pat1 = '"' .. key .. '"%s*:%s*"([^"]+)"'
    local pat2 = key .. '%s*=%s*([^\r\n]+)'
    local value = raw:match(pat1) or raw:match(pat2)
    if value then
        value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
    end
    return value
end

function MSHelper_UpdateMsg(text)
    if helper_msg then helper_msg(text) else sampAddChatMessage('[MS Helper] ' .. tostring(text), -1) end
end

function MSHelper_UpdateInstall(downloaded_path, latest)
    local self_path = thisScript().path
    local backup_path = self_path .. '.backup'
    local new_data = MSHelper_UpdateReadFile(downloaded_path)

    if not new_data or #new_data < 10000 then
        MSHelper_UpdateMsg('Файл обновления пустой или повреждён. Обновление отменено.')
        pcall(os.remove, downloaded_path)
        return false
    end

    pcall(os.remove, backup_path)
    MSHelper_UpdateCopyFile(self_path, backup_path)

    if not MSHelper_UpdateWriteFile(self_path, new_data) then
        MSHelper_UpdateMsg('Не удалось заменить файл скрипта. Старый файл не тронут.')
        return false
    end

    pcall(os.remove, downloaded_path)
    MSHelper_UpdateMsg('Обновление до версии ' .. tostring(latest or '?') .. ' установлено. Перезагружаю скрипт...')

    lua_thread.create(function()
        wait(700)
        pcall(function() thisScript():reload() end)
    end)
    return true
end

function MSHelper_UpdateHandleJson(raw, json_path, upd_path, force)
    pcall(os.remove, json_path)

    raw = tostring(raw or '')
    raw = raw:gsub('^\239\187\191', ''):gsub('^%s+', ''):gsub('%s+$', '')

    if raw == '' or #raw < 10 then
        MSHelper_UpdateMsg('Не удалось прочитать update.json.')
        MSH_UPDATER_BUSY = false
        return
    end

    local latest = MSHelper_UpdateJsonValue(raw, 'latest') or MSHelper_UpdateJsonValue(raw, 'version')
    local updateurl = MSHelper_UpdateJsonValue(raw, 'updateurl') or MSHelper_UpdateJsonValue(raw, 'url')
    local changelog = MSHelper_UpdateJsonValue(raw, 'changelog')

    if not latest or not updateurl then
        MSHelper_UpdateMsg('В update.json не найдены latest/updateurl.')
        MSH_UPDATER_BUSY = false
        return
    end

    if latest == MSH_UPDATER_VERSION and not force then
        MSHelper_UpdateMsg('Обновлений нет. Текущая версия: ' .. tostring(MSH_UPDATER_VERSION) .. '.')
        MSH_UPDATER_BUSY = false
        return
    end

    MSHelper_UpdateMsg('Найдена версия ' .. tostring(latest) .. '. Скачиваю...')
    if changelog and changelog ~= '' then
        MSHelper_UpdateMsg('Список изменений можно посмотреть на GitHub в update/changelog.txt.')
    end

    local upd_done = false
    pcall(os.remove, upd_path)
    downloadUrlToFile(updateurl, upd_path, function(id2, status2)
        if upd_done then return end

        if status2 == 6 then
            upd_done = true
            lua_thread.create(function()
                wait(700) -- даём MoonLoader/Windows дописать файл на диск
                MSHelper_UpdateInstall(upd_path, latest)
                MSH_UPDATER_BUSY = false
            end)
        elseif status2 == 7 or status2 == 8 or status2 == 58 then
            upd_done = true
            MSHelper_UpdateMsg('Ошибка скачивания обновления.')
            pcall(os.remove, upd_path)
            MSH_UPDATER_BUSY = false
        end
    end)
end

function MSHelper_UpdateRun(arg)
    if MSH_UPDATER_BUSY then
        MSHelper_UpdateMsg('Обновление уже выполняется.')
        return
    end

    arg = tostring(arg or ''):lower()
    local force = arg:find('force', 1, true) ~= nil or arg:find('форс', 1, true) ~= nil
    MSH_UPDATER_BUSY = true

    lua_thread.create(function()
        local self_path = thisScript().path
        local json_path = self_path .. '.update.json'
        local upd_path = self_path .. '.update'

        MSHelper_UpdateMsg('Проверяю обновление...')
        pcall(os.remove, json_path)
        pcall(os.remove, upd_path)

        local json_done = false
        downloadUrlToFile(MSH_UPDATER_JSON_URL, json_path, function(id, status)
            if json_done then return end

            if status == 6 then -- DL_STATUS_ENDDOWNLOADDATA
                json_done = true
                lua_thread.create(function()
                    local raw = nil
                    for i = 1, 8 do
                        wait(250)
                        raw = MSHelper_UpdateReadFile(json_path)
                        if raw and #raw > 0 then break end
                    end
                    MSHelper_UpdateHandleJson(raw, json_path, upd_path, force)
                end)
            elseif status == 7 or status == 8 or status == 58 then
                json_done = true
                MSHelper_UpdateMsg('Не удалось скачать update.json.')
                pcall(os.remove, json_path)
                MSH_UPDATER_BUSY = false
            end
        end)
    end)
end

lua_thread.create(function()
    repeat wait(0) until isSampAvailable()
    wait(1500)
    sampRegisterChatCommand('msupdate', MSHelper_UpdateRun)
end)

