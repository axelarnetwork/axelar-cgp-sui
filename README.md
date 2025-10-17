# Axelar CGP Sui

An implementation of the Axelar cross-chain contracts in Move for the Sui blockchain.

Generated docs can be found [here](https://axelarnetwork.github.io/axelar-cgp-sui/).

## Installation

Install Sui as shown [here](https://docs.sui.io/guides/developer/getting-started/sui-install). We recommend using the pre-built binaries from the [Sui releases](https://github.com/MystenLabs/sui/releases) page. The version of Sui that should be used can be found [here](./version.json).

Install node.js 18+

Build all Move packages

```sh
npm ci

npm run build
```

## Testing

Run tests for all Move packages

```sh
npm run test
```

If golden test data needs to be updated (such as if public interfaces have changed), then run

```sh
GOLDEN_TESTS=true npm run test
```

### Coverage

To run code coverage, a Sui debug binary needs to be built locally. You can also see coverage reports from the GH actions.

```sh
brew install libpq
brew link --force libpq
```

```sh
npm run coverage
```

See `.coverage.info` for the coverage report.

### Development

Install the `Move` extension in VS Code. It should come pre-installed with `move-analyzer`.

Move Book: https://move-book.com
Move Examples: https://examples.sui.io

Sui framework dependency is pinned to a specific mainnet [release](https://github.com/MystenLabs/sui/releases) for all packages for consistency.

## Deployment and Operations

Official Sui deployment and operations scripts can be found [here](https://github.com/axelarnetwork/axelar-contract-deployments/tree/main/sui#sui-deployment-scripts).

## Release Process

Please check the [release process](./RELEASE.md) for more details.

## Gateway

The gateway lives in a few modules but has all of its storage in a single shared object called `AxelarSigners`.

## Relayer Spec

Relaying to Sui is a bit complicated: the concept of 'smart contracts' is quite warped compared to EVM chains.

### The Problems

Firstly, all persistent storage stems from `Objects` that have the `key` property and are either shared or owned by an account. These objects have a specific `type`, which is defined in a certain module, and only that module can access their storage (either to read or to write to it). This means that instead of calling a smart contract with some data, in Sui one needs to call a module, pass the Objects that are to be modified as arguments, alongside extra arguments that specify the kind of change that should occur. This additionally means that the concept of `msg.sender` does not apply to applications, and a certain `capability` object that functions like a 'key' to unlock certain functionality needs to be used instead.

The second issue is the lack of interfaces whatsoever. It is impossible for a module to ever call a module that is published at a later time. This means applications that want to interface with future applications must be called by those future applications, but need to call pre-existing ones. To expand on this, we expect contract calls that are received to potentially modify the storage of multiple objects in a single call, which makes it impossible to require modules to implement a 'standardized' function that a relayer will call, because the number of arguments required varies depending on the application (or the type of call).

Finally, we do not want to require the payload of incoming calls to have a certain format, because that would mean that working applications that want to exapnd to Sui need to redesign their working protocoll to accomodate Sui, discouraging them from doing so.

### The Solutions

First of all, as we mentioned before, for applications to 'validate' themselves with other applications need to use a `capability` object. This object will be called `Channel`, and it will hold information about the executed contract calls as well. It has a field called `id` which specifies the 'address' of the application for the purposed of incoming and outgoing extenral calls. This `id` has to match the `id` of a shared object that is passed in the channel creation method (alongside a witness for security). This shared object can easily be querried by the relayer to get call fullfilment information. Specifically:

- The shared object has to have a field called `get_call_info_object_ids` that is a `vector<address>`.
- The module that defined the shared object type has to implement a function called `get_call_info`, which has no types, and takes the incoming call `payload` as the first argument, followed by a number of shared objects whose ids are specified by the `get_call_info_object_ids` mentioned above. This function has to return a `std::ascii::String` which is the JSON encoded call data to fullfill the contract call.
- This calldata has the following 3 fields:
  - `target`: the target method, in the form of `package_id::module_name::function_name`.
  - `arguments`: an array of arguments that can be:
    - `contractCall`: the `ApprovedMessage` object (see below).
    - `pure:${info}`: a pure argument specified by `$info`.
    - `obj:${objectId}`: a shared object with the specified `id`.
  - `typeArguments`: a list of types to be passed to the function called

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

### Service

This is the module that anyone would directly interract with. It needs to be able to do the following

- `register_coin_from_info<T>`: This function takes the `InterchainTokenService` object and mutates it by adding a coin with the specified name, symbol, decimals, and `CoinManagement<T>`.
- `register_coin_from_metadata<T>`: This function takes the `InterchainTokenService` object and mutates it by adding a coin with the specified `CoinMetadata<T>` and `CoinManagement<T>`.
- `register_coin_metadata`: This function takes the `CoinMetadata<T>` for a token, and prepares a message for Axelar Hub to register the coin's decimal precision and Sui coin type. The returned `MessageTicket` can be broadcast to the `Gateway` contract to enable linking the coin as an interchain token.
- `link_coin`: This function takes the token linking parameters (`Channel`, salt, destination token, chain and `TokenManagerType`) for a registered coin type, and prepares a `Gateway` message for Axelar Hub. The returned `MessageTicket` can be broadcast to the `Gateway` contract to link the coin to the destination token via Axelar Hub.

