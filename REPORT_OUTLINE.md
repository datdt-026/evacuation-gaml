# Outline – Project 4: Evacuation Simulation Report

_(Based on the structure of the sample report [LE_CHI_THANH] Project 4_ Evacuation)\_

---

## 1. Title & Introduction (1 page)

- **Title:** Final Project: Evacuation – Modelling and Simulation of Complex Systems
- **Suggested content:**
  - Brief context: simulating population evacuation in a flood / dike-breach scenario.
  - Research question: _How do information spread and evacuation behaviour impact community safety during flooding events?_
  - Model goals: compare evacuation strategies to minimise time lost in traffic and maximise survival rates.

---

## 2. Preparation (1–2 pages)

- **Purpose:** Describe the preparation and initialisation of the model.
- **Suggested content:**
  - Data sources: shapefiles (buildings, roads, rivers/water).
  - Agents: building, road, water (rivers).
  - Initialisation rules:
    - Highest / largest building(s) (or top shelters) as evacuation shelter(s).
    - Residents placed at home (in buildings) and move on the road network.
  - Optional: 1–2 figures (map, road network, shelter location).

---

## 3. Simulation Model – Base (2–3 pages)

- **Information spreading:**
  - Initially 10% of residents are informed (chosen randomly).
  - Informed agents know they must evacuate and know the shelter location.
  - Spreading: observing others evacuating (10 m radius, 0.1 probability).
  - End condition: when all informed people have evacuated (or died / flood receded).
- **Inhabitant species:**
  - Inherits `moving` skill.
  - Attributes: `is_aware`, `is_evacuated`, `home`, `speed` (and optionally `health` if flood is modelled).
  - Behaviours: `evacuate` (move to shelter), `inform` (spread awareness with 0.1 probability to agents within 10 m).
- **Global:**
  - Parameters: population size, spread radius/probability, flood (if any), shelter(s).
- **Figure/table:** State machine diagram or table summarising attributes and behaviours.

---

## 4. Batch Experiment – Base (Information spreading capacity) (1–2 pages)

- **Design:**
  - Population: [1000, 2000, 5000, 10000, 20000] (or similar).
  - Each configuration run 3 times (repeat: 3).
  - 1 cycle = 10 s (or 1 s depending on your model).
- **Results to report:**
  - Table or chart: population → total evacuation time (cycles), evacuation rate (%).
- **Observations:**
  - Larger population → higher evacuation rate (due to information spreading).
  - Evacuation rate depends on initial conditions (aware rate, spreading rate, population) → suggests a “golden rate” of awareness.
  - Total evacuation time remains relatively stable → suggests a “golden period” for a given city (e.g. ~29 minutes).
  - Conceptual relation: `evacuation_rate = f(aware_rate, spreading_rate, total_citizen)`.

---

## 5. Extension 1 – Evacuation behaviour (2–3 pages)

- **Rules:**
  - Only 10% of aware residents know the shelter location and go directly there.
  - The remaining 90% move to random buildings to “search” for the shelter.
  - When distance to shelter < 20 m → switch to moving directly to the shelter.
- **Inhabitant (additions):**
  - Attributes: `knows_shelter_location`, `search_target` (current search building/point).
  - Behaviour: if knows shelter → goto shelter; else → goto random building; if < 20 m from shelter → goto shelter.
- **Figure:** Logic diagram or simulation snapshot (direct vs searching behaviour).

---

## 6. Batch Experiment – Extension 1 (1–2 pages)

- **Question:** How does limited knowledge of shelter location affect evacuation efficiency?
- **Design:**
  - Fixed population (e.g. 1000), limited evacuation time (e.g. 30 min = 180 cycles if 1 cycle = 10 s).
  - Shelter knowledge ratio: 0.1, 0.3, 0.5, 0.7, 1.
- **Results:**
  - Table or chart: knowledge ratio → % Evacuated, % Aware (Not Evacuated), % Possible to save.
