/**
 * Evacuation Simulation - Project Specification
 *
 * Context: Population evacuation (e.g. beach/tsunami or flood/dike breach).
 * Flooding is NOT modeled; only resident behavior in the face of the threat.
 *
 * Rules:
 * - All residents start at home.
 * - Only 10% (randomly chosen) are initially aware of the risk.
 * - Shelter = the largest building in the area (single building).
 * - A person observing someone evacuating (distance < 10 m) has probability 0.1
 *   of evacuating in turn (becomes aware and heads to shelter).
 * - Simulation ends when all people who received the information have evacuated.
 *
 * Data: shapefiles from includes/flood_map (buildings, roads, water).
 */

model evac

global {
    string map_folder <- "../includes/flood_map";

    shape_file shapefile_buildings <- shape_file(map_folder + "/building_polygon.shp");
    shape_file shapefile_roads <- shape_file(map_folder + "/highway_line.shp");
    shape_file shapefile_water <- shape_file(map_folder + "/water_polygon.shp");
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    float step <- 1#s;

    building shelter;  // Single shelter = largest building
    int nb_evacuee <- 0;
    bool simulation_finished <- false;

    float information_spread_distance <- 10.0;  // Observation distance (m)
    float information_spread_probability <- 0.1; // Probability to evacuate when observing
    int nb_inhabitants <- 3000;

    init {
        create building from: shapefile_buildings with: [height::10];

        // Shelter = the largest building (by area)
        shelter <- building with_max_of (each.shape.area);
        if shelter != nil {
            shelter.is_shelter <- true;
        }

        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);

        create water from: shapefile_water with: [water_type:: read("water")];

        // Place inhabitants in buildings (their homes)
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
            is_aware <- flip(0.1);  // 10% initially informed
        }
    }

    reflex check_end when: !simulation_finished {
        // End when all people who got the information have evacuated (no aware left in world)
        bool all_informed_evacuated <- (inhabitant count (each.is_aware)) = 0;

        if all_informed_evacuated {
            simulation_finished <- true;
            int total_aware_ever <- nb_evacuee;  // All who were aware have evacuated
            int unaware_left <- length(inhabitant);

            write "========== EVACUATION SIMULATION - RESULTS ==========";
            write "  End cycle: " + cycle;
            write "  Total evacuees (reached shelter): " + nb_evacuee;
            write "  Unaware (never informed, still at home): " + unaware_left;
            write "  Total population: " + (nb_evacuee + unaware_left);
            write "=====================================================";
            do pause;
        }
    }
}

species building {
    int height;
    bool is_shelter <- false;

    aspect default {
        rgb building_color;
        if is_shelter {
            building_color <- rgb(255, 100, 0);
        } else {
            float height_ratio <- height / 50.0;
            building_color <- rgb(int(255 - min(100, height_ratio * 100)), int(220 - min(120, height_ratio * 120)), 150);
        }
        draw shape color: building_color border: rgb(80, 80, 80) depth: height;
    }
}

species road {
    aspect default {
        draw shape color: #black;
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
    float speed <- 10.0;
    building target_shelter;

    // Observation: see someone evacuating (< 10 m) → with probability 0.1 evacuate in turn
    reflex observe_evacuating when: !is_aware and !is_evacuated {
        list<inhabitant> evacuating_nearby <- inhabitant at_distance information_spread_distance where (each.is_aware and !each.is_evacuated);
        if !empty(evacuating_nearby) and flip(information_spread_probability) {
            is_aware <- true;
            if shelter != nil {
                target_shelter <- shelter;
            }
        }
    }

    reflex evacuate when: is_aware and !is_evacuated {
        if target_shelter = nil and shelter != nil {
            target_shelter <- shelter;
        }

        if target_shelter != nil {
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
        } else if is_aware {
            agent_color <- #red;
        } else {
            agent_color <- #blue;
        }
        draw circle(8) color: agent_color;
    }
}

experiment evac_exp type: gui {
    parameter "Population" var: nb_inhabitants category: "Initialization" min: 500 max: 10000;
    parameter "Observation distance (m)" var: information_spread_distance category: "Information" min: 1.0 max: 50.0;
    parameter "Probability when observing (0.1)" var: information_spread_probability category: "Information" min: 0.0 max: 1.0;

    output {
        display map type: 3d {
            species water;
            species road;
            species building;
            species inhabitant;
        }

        display "Information Spread" {
            chart "Aware vs Evacuated vs Unaware" type: series {
                data "Aware (not yet evacuated)" value: (inhabitant count (each.is_aware)) color: #red;
                data "Evacuated" value: nb_evacuee color: #green;
                data "Unaware" value: (inhabitant count (!each.is_aware)) color: #blue;
            }
        }

        display "Population" {
            chart "Distribution" type: pie {
                data "Aware (on the way)" value: (inhabitant count (each.is_aware)) color: #red;
                data "Evacuated" value: nb_evacuee color: #green;
                data "Unaware" value: (inhabitant count (!each.is_aware)) color: #blue;
            }
        }

        monitor "Evacuees" value: nb_evacuee color: #green;
        monitor "Aware (on the way)" value: (inhabitant count (each.is_aware)) color: #red;
        monitor "Unaware" value: (inhabitant count (!each.is_aware)) color: #blue;
        monitor "Cycle" value: cycle color: #gray;
    }
}
