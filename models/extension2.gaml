/**
 * Flood Evacuation Simulation - Extension 2
 * Based on: Flood Evacuation Simulation
 *
 * Extension 2: Transportation
 * - Cars (20%): fastest, most affected by congestion (factor 1.0)
 * - Motorcycles (70%): speed factor 0.85, congestion factor 0.5
 * - Walking (10%): slowest (speed factor 0.1), least affected by congestion (factor 0.2)
 *
 * Base model: 10% initially informed, 10m radius, 0.1 probability
 */

model flood_evacuation_ext2

global {
    string map_folder <- "../includes/flood_map";

    shape_file shapefile_buildings <- shape_file(map_folder + "/building_polygon.shp");
    shape_file shapefile_roads <- shape_file(map_folder + "/highway_line.shp");
    shape_file shapefile_water <- shape_file(map_folder + "/water_polygon.shp");
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    float step <- 1#s;

    list<building> shelters;
    int nb_evacuee <- 0;
    int nb_dead <- 0;
    bool simulation_finished <- false;
    map<road, float> traffic_density;  // Traffic density on each road segment

    float flood_speed <- 2.0;
    int flood_start_cycle <- 30;
    int flood_peak_cycle <- 500;
    float flood_recession_speed <- 2.0;
    geometry flood_zone;
    float max_flood_radius <- 0.0;
    float max_flood_depth <- 5.0;
    float current_flood_depth <- 0.0;
    float dangerous_depth <- 3.0;

    float information_spread_rate <- 0.1;
    float information_spread_distance <- 10.0;
    int nb_inhabitants <- 3000;

    float base_speed <- 10.0;  // Base speed (m/s) for car

    init {
        create building from: shapefile_buildings with: [height::10];

        float max_height <- max(building collect each.height);
        float max_area <- max(building collect each.shape.area);

        ask building {
            float normalized_height <- max_height > 0 ? (self.height / max_height) : 0.0;
            float normalized_area <- max_area > 0 ? (self.shape.area / max_area) : 0.0;
            self.shelter_score <- normalized_height + normalized_area;
        }

        shelters <- building sort_by (-each.shelter_score);
        shelters <- first(100, shelters);

        ask shelters {
            self.is_shelter <- true;
        }

        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        traffic_density <- road as_map (each::0.0);

        create water from: shapefile_water with: [water_type:: read("water")];

        list<geometry> water_shapes <- water collect each.shape;
        geometry water_union <- empty(water_shapes) ? nil : union(water_shapes);
        list<road> roads_near_water <- (water_union != nil) ? road where (each.shape distance_to water_union < 1000) : list(road);
        list<building> buildings_near_water <- (water_union != nil) ? building where (each.location distance_to water_union < 1000) : list(building);

        create inhabitant number: nb_inhabitants {
            if water_union != nil and (!empty(roads_near_water) or !empty(buildings_near_water)) {
                bool use_building <- !empty(buildings_near_water) and flip(0.5);
                if use_building {
                    building b <- one_of(buildings_near_water);
                    location <- any_location_in(b);
                } else if !empty(roads_near_water) {
                    road r <- one_of(roads_near_water);
                    location <- any_location_in(r);
                } else {
                    building b <- one_of(buildings_near_water);
                    location <- any_location_in(b);
                }
            } else {
                location <- flip(0.5) ? any_location_in(one_of(building)) : any_location_in(one_of(road));
            }
            home <- location;
            is_aware <- flip(0.1);

            // Extension 2: Vehicle distribution per slide
            float r <- rnd(0.0, 1.0);
            if r < 0.2 {
                mobility_type <- "car";
                speed_factor <- 1.0;      // Fastest
                congestion_factor <- 1.0; // Most affected by congestion
            } else if r < 0.9 {
                mobility_type <- "motorcycle";
                speed_factor <- 0.85;
                congestion_factor <- 0.5;
            } else {
                mobility_type <- "walking";
                speed_factor <- 0.1;      // Slowest
                congestion_factor <- 0.2;  // Least affected by congestion
            }
        }
    }

    reflex update_traffic when: cycle >= flood_start_cycle {
        // Only need traffic when people evacuate/flee (after flood starts)
        traffic_density <- road as_map (each::0.0);
        ask inhabitant {
            road r <- road closest_to self;
            if r != nil and (self.location distance_to r.shape < 15.0) {
                traffic_density[r] <- traffic_density[r] + 1;
            }
        }
        // Normalize: divide by 8 so 2-3 people on a road already show yellow/red
        ask road {
            traffic_density[self] <- min(1.0, traffic_density[self] / 8.0);
            self.current_density <- traffic_density[self];  // store on agent for display
        }
    }

    reflex update_flood when: cycle >= flood_start_cycle {
        float radius;

        if cycle < flood_peak_cycle {
            radius <- (cycle - flood_start_cycle) * flood_speed;
            max_flood_radius <- radius;
            float progress <- (cycle - flood_start_cycle) / (flood_peak_cycle - flood_start_cycle);
            current_flood_depth <- progress * max_flood_depth;
        } else {
            float recession_time <- cycle - flood_peak_cycle;
            radius <- max(0.0, max_flood_radius - recession_time * flood_recession_speed);
            if max_flood_radius > 0 {
                current_flood_depth <- (radius / max_flood_radius) * max_flood_depth;
            } else {
                current_flood_depth <- 0.0;
            }
        }

        // Flood ONLY from river, NOT from lake
        list<geometry> river_shapes <- (water where (each.water_type = "river")) collect each.shape;
        geometry flood_source <- empty(river_shapes) ? nil : union(river_shapes);
        if flood_source = nil {
            water biggest <- water with_max_of (each.shape.area);
            flood_source <- (biggest != nil) ? biggest.shape : (shape.centroid + 1.0);
        }
        flood_zone <- radius > 0 and flood_source != nil ? (flood_source + radius) : nil;

        // Health system: 100 HP, -3 per cycle underwater
        ask inhabitant {
            if flood_zone != nil and flood_zone covers self.location {
                if !self.is_evacuated {
                    self.health <- self.health - 3;
                    if self.health <= 0 {
                        nb_dead <- nb_dead + 1;
                        do die;
                    }
                }
            }
        }
    }

    reflex check_end when: !simulation_finished {
        bool all_aware_evacuated <- empty(inhabitant) or inhabitant all_match (each.is_evacuated or !each.is_aware);
        bool flood_receded <- cycle > flood_start_cycle and flood_zone = nil;

        if all_aware_evacuated or flood_receded {
            simulation_finished <- true;
            int still_on_road <- inhabitant count (each.is_aware and !each.is_evacuated);
            int unaware_alive <- inhabitant count (!each.is_aware);
            int total <- nb_evacuee + nb_dead + length(inhabitant);
            int survivors <- nb_evacuee + length(inhabitant);
            float survival_rate <- (total > 0 ? (survivors * 100.0 / total) : 0.0);
            
            write "========== EXTENSION 2 - SIMULATION RESULTS ==========";
            write "--- Parameters ---";
            write "  nb_inhabitants: " + nb_inhabitants;
            write "  flood_speed: " + flood_speed + " m/cycle";
            write "  flood_start_cycle: " + flood_start_cycle;
            write "  flood_peak_cycle: " + flood_peak_cycle;
            write "  flood_recession_speed: " + flood_recession_speed;
            write "  information_spread_rate: " + information_spread_rate;
            write "  information_spread_distance: " + information_spread_distance + " m";
            write "  base_speed: " + base_speed + " m/s";
            write "--- Results ---";
            write "  End cycle: " + cycle;
            write "  Reason: " + (flood_receded ? "Flood receded completely" : "All aware people evacuated");
            write "  Total evacuees (at shelter): " + nb_evacuee;
            write "  Safe on road (flood receded): " + still_on_road;
            write "  Unaware alive (not informed, safe): " + unaware_alive;
            write "  Total dead: " + nb_dead;
            write "  Total population: " + total;
            write "  Survivors: " + survivors + " (evacuees + still in sim)";
            write "  Survival rate: " + survival_rate + "%";
            write "=====================================================";
            do pause;
        }
    }
}

