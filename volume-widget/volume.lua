local awful = require("awful")
local wibox = require("wibox")
local watch = require("awful.widget.watch")
local spawn = require("awful.spawn")
local naughty = require("naughty")

local request_command = 'amixer -D pulse sget Master'

local function factory(args)

    if args == nil then
        args = {}
        --see https://stackoverflow.com/questions/6022519/define-default-values-for-function-arguments for adding default arguments
    end

    local volume_widget = wibox.widget {
        {
            id = "icon",
            resize = false,
            widget = wibox.widget.imagebox,
        },
        layout = wibox.container.margin(_, _, _, 3),
        set_image = function(self, path)
            self.icon.image = path
        end
    }

    volume_widget._path_to_icons = args.path_to_icons or "/usr/share/icons/Adwaita/scalable/status/"
    volume_widget._toogle_mute = false
    volume_widget._increase = 0
    volume_widget._widget_update_pending = false
    volume_widget._notification = nil
    volume_widget.image = volume_widget._path_to_icons .. "audio-volume-muted-symbolic.svg"
    volume_widget._bar_char_count = 20

    function volume_widget:_update_widget(stdout, _, _, _)
        local volume = string.match(stdout, "(%d?%d?%d)%%")
        local mute = string.match(stdout, "%[(o%D%D?)%]")
        self._mute = mute == "off"
        self._volume = tonumber(string.format("% 3d", volume))
        volume = self._volume

        self._widget_update_pending = false

        if self._increase ~= 0 then
            volume = self._volume + self._increase
            self._increase = 0
            if volume > 100 then
                volume = 100
            elseif volume < 0 then
                volume = 0
            end
            awful.spawn("amixer -D pulse sset Master " .. volume .. "%", false)
            self._volume = volume
        end

        if self._toogle_mute then
            self._toogle_mute = false
            awful.spawn("amixer -D pulse sset Master toggle", false)
            self._mute = not self._mute
        end

        local volume_icon_name
        if self._mute then volume_icon_name="audio-volume-muted-symbolic"
        elseif (volume == 0) then volume_icon_name="audio-volume-muted-symbolic"
        elseif (volume < 33) then volume_icon_name="audio-volume-low-symbolic"
        elseif (volume < 67) then volume_icon_name="audio-volume-medium-symbolic"
        elseif (volume <= 100) then volume_icon_name="audio-volume-high-symbolic"
        end
        self.image = self._path_to_icons .. volume_icon_name .. ".svg"

        self:update_notification()
    end

    function volume_widget:update_notification()
        if self._notification ~= nil then
            self:notify()
        end
    end

    function volume_widget:update()
        if (not self._widget_update_pending) then
            self._widget_update_pending = true
            spawn.easy_async(request_command, function(stdout, stderr, exitreason, exitcode)
                self:_update_widget(stdout, stderr, exitreason, exitcode)
            end)
        end
    end

    function volume_widget:increase_volume(value)
        local incr = tonumber(value)
        if incr ~= nil then
            self._increase = self._increase + incr
        end
        self:update()
    end

    function volume_widget:toogle_mute()
        self._toogle_mute = not self._toogle_mute
        self:update()
    end

    function volume_widget:notify()
        local printed_volume = string.format(" %3d%%", self._volume)
        local notif_text = ""
        local bar_count = math.floor(self._volume * self._bar_char_count / 100)
        notif_text = string.rep("|", bar_count) .. string.rep(" ", self._bar_char_count - bar_count)
        local notify_args = {
            title = "Volume",
            text = notif_text .. printed_volume,
        }
        if self._mute then
            -- notify_args.fg = '#ff0000' not working, awesome bug? https://github.com/awesomeWM/awesome/issues/2040
            notify_args.title = notify_args.title .. " (muted)"
        end
        if self._notification ~= nil then
            notify_args.replaces_id = self._notification.id
        end
        self._notification = naughty.notify(notify_args)
    end

    function volume_widget:m_enter()
        volume_widget:notify()
        self:update()
    end

    function volume_widget:m_leave()
        if (self._notification ~= nil) then
            local notification = self._notification
            self._notification = nil
            naughty.destroy(notification)
        end
    end

    --[[ allows control volume level by:
    - clicking on the widget to mute/unmute
    - scrolling when cursor is over the widget
    ]]
    volume_widget:connect_signal("button::press", function(_,_,_,button,mods)
        local increment = 5;
        for i,mod in ipairs(mods) do
            if mod == "Shift" then
                increment = 1;
            end
        end
        if (button == 4)     then volume_widget:increase_volume(increment)
        elseif (button == 5) then volume_widget:increase_volume(-increment)
        elseif (button == 1) then volume_widget:toogle_mute()
        end

    end)

    -- show notification when hovering with mouse
    volume_widget:connect_signal("mouse::enter", function() volume_widget:m_enter() end)
    volume_widget:connect_signal("mouse::leave", function() volume_widget:m_leave() end)

    volume_widget:update()
    watch(request_command, 60, volume_widget.update, volume_widget)

    return volume_widget

end

return factory