- **Observations:**
  - Higher knowledge ratio → higher evacuation rate, lower Aware (Not Evacuated).
  - Evacuation rate saturates when knowledge rate > 0.7 → “good knowledge ratio”.
  - Compare with knowledge = 1: aware people who do not reach the shelter may find other solutions → “saved” rate can differ.

---

## 7. Extension 2 – Transportation (2–3 pages)

- **Mobility model:**
  - **Car (20%):** fastest, most affected by congestion (factor 1.0).
  - **Motorcycle (70%):** slightly slower (0.85), less affected by congestion (factor 0.5).
  - **Walking (10%):** slowest (0.1), least affected by congestion (factor 0.2).
- **Inhabitant (additions):**
  - `mobility_type`, `speed_factor`, `congestion_factor` (or `traffic_factor`).
  - Effective speed: depends on traffic density on the road segment (e.g. `effective_speed = base_speed * speed_factor * (1 - congestion_factor * density)`).
- **Global / Road:**
  - Update traffic density from the number of agents on (or near) each road segment.
- **Figure:** Map showing bottlenecks (intersections, central segments) or traffic density plot.

---

## 8. Extension 3 – Awareness strategies (2–3 pages)

- **Three strategies for choosing the initial 10% aware:**
  - **Random:** chosen randomly.
  - **Furthest:** 10% furthest from the shelter.
  - **Closest:** 10% closest to the shelter.
- **Efficiency metric:**
  - `efficiency = time for total evacuation / time spent on the roads`
  - (In code: e.g. `evacuation_end_cycle` and `person_cycles_on_road`; efficiency as ratio or quotient depending on definition.)
  - Higher efficiency = better.
- **Initialisation:** Short description of how “shelter” is defined (single building or list) and how inhabitants are sorted by distance for furthest/closest.
- **Figure (optional):** Comparison of the three strategies on the same map or chart.

---

## 9. Batch Experiment – Extension 3 (1–2 pages)

- **Question:** Which strategy is most efficient?
- **Design:**
  - Strategy: [random, furthest, closest].
  - Initial population (e.g. 1000) and alert time (time before flood, e.g. 30 min = 180 cycles).
  - Each configuration run 5 times (or 3).
- **Results:**
  - Table: strategy → efficiency, evacuation rate, awareness rate (%), evacuation time.
- **Observations (as in sample report):**
  - **Closest:** highest efficiency but lowest awareness rate (e.g. 1%).
  - **Furthest:** highest awareness rate, slightly lower evacuation rate (e.g. 7.8%).
  - **Random:** more balanced awareness and evacuation rates.
  - Short conclusion: choice of strategy depends on the objective (information spread vs. time on roads vs. evacuation rate).

---

## 10. Conclusion (1 page)

- **Golden period:** A “golden period” for evacuating a city can be identified; evacuation rate is maximised within this window.
- **Parameter optimisation:** Metrics (evacuation rate, efficiency) can be expressed as functions of initial parameters → optimisation is possible (e.g. `known_shelter_location_rate`).
- **Bottlenecks:** The simulation helps identify road segments and intersections prone to congestion → useful for traffic management during evacuation.
- **Information strategy:** How initial evacuation information is spread (random / furthest / closest) affects time efficiency and evacuation rate → should be considered when making evacuation decisions.

---

## 11. References & Appendix (optional)

- GAMA documentation, shapefiles (OSM, map sources).
- Code/model: reference main `.gaml` files (base, extensions 1–3, batch) in appendix or repository link.

---

## Quick checklist when writing

- [ ] Each section has 1–2 opening sentences (context).
- [ ] Each model/extension includes: rules (bullets), agent attributes, behaviours (reflex/action).
- [ ] Each batch experiment includes: question, parameters, table/chart, 2–4 observation points.
- [ ] Units and numbers are consistent (cycle, seconds, minutes; % evacuee, % aware).
- [ ] Figures have captions and are referred to in the text.
