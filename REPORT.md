# Final Project: Evacuation – Modelling and Simulation of Complex Systems

**Report**

---

## 1. Introduction

This project addresses the modelling and simulation of population evacuation in the face of a flood or dike-breach threat. Populations in exposed areas (e.g. along rivers) are vulnerable; in the event of a levee failure or flood, evacuating residents before water arrives is critical. The goal is not to simulate the flood itself in detail, but to model **how residents behave** once they are (or are not) informed of the risk.

**Research question:** How do information spread and evacuation behaviour impact community safety during flooding events?

**Model goals:** We compare different evacuation strategies to minimise time lost in traffic and to maximise survival rates. The implementation uses the GAMA platform (GAML) with agent-based models and geographic data (shapefiles) for buildings, roads, and water.

The project consists of a **base model** (information spreading, evacuation to shelter), then **three extensions**: (1) limited knowledge of shelter location and search behaviour, (2) different mobility types (car, motorcycle, walking) and congestion, and (3) alternative strategies for choosing who is initially informed (random, furthest from shelter, closest to shelter). Batch experiments are used to study information spreading capacity, shelter knowledge ratio, and strategy efficiency.

---

## 2. Preparation

### 2.1 Data and environment

All models use shapefiles stored in `includes/flood_map` (OSM-style data):

- **building_polygon.shp** – building footprints; buildings are created with a default `height` (e.g. 10).
- **highway_line.shp** – road network; converted to a graph for pathfinding (`road_network`).
- **water_polygon.shp** – water bodies (rivers, lakes, etc.) with a `water_type` attribute (e.g. `"river"`).

The global `shape` is the envelope of the road layer and defines the simulation bounds.

### 2.2 Agents

- **Building:** Has `height`, `is_shelter`, and in base/extensions a `shelter_score` (normalised height + area). Shelters are either the single largest building by area (evac model) or the top 100 by `shelter_score` (base, ext1, ext2, ext3).
- **Road:** Line geometry; the road network is built with `as_edge_graph(road)` so that inhabitants can use `goto ... on: road_network`.
- **Water:** Polygons with `water_type`; used for placing residents near water and, in base/extensions, for flood source (e.g. river only).

### 2.3 Resident placement

Inhabitants are created in number `nb_inhabitants` (default 3000). They are placed at “home”:

- If water geometry exists, buildings and roads within 1000 m of water are selected; each agent is placed either inside a random building or on a random road in that set.
- Otherwise, placement is random in any building or on any road.

Each inhabitant stores `home` (initial location). They move only along the **road network** when evacuating or fleeing.

**Code (initialisation – base model):** loading shapefiles, building shelters, road network, placing inhabitants.

```gaml
// global init (excerpt)
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
ask shelters { self.is_shelter <- true; }

create road from: shapefile_roads;
road_network <- as_edge_graph(road);
create water from: shapefile_water with: [water_type:: read("water")];

list<geometry> water_shapes <- water collect each.shape;
geometry water_union <- empty(water_shapes) ? nil : union(water_shapes);
list<road> roads_near_water <- (water_union != nil) ? road where (each.shape distance_to water_union < 1000) : list(road);
list<building> buildings_near_water <- (water_union != nil) ? building where (each.location distance_to water_union < 1000) : list(building);

create inhabitant number: nb_inhabitants {
    // ... placement in buildings_near_water or roads_near_water ...
    home <- location;
    is_aware <- flip(0.1);  // 10% initially notified
}
```

---

## 3. Simulation Model – Base

The base model (`flood_evacuation_base` in `base.gaml`) adds flood dynamics and information spreading with evacuation to shelters.

### 3.1 Information spreading

- **Initial awareness:** Exactly **10%** of residents are initially informed (`is_aware <- flip(0.1)` at creation). They know they must evacuate and know a shelter (nearest of the top 100 shelters).
- **Spreading by observation:** Each cycle, every aware inhabitant runs the `inform` reflex. Any other inhabitant within `information_spread_distance` (20 m in base) who is not yet aware has probability `information_spread_rate` (0.1) of becoming aware. If the informer has a `target_shelter`, the newly aware agent can copy it.
- **End condition:** The simulation stops when either (1) all aware people have evacuated (or died), or (2) the flood has fully receded (`flood_zone = nil`). In the first case we have “all informed people had evacuated”.

### 3.2 Flood (base and extensions using it)

Flood is optional in the project spec; in the base and extension models it is implemented as follows:

