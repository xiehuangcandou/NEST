# Dividend system contract specification document
[TOC]
## Architecture
```
graph TB
    Business_Contract -. Fees .-> Dividend_pool_contract
User -. Store_NEST .-> NEST_Storage_Contract
Dividend_calculation_contract -. Receiving .-> User
subgraph dividend system
    Dividend_pool_contract --> Dividend_calculation_contract
    NEST_Storage_Contract --> Dividend_calculation_contract
end
```

## Contract address
- Dividend pool contract:[0x831945D1B744499C16d0072dF1F1C8322002fDd8](https://etherscan.io/address/0x831945d1b744499c16d0072df1f1c8322002fdd8#internaltx)
- NEST storage contract:[0x561d0d6c498a379574eAaA4a5F2532b223fFaeBF](https://etherscan.io/address/0x561d0d6c498a379574eAaA4a5F2532b223fFaeBF#tokentxns)
- Dividend calculation contract:[0xDEeaA1726cc544486eeA4d0E114AEbD04A5016bd](https://etherscan.io/address/0xDEeaA1726cc544486eeA4d0E114AEbD04A5016bd)

## Operating procedures
### Deposited in NEST
```
sequenceDiagram
    User->>NEST Storage Contract: Authorized Storage Amount (Transaction)
User->>Dividend calculation contract: Deposit in NEST (transaction)
Dividend calculation contract-->>NEST Storage Contract: Trigger authorization transfer (internal transaction)
loop transfer (internal transaction)
  NEST Storage Contract-->>User: 
  User->>NEST Storage Contract: 
end
```

### Take out NEST (normal process)
```
sequenceDiagram
    User->>Dividend calculation contract: Take out the NEST amount (transaction)
Dividend calculation contract->>NEST Storage Contract: Trigger NEST transfer (internal transaction)
NEST Storage Contract-->>User: NEST Transfer (internal transaction)
```

### Take out NEST (emergency process)
```
sequenceDiagram
    User->>NEST Storage Contract: Take out all NESTs (transactions) that have been deposited at the transaction origination address.
NEST Storage Contract-->>User: NEST Transfer (internal transaction)
```

### Receive dividends
```
sequenceDiagram
    User->>Dividend Calculation Contract: Receive Dividend (Transaction)
Dividend pool contract-->>Dividend Calculation Contract: Get ETH quantity (internal transaction)
NEST storage contract-->>Dividend Calculation Contract: Get the transaction initiation address NEST deposit amount (internal transaction)
Dividend Calculation Contract-->>Dividend pool contract: Transfer ETH dividend to the transaction origination address (internal transaction)
```

## Contract method
> 1.Get the nest liquidity quota：function allValue() public view returns (uint256)

Input Parameters | Type | Description
---|---|---
--- | uint256 | Nest circulation

> 2.Next dividend time：function getNextTime() public view returns (uint256)

Input Parameters | Type | Description
---|---|---
--- | uint256 | Next dividend time

> 3.Get dividend information
：function getInfo() public view returns (uint256 _nextTime, uint256 _getAbonusTime, uint256 _ethNum, uint256 _nestValue, uint256 _myJoinNest, uint256 _getEth, uint256 _allowNum, uint256 _leftNum, bool allowAbonus)

Input Parameters | Type | Description
---|---|---
_nextTime | uint256 | Next dividend time
_getAbonusTime | uint256 | The deadline for this dividend
_ethNum | uint256 | Total dividend ETH
_nestValue | uint256 | Nest total liquidity
_myJoinNest | uint256 | The number of nests I have deposited
_getEth | uint256 | expected profits
_allowNum | uint256 | Nest authorization amount
_leftNum | uint256 | Nest balance
allowAbonus | bool | Is it currently available?


> 4.Deposit：function depositIn(uint256 amount) public

Input Parameters | Type | Description
---|---|---
amount | uint256 | Deposit quantity

Need to authorize the nest storage contract in advance


> 5.take out：function takeOut(uint256 amount) public

Input Parameters | Type | Description
---|---|---
amount | uint256 | Take out the quantity


> 6.receive：function getETH() public

Receive ETH dividends

## Dividend function instructions

It cannot be deposited during the period of receiving dividends, and when it is deposited has no effect on the final dividends. The NEST that has been deposited can be retrieved at any time, and the number of dividends that can be received after the retrieval is reduced proportionally.

## Dividend function design description
> Option 1: Smart Contracts Batch Transfers and Dividends

Reason for deprecation: The maximum limit of the gas limit for a single block is about 8 million, which is equivalent to 100 internal contract transfers. If there are too many dividends, the operation cannot be realized, and the operators need to pay a large amount of miners.

> Option 2: Centralized server dividends

Reason for deprecation: The centralization is too strong, and the project party needs to extract 10% dividend as the dividend miner

> Option 3: Locking bin dividends (in use)

Reason for use: more decentralized, cancel 10% dividends, and return the operating rights and decision-making rights of dividends to the users.

> PS: Why take a lock mechanism

The dividend distribution algorithm is: receiving the ETH in the dividend pool according to the proportion of the number of NESTs held by the individual in the total circulation. In the process of dividend distribution, the uniqueness of the dividends received by NEST must be guaranteed, that is, each NEST can only receive one dividend in one dividend period.






