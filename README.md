# Axelar CGP Sui

An implementation of the Axelar gateway for the Sui blockchain.

## Installation

Install Sui and run a local Sui network: https://docs.sui.io/build/sui-local-network.
The copy `.env.exaple` to `.env` and add a valid private key for sui. If you want to deploy to testnet you shoukd have its address be funded.

## Deployment

To deploy to testnet run `node scripts/publish-package axelar testnet` 

## Testing

run `npm run test` to run move tests on all the move packages.

## Scripts

First run `node scripts/publish-package` and then any of `node scripts/<testScritpt>` which can be `test-receive-call`, `test-send-call`, and `test-transfer-operatorship`.

## Gateway

The gateway lives in a few modules but has all of its storage in a single shared object called `AxelarValidators`. This is not very aptly named and we might rename it.

## ITS spec

The ITS on sui is supposed to be able to receive 3 messages:
- Register Coin: The payload will be abi encoded data that looks like this:                              
  `4`: `uint256`, fixed,
  `tokenId`: `bytes32`, fixed,
  `name`: `string`, variable,
  `symbol`: `string`, variable,
  `decimals`: `uint8`, fixed,
  `distributor`: `bytes`, variable,
  `mintTo`: `bytes`, variable,
  `mintAmount`: `uint256`, variable,
  `operator`: `bytes`, variable,
Don't worry about the distributor and operator for now

- Receive coin: The payload will be abi encoded data that looks like this:
  `1`, `uint256`, fixed,
  `tokenId`, `bytes32`, fixed,
  `destinationAddress`, `bytes`, variable (has to be converted to address),
  `amount`, `uint256`, fixed,

- Receive coin with data: The payload will be abi encoded data that looks like this:
  `2`, `uint256`, fixed,
  `tokenId`, `bytes32`, fixed,
  `destinationAddress`, bytes, variable (has to be converted to address),
  `amount`, `uint256`, fixed,
  `sourceChain`, `string`, variable,
  `sourceAddress`, `bytes`, variable
This needs to return the coin object only if called with the right capability (another channel) that proves the caller is the `destinationAddress`

ITS also needs to be able to send 2 calls, the call to receive coin and the call to receive coin with data, only id the right coin object is received. Since coins are only u64 some conversion might need to happen when receiving coins (decimals of 18 are too large for Sui to handle).

## ITS Design

### Coin Management

This module and the object it creates (`CoinManagement<T>`) will tell if a coin is registered as a mint/burn or lock unlock token.

To create a `CoinManagement` object one has to call
- `mint_burn<T>`, passing in a `TreasuryCap<T>`.
- `lock_unlock<T>`.
- `lock_unlock_funded<T>` passing in some initial `Coin<T>` to lock.

A distributor can also be added before registerring a coin (this is not completely flushed out)

### Coin Info

This module and the object it creates `CoinInfo<T>` will tell the ITS the information (name, symbol, decimals) for this coin. This information cannot (necesairily) be validated on chain because of how `coin` is implemented, which means that we have to accept whatever the registrar tells us for it. If the `CoinMetadata<T>` exists, we can also take it and create a 'validated' version of `CoinInfo<T>`.

### Token Id

This module is responsible for creating tokenIds for both registerred and 'unregistered' (coins that are given to the ITS expecting a remote incoming `DEPLOY_INTERCHAIN_TOKEN` message) coins. We might just go back to using addresses because the UX would slightly improve, but doing it this way improves code readablility and is more in line with what Sui tries to do.

### Storage

This module is responsible for managing all of the storage needs of the ITS

### Service

This is the module that anyone would directly interract with. It needs to be able to do the following

- `register_coin<T>`: This function takes the `ITS` object and mutates it by adding a coin with the specified `CoinManagement<T>` and `CoinInfo<T>`.
