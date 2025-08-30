// ========================================
// HELICOPTER TRANSPORT MISSION
// Single-player helicopter pilot mission
// ========================================

params ["_heli", "_landingPadPos", "_spawnPos"];

// Mission constants
#define BOARDING_DISTANCE 100
#define LANDING_DISTANCE 50
#define LANDING_HEIGHT 2
#define DROPOFF_MIN_DISTANCE 500
#define DROPOFF_MAX_DISTANCE 750

// Mission state management
MISSION_State = createHashMap;
MISSION_State set ["helicopter", _heli];
MISSION_State set ["pickupLocation", _landingPadPos];
MISSION_State set ["spawnLocation", _spawnPos];
MISSION_State set ["transportGroup", grpNull];
MISSION_State set ["cities", []];
MISSION_State set ["currentMarker", ""];

// Task definitions
MISSION_Tasks = createHashMap;
MISSION_Tasks set ["GET_IN_HELI", "task_get_in_heli"];
MISSION_Tasks set ["PICKUP_SQUAD", "task_pickup_squad"];
MISSION_Tasks set ["TRANSPORT_SQUAD", "task_transport_squad"];
MISSION_Tasks set ["RETURN_TO_BASE", "task_return_to_base"];

// Available unit classes
MISSION_AvailableUnitClasses = "((getNumber (_x >> 'scope') >= 2) &&
{
	getNumber (_x >> 'side') == 1 &&
	{
		getText (_x >> 'vehicleClass') == 'Men'
	} &&
	{
		count getArray (_x >> 'weapons') > 3
	}
}
)" configClasses (configFile >> "CfgVehicles") apply {
	configName _x
};

// ========================================
// CORE FUNCTIONS
// ========================================

MISSION_fnc_initialize = {
	// Wait for mission to fully load
	waitUntil {
		!isNull player && time > 1
	};

	private _heli = MISSION_State get "helicopter";
	if (isNull _heli) exitWith {
		["Error: No helicopter found!"] call MISSION_fnc_showMessage;
	};

	    // Cache cities for performance
	[] call MISSION_fnc_cacheCities;

	    // Start mission flow
	[] call MISSION_fnc_createInitialTask;
	[] spawn MISSION_fnc_monitorPilotSeat;
};

MISSION_fnc_cacheCities = {
	private _cities = [];
	{
		private _cityName = getText (_x >> "name");
		private _cityPos = getArray (_x >> "position");
		if (_cityName != "" && count _cityPos >= 2) then {
			_cities pushBack [_cityName, _cityPos];
		};
	} forEach ("true" configClasses (configFile >> "CfgWorlds" >> worldName >> "Names"));

	MISSION_State set ["cities", _cities];
};

// ========================================
// TASK MANAGEMENT
// ========================================

MISSION_fnc_createInitialTask = {
	private _taskId = MISSION_Tasks get "GET_IN_HELI";
	private _heli = MISSION_State get "helicopter";

	[player, _taskId, [
		"Get into the helicopter and await further orders",
		"Board Helicopter",
		""
	], _heli, "ASSIGNED", 2, true] call BIS_fnc_taskCreate;

	[_taskId, true] call BIS_fnc_taskSetCurrent;
};

MISSION_fnc_completeTask = {
	params ["_taskKey", ["_state", "SUCCEEDED"]];
	private _taskId = MISSION_Tasks get _taskKey;
	[_taskId, _state, true] call BIS_fnc_taskSetState;
};

MISSION_fnc_setCurrentTask = {
	params ["_taskKey"];
	private _taskId = MISSION_Tasks get _taskKey;
	[_taskId, true] call BIS_fnc_taskSetCurrent;
};

// ========================================
// AO MANAGEMENT
// ========================================

MISSION_fnc_scanForTargets = {
	params ["_aa"];

	while { alive _aa } do {
		sleep 0.1;
        private _gunner = gunner _aa;
        private _target = _gunner findNearestEnemy _aa;
        if (!isNull _target && (getPosVisual _target) # 2 > 25) then {
            _gunner doTarget _target;
            _gunner doFire _target;
        } else {
            _gunner doTarget objNull;
        };
	};
};

