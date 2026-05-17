Compiling 108 files with Solc 0.8.24
Solc 0.8.24 finished in 6.39s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
   --> test/fuzz/Fuzz.t.sol:139:9:
    |
139 |         address user = makeAddr("voter");
    |         ^^^^^^^^^^^^

Warning (2072): Unused local variable.
   --> test/unit/PredictionMarket.t.sol:286:9:
    |
286 |         uint256 shares = _buyYES(alice, 100e18);
    |         ^^^^^^^^^^^^^^

Analysing contracts...
Running tests...

Ran 3 tests for test/fork/Fork.t.sol:GasBenchmarkTest
[PASS] test_benchmark_getAmountOutSolidity() (gas: 1561)
[PASS] test_benchmark_getAmountOutYul() (gas: 471)
[PASS] test_benchmark_yulCheaperThanSolidity() (gas: 1771)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 15.88ms (5.90ms CPU time)

Ran 2 tests for test/unit/Security.t.sol:SecurityReentrancyTest
[PASS] test_security_ceiPatternProven() (gas: 340942)
[PASS] test_security_reentrancyBlockedOnClaim() (gas: 344356)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 30.04ms (9.33ms CPU time)

Ran 6 tests for test/unit/Security.t.sol:SecurityAccessControlTest
[PASS] test_security_attackerCannotPause() (gas: 18711)
[PASS] test_security_attackerCannotResolveMarket() (gas: 48539)
[PASS] test_security_attackerCannotUpgrade() (gas: 5718947)
[PASS] test_security_attackerCannotWithdrawTreasury() (gas: 13002)
[PASS] test_security_attackerCannotWithdrawTreasuryERC20() (gas: 50981)
[PASS] test_security_noTxOriginAuth() (gas: 18777)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 32.92ms (14.63ms CPU time)

Ran 7 tests for test/unit/MarketFactory.t.sol:MarketFactoryTest
[PASS] test_create2SaltCannotBeReused() (gas: 588854)
[PASS] test_createMarketDeterministic() (gas: 599865)
[PASS] test_createMarketViaCreate() (gas: 568523)
[PASS] test_getMarketsReturnsAll() (gas: 1585976)
[PASS] test_nonCreatorCannotCreateMarket() (gas: 18106)
[PASS] test_setDisputeWindow() (gas: 19873)
[PASS] test_setDisputeWindowRevertsIfNotAdmin() (gas: 14452)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 32.56ms (20.48ms CPU time)

Ran 15 tests for test/unit/Governance.t.sol:GovernanceTest
[PASS] test_delegationActivatesVotingPower() (gas: 13242)
[PASS] test_fullGovernanceLifecycle() (gas: 465330)
[PASS] test_mintOnlyOwner() (gas: 100891)
[PASS] test_mintRevertsIfNotOwner() (gas: 14473)
[PASS] test_proposalDefeatedIfQuorumNotMet() (gas: 288093)
[PASS] test_proposalRevertsIfBelowThreshold() (gas: 177314)
[PASS] test_proposalThreshold() (gas: 8017)
[PASS] test_quorumFraction() (gas: 10481)
[PASS] test_timelockDelay() (gas: 7982)
[PASS] test_totalSupply() (gas: 7947)
[PASS] test_treasuryReceivesETH() (gas: 17925)
[PASS] test_treasuryRevertsDirectWithdraw() (gas: 13023)
[PASS] test_undelegatedHasNoVotingPower() (gas: 86780)
[PASS] test_votingDelay() (gas: 8080)
[PASS] test_votingPeriod() (gas: 8045)
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 63.22ms (48.52ms CPU time)

