/**
 * Flood Evacuation Simulation - Extension 3
 * Based on: Flood Evacuation Simulation (base)
 *
 * Extension 3: Awareness strategies
 * - The 10% initially aware are no longer random, but chosen by strategy:
 *   - random: 10% chosen randomly
 *   - furthest: 10% who are furthest from the shelter
 *   - closest: 10% who are closest to the shelter
 * - Compare strategies: number of evacuees, evacuation time, time on roads.
 * - Batch exploration: which strategy is most efficient (evacuation time, time on roads)
 *   depending on initial population and alert time (cycles before flood).
 */

model flood_evacuation_ext3

global {
    string map_folder <- "../includes/flood_map";

    shape_file shapefile_buildings <- shape_file(map_folder + "/building_polygon.shp");
    shape_file shapefile_roads <- shape_file(map_folder + "/highway_line.shp");
    shape_file shapefile_water <- shape_file(map_folder + "/water_polygon.shp");
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    float step <- 1#s;

    list<building> shelters;
    building main_shelter;  // Reference shelter for distance-based strategies
    int nb_evacuee <- 0;
    int nb_dead <- 0;
    bool simulation_finished <- false;

    float flood_speed <- 2.0;
    int flood_start_cycle <- 30;   // Alert time: cycles before flood (evacuation window)
    int flood_peak_cycle <- 500;
    float flood_recession_speed <- 2.0;
    geometry flood_zone;
    float max_flood_radius <- 0.0;
    float max_flood_depth <- 5.0;
    float current_flood_depth <- 0.0;
    float dangerous_depth <- 3.0;

    float information_spread_rate <- 0.1;
    float information_spread_distance <- 20.0;
    int nb_inhabitants <- 3000;
    float awareness_fraction <- 0.1;  // 10% initially aware

    // Extension 3: strategy for choosing initial 10% aware
    string awareness_strategy <- "random";  // "random", "furthest", "closest"

    // Metrics for comparison
    int evacuation_end_cycle <- 0;           // Cycle when all informed have evacuated
    int person_cycles_on_road <- 0;         // Sum over cycles of (aware and not evacuated)
    float efficiency_ratio <- 0.0;           // evacuation_time / avg_time_on_road per evacuee

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
        main_shelter <- shelters[0];
        ask shelters { self.is_shelter <- true; }

        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        create water from: shapefile_water with: [water_type:: read("water")];

        list<geometry> water_shapes <- water collect each.shape;
        geometry water_union <- empty(water_shapes) ? nil : union(water_shapes);
        list<road> roads_near_water <- (water_union != nil) ? road where (each.shape distance_to water_union < 1000) : list(road);
        list<building> buildings_near_water <- (water_union != nil) ? building where (each.location distance_to water_union < 1000) : list(building);

        // Create all inhabitants with is_aware <- false first
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
            is_aware <- false;
        }

        // Extension 3: choose 10% to be aware according to strategy
        int n_aware <- max(1, int(awareness_fraction * length(inhabitant)));
        list<inhabitant> to_make_aware;

        if awareness_strategy = "random" {
            to_make_aware <- first(n_aware, shuffle(inhabitant));
        } else if awareness_strategy = "furthest" and main_shelter != nil {
            to_make_aware <- first(n_aware, inhabitant sort_by (-(each.location distance_to main_shelter.location)));
        } else if awareness_strategy = "closest" and main_shelter != nil {
            to_make_aware <- first(n_aware, inhabitant sort_by (each.location distance_to main_shelter.location));
        } else {
            to_make_aware <- first(n_aware, shuffle(inhabitant));
        }

        ask to_make_aware { is_aware <- true; }
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
            current_flood_depth <- (max_flood_radius > 0 ? (radius / max_flood_radius) * max_flood_depth : 0.0);
        }
        list<geometry> river_shapes <- (water where (each.water_type = "river")) collect each.shape;
        geometry flood_source <- empty(river_shapes) ? nil : union(river_shapes);
        if flood_source = nil {
            water biggest <- water with_max_of (each.shape.area);
            flood_source <- (biggest != nil) ? biggest.shape : (shape.centroid + 1.0);
        }
        flood_zone <- radius > 0 and flood_source != nil ? (flood_source + radius) : nil;

        ask inhabitant {
            if flood_zone != nil and flood_zone covers self.location and !self.is_evacuated {
                self.health <- self.health - 3;
                if self.health <= 0 {
                    nb_dead <- nb_dead + 1;
                    do die;
                }
            }
        }
    }

    reflex accumulate_metrics when: !simulation_finished {
        person_cycles_on_road <- person_cycles_on_road + (inhabitant count (each.is_aware and !each.is_evacuated));
    }

    reflex check_end when: !simulation_finished {
        bool all_aware_evacuated <- empty(inhabitant) or inhabitant all_match (each.is_evacuated or !each.is_aware);
        bool flood_receded <- cycle > flood_start_cycle and flood_zone = nil;

        if all_aware_evacuated or flood_receded {
            simulation_finished <- true;
            evacuation_end_cycle <- cycle;
            int still_on_road <- inhabitant count (each.is_aware and !each.is_evacuated);
            int total <- nb_evacuee + nb_dead + length(inhabitant);
            int survivors <- nb_evacuee + length(inhabitant);
            float survival_rate <- (total > 0 ? (survivors * 100.0 / total) : 0.0);

            if nb_evacuee > 0 and person_cycles_on_road > 0 {
                float avg_time_on_road <- person_cycles_on_road / float(nb_evacuee);
                efficiency_ratio <- evacuation_end_cycle / avg_time_on_road;
            }

            write "========== EXTENSION 3 - SIMULATION RESULTS ==========";
            write "  Strategy: " + awareness_strategy;
            write "  nb_inhabitants: " + nb_inhabitants + "  alert_time (flood_start_cycle): " + flood_start_cycle;
            write "  Total evacuees: " + nb_evacuee;
            write "  Evacuation end cycle (total time): " + evacuation_end_cycle;
            write "  Person-cycles on road: " + person_cycles_on_road;
            write "  Efficiency (evac_time/avg_time_on_road): " + efficiency_ratio;
            write "  Dead: " + nb_dead + "  Survival rate: " + survival_rate + "%";
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
        if is_shelter { building_color <- rgb(255, 100, 0); }
        else {
            float height_ratio <- height / 50.0;
            building_color <- rgb(int(255 - min(100, height_ratio * 100)), int(220 - min(120, height_ratio * 120)), 150);
        }
        draw shape color: building_color border: rgb(80, 80, 80) depth: height;
    }
}

