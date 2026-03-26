driver:
if builtins.hasAttr "browsers-chromium" driver then
  driver."browsers-chromium"
else if builtins.hasAttr "browsers" driver then
  driver.browsers
else
  driver