Ran 38 tests for test/unit/PredictionMarket.t.sol:PredictionMarketTest
[PASS] test_addLiquidity() (gas: 103577)
[PASS] test_buyNOShares() (gas: 219939)
[PASS] test_buySharesCollectsFee() (gas: 218869)
[PASS] test_buySharesRevertsInvalidOutcome() (gas: 59466)
[PASS] test_buySharesRevertsOnSlippage() (gas: 65334)
[PASS] test_buySharesRevertsZeroAmount() (gas: 29791)
[PASS] test_buySharesTransfersCollateral() (gas: 219536)
[PASS] test_buySharesUpdatesReserves() (gas: 219821)
[PASS] test_buyYESShares() (gas: 220057)
[PASS] test_claimRevertsIfAlreadyClaimed() (gas: 306444)
[PASS] test_claimRevertsIfNothingToClaim() (gas: 109935)
[PASS] test_claimWinnings() (gas: 308326)
[PASS] test_closeMarketAfterResolutionTime() (gas: 52611)
[PASS] test_closeMarketRevertsBeforeTime() (gas: 17678)
[PASS] test_disputeResolutionWithinWindow() (gas: 106055)
[PASS] test_impliedProbabilityAtInit50Percent() (gas: 15793)
[PASS] test_impliedProbabilityShiftsOnBuy() (gas: 217887)
[PASS] test_initializeGrantsRoles() (gas: 30653)
[PASS] test_initializeRevertsIfCalledTwice() (gas: 27942)
[PASS] test_initializeSetsQuestion() (gas: 30274)
[PASS] test_initializeSetsReserves() (gas: 15782)
[PASS] test_initializeSetsStateOpen() (gas: 26360)
[PASS] test_loserCannotClaim() (gas: 307742)
[PASS] test_onlyPauserCanPause() (gas: 18727)
[PASS] test_pauseStopsBuying() (gas: 86614)
[PASS] test_removeLiquidity() (gas: 115504)
[PASS] test_resolveDisputeByAdmin() (gas: 133144)
[PASS] test_resolveMarket() (gas: 100818)
[PASS] test_resolveMarketRevertsIfNotResolver() (gas: 48430)
[PASS] test_sellSharesRevertsOnSlippage() (gas: 225879)
[PASS] test_sellSharesRevertsZeroAmount() (gas: 29750)
[PASS] test_sellYESShares() (gas: 278979)
[PASS] test_settleMarketAfterDisputeWindow() (gas: 106457)
[PASS] test_staleOracleBlocksResolution() (gas: 91958)
[PASS] test_unpauseResumesTrading() (gas: 228402)
[PASS] test_upgradePreservesState() (gas: 6091689)
[PASS] test_upgradeRevertsIfNotUpgrader() (gas: 5862114)
[PASS] test_upgradeToV2() (gas: 5871115)
Suite result: ok. 38 passed; 0 failed; 0 skipped; finished in 186.92ms (111.42ms CPU time)

Ran 3 tests for test/fork/Fork.t.sol:ForkChainlinkTest
[PASS] test_fork_chainlinkFeedIsFresh() (gas: 25469)
[PASS] test_fork_chainlinkFeedReturnsPositivePrice() (gas: 27623)
[PASS] test_fork_stalePriceReverts() (gas: 29234)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 2.65s (3.98s CPU time)

Ran 2 tests for test/fork/Fork.t.sol:ForkUSDCTest
[PASS] test_fork_usdcExists() (gas: 12847)
[PASS] test_fork_usdcTransfer() (gas: 251497)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 2.86s (2.50s CPU time)

Ran 6 tests for test/fuzz/Fuzz.t.sol:FuzzTests
[PASS] testFuzz_assemblyMatchesSolidity(uint96,uint96,uint96) (runs: 256, μ: 6339, ~: 6339)
[PASS] testFuzz_buySharesSucceeds(uint96) (runs: 256, μ: 227716, ~: 227716)
[PASS] testFuzz_getAmountOutLessThanReserve(uint128,uint128,uint128) (runs: 256, μ: 6039, ~: 6039)
[PASS] testFuzz_getAmountOutMonotone(uint96,uint96,uint96,uint96) (runs: 256, μ: 5942, ~: 5942)
[PASS] testFuzz_vaultDepositWithdraw(uint96) (runs: 256, μ: 150543, ~: 150543)
[PASS] testFuzz_votingPowerAfterDelegate(uint96) (runs: 256, μ: 8970, ~: 8970)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 3.03s (722.03ms CPU time)

Ran 5 tests for test/invariant/Invariant.t.sol:InvariantTests
[PASS] invariant_contractBalanceCoversReserves() (runs: 64, calls: 2048, reverts: 0)

╭---------------+----------+-------+---------+----------╮
| Contract      | Selector | Calls | Reverts | Discards |
+=======================================================+
| MarketHandler | addLiq   | 499   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyNO    | 543   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyYES   | 468   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | sellYES  | 538   | 0       | 0        |
╰---------------+----------+-------+---------+----------╯

[PASS] invariant_kNeverDecreases() (runs: 64, calls: 2048, reverts: 0)

╭---------------+----------+-------+---------+----------╮
| Contract      | Selector | Calls | Reverts | Discards |
+=======================================================+
| MarketHandler | addLiq   | 499   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyNO    | 543   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyYES   | 468   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | sellYES  | 538   | 0       | 0        |
╰---------------+----------+-------+---------+----------╯

