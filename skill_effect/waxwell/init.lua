local WaxwellPuppeteer = require("skill_effect/waxwell/puppeteer/_shared/hook")
local WaxwellUmbra = require("skill_effect/waxwell/umbra/_shared/hook")
local WaxwellSovereign = require("skill_effect/waxwell/sovereign/_shared/hook")
local WaxwellEmperor = require("skill_effect/waxwell/emperor/_shared/hook")
local JournalCastGate = require("skill_effect/waxwell/_shared/journal_cast_gate")
local ShardMigrateCleanup = require("skill_effect/waxwell/_shared/shard_migrate_cleanup")

local M = {}

function M.Register(env)
    WaxwellPuppeteer.Register(env)
    WaxwellSovereign.Register(env)
    WaxwellUmbra.Register(env)
    WaxwellEmperor.Register(env)
    JournalCastGate.Register(env)
    ShardMigrateCleanup.Register(env)
end

return M
