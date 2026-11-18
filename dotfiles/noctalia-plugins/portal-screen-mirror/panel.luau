--!nonstrict

local outputs = {}
local destinationName = nil
local destinationIndex = -1
local requestSerial = 0
local render

local status = noctalia.state.get("mirror_status") or {
	phase = "stopped",
	running = false,
	message = "",
}

local function tr(key, values)
	return noctalia.tr(key, values)
end

local function isInternalPanel(name)
	return string.sub(name or "", 1, 4) == "eDP-"
end

local function outputLabel(out)
	local desc = out.description or ""
	if desc == "" or desc == out.name then
		return out.name
	end
	return out.name .. " — " .. desc
end

local function findOutputIndex(items, name)
	if name == nil then
		return -1
	end
	for idx, out in ipairs(items) do
		if out.name == name then
			return idx - 1
		end
	end
	return -1
end

local function refreshOutputs()
	local raw = noctalia.outputs() or {}
	outputs = {}
	for _, out in ipairs(raw) do
		if type(out.name) == "string" and out.name ~= "" then
			table.insert(outputs, out)
		end
	end

	-- External, unfocused displays sort first (e.g. HDMI-A-1 before eDP-1).
	table.sort(outputs, function(a, b)
		local aInternal = isInternalPanel(a.name)
		local bInternal = isInternalPanel(b.name)
		if aInternal ~= bInternal then
			return not aInternal
		end
		local aFocused = a.focused == true
		local bFocused = b.focused == true
		if aFocused ~= bFocused then
			return not aFocused
		end
		return a.name < b.name
	end)

	if (status.phase == "running" or status.phase == "starting") and findOutputIndex(outputs, status.destination) >= 0 then
		destinationName = status.destination
	elseif findOutputIndex(outputs, destinationName) < 0 then
		destinationName = outputs[1] and outputs[1].name or nil
	end

	destinationIndex = findOutputIndex(outputs, destinationName)
end

local function statusBanner()
	local phase = status.phase or "stopped"
	local glyph = "screen-share"
	local color = "on_surface_variant"
	local text = tr("panel.status_ready")

	if phase == "running" then
		glyph = "screen-share"
		color = "primary"
		text = tr("panel.status_running", { destination = status.destination or "?" })
	elseif phase == "starting" then
		glyph = "loader-2"
		color = "on_surface_variant"
		text = tr("panel.status_starting")
	elseif phase == "stopping" then
		glyph = "loader-2"
		color = "on_surface_variant"
		text = tr("widget.stopping")
	elseif phase == "error" then
		glyph = "alert-circle"
		color = "error"
		text = (type(status.message) == "string" and status.message ~= "") and status.message or tr("widget.error")
	end

	return ui.row({
		gap = 10,
		padding = 12,
		align = "center",
		fill = "surface_container",
		radius = 10,
	}, {
		ui.glyph({ name = glyph, size = 18, color = color }),
		ui.label({
			text = text,
			color = phase == "error" and "error" or "on_surface",
			maxLines = 2,
			flexGrow = 1,
		}),
	})
end

local function startMode(mode)
	if destinationName == nil or destinationName == "" then
		return
	end
	requestSerial += 1
	noctalia.state.set("mirror_request", {
		action = "start",
		mode = mode,
		destination = destinationName,
		serial = requestSerial,
	})
	panel.close()
end

function onCloseClicked()
	panel.close()
end

function onStopClicked()
	requestSerial += 1
	noctalia.state.set("mirror_request", {
		action = "stop",
		serial = requestSerial,
	})
end

function onDestinationChanged(idxStr)
	local idx = tonumber(idxStr)
	if idx ~= nil and outputs[idx + 1] ~= nil then
		destinationName = outputs[idx + 1].name
		destinationIndex = idx
		render()
	end
end

function onPortalClicked()
	startMode("portal")
end

function onRegionClicked()
	startMode("region")
end

render = function()
	refreshOutputs()

	local phase = status.phase or "stopped"
	local active = phase == "running" or phase == "starting"
	local busy = phase == "starting" or phase == "stopping"

	local children = {
		ui.row({ align = "center", justify = "space_between" }, {
			ui.row({ gap = 8, align = "center", flexGrow = 1 }, {
				ui.glyph({ name = "screen-share", size = 18, color = "primary" }),
				ui.label({
					text = tr("title"),
					fontSize = 16,
					fontWeight = "bold",
					flexGrow = 1,
				}),
			}),
			ui.button({
				glyph = "x",
				variant = "ghost",
				controlSize = "sm",
				onClick = "onCloseClicked",
			}),
		}),
		statusBanner(),
	}

	if active then
		table.insert(
			children,
			ui.button({
				key = "stop-btn",
				text = tr("panel.stop_button"),
				glyph = "player-stop",
				variant = "destructive",
				controlSize = "lg",
				enabled = phase ~= "stopping",
				onClick = "onStopClicked",
			})
		)
	end

	if #outputs < 2 then
		table.insert(
			children,
			ui.column({
				gap = 4,
				padding = 12,
				fill = "surface_container",
				radius = 10,
			}, {
				ui.label({ text = tr("panel.no_outputs_title"), fontWeight = "bold" }),
				ui.label({ text = tr("panel.no_outputs_body"), color = "on_surface_variant", maxLines = 3 }),
			})
		)
	else
		local optionLabels = {}
		for _, out in ipairs(outputs) do
			table.insert(optionLabels, outputLabel(out))
		end

		table.insert(
			children,
			ui.column({ gap = 6 }, {
				ui.label({
					text = tr("panel.destination_label"),
					fontWeight = "medium",
					color = "on_surface_variant",
				}),
				ui.select({
					key = "dest-select",
					options = optionLabels,
					selectedIndex = math.max(0, destinationIndex),
					enabled = not busy,
					controlSize = "md",
					onChange = "onDestinationChanged",
				}),
			})
		)

		table.insert(
			children,
			ui.column({ gap = 8 }, {
				ui.label({
					text = tr("panel.source_label"),
					fontWeight = "medium",
					color = "on_surface_variant",
				}),
				ui.button({
					key = "portal-btn",
					text = tr("panel.portal_button"),
					glyph = "device-desktop",
					variant = "primary",
					controlSize = "lg",
					contentAlign = "start",
					enabled = not busy and destinationName ~= nil,
					onClick = "onPortalClicked",
				}),
				ui.button({
					key = "region-btn",
					text = tr("panel.region_button"),
					glyph = "crop",
					variant = "secondary",
					controlSize = "lg",
					contentAlign = "start",
					enabled = not busy and destinationName ~= nil,
					onClick = "onRegionClicked",
				}),
			})
		)
	end

	panel.render(ui.column({ gap = 12, padding = 4 }, children))
end

noctalia.state.watch("mirror_status", function(value)
	if type(value) == "table" then
		status = value
		render()
	end
end)

function onOpen(_context)
	local current = noctalia.state.get("mirror_status")
	if type(current) == "table" then
		status = current
	end
	render()
end

function update()
	render()
end

render()
