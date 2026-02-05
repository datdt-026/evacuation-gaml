/**
 * Flood Evacuation Simulation - Base Model
 *
 * PROJECT OBJECTIVES (based on Flood Evacuation Simulation):
 * 1. Explore how information spreading affects community safety in flood scenarios
 * 2. Evaluate evacuation strategies to minimize congestion
 * 3. Maximize survival rate through optimal decision-making
 *
 * Base Model - Information Spreading:
 * - 10% of residents are initially notified about evacuation
 * - Awareness spreads through observation (10m radius, 0.1 probability)
 * - Simulation ends when all notified residents have evacuated
 *
 * Shapefiles from includes/flood_map (OSM format)
 */

model flood_evacuation_base

global {
    string map_folder <- "../includes/flood_map";

    shape_file shapefile_buildings <- shape_file(map_folder + "/building_polygon.shp");
    shape_file shapefile_roads <- shape_file(map_folder + "/highway_line.shp");
    shape_file shapefile_water <- shape_file(map_folder + "/water_polygon.shp");
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    float step <- 1#s;  // 1 second per cycle - same as backup for smooth running

    list<building> shelters;
    int nb_evacuee <- 0;
    int nb_dead <- 0;
    bool simulation_finished <- false;
    float flood_speed <- 2.0;       // Flood spread speed (m/cycle)
    int flood_start_cycle <- 30;    // Cycle when flood starts
    int flood_peak_cycle <- 500;    // Cycle when flood peaks
    float flood_recession_speed <- 2.0;  // Water recession speed
    geometry flood_zone;             // Flooded area
    float max_flood_radius <- 0.0;   // Maximum flood radius (at peak)
    
    // Flood depth simulation
    float max_flood_depth <- 5.0;    // Maximum water depth (m)
    float current_flood_depth <- 0.0; // Current water depth (m)
    float dangerous_depth <- 3.0;     // Dangerous depth (≥3m) - lowered for more danger
    
    float information_spread_rate <- 0.1;  // Information spreading probability
    float information_spread_distance <- 20.0;  // Distance for information spreading (m)
    int nb_inhabitants <- 3000;  // Reduced for faster loading (can increase if machine is powerful)

    init {
        create building from: shapefile_buildings with: [height::10];
        
        // Shelters: top 100 tallest and largest buildings
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

        // Place inhabitants near water (both banks - use road for banks without buildings)
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
        }
    }

    // Flood dynamics: water spreads from rivers/lakes, peaks, then recedes
    reflex update_flood when: cycle >= flood_start_cycle {
        float radius;
        
        if cycle < flood_peak_cycle {
            // Rising phase
            radius <- (cycle - flood_start_cycle) * flood_speed;
            max_flood_radius <- radius;
            
            float progress <- (cycle - flood_start_cycle) / (flood_peak_cycle - flood_start_cycle);
            current_flood_depth <- progress * max_flood_depth;
        } else {
            // Receding phase
            float recession_time <- cycle - flood_peak_cycle;
            radius <- max(0.0, max_flood_radius - recession_time * flood_recession_speed);
            
            if max_flood_radius > 0 {
                current_flood_depth <- (radius / max_flood_radius) * max_flood_depth;
            } else {
                current_flood_depth <- 0.0;
            }
        }
        
        // Update flooded area - ONLY from river, NOT from lake/pond/reservoir
        list<geometry> river_shapes <- (water where (each.water_type = "river")) collect each.shape;
        geometry flood_source <- empty(river_shapes) ? nil : union(river_shapes);
        if flood_source = nil {
            // Fallback: if no polygon type=river, use water with largest area (main river)
            water biggest <- water with_max_of (each.shape.area);
            flood_source <- (biggest != nil) ? biggest.shape : (shape.centroid + 1.0);
        }
        flood_zone <- radius > 0 and flood_source != nil ? (flood_source + radius) : nil;
        
        // Check inhabitants in flooded area - Health system: 100 HP, -3 per cycle underwater
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

    // End when: (1) all aware people evacuated/dead, OR (2) flood receded (people still on road = safe)
    reflex check_end when: !simulation_finished {
        bool all_aware_evacuated <- empty(inhabitant) or inhabitant all_match (each.is_evacuated or !each.is_aware);
        bool flood_receded <- cycle > flood_start_cycle and flood_zone = nil;
        
        if all_aware_evacuated or flood_receded {
            simulation_finished <- true;
            int still_on_road <- inhabitant count (each.is_aware and !each.is_evacuated);
            int unaware_alive <- inhabitant count (!each.is_aware);
            int total <- nb_evacuee + nb_dead + length(inhabitant);
            // Survivors = all alive: evacuees + people still in simulation (on road + unaware)
            int survivors <- nb_evacuee + length(inhabitant);
            float survival_rate <- (total > 0 ? (survivors * 100.0 / total) : 0.0);
            
            write "========== BASE MODEL - SIMULATION RESULTS ==========";
            write "--- Parameters ---";
            write "  nb_inhabitants: " + nb_inhabitants;
            write "  flood_speed: " + flood_speed + " m/cycle";
            write "  flood_start_cycle: " + flood_start_cycle;
            write "  flood_peak_cycle: " + flood_peak_cycle;
            write "  flood_recession_speed: " + flood_recession_speed;
            write "  information_spread_rate: " + information_spread_rate;
            write "  information_spread_distance: " + information_spread_distance + " m";
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
            write "==================================================";
            do pause;
        }
    }
}

