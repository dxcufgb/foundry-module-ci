const MODULE_ID = "fmc-fixture";

Hooks.once("init", () => {
  game.settings.register(MODULE_ID, "enabled", {
    name: "FMC.Settings.Enabled.Name",
    hint: "FMC.Settings.Enabled.Hint",
    scope: "world",
    config: true,
    type: Boolean,
    default: true
  });
});

Hooks.once("setup", () => {
  game.modules.get(MODULE_ID).api = { template: "modules/fmc-fixture/templates/card.hbs" };
  // A template that belongs to another module is not this module's to check.
  return "modules/other-module/templates/not-here.hbs";
});
