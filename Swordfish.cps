/*
homepage = "%homepage%";
version = "%version%";
*/

description = "Swordfish CNC Controller %version%";
vendor = "Zealandia Systems";
vendorUrl = "https://github.com/Zealandia-Systems/Swordfish-Post-Fusion360";
certificationLevel = 2;
extension = "gcode";
setCodePage("ascii");
capabilities = CAPABILITY_MILLING | CAPABILITY_JET;
keywords = "MODEL_IMAGE PREVIEW_IMAGE";
minimumRevision = 40502;
programNameIsInteger = false;

// Arc support variables
minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined;

// user-defined properties
properties = {
	jobTravelSpeedXY: {
		title: "Job: Travel speed X/Y",
		description: "High speed for travel movements X & Y (mm/min; in/min)",
		group: "configuration",
		type: "number",
		value: 5000,
		scope: "post"
	},
	jobTravelSpeedZ: {
		title: "Job: Travel Speed Z",
		description: "High speed for travel movements z (mm/min; in/min)",
		group: "configuration",
		type: "number",
		value: 5000,
		scope: "post"
	},
	jobUseArcs: {
		title: "Job: Use Arcs",
		description: "Use G2/G3 g-codes fo circular movements",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},

	jobSetOriginOnStart: {
		title: "Job: Reset on start (G92)",
		description: "Set origin when gcode start (G92)",
		group: "configuration",
		type: "boolean",
		value: false,
		scope: "post"
	},
	jobGoOriginOnFinish: {
		title: "Job: Goto 0 at end",
		description: "Go X0 Y0 at gcode end",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},

	/*
	jobSequenceNumbers: false,           // show sequence numbers
	jobSequenceNumberStart: 1,          // first sequence number
	jobSequenceNumberIncrement: 1,       // increment for sequence numbers
	*/
	jobSeparateWordsWithSpace: {
		title: "Job: Separate words",
		description: "Specifies that the words should be separated with a white space",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},

	toolChangeEnabled: {
		title: "Tool Change: Enabled",
		description: "Enable tool change code",
		group: "configuration",
		type: "boolean",
		value: false,
		scope: "post"
	},

	gcodeStartFile: {
		title: "Extern: Start File",
		description: "File with custom Gcode for header/start (in nc folder)",
		group: "configuration",
		type: "file",
		value: "",
		scope: "post"
	},
	gcodeStopFile: {
		title: "Extern: Stop File",
		description: "File with custom Gcode for footer/end (in nc folder)",
		group: "configuration",
		type: "file",
		value: "",
		scope: "post"
	},
	commentWriteTools: {
		title: "Comment: Write Tools",
		description: "Write table of used tools in job header",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
	commentActivities: {
		title: "Comment: Activities",
		description: "Write comments which somehow helps to understand current piece of g-code",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
	commentSections: {
		title: "Comment: Sections",
		description: "Write header of every section",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
	commentCommands: {
		title: "Comment: Trace Commands",
		description: "Write stringified commands called by CAM",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
	commentMovements: {
		title: "Comment: Trace Movements",
		description: "Write stringified movements called by CAM",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
};

const WARNING_WORK_OFFSET = 0;

var sequenceNumber;

// Formats
var G = createFormat({ prefix: "G", decimals: 2 });
var M = createFormat({ prefix: "M", decimals: 0 });

var XYZ = createFormat({ decimals: (unit == MM ? 3 : 4) });
var X = createFormat({ prefix: "X", decimals: (unit == MM ? 3 : 4) });
var Y = createFormat({ prefix: "Y", decimals: (unit == MM ? 3 : 4) });
var Z = createFormat({ prefix: "Z", decimals: (unit == MM ? 3 : 4) });
var I = createFormat({ prefix: "I", decimals: (unit == MM ? 3 : 4) });
var J = createFormat({ prefix: "J", decimals: (unit == MM ? 3 : 4) });
var K = createFormat({ prefix: "K", decimals: (unit == MM ? 3 : 4) });

var speedFormat = createFormat({ decimals: 0 });
var S = createFormat({ prefix: "S", decimals: 0 });

var P = createFormat({ prefix: "P", decimals: 0 });
var O = createFormat({ prefix: "O", decimals: 0 });
var L = createFormat({ prefix: "L", decimals: 0 });
var H = createFormat({ prefix: "H", decimals: 0 });

var feedFormat = createFormat({ decimals: (unit == MM ? 0 : 2) });
var F = createFormat({ prefix: "F", decimals: (unit == MM ? 0 : 2) });

var toolFormat = createFormat({ decimals: 0 });
var T = createFormat({ prefix: "T", decimals: 0 });

var taperFormat = createFormat({ decimals: 1, scale: DEG });
var secFormat = createFormat({ decimals: 3, forceDecimal: true }); // seconds - range 0.001-1000

// Linear outputs
var xOutput = createVariable({}, X);
var yOutput = createVariable({}, Y);
var zOutput = createVariable({}, Z);
var fOutput = createVariable({ force: true }, F);
var sOutput = createVariable({ force: true }, S);

// Circular outputs
var iOutput = createReferenceVariable({}, I);
var jOutput = createReferenceVariable({}, J);
var kOutput = createReferenceVariable({}, K);

/**
	Writes the specified block.
*/
function writeBlock() {
	if (getProperty("jobSequenceNumbers")) {
		writeWords2("N" + sequenceNumber, arguments);
		sequenceNumber += getProperty("jobSequenceNumberIncrement");
	} else {
		writeWords(arguments);
	}
}

// Called in every new gcode file
function onOpen() {
	sequenceNumber = getProperty("jobSequenceNumberStart");
	if (!getProperty("jobSeparateWordsWithSpace")) {
		setWordSeparator("");
	}
}

// Called at end of gcode file
function onClose() {
	writeActivityComment(" *** STOP begin ***");
	flushMotions();

	if (getProperty("gcodeStopFile") == "") {
		onCommand(COMMAND_COOLANT_OFF);
		onCommand(COMMAND_STOP_SPINDLE);

		if (getProperty("jobGoOriginOnFinish")) {
			var z = zOutput.format(0);
			var f = fOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));

			writeBlock(G.format(53), G.format(0), z, f);

			var x = xOutput.format(0);
			var y = yOutput.format(0);

			f = fOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedXY")));
			writeBlock(G.format(0), x, y, f);
		}

		displayText("Job end");
		writeActivityComment(" *** STOP end ***");
	} else {
		loadFile(getProperty("gcodeStopFile"));
	}
}

var cutterOnCurrentPower;

function onSection() {
	// Write Start gcode of the documment (after the "onParameters" with the global info)
	if (isFirstSection()) {
		writeFirstSection();
	}
	writeActivityComment(" *** SECTION begin ***");

	// Tool change
	if (getProperty("toolChangeEnabled") && (isFirstSection() || tool.number != getPreviousSection().getTool().number)) {
		// Builtin tool change gcode
		writeActivityComment(" --- CHANGE TOOL begin ---");
		toolChange();
		writeActivityComment(" --- CHANGE TOOL end ---");
	}

	if (getProperty("commentSections")) {
		// Machining type
		if (currentSection.type == TYPE_MILLING) {
			// Specific milling code
			writeComment(sectionComment + " - Milling - Tool: " + tool.number + " - " + tool.comment + " " + getToolTypeName(tool.type));
		}

		if (currentSection.type == TYPE_JET) {
			// Cutter mode used for different cutting power in PWM laser
			switch (currentSection.jetMode) {
				case JET_MODE_THROUGH:
					cutterOnCurrentPower = getProperty("cutterOnThrough");
					break;
				case JET_MODE_ETCHING:
					cutterOnCurrentPower = getProperty("cutterOnEtch");
					break;
				case JET_MODE_VAPORIZE:
					cutterOnCurrentPower = getProperty("cutterOnVaporize");
					break;
				default:
					error("Cutting mode is not supported.");
			}
			writeComment(sectionComment + " - Laser/Plasma - Cutting mode: " + getParameter("operation:cuttingMode"));
		}

		// Print min/max boundaries for each section
		vectorX = new Vector(1, 0, 0);
		vectorY = new Vector(0, 1, 0);
		writeComment(" X Min: " + XYZ.format(currentSection.getGlobalRange(vectorX).getMinimum()) + " - X Max: " + XYZ.format(currentSection.getGlobalRange(vectorX).getMaximum()));
		writeComment(" Y Min: " + XYZ.format(currentSection.getGlobalRange(vectorY).getMinimum()) + " - Y Max: " + XYZ.format(currentSection.getGlobalRange(vectorY).getMaximum()));
		writeComment(" Z Min: " + XYZ.format(currentSection.getGlobalZRange().getMinimum()) + " - Z Max: " + XYZ.format(currentSection.getGlobalZRange().getMaximum()));
	}

	var workOffset = currentSection.workOffset;

	if (workOffset == 0) { // change work offset of 0 to 1
		warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
		workOffset = 1;
	}

	if (workOffset > 0) {
		//forceWorkPlane();
		const primary = Math.floor(workOffset / 10) + 4;
		const secondary = (workOffset % 10) - 1;

		writeBlock(G.format(50 + primary) + "." + secondary); // G59.n

		const z = zOutput.format(0);
		const f = fOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));

		writeBlock(G.format(53), G.format(0), z, f);
	}

	onCommand(COMMAND_START_SPINDLE);
	onCommand(COMMAND_COOLANT_ON);
	// Display section name in LCD
	displayText(" " + sectionComment);
}

function resetAll() {
	xOutput.reset();
	yOutput.reset();
	zOutput.reset();
	fOutput.reset();
}

// Called in every section end
function onSectionEnd() {
	resetAll();
	writeActivityComment(" *** SECTION end ***");
	writeln("");
}

function onComment(message) {
	writeComment(message);
}

var pendingRadiusCompensation = RADIUS_COMPENSATION_OFF;

function onRadiusCompensation() {
	pendingRadiusCompensation = radiusCompensation;
}

// Rapid movements
function onRapid(_x, _y, _z) {
	if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
		error(localize("Radius compensation mode cannot be changed at rapid traversal."));
		return;
	}

	var z = zOutput.format(_z);
	var x = xOutput.format(_x);
	var y = yOutput.format(_y);

	if (z) {
		f = fOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));
		writeBlock(G.format(0), z, f);
	}

	if (x || y) {
		f = fOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedXY")));
		writeBlock(G.format(0), x, y, f);
	}
}