species building {
    int height;
    bool is_shelter <- false;
    float shelter_score <- 0.0;

    aspect default {
        rgb building_color;
        if is_shelter {
            building_color <- rgb(255, 100, 0);
        } else {
            float height_ratio <- height / 50.0;
            int red_val <- int(255 - min(100, height_ratio * 100));
            int green_val <- int(220 - min(120, height_ratio * 120));
            building_color <- rgb(red_val, green_val, 150);
        }
        draw shape color: building_color border: rgb(80, 80, 80) depth: height;
    }
}

species road {
    float current_density <- 0.0;  // updated each cycle in update_traffic (when cycle >= flood_start_cycle)
    aspect default {
        // Highlight congestion: black (no traffic) -> green -> yellow -> red (congested)
        float density <- current_density;
        rgb road_color;
        if density <= 0.0 {
            road_color <- #black;
        } else if density < 0.2 {
            road_color <- rgb(0, 200, 0);  // green = low
        } else if density < 0.5 {
            road_color <- rgb(255, 220, 0);  // yellow = medium
        } else {
            road_color <- rgb(255, 0, 0);   // red = congested
        }
        draw shape color: road_color border: rgb(60, 60, 60);
    }
}

species water {
    string water_type <- "";
    aspect default {
        draw shape color: rgb(100, 150, 255) border: rgb(50, 100, 200);
    }
}

