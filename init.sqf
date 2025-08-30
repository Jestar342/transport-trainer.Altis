MISSION_fnc_ServiceArea = compile preprocessFileLineNumbers "service_area.sqf";
[heli, getMarkerPos "landingpad", getMarkerPos "spawn"] execVM "transport_mission.sqf";