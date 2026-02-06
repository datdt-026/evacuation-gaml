# Slide Outline – Evacuation Simulation Presentation

_~27 slides | Longer, readable content for reading directly from slides_

---

## Slide 1 — Title

- **Final Project: Evacuation**
- Modelling and Simulation of Complex Systems
- _(Optional: your name, date)_

---

## Slide 2 — Simulation goals

- **Research question:** How do information spread and evacuation behaviour impact community safety during flooding events?
- **Model focus:** We compare different evacuation strategies to minimise time lost in traffic jams and to maximise survival rates.
- The project uses an agent-based model in GAMA with shapefile data (buildings, roads, water).

---

## Slide 3 — Preparation (section title)

- Preparation

---

## Slide 4 — Preparation: initialisation

- **Data:** We load shapefiles from the flood_map folder (building polygons, highway lines, water polygons).
- **Agents:** We create **building**, **road**, and **water** agents. The largest or highest-scoring buildings are set as **shelters** (e.g. top 100 or single largest).
- **Residents:** Inhabitants are placed at **home** (inside buildings or on roads near water). They move only on the **road network** when evacuating.
- _Use a map or screenshot of the environment here._

---

## Slide 5 — Simulation model – Base (section title)

- Simulation Model – Base

---

## Slide 6 — Base: information spreading

- **Who is informed:** Initially **10%** of residents are informed about the evacuation (chosen randomly). They know they must evacuate and know the shelter location.
- **How information spreads:** When an uninformed person observes someone else evacuating within **10 m**, they have a **0.1 probability** of becoming aware and starting to evacuate.
- **End condition:** The simulation finishes when all people who received the information have evacuated (or when the flood has receded, depending on the model).

---

## Slide 7 — Base: inhabitant species

- **Inhabitant** is an active agent with movement (inherits the `moving` skill in GAMA).
- **Attributes:** `is_aware` (knows about evacuation), `is_evacuated` (reached shelter), `home` (starting location), `speed` (movement rate). Optionally `health` if flood and casualties are modelled.
- **Actions:** **evacuate** — move towards the nearest shelter on the road network; **inform** — each cycle, spread awareness to nearby agents within 10 m with 10% success probability.
- Global parameters control population size, spread distance, spread probability, and flood timing.

---

## Slide 8 — Base: screenshot / demo

- **Simulation Model – Base**
- _Place a screenshot or short video of the base model running: map with buildings, roads, water, and agents (e.g. blue = unaware, red = aware, green = evacuated)._

---

## Slide 9 — Batch experiment – Base: setup & results

- **Batch experiment: Information spreading capacity**
  - We vary **population**: [1000, 2000, 5000, 10000, 20000]. Each configuration is run **3 times**.
  - We record **total evacuation time** (in cycles) and **evacuation rate** (percentage of population that evacuated).
  - _Show a table or chart:_ Population → Time (cycles), Evacuation rate (%).
  - _(Note: 1 cycle = 10 s in the sample; adjust if your model uses 1 s per cycle.)_

---

## Slide 10 — Batch – Base: observations

- **Observations:**
  - The more people in the city, the higher the evacuation rate, because information spreads through observation to more people.
  - Evacuation rate depends on initial conditions (initial aware rate, spreading rate, total population). This suggests a **“golden rate”** of awareness so that evacuation can approach 100%.
  - Total time to complete evacuation stays relatively stable across populations. This suggests a **“golden period”** for a given city (e.g. around 29 minutes in the sample).
  - We can think of it as: **evacuation_rate = f(aware_rate, spreading_rate, total_citizen)**.

---

## Slide 11 — Extension 1 (section title)

- Extension 1

---

## Slide 12 — Extension 1: evacuation behaviour

- **Idea:** Not everyone who is aware knows where the shelter is.
- **Rules:** Only **10% of the 10% who are initially aware** know the shelter location and go **directly** to it. The remaining 90% of aware people do **not** know the shelter; they move to **random buildings** to search.
- **Switch to direct movement:** When an agent searching in this way gets within **20 m** of the shelter, they then go **directly** to the shelter instead of continuing to search randomly.

---

## Slide 13 — Extension 1: inhabitant (additions)

- **New attributes:** `knows_shelter_location` (true for the 10% of aware who know the shelter), `search_target` (the current random building they are moving towards when searching).
- **Behaviour:** If the agent knows the shelter → move directly to the shelter. If not, move to `search_target` (a random non-shelter building). When they reach it, pick a new random building. If at any time the distance to the shelter is less than 20 m, switch to moving directly to the shelter.

---

## Slide 14 — Extension 1: screenshot

- **Simulation Model – Extension 1**
- _Screenshot showing agents who know the shelter (e.g. red, moving straight to shelter) and agents who are searching (e.g. orange, moving to random buildings)._

---

## Slide 15 — Batch – Ext1: setup & results

- **Batch experiment: How does limited knowledge of shelter location affect evacuation efficiency?**
  - **Setup:** Fixed population (e.g. 1000), limited evacuation time (e.g. 30 min = 180 cycles if 1 cycle = 10 s). We vary **shelter knowledge ratio**: 0.1, 0.3, 0.5, 0.7, 1.
  - **Outputs:** For each ratio we report % **Evacuated**, % **Aware (Not Evacuated)**, and % **Possible to save**.
  - _Show a table with these columns for each knowledge ratio._

---

## Slide 16 — Batch – Ext1: observations