- Flood starts at `flood_start_cycle` (e.g. 30). The flooded area `flood_zone` is built from the **river** polygons (or largest water body if no river) buffered by a radius that increases until `flood_peak_cycle` then decreases (recession).
- **Health:** Inhabitants in the flood zone lose 3 HP per cycle; at 0 HP they die (`nb_dead`). Evacuation speed is reduced when in water (e.g. 50% in shallow, 20% in deep).
- **Panic:** Uninformed agents who find themselves in the flood zone start “fleeing” (move away from flood); when they leave the water they become aware and can learn shelter from nearby aware agents.

### 3.3 Inhabitant species (base)

- **Skills:** `moving` for pathfinding on the road network.
- **Attributes:** `home`, `is_aware`, `is_evacuated`, `speed` (e.g. 10.0), `target_shelter`, `health` (100), and for base/extensions that have flood: `is_fleeing`, `flee_target`.
- **Reflexes:**
  - **inform** – spread awareness to agents within `information_spread_distance` with probability `information_spread_rate`.
  - **panic_on_flood** – if unaware and in flood zone, set `is_fleeing` and a `flee_target` away from the flood.
  - **flee_from_water** – move towards `flee_target`; when reached or out of water, set `is_aware`, try to copy `target_shelter` from nearby aware agents.
  - **evacuate** – if aware and not evacuated and (in base) `cycle >= flood_start_cycle`, set `target_shelter` to nearest shelter if needed, then `goto target_shelter.location on: road_network` with speed reduced in water. On arrival, set `is_evacuated`, increment `nb_evacuee`, and the agent is removed (`do die`).

Global parameters include `nb_inhabitants`, `information_spread_rate`, `information_spread_distance`, and flood-related variables (`flood_speed`, `flood_start_cycle`, `flood_peak_cycle`, etc.).

**Code (base – inform and evacuate reflexes):**

```gaml
// Awareness spreading: aware agents inform nearby unaware (10 m, 0.1 probability)
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

// Evacuate to shelter when aware and flood has started; speed reduced in water
reflex evacuate when: is_aware and !is_evacuated and cycle >= flood_start_cycle {
    if target_shelter = nil { target_shelter <- shelters closest_to self; }
    if target_shelter != nil {
        float effective_speed <- speed;
        if flood_zone != nil and flood_zone covers self.location {
            if current_flood_depth >= dangerous_depth { effective_speed <- speed * 0.2; }
            else { effective_speed <- speed * 0.5; }
        }
        do goto target: target_shelter.location on: road_network speed: effective_speed;
        if location = target_shelter.location {
            is_evacuated <- true;
            nb_evacuee <- nb_evacuee + 1;
            do die;
        }
    }
}
```

---

## 4. Batch Experiment – Base (Information spreading capacity)

**Objective:** See how the number of residents affects total evacuation time and the fraction of the population that evacuates, under the same initial 10% aware and same spread rules.

**Design:**

- **Population:** e.g. [1000, 2000, 5000, 10000, 20000] (configurable in the GUI; batch can use the same set).
- **Runs:** Each configuration run 3 times (e.g. `repeat: 3` in a batch experiment).
- **Time step:** In the code, `step <- 1#s` (1 second per cycle). If a batch or analysis uses 1 cycle = 10 s, that should be stated for comparison with the sample report.
- **Outputs:** Total evacuation time (cycle when simulation ends) and evacuation rate (e.g. percentage of initial population that reached a shelter, or percentage of those who were ever aware).

**Expected results (to be filled with your runs):**

| Population | Time (cycles) | Evacuation rate (%) |
| ---------- | ------------- | ------------------- |
| 1000       | …             | …                   |
| 2000       | …             | …                   |
| 5000       | …             | …                   |
| 10000      | …             | …                   |
| 20000      | …             | …                   |

_Insert your table or chart here._

**Observations:**

- The more people in the city, the higher the evacuation rate tends to be, because there are more opportunities for observation-based spreading.
- Evacuation rate can be seen as a function of initial conditions: `evacuation_rate = f(aware_rate, spreading_rate, total_citizen)`, suggesting a “golden rate” of initial awareness to approach full evacuation.
- Total time to complete evacuation often remains relatively stable across populations, suggesting a “golden period” for the given city and parameters (e.g. on the order of tens of minutes if 1 cycle = 10 s).

---

## 5. Extension 1 – Evacuation behaviour (limited shelter knowledge)

In Extension 1 (`flood_evacuation_ext1` in `extension1.gaml`), not all aware residents know where the shelter is.

### 5.1 Rules

