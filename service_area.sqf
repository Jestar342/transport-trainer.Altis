params ["_command", "_trigger", "_objects", "_precondition"];

fnc_FilterNeedsService = {
	params ["_vehicle"];
	(damage _vehicle > 0.1 || fuel _vehicle < 0.9)
};

fnc_DoServicing = {
	params ["_needService", "_trigger"];

	private _hash = createHashMap;
	_hash set ["_needService", _needService];
	_hash set ["_trigger", _trigger];

	while { count (_hash get "_needService") > 0 } do {
		sleep 0.1;
		{
			if (alive _x && _x getVariable ["SERVICING", false]) then {
				private _currentDamage = damage _x;
				private _currentFuel = fuel _x;
				if (_currentDamage > 0.0) then {
					_x setDamage (_currentDamage - 0.01);
				};
				if (_currentFuel < 1.0) then {
					_x setFuel (_currentFuel + 0.01);
				};
				if (damage _x <= 0.0 && fuel _x >= 1.0) then {
					_x setVariable ["SERVICING", false];
				};
			};
		} forEach (_hash get "_needService");

		_oldRepairables = _hash get "_needService";
		_hash set ["_needService", _oldRepairables select {
			_x getVariable ["SERVICING", false]
		}];
	};
};

fnc_Activate = {
	params ["_trigger", "_objects"];

	_trigger setVariable ["ACTIVATED", true];

	private _needService = _objects select {
		[_x] call fnc_FilterNeedsService
	};

	{
		_x setVariable ["SERVICING", true];
	} forEach _needService;

	[_needService, _trigger] spawn fnc_DoServicing;
};

fnc_Deactivate = {
	params ["_trigger"];
	_trigger setVariable ["ACTIVATED", false];
};

fnc_Condition = {
	params ["_trigger", "_objects", "_precondition"];

	_precondition &&
	{
		(_x isKindOf "Air") &&
		([_x] call fnc_FilterNeedsService)
	} count _objects > 0;
};

switch (_command) do {
	case "ACTIVATE": {
		[_trigger, _objects] call fnc_Activate;
	};
	case "DEACTIVATE": {
		[_trigger] call fnc_Deactivate;
	};
	case "CONDITION": {
		[_trigger, _objects, _precondition] call fnc_Condition;
	};
	default {
		systemChat format ["Unknown command: %1", _command];
	};
};