species inhabitant skills: [moving] {
    point home;
    bool is_aware <- false;
    bool is_evacuated <- false;
    bool is_fleeing <- false;
    string mobility_type;      // "car", "motorcycle", "walking"
    float speed_factor;        // 1.0, 0.85, 0.1
    float congestion_factor;   // 1.0, 0.5, 0.2
    int health <- 100;  // Health system: -3 per cycle underwater
    building target_shelter;
    point flee_target;

    // Effective speed = base_speed * speed_factor * (1 - congestion_factor * traffic_density)
    float get_effective_speed(road current_road) {
        float density <- (current_road != nil and traffic_density contains current_road) ? traffic_density[current_road] : 0.0;
        float congestion_penalty <- 1.0 - (congestion_factor * density);
        return base_speed * speed_factor * max(0.1, congestion_penalty);
    }

    reflex inform when: is_aware {
        ask inhabitant at_distance information_spread_distance {
            if !self.is_aware and flip(information_spread_rate) {
                self.is_aware <- true;
            }
        }
    }

    reflex panic_on_flood when: !is_aware and !is_evacuated and !is_fleeing and cycle >= flood_start_cycle {
        if flood_zone != nil and flood_zone covers self.location {
            is_fleeing <- true;
            point flood_center <- flood_zone.location;
            float angle <- self.location towards flood_center + 180;
            float flee_distance <- 100.0;
            flee_target <- self.location + {flee_distance * cos(angle), flee_distance * sin(angle)};
        }
    }

    reflex flee_from_water when: is_fleeing and !is_evacuated {
        if flee_target != nil {
            road current_road <- road closest_to self;
            float speed <- get_effective_speed(current_road);
            do goto target: flee_target on: road_network speed: speed;

            bool reached_target <- location distance_to flee_target < 5.0;
            bool out_of_water <- flood_zone = nil or !(flood_zone covers self.location);

            if reached_target or out_of_water {
                is_fleeing <- false;
                is_aware <- true;
                flee_target <- nil;
            }
        }
    }

    reflex evacuate when: is_aware and !is_evacuated and cycle >= flood_start_cycle {
        if target_shelter = nil {
            target_shelter <- shelters closest_to self;
        }

        if target_shelter != nil {
            road current_road <- road closest_to self;
            float speed <- get_effective_speed(current_road);

            if flood_zone != nil and flood_zone covers self.location {
                if current_flood_depth >= dangerous_depth {
                    speed <- speed * 0.2;
                } else {
                    speed <- speed * 0.5;
                }
            }

            do goto target: target_shelter.location on: road_network speed: speed;

            if location = target_shelter.location {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                do die;
            }
        }
    }

    aspect default {
        rgb agent_color;
        if is_evacuated {
            agent_color <- #green;
        } else if is_fleeing {
            agent_color <- #yellow;
        } else if is_aware {
            agent_color <- #red;
        } else {
            agent_color <- #blue;
        }

        if mobility_type = "car" {
            draw square(10) color: agent_color border: #black;
        } else if mobility_type = "motorcycle" {
            draw triangle(8) color: agent_color border: #black;
        } else {
            draw circle(6) color: agent_color border: #black;
        }
    }
}

experiment flood_ext2_exp type: gui {
    parameter "Population (reduced for faster load)" var: nb_inhabitants category: "Initialization" min: 500 max: 10000;
    parameter "Flood speed (m/cycle)" var: flood_speed category: "Flood" min: 1 max: 500;
    parameter "Flood start cycle" var: flood_start_cycle category: "Flood" min: 1 max: 100;
    parameter "Flood peak cycle" var: flood_peak_cycle category: "Flood" min: 50 max: 1000;
    parameter "Water recession speed (m/cycle)" var: flood_recession_speed category: "Flood" min: 1 max: 500;
    parameter "Information spread rate" var: information_spread_rate category: "Information" min: 0.0 max: 1.0;

    output {
        display map type: 3d {
            species water;
            graphics "Flooded area" {
                if flood_zone != nil {
                    draw flood_zone color: rgb(0, 100, 200) border: rgb(0, 50, 150);
                }
            }
            species road;
            species building;
            species inhabitant;
            graphics "Traffic legend" {
                draw circle(4) at: {15, 15} color: #green border: #black;
                draw circle(4) at: {15, 28} color: #red border: #black;
            }
        }

        display "Information Spread Chart" {
            chart "Information Spread Over Time" type: series {
                data "Aware" value: inhabitant count (each.is_aware) color: #red;
                data "Evacuated" value: nb_evacuee color: #green;
                data "Unaware" value: inhabitant count (!each.is_aware) color: #blue;
                data "Dead" value: nb_dead color: #black;
            }
        }

        monitor "Evacuees" value: nb_evacuee color: #green;
        monitor "Dead" value: nb_dead color: #red;
        monitor "Cycles" value: cycle color: #blue;
        monitor "Survival rate (%)" value: (((length(inhabitant) + nb_evacuee + nb_dead) > 0) ? ((nb_evacuee + length(inhabitant)) * 100.0 / (length(inhabitant) + nb_evacuee + nb_dead)) : 0.0) with_precision 2;
        monitor "Cars (20%)" value: inhabitant count (each.mobility_type = "car") color: #blue;
        monitor "Motorcycles (70%)" value: inhabitant count (each.mobility_type = "motorcycle") color: #purple;
        monitor "Walking (10%)" value: inhabitant count (each.mobility_type = "walking") color: #brown;
    }
}