species road {
    aspect default { draw shape color: #black; }
}

species water {
    string water_type <- "";
    aspect default { draw shape color: rgb(100, 150, 255) border: rgb(50, 100, 200); }
}

species inhabitant skills: [moving] {
    point home;
    bool is_aware <- false;
    bool is_evacuated <- false;
    bool is_fleeing <- false;
    float speed <- 10.0;
    int health <- 100;
    building target_shelter;
    point flee_target;

    reflex inform when: is_aware {
        ask inhabitant at_distance information_spread_distance {
            if !self.is_aware and flip(information_spread_rate) {
                self.is_aware <- true;
                if myself.target_shelter != nil and self.target_shelter = nil {
                    self.target_shelter <- myself.target_shelter;
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
                list<inhabitant> nearby_aware <- inhabitant at_distance (information_spread_distance * 2) where (each.is_aware and each.target_shelter != nil);
                if !empty(nearby_aware) {
                    target_shelter <- (nearby_aware closest_to self).target_shelter;
                }
            }
        }
    }

    reflex evacuate when: is_aware and !is_evacuated and cycle >= flood_start_cycle {
        if target_shelter = nil { target_shelter <- shelters closest_to self; }
        if target_shelter != nil {
            float effective_speed <- speed;
            if flood_zone != nil and flood_zone covers self.location {
                effective_speed <- current_flood_depth >= dangerous_depth ? speed * 0.2 : speed * 0.5;
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
        rgb agent_color;
        if is_evacuated { agent_color <- #green; }
        else if is_fleeing { agent_color <- #yellow; }
        else if is_aware { agent_color <- #red; }
        else { agent_color <- #blue; }
        draw circle(8) color: agent_color;
    }
}

experiment flood_ext3_exp type: gui {
    parameter "Population" var: nb_inhabitants category: "Initialization" min: 500 max: 10000;
    parameter "Awareness strategy" var: awareness_strategy category: "Extension 3" among: ["random", "furthest", "closest"];
    parameter "Alert time (cycles before flood)" var: flood_start_cycle category: "Flood" min: 5 max: 200;
    parameter "Flood speed (m/cycle)" var: flood_speed category: "Flood" min: 1 max: 500;
    parameter "Flood peak cycle" var: flood_peak_cycle category: "Flood" min: 50 max: 1000;
    parameter "Information spread rate" var: information_spread_rate category: "Information" min: 0.0 max: 1.0;

    output {
        display map type: 3d {
            species water;
            graphics "Flooded area" {
                if flood_zone != nil { draw flood_zone color: rgb(0, 100, 200) border: rgb(0, 50, 150); }
            }
            species road;
            species building;
            species inhabitant;
        }
        display "Charts" {
            chart "Aware / Evacuated / Unaware" type: series {
                data "Aware" value: inhabitant count (each.is_aware) color: #red;
                data "Evacuated" value: nb_evacuee color: #green;
                data "Unaware" value: inhabitant count (!each.is_aware) color: #blue;
                data "Dead" value: nb_dead color: #black;
            }
        }
        monitor "Strategy" value: awareness_strategy color: #purple;
        monitor "Evacuees" value: nb_evacuee color: #green;
        monitor "Evacuation end cycle" value: evacuation_end_cycle color: #orange;
        monitor "Person-cycles on road" value: person_cycles_on_road color: #gray;
        monitor "Dead" value: nb_dead color: #red;
        monitor "Cycle" value: cycle color: #blue;
    }
}

/**
 * Batch exploration: compare strategies (random, furthest, closest) on:
 * - number of evacuees
 * - evacuation time (cycle when all informed have evacuated)
 * - time on roads (person-cycles)
 * - efficiency (evacuation_time / avg_time_on_road per evacuee)
 * Vary: initial population, alert time (cycles before flood).
 */
experiment flood_ext3_batch type: batch repeat: 3 keep_seed: true {
    parameter "Awareness strategy" var: awareness_strategy among: ["random", "furthest", "closest"];
    parameter "Population" var: nb_inhabitants among: [1000, 2000, 3000];
    parameter "Alert time (cycles before flood)" var: flood_start_cycle among: [10, 30, 50, 80];

    output {
        monitor "Strategy" value: awareness_strategy;
        monitor "Population" value: nb_inhabitants;
        monitor "Alert time" value: flood_start_cycle;
        monitor "Evacuees" value: nb_evacuee;
        monitor "Evacuation end cycle" value: evacuation_end_cycle;
        monitor "Person-cycles on road" value: person_cycles_on_road;
        monitor "Efficiency (evac_time/avg_time_on_road)" value: efficiency_ratio;
        monitor "Dead" value: nb_dead;
    }
}
