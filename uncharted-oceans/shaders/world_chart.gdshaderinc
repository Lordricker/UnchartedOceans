// Shared by ocean.gdshader and world_terrain.gdshader.
// Must match WorldChart.sea_depth_m() in world_chart.gd (shelf: about 2 m at the beach,
// 40 m at 12 km out, then falling away to 2500 m by 42 km).
float chart_shelf_depth(float d_km) {
	if (d_km < 12.0) {
		return mix(2.0, 40.0, pow(d_km / 12.0, 0.8));
	}
	return mix(40.0, 2500.0, pow(clamp((d_km - 12.0) / 30.0, 0.0, 1.0), 1.5));
}