[PASS] invariant_lpSharesPositive() (runs: 64, calls: 2048, reverts: 0)

╭---------------+----------+-------+---------+----------╮
| Contract      | Selector | Calls | Reverts | Discards |
+=======================================================+
| MarketHandler | addLiq   | 499   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyNO    | 543   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyYES   | 468   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | sellYES  | 538   | 0       | 0        |
╰---------------+----------+-------+---------+----------╯

[PASS] invariant_stateIsOpen() (runs: 64, calls: 2048, reverts: 0)

╭---------------+----------+-------+---------+----------╮
| Contract      | Selector | Calls | Reverts | Discards |
+=======================================================+
| MarketHandler | addLiq   | 499   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyNO    | 543   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyYES   | 468   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | sellYES  | 538   | 0       | 0        |
╰---------------+----------+-------+---------+----------╯

[PASS] invariant_totalCollateralCoversReserves() (runs: 64, calls: 2048, reverts: 0)

╭---------------+----------+-------+---------+----------╮
| Contract      | Selector | Calls | Reverts | Discards |
+=======================================================+
| MarketHandler | addLiq   | 499   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyNO    | 543   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | buyYES   | 468   | 0       | 0        |
|---------------+----------+-------+---------+----------|
| MarketHandler | sellYES  | 538   | 0       | 0        |
╰---------------+----------+-------+---------+----------╯

Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 3.03s (14.43s CPU time)

Ran 10 test suites in 3.06s (11.94s CPU time): 87 tests passed, 0 failed, 0 skipped (87 total tests)

╭------------------------------------+------------------+------------------+----------------+-----------------╮
| File                               | % Lines          | % Statements     | % Branches     | % Funcs         |
+=============================================================================================================+
| script/Deploy.s.sol                | 0.00% (0/44)     | 0.00% (0/50)     | 100.00% (0/0)  | 0.00% (0/2)     |
|------------------------------------+------------------+------------------+----------------+-----------------|
| script/Verify.s.sol                | 0.00% (0/28)     | 0.00% (0/37)     | 0.00% (0/12)   | 0.00% (0/1)     |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/core/FeeVault.sol              | 100.00% (9/9)    | 85.71% (6/7)     | 0.00% (0/1)    | 100.00% (3/3)   |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/core/PredictionMarketV1.sol    | 97.28% (143/147) | 91.53% (162/177) | 60.71% (17/28) | 95.24% (20/21)  |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/core/PredictionMarketV2.sol    | 15.38% (2/13)    | 6.25% (1/16)     | 0.00% (0/2)    | 50.00% (1/2)    |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/factory/MarketFactory.sol      | 100.00% (44/44)  | 91.11% (41/45)   | 20.00% (1/5)   | 100.00% (11/11) |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/governance/GovernanceToken.sol | 75.00% (6/8)     | 60.00% (3/5)     | 100.00% (0/0)  | 75.00% (3/4)    |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/governance/MarketGovernor.sol  | 75.00% (15/20)   | 78.95% (15/19)   | 100.00% (0/0)  | 70.00% (7/10)   |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/governance/Treasury.sol        | 70.00% (14/20)   | 47.83% (11/23)   | 0.00% (0/6)    | 83.33% (5/6)    |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/oracles/ChainlinkAdapter.sol   | 89.47% (17/19)   | 82.61% (19/23)   | 37.50% (3/8)   | 100.00% (3/3)   |
|------------------------------------+------------------+------------------+----------------+-----------------|
| src/oracles/MockAggregator.sol     | 62.50% (10/16)   | 61.54% (8/13)    | 100.00% (0/0)  | 50.00% (3/6)    |
|------------------------------------+------------------+------------------+----------------+-----------------|
| test/invariant/Invariant.t.sol     | 100.00% (42/42)  | 100.00% (45/45)  | 100.00% (5/5)  | 100.00% (5/5)   |
|------------------------------------+------------------+------------------+----------------+-----------------|
| test/unit/Security.t.sol           | 0.00% (0/9)      | 0.00% (0/8)      | 0.00% (0/2)    | 0.00% (0/3)     |
|------------------------------------+------------------+------------------+----------------+-----------------|
| Total                              | 72.08% (302/419) | 66.45% (311/468) | 37.68% (26/69) | 79.22% (61/77)  |
╰------------------------------------+------------------+------------------+----------------+-----------------╯
