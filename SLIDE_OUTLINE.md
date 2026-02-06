# Slide Outline – Evacuation Simulation (20 slides)

_Readable content for reading directly from slides_

---

## Slide 1 — Title

- **Final Project: Evacuation**
- Modelling and Simulation of Complex Systems
- _(Optional: your name, date)_

---

## Slide 2 — Simulation goals

- **Research question:** How do information spread and evacuation behaviour impact community safety during flooding events?
- **Model focus:** Compare evacuation strategies to minimise time lost in traffic and maximise survival rates. We use an agent-based model in GAMA with shapefile data (buildings, roads, water).

---

## Slide 3 — Preparation

- **Data:** Shapefiles from flood_map (building polygons, highways, water). We create **building**, **road**, and **water** agents. Largest/highest-scoring buildings → **shelters**.
- **Residents:** Placed at **home** (in buildings or on roads near water). They move only on the **road network** when evacuating.
- _Use a map or screenshot of the environment._

---

## Slide 4 — Base model: information spreading

- **Who is informed:** Initially **10%** of residents (chosen randomly). They know the shelter.
- **How it spreads:** Uninformed agents who observe someone evacuating within **10 m** have **0.1 probability** of becoming aware. Simulation ends when all informed have evacuated (or flood receded).
- **Inhabitant:** Active agent with `moving` skill. **Attributes:** `is_aware`, `is_evacuated`, `home`, `speed`. **Actions:** **evacuate** (to shelter on road network), **inform** (spread awareness within 10 m, 10% probability each cycle).

---

## Slide 5 — Base: screenshot

- **Simulation Model – Base**
- _Screenshot: map with buildings, roads, water; agents (e.g. blue = unaware, red = aware, green = evacuated)._

---

## Slide 6 — Batch experiment – Base

- **Information spreading capacity:** Population [1000, 2000, 5000, 10000, 20000], each **3 runs**. Record total evacuation time (cycles) and evacuation rate (%).
- _Table or chart:_ Population → Time (cycles), Evacuation rate (%).
- **Observations:** More people → higher evacuation rate. Evacuation rate = f(aware rate, spreading rate, population) → **“golden rate”**. Total time stable → **“golden period”** (e.g. ~29 min). **evacuation_rate = f(aware_rate, spreading_rate, total_citizen)**.

---

## Slide 7 — Extension 1 (section)

- Extension 1 – Evacuation behaviour

---

## Slide 8 — Extension 1: behaviour & batch

- **Behaviour:** Only **10% of the 10% aware** know the shelter and go **directly** there. The rest move to **random buildings** to search. If **distance to shelter < 20 m** → go directly. New attributes: `knows_shelter_location`, `search_target`.
- **Batch:** Population 1000, 30 min window. Shelter knowledge ratio 0.1–1. _Table:_ % Evacuated, % Aware (Not Evacuated), % Possible to save. Higher knowledge → higher evacuate rate; saturates above 0.7 (“good knowledge ratio”).

---

## Slide 9 — Extension 2 (section)

- Extension 2 – Transportation

---

## Slide 10 — Extension 2: transport & bottlenecks

- **Car (20%):** fastest, most affected by congestion (1.0). **Motorcycle (70%):** slower (0.85), half as affected (0.5). **Walking (10%):** slowest (0.1), least affected (0.2).
- **Effective speed** = base_speed × speed_factor × (1 − congestion_factor × traffic_density). Traffic density per road segment updated each cycle.
- **Bottlenecks:** Intersections and central roads. _Screenshot: map with density or congestion._

---

## Slide 11 — Extension 3 (section)

- Extension 3 – Awareness strategies

---

## Slide 12 — Extension 3: strategies & efficiency

- **Strategies for initial 10% aware:** **Random** (random on map), **Furthest** (10% furthest from shelter), **Closest** (10% closest). Sort inhabitants by distance to main shelter; select top/bottom 10%.
- **Efficiency** = time for total evacuation / time spent on roads (higher = better). Metrics: evacuation_end_cycle, person_cycles_on_road, efficiency ratio.

---

## Slide 13 — Batch – Extension 3

- **Which strategy is most efficient?** Each strategy run several times (e.g. 5). Population 1000, alert time 30 min. _Table:_ Strategy → Efficiency, Evacuation rate (%), Awareness rate (%).
- **Findings:** **Closest** — highest efficiency, lowest awareness (~1%). **Furthest** — highest awareness, slightly lower evacuation (~7.8%). **Random** — balanced. Best strategy depends on goal (information spread vs time on roads vs evacuation rate).

---

## Slide 14 — Conclusion (section)

- Conclusion

---

## Slide 15 — Conclusion: takeaway points

- **Golden period:** Time window where evacuation rate is maximised; plan to finish within it.
- **Parameter optimisation:** Evacuation rate and efficiency as functions of initial parameters → optimise (e.g. shelter knowledge rate).
- **Bottlenecks:** Simulation identifies congestion-prone segments → useful for traffic management.
- **Information strategy:** Choice of initial 10% (random / furthest / closest) affects efficiency and evacuation rate → important for evacuation alerts.

---

## Slide 16 — Summary (optional)

- **Summary:** Base (10% aware, 10 m / 0.1 spread) → Ext1 (shelter knowledge, search) → Ext2 (car/motorcycle/walking, congestion) → Ext3 (random/furthest/closest strategies). Batch experiments compare population, knowledge ratio, and strategy.

---

## Slide 17 — References (optional)

- GAMA platform, shapefiles (OSM / flood_map). Model files: base.gaml, extension1.gaml, extension2.gaml, extension3.gaml, evac.gaml.

---

## Slide 18 — (Reserve)

- _Backup slide or extra figure._

---

## Slide 19 — (Reserve)

- _Backup slide or extra figure._

---

## Slide 20 — Thank you / Q&A

- **Thank you**
- Questions?