- Among the **10%** who are initially aware, only **10% of those** (i.e. 1% of the population) know the shelter location and go **directly** to it. The remaining 90% of aware agents do **not** know the shelter; they move to **random non-shelter buildings** to “search”.
- When an agent who is searching gets within **20 m** of any shelter (`shelter_detection_distance`), they switch to moving **directly** to that shelter.
- Awareness spreading is unchanged (e.g. 10 m, 0.1); when a new agent becomes aware, they have probability 0.1 of knowing the shelter; if not, they get a random `search_target` building.

### 5.2 Inhabitant (additions)

- **Attributes:** `knows_shelter_location`, `search_target` (a point, e.g. `any_location_in(rand_b)` for a random non-shelter building).
- **Behaviour in evacuate:**
  - If `knows_shelter_location` or distance to `target_shelter` &lt; `shelter_detection_distance` (20 m): move to shelter; on arrival, evacuate and remove.
  - Else: move to `search_target`; when within ~5 m of it, draw a new random non-shelter building as `search_target`. If at any time distance to shelter &lt; 20 m, switch to direct movement.

Implementation detail: if `search_target` is nil (e.g. no non-shelter building), the code assigns a new random building so that searching agents always have a target.

### 5.3 Parameters

- `shelter_detection_distance <- 20.0` (metres).
- Shelter knowledge among the initially aware: `knows_shelter_location <- is_aware ? flip(0.1) : false` in init; when spreading, newly aware get `flip(0.1)` for knowledge and, if not knowing, a random `search_target`.

**Code (Extension 1 – init: shelter knowledge and search_target):**

```gaml
knows_shelter_location <- is_aware ? flip(0.1) : false;
if is_aware and !knows_shelter_location {
    building rand_b <- one_of(building where (!each.is_shelter));
    if rand_b != nil { search_target <- any_location_in(rand_b); }
}
```

**Code (Extension 1 – evacuate: direct vs search, &lt; 20 m switch):**

```gaml
float distance_to_shelter <- location distance_to target_shelter.location;

if knows_shelter_location or distance_to_shelter < shelter_detection_distance {
    do goto target: target_shelter.location on: road_network speed: effective_speed;
    if location = target_shelter.location {
        is_evacuated <- true;
        nb_evacuee <- nb_evacuee + 1;
        do die;
    }
} else {
    if search_target = nil {
        building rand_b <- one_of(building where (!each.is_shelter));
        if rand_b != nil { search_target <- any_location_in(rand_b); }
    }
    if search_target != nil {
        do goto target: search_target on: road_network speed: effective_speed;
        if location distance_to search_target < 5.0 {
            building rand_b <- one_of(building where (!each.is_shelter));
            if rand_b != nil { search_target <- any_location_in(rand_b); }
        }
    }
}
```

---

## 6. Batch Experiment – Extension 1

**Question:** How does limited knowledge of shelter location affect evacuation efficiency (evacuation rate, share still aware but not evacuated, “possible to save”)?

**Design:**

- **Population:** Fixed (e.g. 1000).
- **Evacuation window:** e.g. 30 minutes before flood or as time limit; in cycles, e.g. 180 if 1 cycle = 10 s.
- **Shelter knowledge ratio:** Among the initially aware, the fraction who know the shelter can be varied (e.g. 0.1, 0.3, 0.5, 0.7, 1). In the current code this is fixed at 0.1; to vary it, the `flip(0.1)` would be replaced by a parameter (e.g. `flip(shelter_knowledge_ratio)`).
- **Outputs:** For each ratio: % Evacuated, % Aware (Not Evacuated), % Possible to save (e.g. evacuated + still alive and aware but not yet at shelter, or as defined in the report).

**Expected results (to be filled with your runs):**

| Shelter knowledge ratio | % Evacuated | % Aware (Not Evacuated) | % Possible to save |
| ----------------------- | ----------- | ----------------------- | ------------------ |
| 0.1                     | …           | …                       | …                  |
| 0.3                     | …           | …                       | …                  |
| …                       | …           | …                       | …                  |

**Observations:**

- Higher shelter knowledge ratio generally increases the evacuation rate and reduces the share “Aware (Not Evacuated)”.
- Evacuation rate tends to saturate when knowledge rate is above about 0.7 (“good knowledge ratio”).
- When not everyone knows the shelter (e.g. ratio &lt; 1), some aware people may not reach the shelter in time but may still find other solutions (e.g. high ground); the “saved” rate can differ from the “evacuated to shelter” rate.

---

## 7. Extension 2 – Transportation (mobility types and congestion)

