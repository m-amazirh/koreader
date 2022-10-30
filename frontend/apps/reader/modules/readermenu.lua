local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screensaver = require("ui/screensaver")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local dbg = require("dbg")
local util  = require("util")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderMenu = InputContainer:extend{
    tab_item_table = nil,
    menu_items = nil, -- table, mandatory
    registered_widgets = nil, -- array
}

function ReaderMenu:init()
    self.menu_items = {
        ["KOMenu:menu_buttons"] = {
            -- top menu
        },
        -- items in top menu
        navi = {
            icon = "appbar.navigation",
        },
        typeset = {
            icon = "appbar.typeset",
        },
        setting = {
            icon = "appbar.settings",
        },
        tools = {
            icon = "appbar.tools",
        },
        search = {
            icon = "appbar.search",
        },
        filemanager = {
            icon = "appbar.filebrowser",
            remember = false,
            callback = function()
                self:onTapCloseMenu()
                self.ui:onClose()
                self.ui:showFileManager()
            end,
        },
        main = {
            icon = "appbar.menu",
        }
    }

    self.registered_widgets = {}

    if Device:hasKeys() then
        if Device:isTouchDevice() then
            self.key_events.TapShowMenu = { { "Menu" } }
            if Device:hasFewKeys() then
                self.key_events.TapShowMenu = { { { "Menu", "Right" } } }
            end
        else
            -- map menu key to only top menu because bottom menu is only
            -- designed for touch devices
            self.key_events.ShowMenu = { { "Menu" } }
            if Device:hasFewKeys() then
                self.key_events.ShowMenu = { { { "Menu", "Right" } } }
            end
        end
    end
    if G_reader_settings:has("activate_menu") then
        self.activation_menu = G_reader_settings:readSetting("activate_menu")
    else
        self.activation_menu = "swipe_tap"
    end

    -- delegate gesture listener to readerui, NOP our own
    self.ges_events = nil
end

function ReaderMenu:onGesture() end

function ReaderMenu:getPreviousFile()
    return require("readhistory"):getPreviousFile(self.ui.document.file)
end

