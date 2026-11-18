--!nonstrict

local PANEL_ID = "fumoctl/portal-screen-mirror:controls"
local LAYER_ID = "display"

local pluginDir = noctalia.pluginDir()
local dataDir = noctalia.pluginDataDir()
local runFile = dataDir and (dataDir .. "/mirror.run") or nil
local sockFile = dataDir and (dataDir .. "/stream.sock") or nil

local sessionCounter = 0
local lastRequestSerial = -1
local streamActive = false
local notifyOnStop = false
local pendingRestart = nil

local status = {
	phase = "stopped",
	running = false,
	destination = nil,
	mode = nil,
	socket = nil,
	message = "",
}

local function tr(key, values)
	return noctalia.tr(key, values)
end

local function shellQuote(value)
	return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

local function isInternalPanel(name)
	return string.sub(name or "", 1, 4) == "eDP-"
end

local function publishStatus(phase, message)
	status.phase = phase
	status.running = phase == "running"
	status.message = message or ""
	noctalia.state.set("mirror_status", {
		phase = status.phase,
		running = status.running,
		destination = status.destination,
		mode = status.mode,
		socket = status.socket,
		message = status.message,
	})
end

local function findOutput(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	for _, out in ipairs(noctalia.outputs() or {}) do
		if out.name == name then
			return out
		end
	end
	return nil
end

local function defaultDestination()
	local list = {}
	for _, out in ipairs(noctalia.outputs() or {}) do
		if type(out.name) == "string" and out.name ~= "" then
			table.insert(list, out)
		end
	end
	if #list < 2 then
		return nil
	end
	table.sort(list, function(a, b)
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
	return list[1].name
end

local function cleanupFiles()
	if runFile ~= nil then
		noctalia.removeFile(runFile)
	end
	if sockFile ~= nil then
		noctalia.removeFile(sockFile)
	end
end

local startMirror

local function finishStopped(showOsd, customMsg)
	streamActive = false
	notifyOnStop = false
	noctalia.layer.hide(LAYER_ID)
	cleanupFiles()

	status.destination = nil
	status.mode = nil
	status.socket = nil
	publishStatus("stopped", customMsg or "")

	if showOsd then
		noctalia.osd.show("screen-share-off", customMsg or tr("osd.stopped"), { inactive = true })
	end

	if pendingRestart ~= nil then
		local req = pendingRestart
		pendingRestart = nil
		startMirror(req.destination, req.mode)
	end
end

local function finishFailed(errMsg)
	streamActive = false
	notifyOnStop = false
	pendingRestart = nil
	noctalia.layer.hide(LAYER_ID)
	cleanupFiles()

	status.destination = nil
	status.mode = nil
	status.socket = nil
	local msg = (type(errMsg) == "string" and errMsg ~= "") and errMsg or tr("error.stream_exited")
	publishStatus("error", msg)
	noctalia.notifyError(tr("title"), msg)
end

local function stopMirror(showOsd, customMsg)
	if not streamActive then
		finishStopped(showOsd, customMsg)
		return
	end
	notifyOnStop = showOsd == true
	publishStatus("stopping", tr("widget.stopping"))
	noctalia.layer.hide(LAYER_ID)
	if runFile ~= nil then
		noctalia.removeFile(runFile)
	end
end

local function buildCompanionCmd(sessionId, destOut, mode)
	local companionPath = (pluginDir or ".") .. "/companion.py"
	local scale = tonumber(destOut.scale) or 1.0
	if scale <= 0 then
		scale = 1.0
	end
	local maxW = math.max(64, math.floor((tonumber(destOut.width) or 1920) * scale + 0.5))
	local maxH = math.max(64, math.floor((tonumber(destOut.height) or 1080) * scale + 0.5))
	local cursorMode = noctalia.getConfig("show_cursor") ~= false and 2 or 1
	local outputsJson = noctalia.json.encode(noctalia.outputs() or {}) or "[]"

	return table.concat({
		shellQuote(companionPath),
		"--socket",
		shellQuote(sockFile),
		"--run-file",
		shellQuote(runFile),
		"--session-id",
		shellQuote(sessionId),
		"--data-dir",
		shellQuote(dataDir),
		"--mode",
		shellQuote(mode),
		"--cursor-mode",
		tostring(cursorMode),
		"--max-width",
		tostring(maxW),
		"--max-height",
		tostring(maxH),
		"--outputs-json",
		shellQuote(outputsJson),
		"2>/dev/null || printf 'exited:%s\\n' \"$?\"",
	}, " ")
end

local function handleStreamLine(line)
	line = noctalia.string.trim(line or "")
	if line == "" then
		return
	end

	if line == "selecting" then
		publishStatus("starting", tr("panel.status_starting"))
	elseif line == "ready" then
		if status.destination == nil then
			stopMirror(false)
			return
		end
		status.socket = sockFile
		noctalia.layer.configure(LAYER_ID, {
			output = status.destination,
			layer = "overlay",
			anchors = { "top", "bottom", "left", "right" },
			exclusiveZone = -1,
			keyboard = "none",
			clickThrough = true,
		})
		noctalia.layer.show(LAYER_ID)
		publishStatus("running", tr("panel.status_running", { destination = status.destination }))
		noctalia.osd.show("screen-share", tr("osd.started", { destination = status.destination }))
	elseif line == "cancelled" then
		finishStopped(false)
	elseif line == "stopped" then
		finishStopped(notifyOnStop)
	elseif string.sub(line, 1, 6) == "error:" then
		finishFailed(noctalia.string.trim(string.sub(line, 7)))
	elseif string.sub(line, 1, 7) == "exited:" then
		local code = tonumber(string.sub(line, 8)) or 1
		if code == 0 or code == 130 or code == 143 or notifyOnStop then
			finishStopped(notifyOnStop)
		else
			finishFailed(tr("error.stream_exited"))
		end
	end
end

startMirror = function(destination, mode)
	mode = (mode == "region") and "region" or "portal"

	if runFile == nil or sockFile == nil or pluginDir == nil or dataDir == nil then
		finishFailed(tr("error.launch_failed"))
		return
	end
	if not noctalia.portalAvailable() then
		finishFailed(tr("error.portal_unavailable"))
		return
	end
	if mode == "region" and not noctalia.commandExists("slurp") then
		finishFailed(tr("error.slurp_missing"))
		return
	end

	local destOut = findOutput(destination)
	if destOut == nil then
		finishFailed(tr("error.no_destination"))
		return
	end

	if streamActive then
		pendingRestart = { destination = destination, mode = mode }
		stopMirror(false)
		return
	end

	sessionCounter += 1
	local sessionId = tostring(noctalia.nowMs()) .. "-" .. tostring(sessionCounter)
	local ok, err = noctalia.writeFile(runFile, sessionId .. "\n")
	if not ok then
		finishFailed(err or tr("error.launch_failed"))
		return
	end

	status.destination = destination
	status.mode = mode
	status.socket = nil
	notifyOnStop = false
	streamActive = true
	publishStatus("starting", tr("panel.status_starting"))

	local cmd = buildCompanionCmd(sessionId, destOut, mode)
	if not noctalia.runStream(cmd, handleStreamLine) then
		streamActive = false
		cleanupFiles()
		finishFailed(tr("error.launch_failed"))
	end
end

noctalia.state.watch("mirror_request", function(req)
	if type(req) ~= "table" then
		return
	end
	if type(req.serial) == "number" then
		if req.serial == lastRequestSerial then
			return
		end
		lastRequestSerial = req.serial
	end

	if req.action == "start" then
		startMirror(req.destination, req.mode)
	elseif req.action == "stop" then
		pendingRestart = nil
		stopMirror(true)
	end
end)

function onOutputsChanged()
	if (status.phase == "running" or status.phase == "starting") and findOutput(status.destination) == nil then
		pendingRestart = nil
		stopMirror(true, tr("error.disconnected"))
	end
end

function onConfigChanged()
	-- Keep active session intact; new show_cursor setting applies on next start.
end

function onIpc(event, payload)
	local arg = noctalia.string.trim(payload or "")
	if event == "toggle" then
		if status.phase == "running" or status.phase == "starting" then
			pendingRestart = nil
			stopMirror(true)
		else
			noctalia.togglePanel(PANEL_ID)
		end
	elseif event == "stop" then
		pendingRestart = nil
		stopMirror(true)
	elseif event == "portal" or event == "region" then
		if status.phase == "running" or status.phase == "starting" then
			pendingRestart = nil
			stopMirror(true)
			return
		end
		local dest = arg ~= "" and arg or defaultDestination()
		if dest == nil then
			noctalia.notifyError(tr("title"), tr("error.no_destination"))
			return
		end
		startMirror(dest, event)
	end
end

function onExit(_signal, _reason)
	pendingRestart = nil
	noctalia.layer.hide(LAYER_ID)
	cleanupFiles()
end

cleanupFiles()
publishStatus("stopped", "")
