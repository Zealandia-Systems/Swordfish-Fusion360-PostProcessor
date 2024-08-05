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
		description: "Use G2/G3 G-codes fo circular movements",
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
		description: "G0 X0 Y0 at gcode end",
		group: "configuration",
		type: "boolean",
		value: true,
		scope: "post"
	},
	fourthAxis: {
		title: "Fourth axis",
		description: "Select fourth axis orientation",
		group: "configuration",
		scope: "post",
		type: "enum",
		values: [
			{ title: "None", id: "0" },
			{ title: "Along X", id: "1" },
			{ title: "Along X (Inverted)", id: "2" },
			{ title: "Along Y", id: "3" },
			{ title: "Along Y (Inverted)", id: "4" },
		],
		value: "0"
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
		description: "Write comments which somehow helps to understand current piece of G-code",
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

// wcs definiton
wcsDefinitions = {
	useZeroOffset: true, // set to 'true' to allow for workoffset 0, 'false' treats 0 as 1
	wcs: [
		{ name: "Standard", format: "gFormat", range: [54, 59] }, // standard WCS, output as G54-G59
		{ name: "Extended", format: "G59.#", range: [1, 9] } // extended WCS, output as G59.7, etc.
	]
};


var state = {
	retractedX: false, // specifies that the machine has been retracted in X
	retractedY: false, // specifies that the machine has been retracted in Y
	retractedZ: false, // specifies that the machine has been retracted in Z
	mainState: true // specifies the current context of the state (true = main, false = optional)
};

// Formats
var gFormat = createFormat({ prefix: "G", decimals: 1, minDigitsLeft: 1 });
var mFormat = createFormat({ prefix: "M", decimals: 0, minDigitsLeft: 1 });
var hFormat = createFormat({ prefix: "H", decimals: 0, minDigitsLeft: 1 });
var sFormat = createFormat({ prefix: "S", decimals: 0, minDigitsLeft: 1 });
var diameterOffsetFormat = createFormat({ prefix: "D", decimals: 0, minDigitsLeft: 1 });

var xyzFormat = createFormat({ decimals: (unit == MM ? 3 : 4) });
var abcFormat = createFormat({ decimals: 3, type: FORMAT_REAL, scale: DEG });
var fpmFormat = createFormat({ decimals: (unit == MM ? 1 : 2) });
var fprFormat = createFormat({ type: FORMAT_REAL, decimals: (unit == MM ? 3 : 4), minimum: (unit == MM ? 0.001 : 0.0001) });
var feedFormat = fpmFormat;
var inverseTimeFormat = createFormat({ decimals: 3, type: FORMAT_REAL });
var toolFormat = createFormat({ decimals: 0 });
var rpmFormat = createFormat({ decimals: 0 });
var secFormat = createFormat({ decimals: 3, type: FORMAT_REAL }); // seconds - range 0.001-1000
var taperFormat = createFormat({ decimals: 1, scale: DEG });

var xOutput = createOutputVariable({ onchange: function () { state.retractedX = false; }, prefix: "X" }, xyzFormat);
var yOutput = createOutputVariable({ onchange: function () { state.retractedY = false; }, prefix: "Y" }, xyzFormat);
var zOutput = createOutputVariable({ onchange: function () { state.retractedZ = false; }, prefix: "Z" }, xyzFormat);
var aOutput = createOutputVariable({ prefix: "A" }, abcFormat);
var bOutput = createOutputVariable({ prefix: "B" }, abcFormat);
var cOutput = createOutputVariable({ prefix: "C" }, abcFormat);
var feedOutput = createOutputVariable({ prefix: "F", control: CONTROL_FORCE }, feedFormat);

var inverseTimeOutput = createOutputVariable({ prefix: "F", control: CONTROL_FORCE }, inverseTimeFormat);
var sOutput = createOutputVariable({ prefix: "S", control: CONTROL_FORCE }, rpmFormat);
var iOutput = createOutputVariable({ prefix: "I", control: CONTROL_NONZERO }, xyzFormat);
var jOutput = createOutputVariable({ prefix: "J", control: CONTROL_NONZERO }, xyzFormat);
var kOutput = createOutputVariable({ prefix: "K", control: CONTROL_NONZERO }, xyzFormat);

var hOutput = createOutputVariable({ prefix: "H" }, toolFormat);
var pOutput = createOutputVariable({ prefix: "P" }, toolFormat);
var lOutput = createOutputVariable({ prefix: "L" }, toolFormat);

var gMotionModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createOutputVariable({ control: CONTROL_FORCE, onchange: function () { forceModals(gMotionModal); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 5 // G93-95
var gUnitModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 6 // G20-21
var gCycleModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 9 // G81, ...
var gRetractModal = createOutputVariable({ control: CONTROL_FORCE }, gFormat); // modal group 10 // G98-99
var fourthAxisClamp = createOutputVariable({ control: CONTROL_FORCE }, mFormat);
var fithAxisClamp = createOutputVariable({ control: CONTROL_FORCE }, mFormat);

function forceFeed() {
	currentFeedId = undefined;
	feedOutput.reset();
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
	xOutput.reset();
	yOutput.reset();
	zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
	aOutput.reset();
	bOutput.reset();
	cOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
	forceXYZ();
	forceABC();
	forceFeed();
}

function getFeed(f) {
	return feedOutput.format(f);
}

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

var receivedMachineConfiguration = false;

function defineMachine() {
	var fourthAxis = getProperty("fourthAxis");

	if (fourthAxis != "0") {
		var axis = [1, 0, 0];

		switch (fourthAxis) {
			case "1": {
				axis = [1, 0, 0];

				break;
			}

			case "2": {
				axis = [-1, 0, 0];

				break;
			}

			case "3": {
				axis = [0, 1, 0];

				break;
			}

			case "4": {
				axis = [0, -1, 0];

				break;
			}
		}

		var aAxis = createAxis({
			coordinate: 0,
			table: true,
			axis,
			offset: [0, 0, 0],
			cyclic: true,
			reset: 0,
			preference: 0,
			tcp: false
		});

		machineConfiguration = new MachineConfiguration(aAxis);
	} else {
		warning("No fourth axis");
		machineConfiguration = new MachineConfiguration();
	}

	if (machineConfiguration.isMultiAxisConfiguration()) {
		machineConfiguration.setMultiAxisFeedrate(
			FEED_INVERSE_TIME,
			20000.00,
			INVERSE_SECONDS,
			0.0,
			0.0,
		);
	}

	if (machineConfiguration.isHeadConfiguration()) {
		machineConfiguration.setVirtualTooltip(false); // translate the pivot point to the virtual tool tip for nonTCP rotary heads
	}

	setMachineConfiguration(machineConfiguration); // inform post kernel of hardcoded machine configuration

	if (receivedMachineConfiguration) {
		warning(localize("The provided CAM machine configuration is overwritten by the postprocessor."));
		receivedMachineConfiguration = false; // CAM provided machine configuration is overwritten
	}
}

function activateMachine() {
	// disable unsupported rotary axes output
	if (!machineConfiguration.isMachineCoordinate(0) && (typeof aOutput != "undefined")) {
		aOutput.disable();
	}
	if (!machineConfiguration.isMachineCoordinate(1) && (typeof bOutput != "undefined")) {
		bOutput.disable();
	}
	if (!machineConfiguration.isMachineCoordinate(2) && (typeof cOutput != "undefined")) {
		cOutput.disable();
	}

	if (!machineConfiguration.isMultiAxisConfiguration()) {
		return; // don't need to modify any settings for 3-axis machines
	}

	// save multi-axis feedrate settings from machine configuration
	var mode = machineConfiguration.getMultiAxisFeedrateMode();
	var type = mode == FEED_INVERSE_TIME ? machineConfiguration.getMultiAxisFeedrateInverseTimeUnits() :
		(mode == FEED_DPM ? machineConfiguration.getMultiAxisFeedrateDPMType() : DPM_STANDARD);
	multiAxisFeedrate = {
		mode: mode,
		maximum: machineConfiguration.getMultiAxisFeedrateMaximum(),
		type: type,
		tolerance: mode == FEED_DPM ? machineConfiguration.getMultiAxisFeedrateOutputTolerance() : 0,
		bpwRatio: mode == FEED_DPM ? machineConfiguration.getMultiAxisFeedrateBpwRatio() : 1
	};

	if (machineConfiguration.isHeadConfiguration()) {
		compensateToolLength = typeof compensateToolLength == "undefined" ? false : compensateToolLength;
	}

	if (machineConfiguration.isHeadConfiguration() && compensateToolLength) {
		for (var i = 0; i < getNumberOfSections(); ++i) {
			var section = getSection(i);
			if (section.isMultiAxis()) {
				machineConfiguration.setToolLength(getBodyLength(section.getTool())); // define the tool length for head adjustments
				section.optimizeMachineAnglesByMachine(machineConfiguration, OPTIMIZE_AXIS);
			}
		}
	} else {
		optimizeMachineAngles2(OPTIMIZE_AXIS);
	}
}

// Called in every new gcode file
function onOpen() {
	receivedMachineConfiguration = machineConfiguration.isReceived();

	defineMachine();
	activateMachine();

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
			var f = feedOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));

			writeBlock(gFormat.format(53), gFormat.format(0), z, f);

			var x = xOutput.format(0);
			var y = yOutput.format(0);

			f = feedOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedXY")));
			writeBlock(gFormat.format(0), x, y, f);
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
		writeComment(" X Min: " + xyzFormat.format(currentSection.getGlobalRange(vectorX).getMinimum()) + " - X Max: " + xyzFormat.format(currentSection.getGlobalRange(vectorX).getMaximum()));
		writeComment(" Y Min: " + xyzFormat.format(currentSection.getGlobalRange(vectorY).getMinimum()) + " - Y Max: " + xyzFormat.format(currentSection.getGlobalRange(vectorY).getMaximum()));
		writeComment(" Z Min: " + xyzFormat.format(currentSection.getGlobalZRange().getMinimum()) + " - Z Max: " + xyzFormat.format(currentSection.getGlobalZRange().getMaximum()));
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

		writeBlock(gFormat.format(50 + primary) + "." + secondary); // G59.n

		const z = zOutput.format(0);
		const f = feedOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));

		writeBlock(gFormat.format(53), gFormat.format(0), z, f);
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
	feedOutput.reset();
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
		f = feedOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedZ")));
		writeBlock(gFormat.format(0), z, f);
	}

	if (x || y) {
		f = feedOutput.format(propertyMmToUnit(getProperty("jobTravelSpeedXY")));
		writeBlock(gFormat.format(0), x, y, f);
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
	var f = feedOutput.format(_feed);
	if (x || y || z) {
		if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
			error(localize("Radius compensation mode is not supported."));
			return;
		} else {
			writeBlock(gFormat.format(1), x, y, z, f);
		}
	} else if (f) {
		if (getNextRecord().isMotion()) { // try not to output feed without motion
			feedOutput.reset(); // force feed on next line
		} else {
			writeBlock(gFormat.format(1), f);
		}
	}
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
	if (!currentSection.isOptimizedForMachine()) {
		forceXYZ();
	}

	var x = xOutput.format(_x);
	var y = yOutput.format(_y);
	var z = zOutput.format(_z);
	var a = aOutput.format(_a);
	var b = bOutput.format(_b);
	var c = cOutput.format(_c);

	/*
	var a = currentSection.isOptimizedForMachine() ? aOutput.format(_a) : toolVectorOutputI.format(_a);
	var b = currentSection.isOptimizedForMachine() ? bOutput.format(_b) : toolVectorOutputJ.format(_b);
	var c = currentSection.isOptimizedForMachine() ? cOutput.format(_c) : toolVectorOutputK.format(_c);
	*/

	if (x || y || z || a || b || c) {
		writeBlock(gMotionModal.format(0), x, y, z, a, b, c);
		forceFeed();
	}
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed, feedMode) {
	if (!currentSection.isOptimizedForMachine()) {
		forceXYZ();
	}

	var x = xOutput.format(_x);
	var y = yOutput.format(_y);
	var z = zOutput.format(_z);
	var a = aOutput.format(_a);
	var b = bOutput.format(_b);
	var c = cOutput.format(_c);
	/*
	var a = currentSection.isOptimizedForMachine() ? aOutput.format(_a) : toolVectorOutputI.format(_a);
	var b = currentSection.isOptimizedForMachine() ? bOutput.format(_b) : toolVectorOutputJ.format(_b);
	var c = currentSection.isOptimizedForMachine() ? cOutput.format(_c) : toolVectorOutputK.format(_c);
	*/

	if (feedMode == FEED_INVERSE_TIME) {
		forceFeed();
	}
	var f = feedMode == FEED_INVERSE_TIME ? inverseTimeOutput.format(feed) : getFeed(feed);
	var fMode = feedMode == FEED_INVERSE_TIME ? 93 : 94;

	if (x || y || z || a || b || c) {
		writeBlock(gFeedModeModal.format(fMode), gMotionModal.format(1), x, y, z, a, b, c, f);
	} else if (f) {
		if (getNextRecord().isMotion()) { // try not to output feed without motion
			forceFeed(); // force feed on next line
		} else {
			writeBlock(gFeedModeModal.format(fMode), gMotionModal.format(1), f);
		}
	}
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
					gFormat.format(17), gFormat.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					iOutput.format(cx - start.x), jOutput.format(cy - start.y),
					feedOutput.format(feed)
				);

				break;
			}

			case PLANE_ZX: {
				writeBlock(
					gFormat.format(18), gFormat.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					iOutput.format(cx - start.x), kOutput.format(cz - start.z),
					feedOutput.format(feed)
				);

				break;
			}

			case PLANE_YZ: {
				writeBlock(
					gFormat.format(19), gFormat.format(clockwise ? 2 : 3),
					xOutput.format(x), yOutput.format(y), zOutput.format(z),
					jOutput.format(cy - start.y), kOutput.format(cz - start.z),
					feedOutput.format(feed)
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
	writeBlock(gFormat.format(4), "S" + secFormat.format(seconds));
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
				writeBlock(mFormat.format(5));
			}

			const code = _clockwise ? 3 : 4;

			writeBlock(mFormat.format(code), sOutput.format(_spindleSpeed));
		} else {
			writeBlock(mFormat.format(5));
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

			writeBlock(gFormat.format(49));
			writeBlock(gFormat.format(53), gFormat.format(0), zOutput.format(0));
			writeBlock(gFormat.format(59.9), gFormat.format(0), xOutput.format(0), yOutput.format(0));
			writeBlock(gFormat.format(37));
			writeBlock(gFormat.format(59.9), gFormat.format(10), lOutput.format(10), pOutput.format(tool.number));
			writeBlock(gFormat.format(43), hOutput.format(tool.number));

			return;
		}
		case COMMAND_STOP:
			writeBlock(mFormat.format(0));
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
	writeComment(" X: Min=" + xyzFormat.format(ranges.x.min) + " Max=" + xyzFormat.format(ranges.x.max) + " Size=" + xyzFormat.format(ranges.x.max - ranges.x.min));
	writeComment(" Y: Min=" + xyzFormat.format(ranges.y.min) + " Max=" + xyzFormat.format(ranges.y.max) + " Size=" + xyzFormat.format(ranges.y.max - ranges.y.min));
	writeComment(" Z: Min=" + xyzFormat.format(ranges.z.min) + " Max=" + xyzFormat.format(ranges.z.max) + " Size=" + xyzFormat.format(ranges.z.max - ranges.z.min));

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
				var comment = " T" + toolFormat.format(tool.number) + " D=" + xyzFormat.format(tool.diameter) + " CR=" + xyzFormat.format(tool.cornerRadius);
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
		writeBlock(gFormat.format(90)); // Set to Absolute Positioning
		writeBlock(gFormat.format(unit == IN ? 20 : 21));
		writeBlock(mFormat.format(84), sFormat.format(0)); // Disable steppers timeout
		if (getProperty("jobSetOriginOnStart")) {
			writeBlock(gFormat.format(92), xOutput.format(0), yOutput.format(0), zOutput.format(0)); // Set origin to initial position
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
			writeBlock(mFormat.format(9));

			break;
		}

		case 1:   // COOLANT_MIST
		case 2:
		case 7: {
			writeActivityComment(" >> Coolant on: Mist/Flood");
			writeBlock(mFormat.format(7));
			break;
		}

		case 4: { // COOLANT_AIR
			writeActivityComment(" >> Coolant on: Air");
			writeBlock(mFormat.format(9));
			writeBlock(mFormat.format(12));

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
	writeBlock(mFormat.format(400));
}

function displayText(txt) {
	writeBlock(mFormat.format(117), (getProperty("jobSeparateWordsWithSpace") ? "" : " ") + txt);
}

function toolChange() {
	flushMotions();

	// turn off spindle and coolant
	onCommand(COMMAND_COOLANT_OFF);
	onCommand(COMMAND_STOP_SPINDLE);

	writeBlock(tFormat.format(tool.number));
	writeBlock(mFormat.format(6));
}