species building {
    int height;
    bool is_shelter <- false;
    float shelter_score <- 0.0;  // Combined score of height + area

    aspect default {
        // Color gradient by height
        rgb building_color;
        if is_shelter {
            building_color <- rgb(255, 100, 0);  // Bright orange for shelters
        } else {
            // Gradient from light yellow (low) -> dark brown (high)
            float height_ratio <- height / 50.0;  // Assume max ~50m
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
    string water_type <- "";  // From shapefile: river, lake, pond, reservoir, canal
    aspect default {
        draw shape color: rgb(100, 150, 255) border: rgb(50, 100, 200);
    }
}

species inhabitant skills: [moving] {
    point home;
    bool is_aware <- false;
    bool is_evacuated <- false;
    bool is_fleeing <- false;  // Fleeing from water (panic mode)
    float speed <- 10.0;  // Distance per cycle (step=1s, same as backup)
    int health <- 100;  // Health system: -3 per cycle underwater, die when <= 0
    building target_shelter;   // Nearest shelter
    point flee_target;  // Temporary target when fleeing from water

    // Awareness spreading: observation (adjustable radius and probability) - Enhanced
    // Aware people inform nearby unaware people about shelters
    reflex inform when: is_aware {
        ask inhabitant at_distance information_spread_distance {
            if !self.is_aware and flip(information_spread_rate) {
                self.is_aware <- true;
                // Also share shelter knowledge
                if myself.target_shelter != nil and self.target_shelter = nil {
                    self.target_shelter <- myself.target_shelter;
                }
            }
        }
    }
    
    // Panic behavior: when flood arrives, uninformed people flee (only when cycle >= flood_start_cycle)
    reflex panic_on_flood when: !is_aware and !is_evacuated and !is_fleeing and cycle >= flood_start_cycle {
        if flood_zone != nil and flood_zone covers self.location {
            is_fleeing <- true;
            point flood_center <- flood_zone.location;
            float angle <- self.location towards flood_center + 180;
            float flee_distance <- 100.0;
            flee_target <- self.location + {flee_distance * cos(angle), flee_distance * sin(angle)};
        }
    }
    
    // Flee from water until safe, then become aware and look for shelter
    reflex flee_from_water when: is_fleeing and !is_evacuated {
        if flee_target != nil {
            do goto target: flee_target on: road_network speed: speed;
            
            // Check if reached flee target or out of water
            bool reached_target <- location distance_to flee_target < 5.0;
            bool out_of_water <- flood_zone = nil or !(flood_zone covers self.location);
            
            if reached_target or out_of_water {
                // Stop fleeing, become aware
                is_fleeing <- false;
                is_aware <- true;
                flee_target <- nil;
                
                // Look for nearby aware people to learn shelter location
                list<inhabitant> nearby_aware <- inhabitant at_distance (information_spread_distance * 2) where (each.is_aware and each.target_shelter != nil);
                if !empty(nearby_aware) {
                    // Learn from the nearest aware person
                    inhabitant teacher <- nearby_aware closest_to self;
                    target_shelter <- teacher.target_shelter;
                }
            }
        }
    }

    // Only evacuate when flood has started (avoid running before flood rises)
    reflex evacuate when: is_aware and !is_evacuated and cycle >= flood_start_cycle {
        if target_shelter = nil {
            target_shelter <- shelters closest_to self;
        }
        
        if target_shelter != nil {
            // Calculate speed based on water depth
            float effective_speed <- speed;
            if flood_zone != nil and flood_zone covers self.location {
                if current_flood_depth >= dangerous_depth {
                    effective_speed <- speed * 0.2;  // 80% reduction in deep water
                } else {
                    effective_speed <- speed * 0.5;  // 50% reduction in shallow water
                }
            }
            
            do goto target: target_shelter.location on: road_network speed: effective_speed;
            
            if location = target_shelter.location {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                do die;
            }
        }
    }

    aspect default {
        // Color coding: green=evacuated, red=aware, yellow=fleeing, blue=unaware
        rgb agent_color;
        if is_evacuated {
            agent_color <- #green;
        } else if is_fleeing {
            agent_color <- #yellow;  // Yellow for people fleeing from water
        } else if is_aware {
            agent_color <- #red;
        } else {
            agent_color <- #blue;
        }
        draw circle(8) color: agent_color;
    }
}

experiment flood_base_exp type: gui {
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
        }

        display "Information Spread Chart" {
            chart "Information Spread Over Time" type: series {
                data "Aware People" value: inhabitant count (each.is_aware) color: #red;
                data "Evacuated (Safe)" value: nb_evacuee color: #green;
                data "Unaware People" value: inhabitant count (!each.is_aware) color: #blue;
                data "Dead" value: nb_dead color: #black;
            }
        }

        display "Population Statistics" {
            chart "Population Distribution" type: pie {
                data "Aware (Not Evacuated)" value: (inhabitant count (each.is_aware and !each.is_evacuated)) color: #red;
                data "Evacuated (Safe)" value: nb_evacuee color: #green;
                data "Unaware" value: (inhabitant count (!each.is_aware)) color: #blue;
                data "Dead" value: nb_dead color: #black;
            }
        }

        monitor "Evacuees" value: nb_evacuee color: #green;
        monitor "Still on road" value: (inhabitant count (each.is_aware and !each.is_evacuated)) color: #orange;
        monitor "Dead" value: nb_dead color: #red;
        monitor "Cycles" value: cycle color: #blue;
        monitor "Survival rate (%)" value: (((length(inhabitant) + nb_evacuee + nb_dead) > 0) ? ((nb_evacuee + length(inhabitant)) * 100.0 / (length(inhabitant) + nb_evacuee + nb_dead)) : 0.0) with_precision 2;
        monitor "Total population" value: length(inhabitant) + nb_evacuee + nb_dead;
        monitor "Flood coverage (%)" value: ((flood_zone != nil) ? min(100.0, (flood_zone.area / shape.area * 100)) : 0.0) with_precision 2;
        monitor "Flood depth (m)" value: current_flood_depth with_precision 1 color: current_flood_depth >= dangerous_depth ? #red : #orange;
    }
}