MISSION_fnc_createAA = {
	params ["_position"];

	private _aaPos = [_position, 50, 200, 10, 0, 10] call BIS_fnc_findSafePos;
	_aa = createVehicle ["O_APC_Tracked_02_AA_F", _aaPos, [], 0, "NONE"];
	_aa setDir (random 360);
	createVehicleCrew _aa;
	_aa setVehicleLock "LOCKED";
	_aa engineOn false;
	_aa setFuel 0;
	_aa allowCrewInImmobile true;

	{
        _x disableAI "AUTOTARGET";
        _x disableAI "TARGET";
	} forEach crew _aa;

	_gunner = gunner _aa;
	_gunner setSkill 0.8;

	_aa spawn MISSION_fnc_scanForTargets;

	_aa
};

MISSION_fnc_removeAO = {
	{
		deleteVehicle _x;
	} forEach (MISSION_State getOrDefault ["currentAAs", []]);

	deleteMarker "aomarker";
};

MISSION_fnc_createAO = {
	params ["_position"];

	[] call MISSION_fnc_removeAO;

	private _marker = createMarker ["aomarker", _position];
	_marker setMarkerType "hd_objective";
	_marker setMarkerColor "ColorRed";
	_marker setMarkerText "Area of Operations";
	_marker setMarkerShape "ELLIPSE";
	_marker setMarkerSize [500, 500];
	_marker setMarkerBrush "DIAGGRID";

	private _aas = [];
	for "_i" from 1 to 3 do {
		private _aa = [_position] call MISSION_fnc_createAA;
		_aas pushBack _aa;
	};

	MISSION_State set ["currentAAs", _aas];
};

// ========================================
// UTILITY FUNCTIONS
// ========================================

MISSION_fnc_showMessage = {
	params ["_message", ["_type", "hint"]];
	switch (_type) do {
		case "hint": {
			hint _message;
		};
		case "sideChat": {
			player sideChat _message;
		};
		default {
			hint _message;
		};
	};
};

MISSION_fnc_isHelicopterLanded = {
	params ["_position", ["_distance", LANDING_DISTANCE]];
	private _heli = MISSION_State get "helicopter";

	(_heli distance _position < _distance) &&
	(getPos _heli select 2 < LANDING_HEIGHT)
};

MISSION_fnc_areUnitsInVehicle = {
	params ["_units", "_vehicle"];
	_units findIf {
		vehicle _x != _vehicle
	} == -1
};

MISSION_fnc_areUnitsOutOfVehicle = {
	params ["_units", "_vehicle"];
	_units findIf {
		vehicle _x == _vehicle
	} == -1
};

// ========================================
// MISSION PHASES
// ========================================

MISSION_fnc_monitorPilotSeat = {
	private _heli = MISSION_State get "helicopter";

	waitUntil {
		sleep 1;
		!alive player || driver _heli == player
	};

	if (!alive player) exitWith {};

	["GET_IN_HELI"] call MISSION_fnc_completeTask;
	[] spawn MISSION_fnc_spawnPickupSquad;
};

MISSION_fnc_spawnPickupSquad = {
	sleep 3; // Immersion delay

	private _spawnPos = MISSION_State get "spawnLocation";
	private _group = createGroup west;

	    // Create squad members
	for "_i" from 0 to 7 step 1 do
	{
		private _classname = selectRandom MISSION_AvailableUnitClasses;
		_group createUnit [_classname, _spawnPos, [], 0, "NONE"];
	};

	    // Configure group
	_group setBehaviour "SAFE";
	_group setSpeedMode "LIMITED";

	MISSION_State set ["transportGroup", _group];

	    // Create pickup task
	private _pickupPos = MISSION_State get "pickupLocation";
	[player, MISSION_Tasks get "PICKUP_SQUAD", [
		format ["Pick up the squad at grid %1. They are waiting for transport.", mapGridPosition _pickupPos],
		"Pick up Squad",
		""
	], _pickupPos, "ASSIGNED", 2, true] call BIS_fnc_taskCreate;

	["PICKUP_SQUAD"] call MISSION_fnc_setCurrentTask;

	["Command: Squad Alpha is ready for pickup. Proceed to marked location.", "sideChat"] call MISSION_fnc_showMessage;

	[] spawn MISSION_fnc_monitorSquadBoarding;
};