function ReaderMenu:onReaderReady()
    if not Device:isTouchDevice() then return end

    local DTAP_ZONE_MENU = G_defaults:readSetting("DTAP_ZONE_MENU")
    local DTAP_ZONE_MENU_EXT = G_defaults:readSetting("DTAP_ZONE_MENU_EXT")
    self.ui:registerTouchZones({
        {
            id = "readermenu_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            overrides = {
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTapShowMenu(ges) end,
        },
        {
            id = "readermenu_ext_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "readermenu_tap",
            },
            handler = function(ges) return self:onTapShowMenu(ges) end,
        },
        {
            id = "readermenu_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
        {
            id = "readermenu_ext_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "readermenu_swipe",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
        {
            id = "readermenu_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            overrides = {
                "rolling_pan",
                "paging_pan",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
        {
            id = "readermenu_ext_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "readermenu_pan",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
    })
end

function ReaderMenu:setUpdateItemTable()
    for _, widget in pairs(self.registered_widgets) do
        local ok, err = pcall(widget.addToMainMenu, widget, self.menu_items)
        if not ok then
            logger.err("failed to register widget", widget.name, err)
        end
    end

    -- typeset tab
    self.menu_items.document_settings = {
        text = _("Document settings"),
        sub_item_table = {
            {
                text = _("Reset document settings to default"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Reset current document settings to their default values?\n\nReading position, highlights and bookmarks will be kept.\nThe document will be reloaded."),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            local current_file = self.ui.document.file
                            self:onTapCloseMenu()
                            self.ui:onClose()
                            require("apps/filemanager/filemanagerutil").resetDocumentSettings(current_file)
                            require("apps/reader/readerui"):showReader(current_file)
                        end,
                    })
                end,
            },
            {
                text = _("Save document settings as default"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Save current document settings as default values?"),
                        ok_text = _("Save"),
                        ok_callback = function()
                            self:onTapCloseMenu()
                            self:saveDocumentSettingsAsDefault()
                            UIManager:show(require("ui/widget/notification"):new{
                                text = _("Default settings updated"),
                            })
                        end,
                    })
                end,
            },
        },
    }

    self.menu_items.page_overlap = require("ui/elements/page_overlap")

    -- settings tab
    -- insert common settings
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_settings_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end

    if Device:isTouchDevice() then
        self.menu_items.page_turns = require("ui/elements/page_turns")
    else
        -- Placed elsewhere than in Taps and gestures, with only a subset of menu items.
        self.menu_items.page_turns_non_touch = require("ui/elements/page_turns")
    end
    -- insert DjVu render mode submenu just before the last entry (show advanced)
    -- this is a bit of a hack
    if self.ui.document.is_djvu then
        self.menu_items.djvu_render_mode = self.view:getRenderModeMenuTable()
    end

    if Device:supportsScreensaver() then
        local ss_book_settings = {
            text = _("Exclude this book's cover from screensaver"),
            enabled_func = function()
                return not (self.ui == nil or self.ui.document == nil)
                    and G_reader_settings:readSetting("screensaver_type") == "cover"
            end,
            checked_func = function()
                return self.ui and self.ui.doc_settings and self.ui.doc_settings:isTrue("exclude_screensaver")
            end,
            callback = function()
                if Screensaver:isExcluded() then
                    self.ui.doc_settings:makeFalse("exclude_screensaver")
                else
                    self.ui.doc_settings:makeTrue("exclude_screensaver")
                end
                self.ui:saveSettings()
            end,
            added_by_readermenu_flag = true,
        }
        local screensaver_sub_item_table = require("ui/elements/screensaver_menu")
        -- Before inserting this new item, remove any previously added one
        for i = #screensaver_sub_item_table, 1, -1 do
            if screensaver_sub_item_table[i].added_by_readermenu_flag then
                table.remove(screensaver_sub_item_table, i)
            end
        end
        table.insert(screensaver_sub_item_table, ss_book_settings)
        self.menu_items.screensaver = {
            text = _("Screensaver"),
            sub_item_table = screensaver_sub_item_table,
        }
    end

    local PluginLoader = require("pluginloader")
    self.menu_items.plugin_management = {
        text = _("Plugin management"),
        sub_item_table = PluginLoader:genPluginManagerSubItem()
    }
    -- main menu tab
    -- insert common info
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_info_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end
    -- insert common exit for reader
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_exit_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end

    self.menu_items.open_previous_document = {
        text_func = function()
            local previous_file = self:getPreviousFile()
            if not G_reader_settings:isTrue("open_last_menu_show_filename") or not previous_file then
                return _("Open previous document")
            end
            local path, file_name = util.splitFilePathName(previous_file) -- luacheck: no unused
            return T(_("Previous: %1"), BD.filename(file_name))
        end,
        enabled_func = function()
            return self:getPreviousFile() ~= nil
        end,
        callback = function()
            self.ui:onOpenLastDoc()
        end,
        hold_callback = function()
            local previous_file = self:getPreviousFile()
            UIManager:show(ConfirmBox:new{
                text = T(_("Would you like to open the previous document: %1?"), BD.filepath(previous_file)),
                ok_text = _("OK"),
                ok_callback = function()
                    self.ui:switchDocument(previous_file)
                end,
            })
        end
    }

    local order = require("ui/elements/reader_menu_order")

    local MenuSorter = require("ui/menusorter")
    self.tab_item_table = MenuSorter:mergeAndSort("reader", self.menu_items, order)
end
dbg:guard(ReaderMenu, 'setUpdateItemTable',
    function(self)
        local mock_menu_items = {}
        for _, widget in pairs(self.registered_widgets) do
            -- make sure addToMainMenu works in debug mode
            widget:addToMainMenu(mock_menu_items)
        end
    end)

function ReaderMenu:saveDocumentSettingsAsDefault()
    local prefix
    if self.ui.rolling then
        G_reader_settings:saveSetting("cre_font", self.ui.font.font_face)
        G_reader_settings:saveSetting("copt_css", self.ui.document.default_css)
        G_reader_settings:saveSetting("style_tweaks", self.ui.styletweak.global_tweaks)
        prefix = "copt_"
    else
        prefix = "kopt_"
    end
    for k, v in pairs(self.ui.document.configurable) do
        G_reader_settings:saveSetting(prefix .. k, v)
    end
end

function ReaderMenu:exitOrRestart(callback, force)
    if self.menu_container then self:onTapCloseMenu() end

    -- Only restart sets a callback, which suits us just fine for this check ;)
    if callback and not force and not Device:isStartupScriptUpToDate() then
        UIManager:show(ConfirmBox:new{
            text = _("KOReader's startup script has been updated. You'll need to completely exit KOReader to finalize the update."),
            ok_text = _("Restart anyway"),
            ok_callback = function()
                self:exitOrRestart(callback, true)
            end,
        })
        return
    end

    UIManager:nextTick(function()
        self.ui:onClose()
        if callback ~= nil then
            -- show an empty widget so that the callback always happens
            local Widget = require("ui/widget/widget")
            local widget = Widget:new{
                width = Screen:getWidth(),
                height = Screen:getHeight(),
            }
            UIManager:show(widget)
            local waiting = function(waiting)
                -- if we don't do this you can get a situation where either the
                -- program won't exit due to remaining widgets until they're
                -- dismissed or if the callback forces all widgets to close,
                -- that the save document ConfirmBox is also closed
                if self.ui and self.ui.document and self.ui.document:isEdited() then
                    logger.dbg("waiting for save settings")
                    UIManager:scheduleIn(1, function() waiting(waiting) end)
                else
                    callback()
                    UIManager:close(widget)
                end
            end
            UIManager:scheduleIn(1, function() waiting(waiting) end)
        end
    end)
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:onClose()
    end
