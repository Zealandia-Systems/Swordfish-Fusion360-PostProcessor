/*
homepage = "%homepage%";
version = "%version%";
*/

description = "Swordfish CNC Controller 1.0"
vendor = "Zealandia Systems";
vendorUrl = "https://github.com/zealandia-systems/swordfish_posts_processor";
legal = "Copyright (C) 2021-2022 by Zealandia Systems Ltd.";
certificationLevel = 2;
extension = "gcode";
setCodePage("ascii");
capabilities = CAPABILITY_MILLING | CAPABILITY_JET;
keywords = "MODEL_IMAGE PREVIEW_IMAGE";
minimumRevision = 45702;
programNameIsInteger = false;

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined;

properties = {
  jobTravelSpeedXY: {
    title: "Travel speed X/Y",
    description: "High speed for travel movements X & Y (mm/min; in/min)",
    group: "job",
    type: "spatial",
    value: 8000,
    scope: "post"
  },
  jobTravelSpeedZ: {
    title: "Travel Speed Z",
    description: "High speed for travel movements z (mm/min; in/min)",
    group: "job",
    type: "spatial",
    value: 8000,
    scope: "post"
  },
  jobUseArcs: {
    title: "Use Arcs",
    description: "Use G2/G3 g-codes fo circular movements",
    group: "job",
    type: "boolean",
    value: true,
    scope: "post"
  },
  jobEnforceFeedrate: {
    title: "Enforce Feedrate",
    description: "Add feedrate to each movement g-code",
    group: "job",
    type: "boolean",
    value: false,
    scope: "post"
  },
  jobSetOriginOnStart: {
    title: "Reset on start (G92)",
    description: "Set origin when gcode start (G92)",
    group: "job",
    type: "boolean",
    value: false,
    scope: "post"
  },
  jobGoOriginOnFinish: {
    title: "Goto 0 at end",
    description: "Go X0 Y0 at gcode end",
    group: "job",
    type: "boolean",
    value: true,
    scope: "post"
  },
  jobSequenceNumbers: {
    title: "Line numbers",
    description: "Show sequence numbers",
    group: "job",
    type: "boolean",
    value: false,
    scope: "post",
    visible: false
  },
  jobSequenceNumberStart: {
    title: "Line start",
    description: "First sequence number",
    group: "job",
    type: "integer",
    value: 1,
    scope: "post",
    visible: false
  },
  jobSequenceNumberIncrement: {
    title: "Line increment",
    description: "Increment for sequence numbers",
    group: "job",
    type: "integer",
    value: 1,
    scope: "post",
    visible: false
  },
  jobSeparateWordsWithSpace: {
    title: "Separate words",
    description: "Specifies that the words should be separated with a white space",
    group: "job",
    type: "boolean",
    value: true,
    scope: "post"
  },
  toolChangeEnabled: {
    title: "Enabled",
    description: "Enable tool change code",
    group: "toolChange",
    type: "boolean",
    value: false,
    scope: "post"
  },
  toolChangeHasATC: {
    title: "Machine has ATC",
    description: "let the machine perform the tool change",
    group: "toolChange",
    type: "boolean",
    value: false,
    scope: "post"
  },
  commentWriteTools: {
    title: "Write Tools",
    description: "Write table of used tools in job header",
    group: "comments",
    type: "boolean",
    value: true,
    scope: "post"
  },
  commentActivities: {
    title: "Activities",
    description: "Write comments which somehow helps to understand current piece of g-code",
    group: "comments",
    type: "boolean",
    value: true,
    scope: "post"
  },
  commentSections: {
    title: "Sections",
    description: "Write header of every section",
    group: "comments",
    type: "boolean",
    value: true,
    scope: "post"
  },
  commentCommands: {
    title: "Trace Commands",
    description: "Write stringified commands called by CAM",
    group: "comments",
    type: "boolean",
    value: true,
    scope: "post"
  },
  commentMovements: {
    title: " Trace Movements",
    description: "Write stringified movements called by CAM",
    group: "comments",
    type: "boolean",
    value: true,
    scope: "post"
  }
};