MISSION_fnc_monitorSquadBoarding = {
	private _pickupPos = MISSION_State get "pickupLocation";
	private _heli = MISSION_State get "helicopter";
	private _group = MISSION_State get "transportGroup";

	    // Wait for helicopter to arrive
	waitUntil {
		sleep 1;
		_heli distance _pickupPos < BOARDING_DISTANCE
	};

	    // Order squad to board
	private _units = units _group;
	{
		_x assignAsCargo _heli;
	} forEach _units;
	_units orderGetIn true;

	    // Wait for all to board
	waitUntil {
		sleep 2;
		[_units, _heli] call MISSION_fnc_areUnitsInVehicle
	};

	["PICKUP_SQUAD"] call MISSION_fnc_completeTask;

	[] spawn MISSION_fnc_assignTransportTask;
};

MISSION_fnc_assignTransportTask = {
	sleep 5; // Brief delay

	private _cities = MISSION_State get "cities";
	if (count _cities == 0) exitWith {
		["No cities found for transport mission!"] call MISSION_fnc_showMessage;
	};

	private _randomCity = selectRandom _cities;
	_randomCity params ["_cityName", "_cityPos"];

	[_cityPos] call MISSION_fnc_createAO;

	private _dropoffPos = [_cityPos, DROPOFF_MIN_DISTANCE, DROPOFF_MAX_DISTANCE, 10, 0, 5] call BIS_fnc_findSafePos;
	MISSION_State set ["dropoffLocation", _dropoffPos];
	MISSION_State set ["cityDestination", _cityPos];

	    // Create transport task
	[player, MISSION_Tasks get "TRANSPORT_SQUAD", [
		format ["Transport the squad to the designated landing zone near %1, at grid %2", _cityName, mapGridPosition _dropoffPos],
		"Transport Squad",
		""
	], _dropoffPos, "ASSIGNED", 2, true] call BIS_fnc_taskCreate;

	["TRANSPORT_SQUAD"] call MISSION_fnc_setCurrentTask;

	[] spawn MISSION_fnc_monitorDropoff;
};

MISSION_fnc_monitorDropoff = {
	private _dropoffPos = MISSION_State get "dropoffLocation";
	private _heli = MISSION_State get "helicopter";
	private _group = MISSION_State get "transportGroup";

	    // Wait for landing
	waitUntil {
		sleep 1;
		[_dropoffPos, 10] call MISSION_fnc_isHelicopterLanded
	};

	["Thanks for the ride. We'll take it from here!", "sideChat"] call MISSION_fnc_showMessage;

	    // Order squad to disembark
	private _units = units _group;
	{
		unassignVehicle _x;
		_x action ["GetOut", _heli];
	} forEach _units;

	    // Wait for disembark
	waitUntil {
		sleep 1;
		[_units, _heli] call MISSION_fnc_areUnitsOutOfVehicle
	};

	["TRANSPORT_SQUAD"] call MISSION_fnc_completeTask;

	    // Configure group for movement
	_group setBehaviour "STEALTH";
	_group setSpeedMode "LIMITED";
	_group setFormation "WEDGE";

	private _cityPos = MISSION_State get "cityDestination";
	_group move _cityPos;

	    sleep 10; // Allow movement to begin

	[] spawn MISSION_fnc_returnToBase;
};

MISSION_fnc_returnToBase = {
	private _basePos = MISSION_State get "pickupLocation";

	[player, MISSION_Tasks get "RETURN_TO_BASE", [
		"Return to base and await further orders",
		"Return to Base",
		""
	], _basePos, "ASSIGNED", 2, true] call BIS_fnc_taskCreate;

	["RETURN_TO_BASE"] call MISSION_fnc_setCurrentTask;

	[] spawn MISSION_fnc_monitorReturnToBase;
};

MISSION_fnc_monitorReturnToBase = {
	private _basePos = MISSION_State get "pickupLocation";
	private _group = MISSION_State get "transportGroup";

	    // Wait for return to base
	waitUntil {
		sleep 1;
		[_basePos] call MISSION_fnc_isHelicopterLanded
	};

	["RETURN_TO_BASE"] call MISSION_fnc_completeTask;

	    // Cleanup and restart
	[] call MISSION_fnc_cleanupSquad;
	    [] spawn MISSION_fnc_spawnPickupSquad; // Restart cycle
};

MISSION_fnc_cleanupSquad = {
	private _group = MISSION_State get "transportGroup";
	if (!isNull _group) then {
		{
			deleteVehicle _x;
		} forEach units _group;
		deleteGroup _group;
		MISSION_State set ["transportGroup", grpNull];
	};
};

// Initialize mission
[] spawn MISSION_fnc_initialize;