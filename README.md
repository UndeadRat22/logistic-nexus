# Logistic Nexus

Logistic Nexus is a compact, logistics-aware automatic mall for Factorio 2.0. It watches its logistic network for requested or construction items that are missing, chooses the most important craftable jobs, requests the required materials, and crafts intermediate components internally until the final product is complete.

Multiple Logistic Nexuss share the same demand information and distribute work across the most-needed products. Fluid recipes are supported through filled barrels, with empty barrels returned to the network.

## Basic Use

1. Place an Logistic Nexus inside a logistic network with construction and logistic robots.
2. Supply its network with raw materials and commonly used components.
3. Create demand using requester chests, personal logistic requests, construction ghosts, or module/item installation requests.
4. The blue chest receives ingredients. Completed products and returned materials leave through the purple active provider chest.

Logistic Nexus crafts one final-product job at a time. If a required component is unavailable but can be assembled, it crafts that component internally without abandoning the final goal. Jobs that require unavailable, non-craftable materials are skipped.

Exact-quality requests are supported when matching-quality ingredients are available. Logistic Nexus preserves that quality through every internally crafted intermediate.

## Circuit Control

Connect a red or green wire directly to one or more Logistic Nexuss. A constant combinator can control every connected mall.

- **Block a product:** output any positive item signal. For example, `Solar panel = 1` prevents connected Logistic Nexuss from manufacturing solar panels, even when they are requested.
- **Limit product variety:** output virtual signal `P` with a positive value. `P = 1` restricts each connected mall to the highest-priority product type; `P = 5` allows consideration of the top five product types. With no `P` signal, the default is three.
- Zero or negative signals have no effect.

Example: connect a constant combinator to all Logistic Nexuss, set `Solar panel = 1` and `P = 2`, then turn the combinator on. The malls ignore solar-panel demand and distribute available work among the two highest-priority remaining products.