const groupDefinitions = {
  job: {
    title: "Job",
    description: "Job options",
    order: 0
  },
  toolChange: {
    title: "Tool Change",
    description: "Tool change options",
    order: 1
  },
  comments: {
    title: "Comments",
    description: "Comments options",
    order: 2
  }
};

const WARNING_WORK_OFFSET = 0;

let sequenceNumber;

// Formats
let G = createFormat({ prefix: "G", decimals: 2 });
let M = createFormat({ prefix: "M", decimals: 0 });

let XYZ = createFormat({ decimals: (unit == MM ? 3 : 4) });
let X = createFormat({ prefix: "X", decimals: (unit == MM ? 3 : 4) });
let Y = createFormat({ prefix: "Y", decimals: (unit == MM ? 3 : 4) });
let Z = createFormat({ prefix: "Z", decimals: (unit == MM ? 3 : 4) });
let I = createFormat({ prefix: "I", decimals: (unit == MM ? 3 : 4) });
let J = createFormat({ prefix: "J", decimals: (unit == MM ? 3 : 4) });
let K = createFormat({ prefix: "K", decimals: (unit == MM ? 3 : 4) });

let speedFormat = createFormat({ decimals: 0 });
let S = createFormat({ prefix: "S", decimals: 0 });

let P = createFormat({ prefix: "P", decimals: 0 });
let O = createFormat({ prefix: "O", decimals: 0 });
let L = createFormat({ prefix: "L", decimals: 0 });
let H = createFormat({ prefix: "H", decimals: 0 });

let feedFormat = createFormat({ decimals: (unit == MM ? 0 : 2) });
let F = createFormat({ prefix: "F", decimals: (unit == MM ? 0 : 2) });

let toolFormat = createFormat({ decimals: 0 });
let T = createFormat({ prefix: "T", decimals: 0 });

let taperFormat = createFormat({ decimals: 1, scale: DEG });
let secFormat = createFormat({ decimals: 3, forceDecimal: true }); // seconds - range 0.001-1000

// Linear outputs
let xOutput = createVariable({}, X);
let yOutput = createVariable({}, Y);
let zOutput = createVariable({}, Z);
let fOutput = createVariable({}, F);
let sOutput = createVariable({ force: true }, S);

// Circular outputs
let iOutput = createReferenceVariable({}, I);
let jOutput = createReferenceVariable({}, J);
let kOutput = createReferenceVariable({}, K);

/**
  Writes the specified block.
*/
function writeBlock() {
  if (getProperty(properties.jobSequenceNumbers)) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += getProperty(properties.jobSequenceNumberIncrement);
  } else {
    writeWords(arguments);
  }
}

// Called in every new gcode file
function onOpen() {
  sequenceNumber = getProperty(properties.jobSequenceNumberStart);
  if (!getProperty(properties.jobSeparateWordsWithSpace)) {
    setWordSeparator("");
  }

  machineConfiguration = new MachineConfiguration();
}

// Called at end of gcode file
function onClose() {
  writeActivityComment(" *** STOP begin ***");
  flushMotions();

  onCommand(COMMAND_COOLANT_OFF);
  onCommand(COMMAND_STOP_SPINDLE);

  if (getProperty(properties.jobGoOriginOnFinish)) {
    let z = zOutput.format(0);
    let f = fOutput.format(propertyMmToUnit(getProperty(properties.jobTravelSpeedZ)));

    writeBlock(G.format(53), G.format(0), z, f);

    let x = xOutput.format(0);
    let y = yOutput.format(0);

    f = fOutput.format(propertyMmToUnit(getProperty(properties.jobTravelSpeedXY)));
    writeBlock(G.format(0), x, y, f);
  }

  writeActivityComment(" *** STOP end ***");
}

let cutterOnCurrentPower;

