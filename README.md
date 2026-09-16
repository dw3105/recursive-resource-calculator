# Recursive Resource Calculator
A Lua mod for the automation and base management game Factorio that gives users the ability to more easily plan their factories, by automatically calculating the production rates and machinery needed for all intermediate products.

The mod leverages the game's API (https://lua-api.factorio.com/latest/) to:
+ build a directed graph of recipe dependencies that is used in the decomposition of products;
+ perform precise calculations of the number and type of machines needed, energy consumption and pollution emissions for each product;
+ reprocess excess products with a recipe that consumes them (cracking, recycling, venting), or burn excess fuel in reactors, boilers and burner generators;
+ calculate quality: quality modules on every recipe, and quality targets as loops of crafting and recycling with a recipe and setup per tier, using higher-quality items made elsewhere on the sheet;
+ compile the results of the computations into neatly built reports;
+ edit machines quickly: a module picker window, one pick filling an empty slot row, and the pipette key copying and pasting modules, machine setups and beacon groups;
+ and finally, build the GUI that puts it all together.

This is a fork of Herddex's mod, published on the Factorio Mod Portal as RRC-Fork: https://mods.factorio.com/mod/RRC-Fork

The original mod lives at https://mods.factorio.com/mod/RecursiveResourceCalculator