// Feed movements
function onLinear(_x, _y, _z, _feed) {
	if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
		// ensure that we end at desired position when compensation is turned off
		xOutput.reset();
		yOutput.reset();
	}
	var x = xOutput.format(_x);
	var y = yOutput.format(_y);
	var z = zOutput.format(_z);
	var f = fOutput.format(_feed);
	if (x || y || z) {
		if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
			error(localize("Radius compensation mode is not supported."));
			return;
		} else {
			writeBlock(G.format(1), x, y, z, f);
		}
	} else if (f) {
		if (getNextRecord().isMotion()) { // try not to output feed without motion
			fOutput.reset(); // force feed on next line
		} else {
			writeBlock(G.format(1), f);
		}
	}
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
	error(localize("Multi-axis motion is not supported."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
	error(localize("Multi-axis motion is not supported."));
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
	if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
		error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
		return;
	}

	if (!getProperty("jobUseArcs") /*|| isHelical()*/) {
		linearize(tolerance);

		return;
	}

	var start = getCurrentPosition();

	if ((cx - start.x) == 0 && (cy - start.y) == 0) {
		linearize(tolerance);
	} else {
		switch (getCircularPlane()) {
			case PLANE_XY: {
				writeBlock(
					G.format(17), G.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0),
					fOutput.format(feed)
				);

				break;
			}

			case PLANE_ZX: {
				writeBlock(
					G.format(18), G.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0),
					fOutput.format(feed)
				);

				break;
			}

			case PLANE_YZ: {
				writeBlock(
					G.format(19), G.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0),
					fOutput.format(feed)
				);

				break;
			}

			default: {
				linearize(tolerance);
			}
		}
	}
}