In Extension 2 (`flood_evacuation_ext2` in `extension2.gaml`), residents have different mobility types and are affected by traffic density.

### 7.1 Mobility model

- **Car (20%):** `speed_factor <- 1.0`, `congestion_factor <- 1.0` – fastest on an open road, most affected by congestion.
- **Motorcycle (70%):** `speed_factor <- 0.85`, `congestion_factor <- 0.5` – slightly slower than car, half as affected by congestion.
- **Walking (10%):** `speed_factor <- 0.1`, `congestion_factor <- 0.2` – slowest, five times less affected by congestion.

Assignment at creation: `rnd(0.0, 1.0)`; if `r < 0.2` then car, else if `r < 0.9` then motorcycle, else walking.

### 7.2 Effective speed and traffic density

- **Effective speed** on the current road segment:  
  `effective_speed = base_speed * speed_factor * max(0.1, 1.0 - congestion_factor * traffic_density)`.  
  Implemented as `get_effective_speed(current_road)` using global `base_speed` (e.g. 10.0) and the road’s `traffic_density`.
- **Traffic density:** Each cycle (when `cycle >= flood_start_cycle`), for each road segment the number of inhabitants within 15 m of that segment is counted; density per road is then normalised (e.g. divided by 20 and capped at 1.0). So `map<road, float> traffic_density` is updated in the global `update_traffic` reflex.

### 7.3 Inhabitant (additions)

- **Attributes:** `mobility_type` (string), `speed_factor`, `congestion_factor`.
- **Behaviour:** In `evacuate` and `flee_from_water`, speed is set by `get_effective_speed(road closest_to self)` instead of a constant. Flood depth still reduces speed when in water.

Bottlenecks (e.g. intersections, central roads) emerge naturally where many agents share the same segments and density is high; cars slow down most, pedestrians least.

**Code (Extension 2 – mobility assignment at creation):**

```gaml
float r <- rnd(0.0, 1.0);
if r < 0.2 {
    mobility_type <- "car";
    speed_factor <- 1.0;
    congestion_factor <- 1.0;
} else if r < 0.9 {
    mobility_type <- "motorcycle";
    speed_factor <- 0.85;
    congestion_factor <- 0.5;
} else {
    mobility_type <- "walking";
    speed_factor <- 0.1;
    congestion_factor <- 0.2;
}
```

**Code (Extension 2 – effective speed and traffic update):**

```gaml
// In inhabitant species
float get_effective_speed(road current_road) {
    float density <- (current_road != nil and traffic_density contains current_road) ? traffic_density[current_road] : 0.0;
    float congestion_penalty <- 1.0 - (congestion_factor * density);
    return base_speed * speed_factor * max(0.1, congestion_penalty);
}

// In global – update_traffic reflex (when cycle >= flood_start_cycle)
traffic_density <- road as_map (each::0.0);
ask inhabitant {
    road r <- road closest_to self;
    if r != nil and (self.location distance_to r.shape < 15.0) {
        traffic_density[r] <- traffic_density[r] + 1;
    }
}
ask road { traffic_density[self] <- min(1.0, traffic_density[self] / 20.0); }
```

---

## 8. Extension 3 – Awareness strategies

In Extension 3 (`flood_evacuation_ext3` in `extension3.gaml`), the initial 10% who are aware are chosen by strategy instead of at random.

### 8.1 Strategies

- **Random:** `shuffle(inhabitant)` then take the first 10% (`first(n_aware, shuffle(inhabitant))`).
- **Furthest:** Sort inhabitants by **descending** distance to `main_shelter` and take the first 10% (`inhabitant sort_by (-(each.location distance_to main_shelter.location))`).
- **Closest:** Sort by **ascending** distance to `main_shelter` and take the first 10%.

The reference shelter `main_shelter` is `shelters[0]` (first of the top 100 by `shelter_score`). All inhabitants are created with `is_aware <- false`; then `n_aware <- max(1, int(awareness_fraction * length(inhabitant)))` and the appropriate list is built and set to `is_aware <- true`.

### 8.2 Efficiency metric

- **evacuation_end_cycle:** Cycle at which the simulation ends (all informed evacuated or flood receded).
- **person_cycles_on_road:** Each cycle, add the number of agents who are aware and not yet evacuated (`inhabitant count (each.is_aware and !each.is_evacuated)`). This is the total “person-cycles” spent on the road.
- **efficiency_ratio:** When `nb_evacuee > 0` and `person_cycles_on_road > 0`,  
  `avg_time_on_road = person_cycles_on_road / nb_evacuee`,  
  `efficiency_ratio = evacuation_end_cycle / avg_time_on_road`.  
  Higher efficiency means the evacuation finishes in fewer cycles relative to the average time each evacuee spent on the road.

