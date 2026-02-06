/**
 * Flood Evacuation Simulation - Extension 1
 * Based on: Flood Evacuation Simulation
 *
 * Extension 1: Evacuation Behavior
 * - Only 10% of aware residents know shelter location directly
 * - Remaining 90% move to random buildings to search
 * - Within 20m of shelter: switch to direct movement
 *
 * Base model: 10% initially informed, 10m radius, 0.1 probability
 */

model flood_evacuation_ext1

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
    float information_spread_distance <- 10.0;  // 10m theo slide
    float shelter_detection_distance <- 20.0;   // 20m: switch to direct movement
    int nb_inhabitants <- 3000;

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
            is_aware <- flip(0.1);  // 10% initially notified
            // Extension 1: Only 10% of aware know shelter location
            knows_shelter_location <- is_aware ? flip(0.1) : false;
            if is_aware and !knows_shelter_location {
                building rand_b <- one_of(building where (!each.is_shelter));
                if rand_b != nil {
                    search_target <- any_location_in(rand_b);
                }
            }
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
            
            write "========== EXTENSION 1 - SIMULATION RESULTS ==========";
            write "--- Parameters ---";
            write "  nb_inhabitants: " + nb_inhabitants;
            write "  flood_speed: " + flood_speed + " m/cycle";
            write "  flood_start_cycle: " + flood_start_cycle;
            write "  flood_peak_cycle: " + flood_peak_cycle;
            write "  flood_recession_speed: " + flood_recession_speed;
            write "  information_spread_rate: " + information_spread_rate;
            write "  information_spread_distance: " + information_spread_distance + " m";
            write "  shelter_detection_distance: " + shelter_detection_distance + " m";
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
    bool is_fleeing <- false;
    bool knows_shelter_location <- false;  // Extension 1: 10% of aware know shelter
    float speed <- 10.0;
    int health <- 100;  // Health system: -3 per cycle underwater
    building target_shelter;
    point flee_target;
    point search_target;  // Extension 1: target building khi search

    reflex inform when: is_aware {
        ask inhabitant at_distance information_spread_distance {
            if !self.is_aware and flip(information_spread_rate) {
                self.is_aware <- true;
                self.knows_shelter_location <- flip(0.1);  // 10% learn shelter
                if !self.knows_shelter_location {
                    building rand_b <- one_of(building where (!each.is_shelter));
                    if rand_b != nil {
                        self.search_target <- any_location_in(rand_b);
                    }
                }
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
            do goto target: flee_target on: road_network speed: speed;

            bool reached_target <- location distance_to flee_target < 5.0;
            bool out_of_water <- flood_zone = nil or !(flood_zone covers self.location);

            if reached_target or out_of_water {
                is_fleeing <- false;
                is_aware <- true;
                flee_target <- nil;
                knows_shelter_location <- flip(0.1);
                if !knows_shelter_location {
                    building rand_b <- one_of(building where (!each.is_shelter));
                    if rand_b != nil {
                        search_target <- any_location_in(rand_b);
                    }
                }
            }
        }
    }

    reflex evacuate when: is_aware and !is_evacuated and cycle >= flood_start_cycle {
        if target_shelter = nil {
            target_shelter <- shelters closest_to self;
        }

        if target_shelter != nil {
            float effective_speed <- speed;
            if flood_zone != nil and flood_zone covers self.location {
                if current_flood_depth >= dangerous_depth {
                    effective_speed <- speed * 0.2;
                } else {
                    effective_speed <- speed * 0.5;
                }
            }

            float distance_to_shelter <- location distance_to target_shelter.location;

            // Extension 1: Know shelter OR within 20m -> direct movement
            if knows_shelter_location or distance_to_shelter < shelter_detection_distance {
                do goto target: target_shelter.location on: road_network speed: effective_speed;

                if location = target_shelter.location {
                    is_evacuated <- true;
                    nb_evacuee <- nb_evacuee + 1;
                    do die;
                }
            } else {
                // 90%: move to random buildings to search; if < 20m from shelter, switch above
                if search_target = nil {
                    building rand_b <- one_of(building where (!each.is_shelter));
                    if rand_b != nil {
                        search_target <- any_location_in(rand_b);
                    }
                }
                if search_target != nil {
                    do goto target: search_target on: road_network speed: effective_speed;

                    if location distance_to search_target < 5.0 {
                        building rand_b <- one_of(building where (!each.is_shelter));
                        if rand_b != nil {
                            search_target <- any_location_in(rand_b);
                        }
                    }
                }
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
            agent_color <- knows_shelter_location ? #red : #orange;  // Red=know shelter, Orange=searching
        } else {
            agent_color <- #blue;
        }
        draw circle(8) color: agent_color;
    }
}

experiment flood_ext1_exp type: gui {
    parameter "Population (reduced for faster load)" var: nb_inhabitants category: "Initialization" min: 500 max: 10000;
    parameter "Flood speed (m/cycle)" var: flood_speed category: "Flood" min: 1 max: 500;
    parameter "Flood start cycle" var: flood_start_cycle category: "Flood" min: 1 max: 100;
    parameter "Flood peak cycle" var: flood_peak_cycle category: "Flood" min: 50 max: 1000;
    parameter "Water recession speed (m/cycle)" var: flood_recession_speed category: "Flood" min: 1 max: 500;
    parameter "Information spread rate" var: information_spread_rate category: "Information" min: 0.0 max: 1.0;
    parameter "Shelter detection distance (m)" var: shelter_detection_distance category: "Extension 1" min: 10.0 max: 50.0;

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
        }

        display "Information Spread Chart" {
            chart "Information Spread Over Time" type: series {
                data "Aware (Know Shelter)" value: inhabitant count (each.is_aware and each.knows_shelter_location) color: #red;
                data "Aware (Searching)" value: inhabitant count (each.is_aware and !each.knows_shelter_location) color: #orange;
                data "Evacuated" value: nb_evacuee color: #green;
                data "Unaware" value: inhabitant count (!each.is_aware) color: #blue;
                data "Dead" value: nb_dead color: #black;
            }
        }

        monitor "Evacuees" value: nb_evacuee color: #green;
        monitor "Dead" value: nb_dead color: #red;
        monitor "Cycles" value: cycle color: #blue;
        monitor "Survival rate (%)" value: (((length(inhabitant) + nb_evacuee + nb_dead) > 0) ? ((nb_evacuee + length(inhabitant)) * 100.0 / (length(inhabitant) + nb_evacuee + nb_dead)) : 0.0) with_precision 2;
        monitor "Know shelter" value: inhabitant count (each.knows_shelter_location) color: #red;
        monitor "Searching" value: inhabitant count (each.is_aware and !each.knows_shelter_location) color: #orange;
    }
}
