// ─── Config ───────────────────────────────────────────────────────────────────
const BASE_SEPOLIA_CHAIN_ID = "0x14a34"; // 84532

// Replace these after deployment (also populated from deployment.json in CI)
const ADDRESSES = {
  marketFactory: "0x5e5Dd1B65bBeb5803B8F7f93b78EeB6cDCef2446",
  govToken:      "0xFC213AFE69C46430Cd4C8B7F8AC86D3bA7877df8",
  governor:      "0x49c2FB085f1b5dE12B665fEA322f5827d4FcE25a",
  usdc:          "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
};

const SUBGRAPH_URL =
  "https://api.studio.thegraph.com/query/REPLACE_ME/prediction-market/version/latest";

// ─── ABIs (minimal) ───────────────────────────────────────────────────────────
const FACTORY_ABI = [
  "function getMarkets() external view returns (address[])",
  "function marketCount() external view returns (uint256)",
  "function isMarket(address) external view returns (bool)",
];

const MARKET_ABI = [
  "function getMarketInfo() external view returns (string, uint256, uint8, uint8)",
  "function getReserves() external view returns (uint256, uint256)",
  "function impliedProbabilityYES() external view returns (uint256)",
  "function buyShares(uint256 outcomeId, uint256 amountIn, uint256 minSharesOut) external returns (uint256)",
  "function sellShares(uint256 outcomeId, uint256 sharesIn, uint256 minAmountOut) external returns (uint256)",
  "function claimWinnings() external returns (uint256)",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
  "function lpShares(address) external view returns (uint256)",
  "function state() external view returns (uint8)",
  "event SharesBought(address indexed buyer, uint256 outcomeId, uint256 amountIn, uint256 sharesOut)",
  "event SharesSold(address indexed seller, uint256 outcomeId, uint256 sharesIn, uint256 amountOut)",
  "event WinningsClaimed(address indexed claimer, uint256 payout)",
];

const ERC20_ABI = [
  "function balanceOf(address) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
];

const GOV_TOKEN_ABI = [
  "function balanceOf(address) external view returns (uint256)",
  "function getVotes(address) external view returns (uint256)",
  "function delegates(address) external view returns (address)",
  "function delegate(address) external",
  "function decimals() external view returns (uint8)",
];

const GOVERNOR_ABI = [
  "function state(uint256 proposalId) external view returns (uint8)",
  "function castVote(uint256 proposalId, uint8 support) external returns (uint256)",
  "function proposalDeadline(uint256 proposalId) external view returns (uint256)",
  "function proposalSnapshot(uint256 proposalId) external view returns (uint256)",
  "function hasVoted(uint256 proposalId, address account) external view returns (bool)",
  "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)",
];

// ─── State ────────────────────────────────────────────────────────────────────
let provider, signer, account;
let selectedMarket   = null;
let selectedOutcome  = "yes"; // "yes" | "no"
let markets          = [];

const MARKET_STATES   = ["Open", "Closed", "Resolved", "Disputed", "Settled"];
const PROPOSAL_STATES = ["Pending","Active","Canceled","Defeated","Succeeded","Queued","Expired","Executed"];

// ─── Wallet ───────────────────────────────────────────────────────────────────
async function connectWallet() {
  if (!window.ethereum) {
    showToast("MetaMask not found. Please install it.", "error");
    return;
  }
  try {
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer  = await provider.getSigner();
    account = await signer.getAddress();

    document.getElementById("wallet-btn").textContent =
      account.slice(0, 6) + "..." + account.slice(-4);
    document.getElementById("wallet-info").textContent = "";

    await checkNetwork();
    await loadAll();

    // Listen for account / chain changes
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged",    () => location.reload());

  } catch (err) {
    showToast("Connection failed: " + err.message, "error");
  }
}

async function checkNetwork() {
  const chainId = await window.ethereum.request({ method: "eth_chainId" });
  const warning = document.getElementById("network-warning");
  if (chainId !== BASE_SEPOLIA_CHAIN_ID) {
    warning.style.display = "flex";
  } else {
    warning.style.display = "none";
  }
}

