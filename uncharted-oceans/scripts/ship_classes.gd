class_name ShipClasses
extends RefCounted
## Size classes for docking. Every ship is Small, Medium or Large (ship_motion.gd: ship_class).
## The class decides the size of the light rectangle at a berth, and how gently the ship has to arrive.
## All numbers are first guesses: change them here and every berth follows.

enum Size { SMALL, MEDIUM, LARGE }

const NAMES := ["small", "medium", "large"]

## length / beam in metres (hull, bow to stern and side to side); max_speed in m/s through the water
## (the brig's hull speed is about 5.3 m/s); max_heading in degrees off the berth's heading.
const DATA := [
	{   # small: the cutter (hull only, bowsprit and boom not counted)
		"length": 11.0, "beam": 3.1, "max_speed": 1.5, "max_heading": 28.0,
		# Lies on the outer edge of the berth's light (metres further from the pier than the usual fender gap),
		# so the gangway to the 1.85 m quay is long and gentle for a low deck.
		"slot_offset": 1.55,
		# ship_motion.gd: how the hull follows the sea. An 11 m, ~11 tonne boat drops into a trough and heels to the wave slope almost
		# as fast as the water moves; the brig's heavy-ship springs (heave 0.7 s, pitch 0.9 s, roll 1.3 s) left her hanging above falling
		# waves (keel clear of the water 19% of the time in a storm sea, deck under at a sample point 9%). Measured with tests/cutter_wave_probe.gd.
		"motion": {"heave_lag": 0.25, "rise_lag": 0.12, "max_sink": 0.3, "pitch_lag": 0.35, "roll_lag": 0.45},
		# ship_anchor.gd: a small capstan on the starboard waist (no coil of cable)
		"anchor": {"capstan_pos": Vector3(1.05, 0.85, -1.6), "capstan_radius": 0.26, "coil_pos": Vector3(0.0, -9.0, 0.0), "bar_reach": 0.5, "bar_below_top": 0.1},
		# ship_log_line.gd: the sand glass stands on the transom rim, from the LogLine marker (the marker's own frame); its base sits on the rail top
		"log_line": {"glass_offset": Vector3(-0.45, 0.185, -0.065), "glass_scale": 1.2},
		# ship_flooding.gd: the hold grid is the open well and the cabin; the water physics are an 11 tonne boat's
		"flooding": {"grid_bottom": -1.3, "grid_top": 0.8, "grid_half_width": 1.7, "grid_z_min": -6.0, "grid_z_max": 6.2,
			"waterplane_area": 18.0, "displacement": 11.0, "pump_rate": 0.15, "cargo_swamp_sink": 0.75, "max_sink": 1.0,
			"gm_transverse": 0.6, "gm_longitudinal": 10.0},
		# The wind-vane (ship_windsock.gd) stands on the "Windsock" marker: a lower staff and a smaller pennant, clear of the boom.
		"windsock": {"pole_height": 0.65, "flag_length": 0.8, "hoist_height": 0.18, "tail_height": 0.05},
		# Steering: a tiller (ship_wheel.gd tiller mode). The node is a child of the rudder; the tiller swings +-max_turn_deg, 1:1 with the rudder.
		"helm": {"type": "tiller", "node": "Tiller", "max_turn_deg": 32.0, "degrees_per_pixel": 0.1, "rudder_max_deg": 32.0},
		# Rig numbers for ship_sails.gd (ship frame, bow is -z, z = Blender y, x = -Blender x). The sloop rig: one raked mast with a sprit-boom sail
		# (the "spanker") and a jib. The boom hinges on the gooseneck, 0.15 m abaft the mast; its pin rail is the one round the mast.
		"rig": {
			"spanker_pivot_z": -1.55,
			# Sail area for the physics x2 (2026-11-19): the modelled sails are only 20.6 m2, so she made about 4.5 kn in a 8.5 m/s wind;
			# x2 gives about 6 kn on a reach and 5 kn running in that wind (tests/cutter_speed_probe.gd). Hull speed 8.1 kn caps her in a gale.
			"area_scale": 2.0,
			"rail_z": [-1.4, -1.4], "rail_pin_y": 1.42, "deck_y": [0.85, 0.85],
			"pin_x": {"Jib": 0.3, "Spanker": -0.3},
			"braces": false,
			# The halyards are belayed on the pin rail round the mast (jib on the fore row z -2.0, the spanker on the after row z -1.4).
			"pin_z": {"Jib": -2.0, "Spanker": -1.4},
			# Each haul rope: from the sail's head through these points (ship frame), then down to its pin. "head" is the sail's head,
			# a Vector3 is a fixed block. Both halyard blocks are the ones at the masthead in the model.
			"haul": {
				"Jib": ["head", Vector3(0.12, 6.42, -1.48)],
				"Spanker": ["head", Vector3(-0.17, 6.45, -1.31)],
			},
			# Passive lines that follow the spars and sails instead of being part of the model (so they are never left hanging when the
			# boom or a headsail swings): the mainsheet, a single rope from the block on the horse (the iron arch across the stern) to the
			# clew (back corner) of the sail, and the jib sheets, which go slack on the windward side. See ShipSails.route_point.
			"rope_lines": [
				{"pts": [["spar", Vector3(0.0, 2.15, 3.2)], ["slide", Vector3(0.0, 1.95, 5.2), Vector3(0.0, 2.15, 3.2), 0.9, 13.5, 0.25]]},
				{"sail": "Jib", "side": -1, "pts": [["clew", "Jib"], Vector3(-0.7, 0.95, -1.5)]},
				{"sail": "Jib", "side": 1, "pts": [["clew", "Jib"], Vector3(0.7, 0.95, -1.5)]},
			],
			# Fittings that ride the horse (a node of the model, moved every frame): the mainsheet block follows the clew of the sail across the bar.
			"sliders": [{"node": "Sheet_Block", "rest": Vector3(0.0, 1.95, 5.2), "track": Vector3(0.0, 2.15, 3.2), "half": 0.9, "arc": 13.5, "drop": 0.25}],
		},
		# Gangway, ship-local (x across to port, y up): flat on the quay, down to the rail, over the rail, down onto the deck.
		# It comes aboard just forward of the forward main shroud (z -2.5), beside the swivel gun (z -3.4) (z = Blender y).
		"gangway": [Vector2(-4.15, 1.92), Vector2(-3.3, 1.92), Vector2(-1.55, 1.45), Vector2(-1.3, 1.45), Vector2(-0.75, 0.92)],
		"gangway_z": -2.95, "gangway_width": 0.6, "gangway_min_y": 1.15,
		# Mooring cleats on the port rail (ship-local x, height, z) and the bollard each line goes to.
		"lines": [[Vector3(-0.8, 1.5, -4.4), 0], [Vector3(-1.28, 1.38, -3.0), 2], [Vector3(-1.43, 1.27, 2.0), 1], [Vector3(-1.15, 1.31, 5.1), 3]],
		# Keel footprint (ship-local x, z, depth below the waterline): the cutter draws about 1.3 m.
		"foot": [Vector3(0, -5.4, 0.4), Vector3(0, -4.2, 1.0), Vector3(0, -3.2, 1.2), Vector3(0, -2.0, 1.3), Vector3(0, 0, 1.3),
			Vector3(0, 2.5, 1.3), Vector3(0, 4.0, 1.25), Vector3(0, 5.3, 1.15),
			Vector3(-0.9, -3.0, 0.35), Vector3(0.9, -3.0, 0.35), Vector3(-1.1, 0.0, 0.4), Vector3(1.1, 0.0, 0.4),
			Vector3(-0.9, 4.0, 0.45), Vector3(0.9, 4.0, 0.45)],
	},
	{"length": 19.0, "beam": 7.0, "max_speed": 1.3, "max_heading": 25.0},   # medium: the merchant brig
	{"length": 32.0, "beam": 9.5, "max_speed": 1.2, "max_heading": 20.0},   # large: frigate / big merchantman
	{   # 3 = the two-masted gaff schooner (SchoonerShip.blend). A 15.4 m hull, so she berths as a MEDIUM ship ("size_class") but has her own rig.
		# Measured in the model's Blender frame, then (x, y, z) = (Blender x, Blender z, Blender y) here: bow is -z, port is -x, deck 1.15 m up.
		"length": 15.6, "beam": 4.5, "max_speed": 1.5, "max_heading": 26.0, "size_class": 1,
		"slot_offset": 0.8,
		"motion": {"heave_lag": 0.4, "rise_lag": 0.18, "max_sink": 0.35, "pitch_lag": 0.55, "roll_lag": 0.8},
		# ship_anchor.gd: a small capstan on the waist (the "Capstan" object of the model, in DeckFittings), no coil of cable. The windlass in the bows is only for show.
		"anchor": {"capstan_pos": Vector3(1.45, 1.15, -0.6), "capstan_radius": 0.3, "coil_pos": Vector3(0.0, -9.0, 0.0), "bar_reach": 0.55, "bar_below_top": 0.1},
		"log_line": {"glass_offset": Vector3(-0.45, 0.29, -0.065), "glass_scale": 1.2},
		# The wind-vane (ship_windsock.gd) stands on the "Windsock" marker at the aft starboard corner of the skylight: a short staff and a small pennant, clear of the booms.
		"windsock": {"pole_height": 0.7, "flag_length": 0.9, "hoist_height": 0.2, "tail_height": 0.05},
		"flooding": {"grid_bottom": -1.3, "grid_top": 1.1, "grid_half_width": 2.0, "grid_z_min": -7.0, "grid_z_max": 7.3,
			"waterplane_area": 36.0, "displacement": 55.0, "pump_rate": 0.3, "cargo_swamp_sink": 0.9, "max_sink": 1.6,
			"gm_transverse": 0.8, "gm_longitudinal": 14.0},
		# Rig numbers for ship_sails.gd. Two gaff-rigged masts (each with a boom, a gaff and a gaff topsail that swing together), a staysail,
		# a jib and a flying jib. The node names are the ones in Schooner.glb (tools/schooner_merge/02_build.py KEEP): Sail_Fore, Fore_Boom ...
		# The glb is flat (no parent / child), so "boom_parts" lists what swings with each boom. The topsails are plain meshes: they swing with
		# the boom and are hidden when their sail is furled. The pins are on the pin rails round each mast (x +-0.64, at the mast).
		# Ship frame: (x, y, z) = (Blender x, Blender z, Blender y), bow is -z.
		"rig": {
			"rail_z": [-3.6, 1.8], "rail_pin_y": 2.1, "deck_y": [1.15, 1.15], "braces": false,
			"pin_x": {"FlyingJib": -0.64, "Jib": -0.64, "Staysail": 0.64, "ForeSail": 0.64, "MainSail": -0.64},
			"pin_z": {"FlyingJib": -3.85, "Jib": -3.5, "Staysail": -3.85, "ForeSail": -3.5, "MainSail": 1.7},
			# [id, node, yard, mast, label, pin x, kind (1 = fore-and-aft), reefable, boom]. A sail with a boom swings with it; the first sail
			# listed for a boom steers its swing.
			"sails": [
				["FlyingJib", "Sail_FlyingJib", "", 0, "Flying jib", -0.64, 1, false, ""],
				["Jib", "Sail_Jib", "", 0, "Jib", -0.64, 1, false, ""],
				["Staysail", "Sail_ForeStaysail", "", 0, "Fore staysail", 0.64, 1, false, ""],
				["ForeSail", "Sail_Fore", "", 0, "Foresail", 0.64, 1, false, "Fore_Boom"],
				["MainSail", "Sail_Main", "", 1, "Mainsail", -0.64, 1, false, "Main_Boom"],
			],
			# where each boom turns: on the mast (ship frame z), and the separate nodes that swing with it
			# both masts rake aft, so each boom turns about the mast's own centre line (two points on it, measured off the mast
			# rings in Schooner.glb: foot of the lower mast and the topmast head) and the gaff and topsail stay on the mast
			"booms": {"Fore_Boom": [Vector3(0.0, 3.99, -3.26), Vector3(0.0, 14.5, -2.664)],
				"Main_Boom": [Vector3(0.0, 3.99, 2.246), Vector3(0.0, 15.5, 2.904)]},
			# the block at each headsail's clew is a node of the model that the game keeps on the clew, so the sheet always ends in it
			"clew_blocks": {"Jib": "Clew_Block_Jib", "Staysail": "Clew_Block_Staysail", "FlyingJib": "Clew_Block_FlyingJib"},
			"boom_parts": {"Fore_Boom": ["Fore_Gaff", "Fore_Topsail"], "Main_Boom": ["Main_Gaff", "Main_Topsail"]},
			# Haul ropes: from the sail ("head" = its highest point: the peak of a gaff sail) up to a block at the masthead, then down to the pin.
			"haul": {
				"FlyingJib": ["head", Vector3(-0.06, 14.42, -2.84)],
				"Jib": ["head", Vector3(-0.1, 11.3, -3.05)],
				"Staysail": ["head", Vector3(0.1, 9.5, -3.33)],
				"ForeSail": ["head", Vector3(0.14, 10.95, -2.6)],
				"MainSail": ["head", Vector3(-0.14, 11.85, 2.97)],
			},
			# The main sheet takes hold of the boom 1.3 m in from its end (z 6.0, not the end block at 7.3): from the end, with the boom
			# swung well out, the line ran out over the stern quarter through the bulwark.
			# Passive lines: the sheets of the two booms (two falls from the boom-end block to the block on the horse; ["spar", p, boom] swings
			# with that boom) and the headsail sheets, which go slack on the windward side.
			"rope_lines": [
				{"pts": [["spar", Vector3(-0.04, 3.4, 6.0), "Main_Boom"], ["slide", Vector3(-0.04, 1.43, 7.2), Vector3(0.0, 3.4, 6.0), 0.8, 1000.0, 0.0, "Main_Boom"]]},
				{"pts": [["spar", Vector3(0.04, 3.4, 6.0), "Main_Boom"], ["slide", Vector3(0.04, 1.43, 7.2), Vector3(0.0, 3.4, 6.0), 0.8, 1000.0, 0.0, "Main_Boom"]]},
				{"pts": [["spar", Vector3(-0.04, 3.36, 0.8), "Fore_Boom"], ["slide", Vector3(-0.04, 1.43, 0.6), Vector3(0.0, 3.36, 0.8), 0.8, 1000.0, 0.0, "Fore_Boom"]]},
				{"pts": [["spar", Vector3(0.04, 3.36, 0.8), "Fore_Boom"], ["slide", Vector3(0.04, 1.43, 0.6), Vector3(0.0, 3.36, 0.8), 0.8, 1000.0, 0.0, "Fore_Boom"]]},
				{"sail": "Jib", "side": -1, "pts": [["clew", "Jib"], Vector3(-1.05, 1.3, -4.0)]},
				{"sail": "Jib", "side": 1, "pts": [["clew", "Jib"], Vector3(1.05, 1.3, -4.0)]},
				{"sail": "Staysail", "side": -1, "pts": [["clew", "Staysail"], Vector3(-1.2, 1.3, -3.0)]},
				{"sail": "Staysail", "side": 1, "pts": [["clew", "Staysail"], Vector3(1.2, 1.3, -3.0)]},
				{"sail": "FlyingJib", "side": -1, "pts": [["clew", "FlyingJib"], Vector3(-1.0, 1.3, -5.3)]},
				{"sail": "FlyingJib", "side": 1, "pts": [["clew", "FlyingJib"], Vector3(1.0, 1.3, -5.3)]},
			],
			# The sheet blocks ride the horses (nodes of the model, moved every frame) and follow the boom-end block across the bar.
			"sliders": [
				{"node": "Sheet_Block_Main", "rest": Vector3(0.0, 1.43, 7.2), "track": Vector3(0.0, 3.4, 6.0), "half": 0.8, "arc": 1000.0, "drop": 0.0, "boom": "Main_Boom"},
				{"node": "Sheet_Block_Fore", "rest": Vector3(0.0, 1.43, 0.6), "track": Vector3(0.0, 3.36, 0.8), "half": 0.8, "arc": 1000.0, "drop": 0.0, "boom": "Fore_Boom"},
			],
		},
		# The gangway lies forward of the port hull ladder (z -0.7), between it and the forward port gun, so it does not cover the ladder.
		# Gangway, ship-local (x across to port, y up): flat on the quay, up to the entry port by the boarding steps, down onto the deck.
		"gangway": [Vector2(-4.2, 1.92), Vector2(-3.3, 1.92), Vector2(-2.45, 1.7), Vector2(-2.0, 1.3), Vector2(-1.2, 1.2)],
		"gangway_z": -1.25, "gangway_width": 0.6, "gangway_min_y": 1.45,
		# Mooring cleats on the port side (ship-local x, height, z) and the bollard each line goes to.
		"lines": [[Vector3(-1.95, 1.6, -4.4), 0], [Vector3(-2.05, 1.6, -1.5), 2], [Vector3(-2.05, 1.6, 2.8), 1], [Vector3(-1.7, 1.6, 6.1), 3]],
		# Keel footprint (ship-local x, z, depth below the waterline): she draws about 1.9 m.
		"foot": [Vector3(0, -6.5, 0.6), Vector3(0, -5.0, 1.4), Vector3(0, -3.5, 1.7), Vector3(0, -2.0, 1.85), Vector3(0, 0, 1.9),
			Vector3(0, 2.5, 1.85), Vector3(0, 4.5, 1.6), Vector3(0, 6.2, 1.0),
			Vector3(-1.1, -3.0, 0.5), Vector3(1.1, -3.0, 0.5), Vector3(-1.5, 0.0, 0.5), Vector3(1.5, 0.0, 0.5),
			Vector3(-1.2, 4.5, 0.5), Vector3(1.2, 4.5, 0.5)],
	},
	{   # 4 = the fluyt, a three-masted flute (FluytShip.blend). 24 m on the hull, so she berths as a LARGE ship ("size_class") but has her own rig.
		# Measured in the model's Blender frame, then (x, y, z) = (-Blender x, Blender z, Blender y) here: bow is -z, port is -x, main deck 2.0 m up, quarterdeck 4.0.
		"length": 24.0, "beam": 7.0, "max_speed": 1.2, "max_heading": 22.0, "size_class": 2,
		"slot_offset": 0.9,
		# ship_anchor.gd: the capstan on the main deck abaft the windlass (the "Capstan" object of the model, in DeckFittings)
		"anchor": {"capstan_pos": Vector3(0.0, 2.0, -4.0), "capstan_radius": 0.46, "coil_pos": Vector3(0.0, -9.0, 0.0), "bar_reach": 0.7, "bar_below_top": 0.15},
		# ship_log_line.gd: the glass stands beside the coil of line on the quarterdeck, from the LogLine marker (the marker's own frame)
		"log_line": {"glass_offset": Vector3(-0.45, 0.09, -0.065), "glass_scale": 1.2},
		# the wind-vane stands on the "Windsock" marker, starboard side of the quarterdeck
		"windsock": {"pole_height": 0.8, "flag_length": 1.0, "hoist_height": 0.2, "tail_height": 0.05},
		# ship_flooding.gd: the hold (HoldBounds marker: x +-2.1, z -8.5..2.9, floor -1.78) and the cabins over it; the water physics are a 200 tonne flute's
		"flooding": {"grid_bottom": -1.75, "grid_top": 1.9, "grid_half_width": 3.0, "grid_z_min": -9.5, "grid_z_max": 8.5,
			"waterplane_area": 85.0, "displacement": 230.0, "pump_rate": 0.5, "cargo_swamp_sink": 1.8, "max_sink": 3.2,
			"gm_transverse": 1.2, "gm_longitudinal": 24.0},
		# Rig numbers for ship_sails.gd (ship frame, bow is -z, z = Blender y). Fore and main masts carry a course and a topsail each (square sails on
		# yards that swing with the braces), the mizzen a lateen sail on a long yard that swings from the mizzen mast like a boom, and a spritsail
		# hangs under the bowsprit. The node names are the ones in Fluyt.glb (tools/fluyt_merge/02_build.py): every sail is a child of its yard.
		# "mast" 0 = fore, 1 = main, 2 = mizzen. The pins are on the fife rails round the fore and main masts (z -6.0 and 0.0, abaft each mast), the mizzen's on the
		# little rail across the quarterdeck in front of the mizzen mast, the spritsail's on the fore side of the fore rail.
		"rig": {
			"rail_z": [-6.0, 0.0, 9.3], "rail_pin_y": 2.75, "deck_y": [2.0, 2.0, 4.0], "braces": true,
			"pin_x": {"Fore_1": 0.0, "Fore_0": 0.5, "Main_1": 0.0, "Main_0": 0.5, "Mizzen": 0.0, "Sprit": 0.0},
			"pin_y": {"Mizzen": 4.8},
			"pin_z": {"Sprit": -8.0},
			# [id, node, yard, mast, label, pin x, kind (0 square, 1 fore-and-aft), reefable, boom]
			"sails": [
				["Fore_1", "Sail_Fore_1", "Yard_Fore_1", 0, "Fore topsail", 0.0, 0, true],
				["Fore_0", "Sail_Fore_0", "Yard_Fore_0", 0, "Fore course", 0.5, 0, true],
				["Main_1", "Sail_Main_1", "Yard_Main_1", 1, "Main topsail", 0.0, 0, true],
				["Main_0", "Sail_Main_0", "Yard_Main_0", 1, "Main course", 0.5, 0, true],
				["Mizzen", "Sail_Mizzen", "", 2, "Mizzen", 0.0, 1, false, "Yard_Mizzen"],
				["Sprit", "Sail_Sprit", "Yard_Sprit", 0, "Spritsail", 0.0, 0, false],
			],
			# the mizzen's yard turns about the mizzen mast
			"booms": {"Yard_Mizzen": 10.45},
			# Haul ropes: from the sail's foot (the clew line) round the front of its yard, then down the aft face of the mast to the pin.
			# ["yard", v] is a point in the yard's own frame, so the rope follows the yard when it is braced.
			"haul": {
				"Fore_1": [["yard", Vector3(0.0, -0.12, 0.95)], Vector3(0.0, 13.9, -6.75), Vector3(0.0, 4.0, -6.75)],
				"Fore_0": [["yard", Vector3(0.0, -0.12, 0.95)], Vector3(0.0, 7.9, -6.75), Vector3(0.25, 4.0, -6.75)],
				"Main_1": [["yard", Vector3(0.0, -0.12, 0.95)], Vector3(0.0, 15.9, -0.95), Vector3(0.0, 4.0, -0.95)],
				"Main_0": [["yard", Vector3(0.0, -0.12, 0.95)], Vector3(0.0, 9.3, -0.95), Vector3(0.25, 4.0, -0.95)],
				"Mizzen": ["head", Vector3(0.0, 11.0, 10.35)],
				"Sprit": [["yard", Vector3(0.0, -0.12, 0.95)], Vector3(0.0, 4.6, -12.0), Vector3(0.0, 4.2, -9.5)],
			},
			# the braces: from the yardarm of the course through a block on the shrouds to a pin on the bulwark rail
			"brace_tip": [4.0, 4.7],
			"brace_specs": [
				[0, -1, "Fore brace (port)", Vector3(-2.1, 2.75, -6.1), Vector3(-2.4, 3.5, -5.2)],
				[0, 1, "Fore brace (starboard)", Vector3(2.1, 2.75, -6.1), Vector3(2.4, 3.5, -5.2)],
				[1, -1, "Main brace (port)", Vector3(-2.5, 2.75, 0.0), Vector3(-2.4, 3.5, 0.8)],
				[1, 1, "Main brace (starboard)", Vector3(2.5, 2.75, 0.0), Vector3(2.4, 3.5, 0.8)],
			],
			# the lifts and sheets are ropes of the model that follow the yards and sails (ship_rope_rigs.gd); nothing else is drawn by the game
			"rope_lines": [],
			"sliders": [],
		},
		# Gangway, ship-local (x across to port, y up): flat on the quay, up and over the cap rail (3.0 m), down onto the main deck.
		# It comes aboard in the waist between the fore and main shrouds (z = Blender y).
		"gangway": [Vector2(-5.0, 1.92), Vector2(-4.2, 1.92), Vector2(-3.0, 3.15), Vector2(-2.1, 3.15), Vector2(-1.5, 2.05)],
		"gangway_z": -4.2, "gangway_width": 0.7, "gangway_min_y": 2.3,
		# Mooring cleats on the port side (ship-local x, height, z) and the bollard each line goes to.
		"lines": [[Vector3(-1.7, 3.05, -9.0), 0], [Vector3(-2.35, 3.0, -4.2), 2], [Vector3(-2.3, 3.0, 1.5), 1], [Vector3(-1.7, 4.1, 9.0), 3]],
		# Keel footprint (ship-local x, z, depth below the waterline): she draws about 2.2 m.
		"foot": [Vector3(0, -11.0, 0.7), Vector3(0, -9.0, 1.4), Vector3(0, -6.0, 1.9), Vector3(0, -3.0, 2.1), Vector3(0, 0, 2.2),
			Vector3(0, 3.0, 2.1), Vector3(0, 6.0, 1.8), Vector3(0, 9.0, 1.3),
			Vector3(-1.5, -6.0, 0.6), Vector3(1.5, -6.0, 0.6), Vector3(-2.5, 0.0, 0.6), Vector3(2.5, 0.0, 0.6),
			Vector3(-1.8, 6.0, 0.6), Vector3(1.8, 6.0, 0.6)],
	},
]

