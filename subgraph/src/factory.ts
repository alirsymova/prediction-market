import { MarketCreated } from "../generated/MarketFactory/MarketFactory";
import { Market, Protocol } from "../generated/schema";
import { PredictionMarket } from "../generated/templates";
import { BigDecimal, BigInt } from "@graphprotocol/graph-ts";

const PROTOCOL_ID = "singleton";

export function handleMarketCreated(event: MarketCreated): void {
  let market = new Market(event.params.market.toHexString());
  market.question             = event.params.question;
  market.resolutionTime       = event.params.resolutionTime;
  market.disputeWindow        = BigInt.fromI32(86400); // 1 day default
  market.oracle               = event.params.oracle;
  market.collateral           = event.address; // collateral is factory-level
  market.state                = "Open";
  market.winningOutcome       = null;
  market.reserveYES           = BigDecimal.zero();
  market.reserveNO            = BigDecimal.zero();
  market.impliedProbabilityYES = BigDecimal.fromString("0.5");
  market.totalVolume          = BigDecimal.zero();
  market.totalFeesCollected   = BigDecimal.zero();
  market.tradeCount           = BigInt.zero();
  market.createdAt            = event.block.timestamp;
  market.resolvedAt           = null;
  market.save();

  // Start indexing this market's events
  PredictionMarket.create(event.params.market);

  // Update protocol stats
  let proto = Protocol.load(PROTOCOL_ID);
  if (!proto) {
    proto = new Protocol(PROTOCOL_ID);
    proto.totalMarkets       = BigInt.zero();
    proto.totalVolume        = BigDecimal.zero();
    proto.totalFeesCollected = BigDecimal.zero();
  }
  proto.totalMarkets = proto.totalMarkets.plus(BigInt.fromI32(1));
  proto.save();
}
