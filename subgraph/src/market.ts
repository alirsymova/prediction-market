import {
  SharesBought,
  SharesSold,
  MarketResolved,
  MarketSettled,
  WinningsClaimed,
  LiquidityAdded,
  LiquidityRemoved,
} from "../generated/templates/PredictionMarket/PredictionMarketV1";
import { Market, Trade, Claim, LiquidityEvent, Protocol } from "../generated/schema";
import { BigDecimal, BigInt, Bytes } from "@graphprotocol/graph-ts";

const WAD = BigDecimal.fromString("1000000000000000000");
const PROTOCOL_ID = "singleton";

function getOrCreateProtocol(): Protocol {
  let p = Protocol.load(PROTOCOL_ID);
  if (!p) {
    p = new Protocol(PROTOCOL_ID);
    p.totalMarkets       = BigInt.zero();
    p.totalVolume        = BigDecimal.zero();
    p.totalFeesCollected = BigDecimal.zero();
  }
  return p;
}

function loadMarket(address: Bytes): Market {
  let m = Market.load(address.toHexString())!;
  return m;
}

export function handleSharesBought(event: SharesBought): void {
  let market = loadMarket(event.address);
  let amountIn  = event.params.amountIn.toBigDecimal().div(WAD);
  let sharesOut = event.params.sharesOut.toBigDecimal().div(WAD);
  let fee       = amountIn.times(BigDecimal.fromString("0.003"));

  // Update market stats
  market.totalVolume        = market.totalVolume.plus(amountIn);
  market.totalFeesCollected = market.totalFeesCollected.plus(fee);
  market.tradeCount         = market.tradeCount.plus(BigInt.fromI32(1));

  // Update reserves (YES bought: NO reserve up, YES reserve down)
  if (event.params.outcomeId.equals(BigInt.fromI32(1))) {
    market.reserveNO  = market.reserveNO.plus(amountIn.minus(fee));
    market.reserveYES = market.reserveYES.minus(sharesOut);
  } else {
    market.reserveYES = market.reserveYES.plus(amountIn.minus(fee));
    market.reserveNO  = market.reserveNO.minus(sharesOut);
  }

  // Implied probability: reserveNO / (reserveYES + reserveNO)
  let total = market.reserveYES.plus(market.reserveNO);
  market.impliedProbabilityYES = total.gt(BigDecimal.zero())
    ? market.reserveNO.div(total)
    : BigDecimal.fromString("0.5");

  market.save();

  // Create Trade entity
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let trade = new Trade(id);
  trade.market      = market.id;
  trade.trader      = event.params.buyer;
  trade.outcomeId   = event.params.outcomeId;
  trade.direction   = "buy";
  trade.amountIn    = amountIn;
  trade.sharesOut   = sharesOut;
  trade.timestamp   = event.block.timestamp;
  trade.blockNumber = event.block.number;
  trade.txHash      = event.transaction.hash;
  trade.save();

  // Update protocol
  let proto = getOrCreateProtocol();
  proto.totalVolume = proto.totalVolume.plus(amountIn);
  proto.save();
}

export function handleSharesSold(event: SharesSold): void {
  let market = loadMarket(event.address);
  let sharesIn  = event.params.sharesIn.toBigDecimal().div(WAD);
  let amountOut = event.params.amountOut.toBigDecimal().div(WAD);

  market.totalVolume = market.totalVolume.plus(sharesIn);
  market.tradeCount  = market.tradeCount.plus(BigInt.fromI32(1));
  market.save();

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let trade = new Trade(id);
  trade.market      = market.id;
  trade.trader      = event.params.seller;
  trade.outcomeId   = event.params.outcomeId;
  trade.direction   = "sell";
  trade.amountIn    = sharesIn;
  trade.sharesOut   = amountOut;
  trade.timestamp   = event.block.timestamp;
  trade.blockNumber = event.block.number;
  trade.txHash      = event.transaction.hash;
  trade.save();
}

export function handleMarketResolved(event: MarketResolved): void {
  let market = loadMarket(event.address);
  market.state          = "Resolved";
  market.winningOutcome = event.params.outcome == 1 ? "YES" : "NO";
  market.resolvedAt     = event.params.resolvedAt;
  market.save();
}

export function handleMarketSettled(event: MarketSettled): void {
  let market = loadMarket(event.address);
  market.state = "Settled";
  market.save();
}

export function handleWinningsClaimed(event: WinningsClaimed): void {
  let market = loadMarket(event.address);
  let payout = event.params.payout.toBigDecimal().div(WAD);

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let claim = new Claim(id);
  claim.market    = market.id;
  claim.claimer   = event.params.claimer;
  claim.payout    = payout;
  claim.timestamp = event.block.timestamp;
  claim.txHash    = event.transaction.hash;
  claim.save();
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let market    = loadMarket(event.address);
  let amountYES = event.params.amountYES.toBigDecimal().div(WAD);
  let amountNO  = event.params.amountNO.toBigDecimal().div(WAD);
  let shares    = event.params.shares.toBigDecimal().div(WAD);

  market.reserveYES = market.reserveYES.plus(amountYES);
  market.reserveNO  = market.reserveNO.plus(amountNO);
  market.save();

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.market    = market.id;
  liq.provider  = event.params.provider;
  liq.type      = "add";
  liq.amountYES = amountYES;
  liq.amountNO  = amountNO;
  liq.shares    = shares;
  liq.timestamp = event.block.timestamp;
  liq.txHash    = event.transaction.hash;
  liq.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let market    = loadMarket(event.address);
  let amountYES = event.params.amountYES.toBigDecimal().div(WAD);
  let amountNO  = event.params.amountNO.toBigDecimal().div(WAD);
  let shares    = event.params.shares.toBigDecimal().div(WAD);

  market.reserveYES = market.reserveYES.minus(amountYES);
  market.reserveNO  = market.reserveNO.minus(amountNO);
  market.save();

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.market    = market.id;
  liq.provider  = event.params.provider;
  liq.type      = "remove";
  liq.amountYES = amountYES;
  liq.amountNO  = amountNO;
  liq.shares    = shares;
  liq.timestamp = event.block.timestamp;
  liq.txHash    = event.transaction.hash;
  liq.save();
}
