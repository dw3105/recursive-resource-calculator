#!/usr/bin/env python3
"""Seed offline material fixtures from the installed Draftsman vanilla data."""
from __future__ import annotations
import argparse
from pathlib import Path
from draftsman.data import entities, items, recipes

# Draftsman ships no resource prototypes. Raw leaves (player rule, round 53 grill Q3): what resources yield when mined
# and what tiles give, vanilla 2.0 + Space Age. The mod reads these from the game (logic/catalog.lua material_leaves).
RAW = {"iron-ore", "copper-ore", "stone", "coal", "uranium-ore", "crude-oil", "water", "calcite", "tungsten-ore",
       "scrap", "sulfuric-acid", "lithium-brine", "fluorine", "lava", "ammoniacal-solution", "heavy-oil",
       "wood", "carbon", "metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk"}

KINDS = {"transport-belt", "underground-belt", "splitter", "pipe", "pipe-to-ground",
         "assembling-machine", "furnace", "rocket-silo", "beacon", "inserter", "electric-pole"}

def material_data():
    item_by_entity = {}
    for item_name, item in items.raw.items():
        placed = item.get("place_result")
        if placed:
            item_by_entity.setdefault(placed, item_name)
    targets = sorted(name for name, entity in entities.raw.items() if entity.get("type") in KINDS and name in item_by_entity)
    producers = {}
    for recipe_name, recipe in recipes.raw.items():
        categories = recipe.get("categories", [recipe.get("category", "")])
        if recipe.get("hidden") or any("recycling" in str(category) for category in categories):
            continue
        for product in recipe.get("results", recipe.get("products", [])):
            name = product.get("name")
            if name:
                producers.setdefault(name, []).append(recipe_name)
    def choose(item):
        candidates = sorted(producers.get(item, []))
        return item if item in candidates else (candidates[0] if candidates else None)
    needed = {item_by_entity[name] for name in targets}
    queue = sorted(needed)
    graph = {}
    while queue:
        item = queue.pop(0)
        if item in graph:
            continue
        recipe_name = None if item in RAW else choose(item)
        recipe = recipes.raw.get(recipe_name) if recipe_name else None
        if not recipe:
            graph[item] = (None, [], 1.0)
            continue
        products = recipe.get("results", recipe.get("products", []))
        product_amount = next((p.get("amount", p.get("amount_min", 1)) for p in products if p.get("name") == item), 1)
        ingredients = [(part["name"], float(part.get("amount", part.get("amount_min", 1))))
                       for part in recipe.get("ingredients", []) if part.get("name")]
        graph[item] = (recipe_name, ingredients, float(product_amount))
        queue.extend(sorted(name for name, _ in ingredients if name not in graph))
    memo = {}
    def compute(root):
        if root in memo:
            return memo[root]
        active = set()
        stack = [{"item": root, "index": 0, "total": 0.0, "initialized": False}]
        while stack:
            frame = stack[-1]
            item = frame["item"]
            if item in memo:
                stack.pop()
                continue
            recipe_name, ingredients, divisor = graph.get(item, (None, [], 1.0))
            if not frame["initialized"]:
                if not recipe_name or divisor <= 0:
                    memo[item] = 1.0
                    stack.pop()
                    continue
                active.add(item)
                frame["initialized"] = True
            elif frame["index"] >= len(ingredients):
                memo[item] = frame["total"] / divisor
                active.discard(item)
                stack.pop()
            else:
                child, amount = ingredients[frame["index"]]
                if child in memo:
                    frame["total"] += amount * memo[child]
                    frame["index"] += 1
                elif child in active:
                    frame["total"] += amount
                    frame["index"] += 1
                else:
                    stack.append({"item": child, "index": 0, "total": 0.0, "initialized": False})
        return memo[root]
    return [(entity, compute(item_by_entity[entity])) for entity in targets]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", default="tests/fixtures/material_cost_2.1.txt")
    args = parser.parse_args()
    rows = material_data()
    Path(args.output).write_text("# seed: draftsman 2.1.17 data, replaced by headless probe at merge\n" +
                                 "".join(f"MATERIAL {name} {cost:.4f}\n" for name, cost in rows))

if __name__ == "__main__":
    main()