**Code (Extension 3 – choosing initial 10% aware by strategy):**

```gaml
// After creating all inhabitants with is_aware <- false
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
```

**Code (Extension 3 – metrics: person_cycles_on_road and efficiency_ratio):**

```gaml
// Each cycle
reflex accumulate_metrics when: !simulation_finished {
    person_cycles_on_road <- person_cycles_on_road + (inhabitant count (each.is_aware and !each.is_evacuated));
}

// When simulation ends (in check_end)
evacuation_end_cycle <- cycle;
if nb_evacuee > 0 and person_cycles_on_road > 0 {
    float avg_time_on_road <- person_cycles_on_road / float(nb_evacuee);
    efficiency_ratio <- evacuation_end_cycle / avg_time_on_road;
}
```

---

## 9. Batch Experiment – Extension 3

**Question:** Which strategy (random, furthest, closest) is most efficient, and how do they compare in terms of evacuation rate and awareness rate?

**Design:**

- **Strategies:** `["random", "furthest", "closest"]`.
- **Population:** e.g. 1000 (and optionally 2000, 3000).
- **Alert time:** e.g. `flood_start_cycle` = 10, 30, 50, 80 (cycles before flood starts, or as evacuation window).
- **Runs:** e.g. 3 or 5 per configuration. Batch experiment `flood_ext3_batch` uses `repeat: 3` and varies strategy, `nb_inhabitants`, and `flood_start_cycle`.

**Outputs:** Strategy, population, alert time, nb_evacuee, evacuation_end_cycle, person_cycles_on_road, efficiency_ratio, nb_dead.

**Expected results (to be filled with your runs):**

| Strategy | Population | Alert time | Evacuees | Evacuation end cycle | Person-cycles on road | Efficiency | Dead |
| -------- | ---------- | ---------- | -------- | -------------------- | --------------------- | ---------- | ---- |
| random   | 1000       | 30         | …        | …                    | …                     | …          | …    |
| furthest | 1000       | 30         | …        | …                    | …                     | …          | …    |
| closest  | 1000       | 30         | …        | …                    | …                     | …          | …    |

**Observations (typical):**

- **Closest:** Often highest efficiency (evacuation ends quickly relative to time on road); lowest “awareness rate” in the sense that only people already near the shelter are informed, so information spreads less.
- **Furthest:** Highest awareness spread (information starts from those farthest); evacuation rate can be slightly lower and take longer because those people have farther to go.
- **Random:** Balanced awareness and evacuation rate.  
  Choice of strategy should depend on the objective: maximising information spread, minimising time on roads, or maximising the number of evacuees.

---

## 10. Conclusion

- **Golden period:** For a given city and parameters, a “golden period” of evacuation can be identified in which the evacuation rate is maximised; planning should aim to complete evacuation within this window.
- **Parameter optimisation:** Evacuation rate and efficiency can be expressed as functions of initial parameters (initial aware rate, shelter knowledge ratio, population, alert time). This allows optimisation of policies (e.g. best shelter knowledge ratio under time limits).
- **Bottlenecks:** The simulation (especially with Extension 2) identifies road segments and intersections prone to congestion, which is useful for traffic management and infrastructure planning during evacuation.
- **Information strategy:** The way the initial 10% informed are chosen (random, furthest, or closest to the shelter) significantly affects both time efficiency and evacuation rate. This should be considered when designing evacuation alerts and communication strategies.

---

## 11. References and code

- **GAMA platform:** [gama-platform.org](https://gama-platform.org) – agent-based modelling and simulation.
- **Shapefiles:** OSM-style data in `includes/flood_map` (building_polygon, highway_line, water_polygon).
- **Model files:**
  - `evac.gaml` – minimal evacuation model (no flood; single shelter; 10% aware, 10 m, 0.1 observation).
  - `base.gaml` – flood evacuation base (information spreading, flood, health, panic, shelters).
  - `extension1.gaml` – limited shelter knowledge, search behaviour, 20 m direct-to-shelter.
  - `extension2.gaml` – car / motorcycle / walking, traffic density, effective speed.
  - `extension3.gaml` – awareness strategies (random, furthest, closest), efficiency metrics, batch exploration.

---

_End of report. Fill in the result tables with your own batch run data and add figures (screenshots, charts) where indicated._