// Called on waterjet/plasma/laser cuts
var powerState = false;

function onPower(power) {
	if (power != powerState) {
		if (power) {
			writeActivityComment(" >>> LASER Power ON");

		} else {
			writeActivityComment(" >>> LASER Power OFF");

		}
		powerState = power;
	}
}

// Called on Dwell Manual NC invocation
function onDwell(seconds) {
	if (seconds > 99999.999) {
		warning(localize("Dwelling time is out of range."));
	}
	writeActivityComment(" >>> Dwell");
	writeBlock(G.format(4), "S" + secFormat.format(seconds));
}

// Called with every parameter in the documment/section
function onParameter(name, value) {
	// Write gcode initial info
	// Product version
	if (name == "generated-by") {
		writeComment(value);
		writeComment(" Posts processor: " + FileSystem.getFilename(getConfigurationPath()));
	}
	// Date
	if (name == "generated-at") {
		writeComment(" Gcode generated: " + value + " GMT");
	}

	// Document
	if (name == "document-path") {
		writeComment(" Document: " + value);
	}

	// Setup
	if (name == "job-description") {
		writeComment(" Setup: " + value);
	}

	// Get section comment
	if (name == "operation-comment") {
		sectionComment = value;
	}
}

function onMovement(movement) {
	if (getProperty("commentMovements")) {
		var jet = tool.isJetTool && tool.isJetTool();
		var id;
		switch (movement) {
			case MOVEMENT_RAPID:
				id = "MOVEMENT_RAPID";
				break;
			case MOVEMENT_LEAD_IN:
				id = "MOVEMENT_LEAD_IN";
				break;
			case MOVEMENT_CUTTING:
				id = "MOVEMENT_CUTTING";
				break;
			case MOVEMENT_LEAD_OUT:
				id = "MOVEMENT_LEAD_OUT";
				break;
			case MOVEMENT_LINK_TRANSITION:
				id = jet ? "MOVEMENT_BRIDGING" : "MOVEMENT_LINK_TRANSITION";
				break;
			case MOVEMENT_LINK_DIRECT:
				id = "MOVEMENT_LINK_DIRECT";
				break;
			case MOVEMENT_RAMP_HELIX:
				id = jet ? "MOVEMENT_PIERCE_CIRCULAR" : "MOVEMENT_RAMP_HELIX";
				break;
			case MOVEMENT_RAMP_PROFILE:
				id = jet ? "MOVEMENT_PIERCE_PROFILE" : "MOVEMENT_RAMP_PROFILE";
				break;
			case MOVEMENT_RAMP_ZIG_ZAG:
				id = jet ? "MOVEMENT_PIERCE_LINEAR" : "MOVEMENT_RAMP_ZIG_ZAG";
				break;
			case MOVEMENT_RAMP:
				id = "MOVEMENT_RAMP";
				break;
			case MOVEMENT_PLUNGE:
				id = jet ? "MOVEMENT_PIERCE" : "MOVEMENT_PLUNGE";
				break;
			case MOVEMENT_PREDRILL:
				id = "MOVEMENT_PREDRILL";
				break;
			case MOVEMENT_EXTENDED:
				id = "MOVEMENT_EXTENDED";
				break;
			case MOVEMENT_REDUCED:
				id = "MOVEMENT_REDUCED";
				break;
			case MOVEMENT_HIGH_FEED:
				id = "MOVEMENT_HIGH_FEED";
				break;
			case MOVEMENT_FINISH_CUTTING:
				id = "MOVEMENT_FINISH_CUTTING";
				break;
		}
		if (id == undefined) {
			id = String(movement);
		}
		writeComment(" " + id);
	}
}

