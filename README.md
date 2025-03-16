# HyperBoreDAO Escrow

HyperBoreEscrow is a smart contract for managing escrow transactions on ethereum-inspired blockchains. It allows users to create, dispute, and resolve escrows, with the involvement of a DAO multisig for dispute resolution.

## Features

- Create arbitrary, time-boxed escrows, transfering native or ERC-20 compliant tokens (USDC, USDT, etc).
- Easy Resolution & Disputation process.
- DAO Multisig involvement for dispute resolution. In case of requiring a resolution, 5% of funds are sent to the DAO rather than the standard BPF tax.
- Configurable basis point fee for DAO.
- If DAO fails to rule, funds are returned to depositer.

## Treasury Variant

There is another contract in this repo, `Escrow-Treasury`, that divorces payment and contract management. The managing DAO can indicate a treasury address for the purposes of receiving fees, otherwise, contracts are identical.

## Tooling

- This contract uses Hardhat for Testing and Ignition for deployment.
- This contract inherits OpenZeppelin contracts for Security and Safety.

## Caveats

- There is no method for returning escrowIds from this contract
- escrowIds must be tracked externally by indexing for emitted events.
- updating the daoMultisig requires the daoMultisig to do so - if access to the daoMultisig is lost, this contract will lock deposited funds forever.

## Contract Details

### Constructor

```solidity
constructor(address _daoMultisig)
```

- `_daoMultisig`: The address of the DAO multisig. Must not be the zero address.

### Functions

`updateBasisPointFee`

```solidity
function updateBasisPointFee(uint16 _newBasisPointFee) external
```

- Updates the basis point fee for the DAO.
- Only callable by the DAO Multisig.
- `_newBasisPointFee`: The new basis point fee. Must be between 10 and 500.

`updateDAOMultisig`

```solidity
function updateDAOMultisig(address _newMultisig) external
```

- Updates the DAO multisig address (in case of moving multisig providers)
- Only callable by the current DAO multisig
- `_newMultisig`: The new DAO multisig address. Must not be the zero address.

`createEscrow`

```solidity
function createEscrow(
    address _payee,
    address _token,
    uint256 _amount,
    uint256 _deadline,
    uint256 _daoDeadline
) external payable
```

- Creates a new escrow.
- `_payee`: The address of the payee. Must not be the zero address.
- `_token`: The address of the ERC-20 token being escrowed (use address(0) for ETH).
- `_amount`: The amount to be escrowed.
- `_deadline`: The deadline for the payer to release funds.
- `_daoDeadline`: The deadline for the DAO to resolve disputes. Must be after `_deadline`.

`dispute`

```solidity
function dispute(uint256 _escrowId) external escrowExists(_escrowId)
```

- Raises a dispute for an escrow.
- Only callable by the payer.
- `_escrowId`: the ID of the escrow.

`daoDispute`

```solidity
function daoDispute(uint256 _escrowId) external escrowExists(_escrowId)
```

- Raises a dispute for an escrow by the DAO.
- Only callable by the DAO multisig.
- `_escrowId`: The ID of the escrow.

`resolveDispute`

```solidity
function resolveDispute(uint256 _escrowId, uint8 _resolutionStatus) external escrowExists(_escrowId)
```

- Resolves a dispute for an escrow.
- Only callable by the DAO multisig.
- `_escrowId`: The ID of the escrow.
- `_resolutionStatus`: The resolution status (4 for payee, 5 for payer).

`release`

```solidity
function release(uint256 _escrowId) external escrowExists(_escrowId)
```

- Releases funds to the payee.
- Only callable by the payer.
- ``_escrowId`: The ID of the escrow.

`returnFunds`

```solidity
function returnFunds(uint256 _escrowId) external escrowExists(_escrowId)
```

- Returns funds to the payer after the deadline.
- Only callable by the payer.
- `_escrowId`: The ID of the escrow.

`releaseAfterDeadline`

```solidity
function releaseAfterDeadline(uint256 _escrowId) external escrowExists(_escrowId)
```

- Returns funds to the payer after the deadline.
- Only callable by the payer.
- `_escrowId`: The ID of the escrow.

`withdraw`

```solidity
function withdraw(uint256 _escrowId) external payable nonReentrant escrowExists(_escrowId)
```

- Withdraws funds from the escrow.
- Callable by the DAO multisig, payer, or payee.
- `_escrowId`: The ID of the escrow.

## Events

Deployments/upgrades of this contract should index these events for data analysis, alerts for requests for dispute resolution, and connecting users to their escrows through front ends.

- `EscrowCreated(uint256 indexed escrowId, address indexed payer, address indexed payee, uint256 amount, address token)`
- `FundsWithdrawn(uint256 indexed escrowId, address recipient, uint256 amount)`
- `DisputeRaised(uint256 indexed escrowId)`
- `DisputeResolved(uint256 indexed escrowId, uint8 newStatus)`
- `DAOAddressChanged(address indexed daoMultisig)`
- `BasisPointFeeChanged(uint16 indexed basisPointFee)`