async function switchNetwork() {
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: BASE_SEPOLIA_CHAIN_ID }],
    });
  } catch (err) {
    // Chain not added — add it
    if (err.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: BASE_SEPOLIA_CHAIN_ID,
          chainName: "Base Sepolia",
          nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
          rpcUrls: ["https://sepolia.base.org"],
          blockExplorerUrls: ["https://sepolia.basescan.org"],
        }],
      });
    } else {
      showToast("Network switch failed: " + err.message, "error");
    }
  }
}

// ─── Load everything ──────────────────────────────────────────────────────────
async function loadAll() {
  await Promise.all([
    loadBalances(),
    loadMarkets(),
    loadProposals(),
    loadSubgraphTrades(),
  ]);
}

// ─── Balances ─────────────────────────────────────────────────────────────────
async function loadBalances() {
  if (!account) return;
  try {
    const govToken = new ethers.Contract(ADDRESSES.govToken, GOV_TOKEN_ABI, provider);
    const usdc     = new ethers.Contract(ADDRESSES.usdc,     ERC20_ABI,     provider);

    const [pmtBal, votes, delegate, usdcBal] = await Promise.all([
      govToken.balanceOf(account),
      govToken.getVotes(account),
      govToken.delegates(account),
      usdc.balanceOf(account),
    ]);

    document.getElementById("stat-pmt").textContent =
      fmt18(pmtBal) + " PMT";
    document.getElementById("stat-votes").textContent =
      delegate === ethers.ZeroAddress ? "Undelgated" : fmt18(votes) + " PMT";
    document.getElementById("stat-usdc").textContent =
      fmt6(usdcBal) + " USDC";

  } catch (err) {
    console.warn("Balance load failed:", err);
  }
}

// ─── Markets ──────────────────────────────────────────────────────────────────
async function loadMarkets() {
  const grid    = document.getElementById("markets-grid");
  const loading = document.getElementById("markets-loading");

  try {
    const factory = new ethers.Contract(ADDRESSES.marketFactory, FACTORY_ABI, provider);
    const addrs   = await factory.getMarkets();

    document.getElementById("stat-markets").textContent = addrs.length;

    markets = await Promise.all(addrs.map(addr => fetchMarketData(addr)));
    loading.innerHTML = "";
    renderMarkets();
  } catch (err) {
    loading.innerHTML = `<span class="error-msg">Failed to load markets</span>`;
    console.error(err);
  }
}

async function fetchMarketData(address) {
  const c = new ethers.Contract(address, MARKET_ABI, provider);
  const [info, reserves, prob] = await Promise.all([
    c.getMarketInfo(),
    c.getReserves(),
    c.impliedProbabilityYES(),
  ]);
  return {
    address,
    question:      info[0],
    resolutionTime: Number(info[1]),
    state:          MARKET_STATES[Number(info[2])] ?? "Unknown",
    outcome:        Number(info[3]),
    reserveYES:     reserves[0],
    reserveNO:      reserves[1],
    probYES:        Number(prob) / 1e18,
  };
}