- **Observations:**
  - Higher shelter knowledge ratio leads to higher evacuation rate and smaller share of people who are aware but not yet evacuated.
  - Evacuation rate **saturates** when knowledge rate is above about 0.7 — this indicates a **“good knowledge ratio”** where the number evacuated is near maximum while information still spreads.
  - Having knowledge rate slightly below 1 can sometimes improve “saved” rate: people who are aware but do not reach the shelter may find other solutions (e.g. high ground), so the overall saved rate can be higher than when everyone is told the shelter.

---

## Slide 17 — Extension 2 (section title)

- Extension 2

---

## Slide 18 — Extension 2: transportation

- **Idea:** Residents use different modes of transport, with different speeds and sensitivity to congestion.
- **Car (20% of population):** Fastest on an open road, but **most affected by traffic jams** (congestion factor 1.0).
- **Motorcycle (70%):** Slightly slower than car (speed factor 0.85), **half as affected** by congestion (factor 0.5).
- **Walking (10%):** Slowest (speed factor 0.1), but **five times less affected** by congestion (factor 0.2).

---

## Slide 19 — Extension 2: inhabitant & road

- **Inhabitant:** Each agent has `mobility_type` (car / motorcycle / walking), `speed_factor`, and `congestion_factor`. **Effective speed** on a road segment is: **base_speed × speed_factor × (1 − congestion_factor × traffic_density)**. So when traffic density is high, cars slow down most and pedestrians least.
- **Global / Road:** Each cycle we update **traffic density** on each road segment (e.g. count of agents within a short distance of that segment), then normalise to a value between 0 and 1. This density is used in the effective speed formula above.

---

## Slide 20 — Extension 2: screenshot / bottlenecks

- **Extension 2 – Traffic and bottlenecks**
- The simulation reveals **potential traffic bottlenecks**: for example, intersections and roads in the centre of the area, where density is highest and cars are most slowed.
- _Screenshot: map with roads coloured by traffic density or with many agents clustered at intersections._

---

## Slide 21 — Extension 3 (section title)

- Extension 3

---

## Slide 22 — Extension 3: awareness strategies

- **Idea:** The 10% of the population who are initially aware are no longer chosen randomly. We compare three **strategies** for selecting them:
  - **Random:** 10% chosen randomly on the map (as in the base model).
  - **Furthest:** The 10% of residents who are **furthest** from the shelter are informed first.
  - **Closest:** The 10% of residents who are **closest** to the shelter are informed first.
- **Efficiency:** We measure **efficiency = time for total evacuation / time spent on the roads** (e.g. total evacuation cycles divided by average person-cycles on road per evacuee). **Higher efficiency means better** use of time.

---

## Slide 23 — Extension 3: initialisation & metrics

- **Initialisation:** We define a main shelter (e.g. the first or largest shelter). After creating all inhabitants, we sort them by distance to that shelter. For **closest** we set the 10% closest as aware; for **furthest** we set the 10% furthest as aware; for **random** we shuffle and pick 10%.
- **Metrics we record:** **evacuation_end_cycle** (cycle when all informed have evacuated), **person_cycles_on_road** (sum over cycles of the number of aware agents not yet evacuated), and the **efficiency ratio** (e.g. evacuation_end_cycle divided by average time on road per evacuee).

---

## Slide 24 — Batch – Ext3: which strategy is best?

- **Batch experiment:** We run each strategy (random, furthest, closest) several times (e.g. 5 runs each). Typical setup: **population 1000**, **alert time = 30 min** (e.g. 180 cycles before flood or as evacuation window).
- **Question:** Which strategy is the most efficient?
- _Show a table:_ Strategy → Efficiency, Evacuation rate (%), Awareness rate (%), Evacuation time (cycles).

---

## Slide 25 — Batch – Ext3: key findings

- **Key findings:**
  - **Closest strategy** has the **highest efficiency** (evacuation completed in less time relative to time spent on roads). However, it has the **lowest awareness rate** (e.g. around 1%), because only people already near the shelter are informed.
  - **Furthest strategy** gives the **highest awareness rate** (information starts from those farthest away), but **evacuation rate** can be slightly lower (e.g. around 7.8%) because those people take longer to reach the shelter.
  - **Random strategy** gives a **more balanced** awareness rate and evacuation rate.
- **Conclusion:** The best strategy depends on the goal — maximising information spread, minimising time on roads, or maximising evacuation rate — and can be explored further with different population sizes and alert times.

---

## Slide 26 — Conclusion (section title)

- Conclusion

---

## Slide 27 — Conclusion: takeaway points

- **Golden period:** For a given city layout and parameters, we can identify a “golden period” in which the evacuation rate is maximised; planning should aim to complete evacuation within this window.
- **Parameter optimisation:** Evacuation rate and efficiency can be expressed as functions of initial parameters (e.g. initial aware rate, shelter knowledge rate, population). This allows optimisation of policies (e.g. best shelter knowledge ratio under time limits).
- **Bottlenecks:** The simulation helps identify road segments and intersections that are prone to congestion. This is useful for traffic management and infrastructure planning during evacuation.
- **Information strategy:** How we choose the initial 10% who are informed (random, furthest, or closest to the shelter) significantly affects both time efficiency and evacuation rate. This should be considered when designing evacuation alerts and communication strategies.

---

## Quick tips for building slides

- Use these bullets as **readable text on the slide**; you can shorten slightly if needed for font size.
- Use **one main table or chart** per results slide (Slides 9, 15, 24).
- Include **screenshots** from GAMA on Slides 8, 14, 20 (and optionally 24/25 for Ext3).
- Section slides (3, 5, 11, 17, 21, 26) can stay as title-only.
- Keep **font size** large enough to read from the back of the room; if a slide has too much text, split into two slides.