var currentSpindleSpeed = 0;
var currentSpindleClockwise = 0;

function setSpindleSpeed(_spindleSpeed, _clockwise) {
	if (currentSpindleSpeed != _spindleSpeed || currentSpindleClockwise != _clockwise) {
		if (_spindleSpeed > 0) {
			if (currentSpindleClockwise != _clockwise && currentSpindleSpeed > 0) {
				writeComment('Stop the spindle before changing direction.');
				writeBlock(M.format(5));
			}

			const code = _clockwise ? 3 : 4;

			writeBlock(M.format(code), S.format(_spindleSpeed));
		} else {
			writeBlock(M.format(5));
		}

		currentSpindleSpeed = _spindleSpeed;
		currentSpindleClockwise = _clockwise;
	}
}

function onSpindleSpeed(spindleSpeed) {
	setSpindleSpeed(spindleSpeed, tool.clockwise);
}

function onCommand(command) {
	if (getProperty("commentActivities")) {
		var stringId = getCommandStringId(command);
		writeComment(" " + stringId);
	}
	switch (command) {
		case COMMAND_START_SPINDLE:
			onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
			return;
		case COMMAND_SPINDLE_CLOCKWISE:
			if (tool.jetTool)
				return;
			setSpindleSpeed(spindleSpeed, true);
			return;
		case COMMAND_SPINDLE_COUNTERCLOCKWISE:
			if (tool.jetTool)
				return;
			setSpindleSpeed(spindleSpeed, false);
			return;
		case COMMAND_STOP_SPINDLE:
			if (tool.jetTool)
				return;
			setSpindleSpeed(0, true);
			return;
		case COMMAND_COOLANT_ON:
			setCoolant(tool.coolant);
			return;
		case COMMAND_COOLANT_OFF:
			setCoolant(0);  //COOLANT_DISABLED
			return;
		case COMMAND_LOCK_MULTI_AXIS:
			return;
		case COMMAND_UNLOCK_MULTI_AXIS:
			return;
		case COMMAND_BREAK_CONTROL:
			return;
		case COMMAND_TOOL_MEASURE: {
			if (tool.jetTool) {
				return;
			}

			writeBlock(G.format(49));
			writeBlock(G.format(53), G.format(0), Z.format(0));
			writeBlock(G.format(59.9), G.format(0), X.format(0), Y.format(0));
			writeBlock(G.format(37));
			writeBlock(G.format(59.9), G.format(10), L.format(10), P.format(tool.number));
			writeBlock(G.format(43), H.format(tool.number));

			return;
		}
		case COMMAND_STOP:
			writeBlock(M.format(0));
			return;
	}
}