function onSection() {
  // Write Start gcode of the documment (after the "onParameters" with the global info)
  if (isFirstSection()) {
    writeFirstSection();
  }
  writeActivityComment(" *** SECTION begin ***");

  // Tool change
  if (getProperty(properties.toolChangeEnabled) && (isFirstSection() || tool.number != getPreviousSection().getTool().number)) {
    // Builtin tool change gcode
    writeActivityComment(" --- CHANGE TOOL begin ---");
    toolChange();
    writeActivityComment(" --- CHANGE TOOL end ---");
  }

  if (getProperty(properties.commentSections)) {
    // Machining type
    if (currentSection.type == TYPE_MILLING) {
      // Specific milling code
      writeComment(sectionComment + " - Milling - Tool: " + tool.number + " - " + tool.comment + " " + getToolTypeName(tool.type));
    }

    if (currentSection.type == TYPE_JET) {
      // Cutter mode used for different cutting power in PWM laser
      switch (currentSection.jetMode) {
        case JET_MODE_THROUGH:
          cutterOnCurrentPower = getProperty(properties.cutterOnThrough);
          break;
        case JET_MODE_ETCHING:
          cutterOnCurrentPower = getProperty(properties.cutterOnEtch);
          break;
        case JET_MODE_VAPORIZE:
          cutterOnCurrentPower = getProperty(properties.cutterOnVaporize);
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

  let workOffset = currentSection.workOffset;

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
    const f = fOutput.format(propertyMmToUnit(getProperty(properties.jobTravelSpeedZ)));

    writeBlock(G.format(53), G.format(0), z, f);

    writeBlock(G.format(0), X.format(0), Y.format(0));
  }

  onCommand(COMMAND_START_SPINDLE);
  onCommand(COMMAND_COOLANT_ON);
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

let pendingRadiusCompensation = RADIUS_COMPENSATION_OFF;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

// Rapid movements
function onRapid(_x, _y, _z) {
  if (pendingRadiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }

  let z = zOutput.format(_z);
  let x = xOutput.format(_x);
  let y = yOutput.format(_y);

  if (z) {
    f = fOutput.format(propertyMmToUnit(getProperty(properties.jobTravelSpeedZ)));
    writeBlock(G.format(0), z, f);
  }

  if (x || y) {
    f = fOutput.format(propertyMmToUnit(getProperty(properties.jobTravelSpeedXY)));
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
  let x = xOutput.format(_x);
  let y = yOutput.format(_y);
  let z = zOutput.format(_z);
  let f = fOutput.format(_feed);
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

  if (!getProperty(properties.jobUseArcs) /*|| isHelical()*/) {
    linearize(tolerance);

    return;
  }

  let start = getCurrentPosition();

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
let powerState = false;

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
  if (getProperty(properties.commentMovements)) {
    let jet = tool.isJetTool && tool.isJetTool();
    let id;
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

let currentSpindleSpeed = 0;
let currentSpindleClockwise = 0;

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
  if (getProperty(properties.commentActivities)) {
    let stringId = getCommandStringId(command);
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
  let toolZRanges = {};
  let vectorX = new Vector(1, 0, 0);
  let vectorY = new Vector(0, 1, 0);
  let ranges = {
    x: { min: undefined, max: undefined },
    y: { min: undefined, max: undefined },
    z: { min: undefined, max: undefined },
  };
  let handleMinMax = function (pair, range) {
    let rmin = range.getMinimum();
    let rmax = range.getMaximum();
    if (pair.min == undefined || pair.min > rmin) {
      pair.min = rmin;
    }
    if (pair.max == undefined || pair.max < rmax) {
      pair.max = rmax;
    }
  }

  let numberOfSections = getNumberOfSections();
  for (let i = 0; i < numberOfSections; ++i) {
    let section = getSection(i);
    let tool = section.getTool();
    let zRange = section.getGlobalZRange();
    let xRange = section.getGlobalRange(vectorX);
    let yRange = section.getGlobalRange(vectorY);
    handleMinMax(ranges.x, xRange);
    handleMinMax(ranges.y, yRange);
    handleMinMax(ranges.z, zRange);
    if (is3D() && getProperty(properties.commentWriteTools)) {
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

  let toolRenderer = createToolRenderer();

  if (toolRenderer) {
    toolRenderer.setBackgroundColor(new Color(1, 1, 1));
    toolRenderer.setFluteColor(new Color(40.0 / 255, 40.0 / 255, 40.0 / 255));
    toolRenderer.setShoulderColor(new Color(80.0 / 255, 80.0 / 255, 80.0 / 255));
    toolRenderer.setShaftColor(new Color(80.0 / 255, 80.0 / 255, 80.0 / 255));
    toolRenderer.setHolderColor(new Color(40.0 / 255, 40.0 / 255, 40.0 / 255));
    toolRenderer.setBackgroundColor(new Color(240 / 255.0, 240 / 255.0, 240 / 255.0));
  }

  if (getProperty(properties.commentWriteTools)) {
    writeComment(" ");
    writeComment(" Tools table:");
    let tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (let i = 0; i < tools.getNumberOfTools(); ++i) {
        let tool = tools.getTool(i);
        let comment = " T" + toolFormat.format(tool.number) + " D=" + XYZ.format(tool.diameter) + " CR=" + XYZ.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " TAPER=" + taperFormat.format(tool.taperAngle) + "deg";
        }
        if (toolZRanges[tool.number]) {
          comment += " - ZMIN=" + XYZ.format(toolZRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type) + " " + tool.comment;
        writeComment(comment);

        if (toolRenderer) {
          let path = "tool" + tool.number + ".png";
          toolRenderer.exportAs(path, "image/png", tool, 400, 532);
        }
      }
    }
  }

  writeln("");
  writeActivityComment(" *** START begin ***");

  writeBlock(G.format(90)); // Set to Absolute Positioning
  writeBlock(G.format(unit == IN ? 20 : 21));
  writeBlock(M.format(84), S.format(0)); // Disable steppers timeout
  if (getProperty(properties.jobSetOriginOnStart)) {
    writeBlock(G.format(92), X.format(0), Y.format(0), Z.format(0)); // Set origin to initial position
  }
  /*if (getProperty(properties.probeOnStart) && tool.number != 0 && !tool.jetTool) {
    onCommand(COMMAND_TOOL_MEASURE);
  }*/

  writeActivityComment(" *** START end ***");
  writeln("");
}

// Output a comment
function writeComment(text) {
  writeBlock('; ' + text.replace(/(\(|\))/g, ''));
}

let currentCoolantMode = 0;

// Manage coolant state 
function setCoolant(coolant) {
  if (currentCoolantMode == coolant) {
    return;
  }
  if (getProperty(properties.coolantA_Mode) != 0) {
    if (currentCoolantMode == getProperty(properties.coolantA_Mode)) {
      writeActivityComment(" >>> Coolant A OFF");
      writeBlock(M.format(7));
    } else if (coolant == getProperty(properties.coolantA_Mode)) {
      writeActivityComment(" >>> Coolant A ON");
      writeBlock(M.format(9));
    }
  }
  if (getProperty(properties.coolantB_Mode) != 0) {
    if (currentCoolantMode == getProperty(properties.coolantB_Mode)) {
      writeActivityComment(" >>> Coolant B OFF");
      writeBlock(M.format(8));
    } else if (coolant == getProperty(properties.coolantB_Mode)) {
      writeActivityComment(" >>> Coolant B ON");
      writeBlock(M.format(9));
    }
  }
  currentCoolantMode = coolant;
}

function propertyMmToUnit(_v) {
  return (_v / (unit == IN ? 25.4 : 1));
}

function writeActivityComment(_comment) {
  if (getProperty(properties.commentActivities)) {
    writeComment(_comment);
  }
}

function flushMotions() {
  writeBlock(M.format(400));
}

function toolChange() {
  flushMotions();

  // turn off spindle and coolant
  onCommand(COMMAND_COOLANT_OFF);
  onCommand(COMMAND_STOP_SPINDLE);

  /*if(!getProperty(properties.toolChangeHasATC)) {
    writeComment('Move to specified tool change location.');
    writeBlock(G.format(53), G.format(0), Z.format(getProperty(properties.toolChangeZ)));
    writeBlock(G.format(53), G.format(0), X.format(getProperty(properties.toolChangeX)), Y.format(getProperty(properties.toolChangeY)));
    flushMotions();
  }*/

  writeBlock(T.format(tool.number));
  writeBlock(M.format(6));

  // Run Z probe gcode
  /*if (!getProperty(properties.toolChangeHasATC) && getProperty(properties.toolChangeZProbe) && tool.number != 0) {
    onCommand(COMMAND_TOOL_MEASURE);
  }*/
}
