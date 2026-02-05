# Flood Evacuation Simulation - New Model Set

GAML files based on the presentation "Flood Evacuation Simulation" - Modelling and Simulation of Complex Systems.

## Structure

| File | Description | Experiment |
|------|-------------|------------|
| **base.gaml** | Base model - Information spreading | flood_base_exp |
| **extension1.gaml** | Extension 1 - Evacuation behavior | flood_ext1_exp |
| **extension2.gaml** | Extension 2 - Transportation modes | flood_ext2_exp |

## Differences from old model set (models/)

| Criteria | New set (models/) | Old set |
|----------|-------------------|---------|
| **Shelters** | **Tallest** buildings (height) | **Largest** buildings (area) |
| **Direct movement threshold** | **20m** | 200m - 500m |
| **Context** | Flooding | Red River flood |

## Base Model
- 10% of residents initially know evacuation information
- Spreading via observation: 10m radius, 0.1 probability
- Ends when all informed people have evacuated

## Extension 1
- Only 10% of informed people know shelter location
- Remaining 90% move randomly to search
- Within 20m of shelter → switch to direct movement

## Extension 2
- **Cars (20%)**: fastest, most affected by congestion (factor 1.0)
- **Motorcycles (70%)**: speed 0.85, congestion 0.5
- **Walking (10%)**: slowest (0.1), least affected by congestion (0.2)

## How to Run

1. Open project in GAMA Platform
2. Select .gaml file in models/ folder
3. Choose corresponding experiment
4. Click Run