function writeFirstSection() {
	writeComment("Post Processor Version: " + version);
	// dump tool information
	var toolZRanges = {};
	var vectorX = new Vector(1, 0, 0);
	var vectorY = new Vector(0, 1, 0);
	var ranges = {
		x: { min: undefined, max: undefined },
		y: { min: undefined, max: undefined },
		z: { min: undefined, max: undefined },
	};
	var handleMinMax = function (pair, range) {
		var rmin = range.getMinimum();
		var rmax = range.getMaximum();
		if (pair.min == undefined || pair.min > rmin) {
			pair.min = rmin;
		}
		if (pair.max == undefined || pair.max < rmax) {
			pair.max = rmax;
		}
	};

	var numberOfSections = getNumberOfSections();
	for (var i = 0; i < numberOfSections; ++i) {
		var section = getSection(i);
		var tool = section.getTool();
		var zRange = section.getGlobalZRange();
		var xRange = section.getGlobalRange(vectorX);
		var yRange = section.getGlobalRange(vectorY);
		handleMinMax(ranges.x, xRange);
		handleMinMax(ranges.y, yRange);
		handleMinMax(ranges.z, zRange);
		if (is3D() && getProperty("commentWriteTools")) {
			if (toolZRanges[tool.number]) {
				toolZRanges[tool.number].expandToRange(zRange);
			} else {
				toolZRanges[tool.number] = zRange;
			}
		}
	}

	writeComment(" ");
	writeComment(" Ranges table:");
	writeComment(" X: Min=" + XYZ.format(ranges.x.min) + " Max=" + XYZ.format(ranges.x.max) + " Size=" + XYZ.format(ranges.x.max - ranges.x.min));
	writeComment(" Y: Min=" + XYZ.format(ranges.y.min) + " Max=" + XYZ.format(ranges.y.max) + " Size=" + XYZ.format(ranges.y.max - ranges.y.min));
	writeComment(" Z: Min=" + XYZ.format(ranges.z.min) + " Max=" + XYZ.format(ranges.z.max) + " Size=" + XYZ.format(ranges.z.max - ranges.z.min));

	var toolRenderer = createToolRenderer();

	if (toolRenderer) {
		toolRenderer.setBackgroundColor(new Color(1, 1, 1));
		toolRenderer.setFluteColor(new Color(40.0 / 255, 40.0 / 255, 40.0 / 255));
		toolRenderer.setShoulderColor(new Color(80.0 / 255, 80.0 / 255, 80.0 / 255));
		toolRenderer.setShaftColor(new Color(80.0 / 255, 80.0 / 255, 80.0 / 255));
		toolRenderer.setHolderColor(new Color(40.0 / 255, 40.0 / 255, 40.0 / 255));
		toolRenderer.setBackgroundColor(new Color(240 / 255.0, 240 / 255.0, 240 / 255.0));
	}

	if (getProperty("commentWriteTools")) {
		writeComment(" ");
		writeComment(" Tools table:");
		var tools = getToolTable();
		if (tools.getNumberOfTools() > 0) {
			for (var i = 0; i < tools.getNumberOfTools(); ++i) {
				var tool = tools.getTool(i);
				var comment = " T" + toolFormat.format(tool.number) + " D=" + XYZ.format(tool.diameter) + " CR=" + XYZ.format(tool.cornerRadius);
				if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
					comment += " TAPER=" + taperFormat.format(tool.taperAngle) + "deg";
				}
				if (toolZRanges[tool.number]) {
					comment += " - ZMIN=" + XYZ.format(toolZRanges[tool.number].getMinimum());
				}
				comment += " - " + getToolTypeName(tool.type) + " " + tool.comment;
				writeComment(comment);

				if (toolRenderer) {
					var path = "tool" + tool.number + ".png";
					toolRenderer.exportAs(path, "image/png", tool, 400, 532);
				}
			}
		}
	}

	writeln("");
	writeActivityComment(" *** START begin ***");

	if (getProperty("gcodeStartFile") == "") {
		writeBlock(G.format(90)); // Set to Absolute Positioning
		writeBlock(G.format(unit == IN ? 20 : 21));
		writeBlock(M.format(84), S.format(0)); // Disable steppers timeout
		if (getProperty("jobSetOriginOnStart")) {
			writeBlock(G.format(92), X.format(0), Y.format(0), Z.format(0)); // Set origin to initial position
		}
		/*if (getProperty("probeOnStart") && tool.number != 0 && !tool.jetTool) {
			onCommand(COMMAND_TOOL_MEASURE);
		}*/
	} else {
		loadFile(getProperty("gcodeStartFile"));
	}
	writeActivityComment(" *** START end ***");
	writeln("");
}

