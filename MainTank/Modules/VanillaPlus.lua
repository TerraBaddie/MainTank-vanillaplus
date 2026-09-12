-- MainTank - VanillaPlus compatibility
--
-- Load this file LAST. It is the explicit home for VanillaPlus-only rules and
-- future server-specific overrides, mirroring ProjectLegacy.lua in the separate
-- Project Legacy repository. Generic MainTank accounting fixes should stay in
-- Core; VanillaPlus mechanics should live here (or be documented here) so they
-- never leak into the Project Legacy fork.

if not MainTank then return end
local MT = MainTank

MT.serverFlavor = "VanillaPlus"
MT.isVanillaPlus = true
MT.isProjectLegacy = nil

-- Document the major server-specific assumptions currently owned by the
-- VanillaPlus code line. These values are informational flags for maintainers;
-- existing proven Core/BlockAnalysis/RC6 implementations remain authoritative.
MT.VanillaPlusRules = MT.VanillaPlusRules or {}
MT.VanillaPlusRules.strengthPerBlockValue = 10
MT.VanillaPlusRules.guardiansFavorBoostsSanctuary = true
MT.VanillaPlusRules.sanctuaryIsAllDamageFlatDR = true

-- VP3_LAYEREDSTOP3 is intentionally generic mitigation-accounting work. It does
-- NOT replace VanillaPlus talent, aura, item, Sanctuary, Guardian's Favor, or
-- block-value formulas. This module exists to keep those flavor rules visibly
-- separated from the Project Legacy repository going forward.
