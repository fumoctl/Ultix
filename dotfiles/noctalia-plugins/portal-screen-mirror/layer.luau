--!nonstrict

local function outputDimensions()
	local outName = layer.outputName()
	for _, out in ipairs(noctalia.outputs() or {}) do
		if out.name == outName and (out.width or 0) > 0 and (out.height or 0) > 0 then
			return out.width, out.height
		end
	end
	return 1920, 1080
end

local function fitMode()
	local configured = noctalia.getConfig("fit")
	if configured == "cover" or configured == "stretch" then
		return configured
	end
	return "contain"
end

local function render()
	local status = noctalia.state.get("mirror_status")
	local sockPath = type(status) == "table" and status.socket or ""
	local w, h = outputDimensions()

	if type(sockPath) == "string" and sockPath ~= "" then
		layer.render(ui.column({
			fill = "#000000",
			width = w,
			height = h,
			align = "center",
			justify = "center",
		}, {
			ui.pixelStream({
				key = "mirror-stream",
				path = sockPath,
				width = w,
				height = h,
				fit = fitMode(),
			}),
		}))
	else
		layer.render(ui.column({
			fill = "#000000",
			width = w,
			height = h,
		}, {}))
	end
end

noctalia.state.watch("mirror_status", function(_value)
	render()
end)

function onConfigChanged()
	render()
end

function update()
	render()
end

render()