// Output a comment
function writeComment(text) {
	writeBlock('; ' + text.replace(/(\(|\))/g, ''));
}

// Test if file exist/can read and load it
function loadFile(_file) {
	var folder = FileSystem.getFolderPath(getOutputPath()) + PATH_SEPARATOR;
	if (FileSystem.isFile(folder + _file)) {
		var txt = loadText(folder + _file, "utf-8");
		if (txt.length > 0) {
			writeActivityComment(" --- Start custom gcode " + folder + _file);
			write(txt);
			writeActivityComment(" --- End custom gcode " + folder + _file);
			writeln("");
		}
	} else {
		writeComment(" Can't open file " + folder + _file);
		error("Can't open file " + folder + _file);
	}
}

var currentCoolantMode = 0;

// Manage coolant state
function setCoolant(coolant) {
	if (currentCoolantMode == coolant) {
		return;
	}

	switch (coolant) {
		case 0: { // COOLANT_DISABLED
			writeActivityComment(" >>> Coolant Disabled");
			writeBlock(M.format(9));

			break;
		}

		case 1:   // COOLANT_MIST
		case 2:
		case 7: {
			writeActivityComment(" >> Coolant on: Mist/Flood");
			writeBlock(M.format(7));
			break;
		}

		case 4: { // COOLANT_AIR
			writeActivityComment(" >> Coolant on: Air");
			writeBlock(M.format(9));
			writeBlock(M.format(12));

			break;
		}

		default: {
			writeActivityComment(" >> Coolant not supported: " + coolant);
		}
	}

	currentCoolantMode = coolant;
}

function propertyMmToUnit(_v) {
	return (_v / (unit == IN ? 25.4 : 1));
}

function writeActivityComment(_comment) {
	if (getProperty("commentActivities")) {
		writeComment(_comment);
	}
}

function flushMotions() {
	writeBlock(M.format(400));
}

function displayText(txt) {
	writeBlock(M.format(117), (getProperty("jobSeparateWordsWithSpace") ? "" : " ") + txt);
}

function toolChange() {
	flushMotions();

	// turn off spindle and coolant
	onCommand(COMMAND_COOLANT_OFF);
	onCommand(COMMAND_STOP_SPINDLE);

	writeBlock(T.format(tool.number));
	writeBlock(M.format(6));
}