end

function ReaderMenu:onShowMenu(tab_index)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end

    if not tab_index then
        tab_index = self.last_tab_index
    end

    local menu_container = CenterContainer:new{
        ignore = "height",
        dimen = Screen:getSize(),
    }

    local main_menu
    if Device:isTouchDevice() or Device:hasDPad() then
        local TouchMenu = require("ui/widget/touchmenu")
        main_menu = TouchMenu:new{
            width = Screen:getWidth(),
            last_index = tab_index,
            tab_item_table = self.tab_item_table,
            show_parent = menu_container,
        }
    else
        local Menu = require("ui/widget/menu")
        main_menu = Menu:new{
            title = _("Document menu"),
            item_table = Menu.itemTableFromTouchMenu(self.tab_item_table),
            width = Screen:getWidth() - 100,
            show_parent = menu_container,
        }
    end

    main_menu.close_callback = function()
        self.ui:handleEvent(Event:new("CloseReaderMenu"))
    end

    main_menu.touch_menu_callback = function ()
        self.ui:handleEvent(Event:new("CloseConfigMenu"))
    end

    menu_container[1] = main_menu
    -- maintain a reference to menu_container
    self.menu_container = menu_container
    UIManager:show(menu_container)
    return true
end

function ReaderMenu:onCloseReaderMenu()
    if self.menu_container then
        self.last_tab_index = self.menu_container[1].last_index
        self:onSaveSettings()
        UIManager:close(self.menu_container)
    end
    return true
end

function ReaderMenu:onSetDimensions(dimen)
    self:onCloseReaderMenu()
end

function ReaderMenu:onCloseDocument()
    if Device:supportsScreensaver() then
        -- Remove the item we added (which cleans up references to document
        -- and doc_settings embedded in functions)
        local screensaver_sub_item_table = require("ui/elements/screensaver_menu")
        for i = #screensaver_sub_item_table, 1, -1 do
            if screensaver_sub_item_table[i].added_by_readermenu_flag then
                table.remove(screensaver_sub_item_table, i)
            end
        end
    end
end

function ReaderMenu:_getTabIndexFromLocation(ges)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end
    if not ges then
        return self.last_tab_index
    -- if the start position is far right
    elseif ges.pos.x > Screen:getWidth() * (2/3) then
        return BD.mirroredUILayout() and 1 or #self.tab_item_table
    -- if the start position is far left
    elseif ges.pos.x < Screen:getWidth() * (1/3) then
        return BD.mirroredUILayout() and #self.tab_item_table or 1
    -- if center return the last index
    else
        return self.last_tab_index
    end
end

function ReaderMenu:onSwipeShowMenu(ges)
    if self.activation_menu ~= "tap" and ges.direction == "south" then
        if G_reader_settings:nilOrTrue("show_bottom_menu") then
            self.ui:handleEvent(Event:new("ShowConfigMenu"))
        end
        self.ui:handleEvent(Event:new("ShowMenu", self:_getTabIndexFromLocation(ges)))
        self.ui:handleEvent(Event:new("HandledAsSwipe")) -- cancel any pan scroll made
        return true
    end
end

function ReaderMenu:onTapShowMenu(ges)
    if self.activation_menu ~= "swipe" then
        if G_reader_settings:nilOrTrue("show_bottom_menu") then
            self.ui:handleEvent(Event:new("ShowConfigMenu"))
        end
        self.ui:handleEvent(Event:new("ShowMenu", self:_getTabIndexFromLocation(ges)))
        return true
    end
end

function ReaderMenu:onTapCloseMenu()
    self.ui:handleEvent(Event:new("CloseReaderMenu"))
    self.ui:handleEvent(Event:new("CloseConfigMenu"))
end

function ReaderMenu:onReadSettings(config)
    self.last_tab_index = config:readSetting("readermenu_tab_index") or 1
end

function ReaderMenu:onSaveSettings()
    self.ui.doc_settings:saveSetting("readermenu_tab_index", self.last_tab_index)
end

function ReaderMenu:registerToMainMenu(widget)
    table.insert(self.registered_widgets, widget)
end

return ReaderMenu