## The light rectangle is the ship's size times these.
const ZONE_LENGTH_SCALE := 1.6
const ZONE_WIDTH_SCALE := 2.0

static func data(size: int) -> Dictionary:
	return DATA[clampi(size, 0, DATA.size() - 1)]

## The berth size (Size) a ship of this class needs: a type with its own numbers (the schooner) berths as the size it names.
## Sail-physics numbers for a hull (the SailModel fields: mass, displacement, gm, hull_drag, hull_speed, keel_lat, side_drag).
## SailModel's own defaults are the merchant brig's (19 m x 7 m), so the brig comes out exactly as before and every other
## class is scaled from her by size: mass and displacement by L*B^2, hull drag by wetted area (L*B), keel and side
## resistance by sail-plan scale (L^2), hull speed from the hull length (1.34 * sqrt(feet) knots, the same figure the
## purchase window shows), and the metacentric height so that her heel for the same wind stays like the brig's.
## A class can override any of them with a "sail" dict in DATA, e.g. "sail": {"hull_drag": 220.0}.
const REF_LENGTH_M := 19.0
const REF_BEAM_M := 7.0
const KNOT_MPS := 0.514444

static func sail_tuning(cls: int) -> Dictionary:
	var d := data(cls)
	var l := float(d.get("length", REF_LENGTH_M))
	var b := float(d.get("beam", REF_BEAM_M))
	var vol := (l * b * b) / (REF_LENGTH_M * REF_BEAM_M * REF_BEAM_M)      # displacement ratio
	var wet := (l * b) / (REF_LENGTH_M * REF_BEAM_M)                         # wetted-area ratio
	var scl := (l / REF_LENGTH_M) * (l / REF_LENGTH_M)                       # sail-plan / keel-area ratio
	var t := {
		"mass": 1.9e5 * vol,
		"displacement": 2.0e5 * vol,
		"gm": 0.5 * pow(l / REF_LENGTH_M, 3.0) / maxf(vol, 0.01),
		"hull_drag": 390.0 * wet,
		"hull_speed": 1.34 * sqrt(l * 3.281) * KNOT_MPS,
		"keel_lat": 8000.0 * scl,
		"side_drag": 1800.0 * scl,
	}
	var o: Dictionary = d.get("sail", {})
	for k in o:
		t[k] = o[k]
	return t


static func berth_class(cls: int) -> int:
	return int(data(cls).get("size_class", cls))

## Rectangle (width across the berth, length along it) in metres.
static func zone_size(size: int) -> Vector2:
	var d := data(size)
	return Vector2(float(d.beam) * ZONE_WIDTH_SCALE, float(d.length) * ZONE_LENGTH_SCALE)

## Heading in degrees (0 = north, 90 = west, the way heading_deg grows) as a word.
static func compass(heading_deg: float) -> String:
	var names := ["north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east"]
	return names[int(round(fposmod(heading_deg, 360.0) / 45.0)) % 8]