function renderMarkets() {
  const grid = document.getElementById("markets-grid");
  grid.innerHTML = "";

  if (markets.length === 0) {
    grid.innerHTML = `<div style="color:var(--muted);font-size:0.85rem;">No markets deployed yet.</div>`;
    return;
  }

  markets.forEach(m => {
    const pct     = Math.round(m.probYES * 100);
    const expires = new Date(m.resolutionTime * 1000).toLocaleDateString();
    const card    = document.createElement("div");
    card.className = "market-card" + (selectedMarket?.address === m.address ? " selected" : "");
    card.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:0.5rem;">
        <span class="state-badge state-${m.state}">${m.state}</span>
        <span style="font-family:var(--mono);font-size:0.7rem;color:var(--muted);">Resolves ${expires}</span>
      </div>
      <div class="market-question">${m.question}</div>
      <div class="prob-bar"><div class="prob-fill" style="width:${pct}%"></div></div>
      <div class="prob-labels">
        <span class="yes-pct">YES ${pct}%</span>
        <span class="no-pct">NO ${100 - pct}%</span>
      </div>
      <div class="market-meta">
        <span>YES: ${fmt18(m.reserveYES)}</span>
        <span>NO: ${fmt18(m.reserveNO)}</span>
      </div>
    `;
    card.onclick = () => selectMarket(m);
    grid.appendChild(card);
  });
}

function selectMarket(m) {
  selectedMarket = m;
  renderMarkets(); // re-render to update selected state

  const panel = document.getElementById("trade-panel");
  if (m.state !== "Open") {
    panel.style.display = "none";
    if (m.state === "Settled") {
      showClaimPanel(m);
    }
    return;
  }

  panel.style.display = "block";
  document.getElementById("trade-market-question").textContent = m.question;
  document.getElementById("trade-amount").value = "";
  updateTradePreview();
}

// ─── Trading ──────────────────────────────────────────────────────────────────
function selectOutcome(outcome) {
  selectedOutcome = outcome;
  document.getElementById("tab-yes").className = "outcome-tab yes" + (outcome === "yes" ? " active" : "");
  document.getElementById("tab-no").className  = "outcome-tab no"  + (outcome === "no"  ? " active" : "");
  const btn = document.getElementById("trade-btn");
  btn.className = `trade-btn ${outcome}-btn`;
  btn.textContent = `Buy ${outcome.toUpperCase()}`;
  updateTradePreview();
}

function updateTradePreview() {
  const amountStr = document.getElementById("trade-amount").value;
  const amount    = parseFloat(amountStr);

  if (!selectedMarket || isNaN(amount) || amount <= 0) {
    document.getElementById("preview-shares").textContent = "—";
    document.getElementById("preview-impact").textContent = "—";
    document.getElementById("preview-fee").textContent    = "—";
    return;
  }

  const amountIn  = BigInt(Math.floor(amount * 1e18));
  const resIn     = selectedOutcome === "yes" ? selectedMarket.reserveNO  : selectedMarket.reserveYES;
  const resOut    = selectedOutcome === "yes" ? selectedMarket.reserveYES : selectedMarket.reserveNO;
  const shares    = getAmountOut(amountIn, resIn, resOut);
  const fee       = amountIn * 3n / 1000n;
  const probBefore = selectedMarket.probYES;

  // Simulated prob after trade
  let newResYES = selectedMarket.reserveYES;
  let newResNO  = selectedMarket.reserveNO;
  if (selectedOutcome === "yes") {
    newResNO  = newResNO  + amountIn - fee;
    newResYES = newResYES - shares;
  } else {
    newResYES = newResYES + amountIn - fee;
    newResNO  = newResNO  - shares;
  }
  const total    = newResYES + newResNO;
  const probAfter = total > 0n ? Number(newResNO) / Number(total) : 0.5;
  const impact   = Math.abs(probAfter - probBefore) * 100;

  document.getElementById("preview-shares").textContent = formatBig(shares, 18, 4);
  document.getElementById("preview-impact").textContent = impact.toFixed(2) + "%";
  document.getElementById("preview-fee").textContent    = formatBig(fee, 18, 4) + " USDC";
}

function getAmountOut(amountIn, reserveIn, reserveOut) {
  if (amountIn === 0n || reserveIn === 0n || reserveOut === 0n) return 0n;
  const amountInWithFee = amountIn * 997n;
  const numerator       = amountInWithFee * reserveOut;
  const denominator     = reserveIn * 1000n + amountInWithFee;
  return numerator / denominator;
}

async function executeTrade() {
  if (!account) { showToast("Connect wallet first", "error"); return; }
  if (!selectedMarket) { showToast("Select a market first", "error"); return; }

  const amountStr = document.getElementById("trade-amount").value;
  const amount    = parseFloat(amountStr);
  if (isNaN(amount) || amount <= 0) { showToast("Enter a valid amount", "error"); return; }

  const amountIn  = ethers.parseUnits(amountStr, 18);
  const outcomeId = selectedOutcome === "yes" ? 1n : 2n;
  const btn       = document.getElementById("trade-btn");
  btn.disabled    = true;
  btn.textContent = "Approving…";

  try {
    // 1. Approve USDC
    const usdc = new ethers.Contract(ADDRESSES.usdc, ERC20_ABI, signer);
    const allowance = await usdc.allowance(account, selectedMarket.address);
    if (allowance < amountIn) {
      const approveTx = await usdc.approve(selectedMarket.address, amountIn);
      showToast("Approving USDC… tx: " + approveTx.hash.slice(0, 10) + "…");
      await approveTx.wait();
    }

    // 2. Buy shares
    btn.textContent = "Buying…";
    const market  = new ethers.Contract(selectedMarket.address, MARKET_ABI, signer);
    const minOut  = 1n; // basic slippage — for production use 0.5% slippage
    const tradeTx = await market.buyShares(outcomeId, amountIn, minOut);
    showToast("Tx submitted: " + tradeTx.hash.slice(0, 10) + "…");
    const receipt = await tradeTx.wait();

    showToast(`✅ Bought ${selectedOutcome.toUpperCase()} shares!`, "success");

    // Refresh
    await loadAll();
    selectMarket(await fetchMarketData(selectedMarket.address));

  } catch (err) {
    const msg = parseError(err);
    showToast("Trade failed: " + msg, "error");
  } finally {
    btn.disabled    = false;
    btn.textContent = `Buy ${selectedOutcome.toUpperCase()}`;
  }
}

// ─── Claim panel (settled markets) ───────────────────────────────────────────
async function showClaimPanel(m) {
  const panel = document.getElementById("trade-panel");
  panel.style.display = "block";
  document.getElementById("trade-market-question").textContent = "🏆 " + m.question;

  const winId = m.outcome === 1 ? 1n : 2n;
  const c     = new ethers.Contract(m.address, MARKET_ABI, provider);
  const bal   = await c.balanceOf(account, winId);

  panel.innerHTML = `
    <div class="trade-title">Market Settled — Claim Winnings</div>
    <div class="trade-info">
      <div class="trade-info-row"><span>Winning outcome</span><span>${m.outcome === 1 ? "YES ✅" : "NO ✅"}</span></div>
      <div class="trade-info-row"><span>Your winning shares</span><span>${formatBig(bal, 18, 4)}</span></div>
    </div>
    ${bal > 0n
      ? `<button class="trade-btn yes-btn" onclick="claimWinnings('${m.address}')">Claim Winnings</button>`
      : `<div class="error-msg" style="text-align:center;padding:1rem;">No winning shares to claim.</div>`
    }
  `;
}

async function claimWinnings(marketAddr) {
  if (!account) { showToast("Connect wallet first", "error"); return; }
  try {
    const market = new ethers.Contract(marketAddr, MARKET_ABI, signer);
    const tx     = await market.claimWinnings();
    showToast("Claiming… tx: " + tx.hash.slice(0, 10) + "…");
    const receipt = await tx.wait();
    showToast("✅ Winnings claimed!", "success");
    await loadBalances();
  } catch (err) {
    showToast("Claim failed: " + parseError(err), "error");
  }
}

// ─── Governance ───────────────────────────────────────────────────────────────
async function loadProposals() {
  const listEl  = document.getElementById("proposals-list");
  const loading = document.getElementById("gov-loading");
  if (!account || !provider) {
    loading.innerHTML = "";
    return;
  }

  try {
    const governor  = new ethers.Contract(ADDRESSES.governor, GOVERNOR_ABI, provider);
    const filter    = governor.filters.ProposalCreated();
    const fromBlock = Math.max(0, (await provider.getBlockNumber()) - 100000);
    const events    = await governor.queryFilter(filter, fromBlock);

    loading.innerHTML = "";

    if (events.length === 0) {
      listEl.innerHTML = `<div style="color:var(--muted);font-size:0.8rem;">No proposals found.</div>`;
      return;
    }

    const rows = await Promise.all(events.slice(-10).reverse().map(async ev => {
      const pid       = ev.args.proposalId;
      const stateIdx  = await governor.state(pid);
      const stateName = PROPOSAL_STATES[Number(stateIdx)] ?? "Unknown";
      const hasVoted  = await governor.hasVoted(pid, account);
      const isActive  = stateName === "Active";
      const desc      = ev.args.description.slice(0, 60) + (ev.args.description.length > 60 ? "…" : "");

      return `
        <div class="proposal-row">
          <div class="proposal-desc">${desc}</div>
          <span class="proposal-state">${stateName}</span>
          ${isActive && !hasVoted
            ? `<button class="vote-btn" onclick="castVote('${pid}', 1)">Vote For</button>`
            : hasVoted
              ? `<span style="font-size:0.7rem;color:var(--muted);font-family:var(--mono);">Voted</span>`
              : `<span style="font-size:0.7rem;color:var(--muted);font-family:var(--mono);">${stateName}</span>`
          }
        </div>`;
    }));

    listEl.innerHTML = rows.join("");
  } catch (err) {
    loading.innerHTML = "";
    listEl.innerHTML = `<span class="error-msg">Failed to load proposals</span>`;
    console.error(err);
  }
}

async function castVote(proposalId, support) {
  if (!account) { showToast("Connect wallet first", "error"); return; }
  try {
    const governor = new ethers.Contract(ADDRESSES.governor, GOVERNOR_ABI, signer);
    const tx       = await governor.castVote(proposalId, support);
    showToast("Vote submitted… tx: " + tx.hash.slice(0, 10) + "…");
    await tx.wait();
    showToast("✅ Vote cast!", "success");
    await loadProposals();
  } catch (err) {
    showToast("Vote failed: " + parseError(err), "error");
  }
}

// ─── Subgraph ─────────────────────────────────────────────────────────────────
async function loadSubgraphTrades() {
  const el = document.getElementById("subgraph-trades");
  try {
    const query = `{
      trades(orderBy: timestamp, orderDirection: desc, first: 5) {
        id
        trader
        outcomeId
        direction
        amountIn
        sharesOut
        timestamp
        market { question }
      }
    }`;

    const res  = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });
    const json = await res.json();
    const trades = json?.data?.trades ?? [];

    if (trades.length === 0) {
      el.innerHTML = `<span style="color:var(--muted);font-size:0.75rem;font-family:var(--mono);">No trades indexed yet.</span>`;
      return;
    }

    el.innerHTML = trades.map(t => `
      <div class="subgraph-trade-row">
        <span>${t.trader.slice(0,6)}…${t.trader.slice(-4)}</span>
        <span style="color:${t.outcomeId === '1' ? 'var(--yes)' : 'var(--no)'};">
          ${t.direction.toUpperCase()} ${t.outcomeId === '1' ? 'YES' : 'NO'}
        </span>
        <span>${parseFloat(t.amountIn).toFixed(2)} USDC</span>
        <span style="color:var(--muted);">${timeAgo(Number(t.timestamp))}</span>
      </div>
    `).join("");

  } catch (err) {
    el.innerHTML = `<span style="color:var(--muted);font-size:0.72rem;font-family:var(--mono);">Subgraph unavailable (configure URL in app.js)</span>`;
  }
}

// ─── Utils ────────────────────────────────────────────────────────────────────
function fmt18(val) {
  return parseFloat(ethers.formatUnits(val, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 });
}
function fmt6(val) {
  return parseFloat(ethers.formatUnits(val, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });
}
function formatBig(val, decimals, precision) {
  return parseFloat(ethers.formatUnits(val, decimals)).toFixed(precision);
}

function timeAgo(ts) {
  const diff = Math.floor(Date.now() / 1000) - ts;
  if (diff < 60)   return diff + "s ago";
  if (diff < 3600) return Math.floor(diff / 60) + "m ago";
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
  return Math.floor(diff / 86400) + "d ago";
}

function parseError(err) {
  // Parse common revert reasons into readable messages
  if (err.code === "ACTION_REJECTED") return "Transaction rejected by user";
  if (err.message?.includes("SlippageExceeded"))   return "Slippage too high — try a smaller amount";
  if (err.message?.includes("WrongState"))          return "Market is not in the right state";
  if (err.message?.includes("AlreadyClaimed"))      return "Already claimed winnings";
  if (err.message?.includes("NothingToClaim"))      return "No winning shares to claim";
  if (err.message?.includes("insufficient"))        return "Insufficient balance";
  if (err.message?.includes("user rejected"))       return "Transaction rejected";
  if (err.message?.includes("network"))             return "Network error — check your connection";
  return err.reason ?? err.message ?? "Unknown error";
}

let toastTimeout = null;
function showToast(msg, type = "info") {
  const container = document.getElementById("toast-container");
  const toast     = document.createElement("div");
  toast.className = "toast " + (type === "success" ? "success" : type === "error" ? "error" : "");
  toast.textContent = msg;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

// ─── Auto-connect if already authorised ──────────────────────────────────────
window.addEventListener("DOMContentLoaded", async () => {
  if (window.ethereum) {
    const accounts = await window.ethereum.request({ method: "eth_accounts" });
    if (accounts.length > 0) connectWallet();
  }
});
