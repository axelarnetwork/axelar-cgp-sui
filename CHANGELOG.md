# @axelar-network/axelar-cgp-sui

## 1.1.3

### Patch Changes

- 6356a95: Support mint/burn token register mode in Example module

## 1.1.2

### Patch Changes

- 2efe9a2: Renamed GasCollectorCap to OperatorCap to have more consistent roles across contracts
- 8cc6b8f: Add an owner cap to the GasService and change allow/dissalow_function to work with it.

## 1.1.1

### Patch Changes

- 2aa0674: Change the bcs script to include the new GasServiceV0 structure

## 1.1.0

### Minor Changes

- 81888b8: Change ITS from tracking addresses of remote chains to only tracking trusted chains and always using the ITS HUB.
- 2603003: added the ability to accept multiple coin types at the gas service.
- 56ed455: Changed unregistered token-id derivation to contain a prefix
- 388b537: Added a lot of comments in the abi code for clarity.
- e070df9: Add operator cap to ITS and allow operator to overwrite flow limits
- 2d6d8e6: rename its to interchain_token_service everywhere
- d27fc88: Add read_raw_bytes and write_raw_bytes to abi to support more data formats.

### Patch Changes

- 86f95ea: Removing pre-existing dirs before copying a new one in copyMovePackage
- 72cd3f9: Using prettier-move formatter for move files

## 1.0.2

### Patch Changes

- ee155fd: Fix publish template interchain token

## 1.0.1

### Patch Changes

- d9a6492: Bump sui version from testnet-v1.38.2 to mainnet-v1.38.3

## 1.0.0

### Major Changes

- af17dcb: Change to sui testnet-v1.38.2

### Minor Changes

- e8a50a7: added randomness to all axelar gateway tests
- 7dd615b: Removed remote decimals tracking from ITS as it will be handled at the hub.
- 409d52f: Paying for gas now requires the message ticket instead of the call information.
- 952c2e7: Add events to register and remove transaction on relayer discovery
- c165a48: Add allow_function and disallow_function on gas_service
- 167786c: Add allow_function and disallow_function to relayer_discovery.
- ce71858: add allow and disallow functions in ITS
- 9f656e2: Added js e2e tests for squid, and fixed a few things with squid as well.
- ada6fd9: Add a query for version on version_control, change CreatorCap to OwnerCap and allow owner to set allowed functions in gateway
- d0bfec4: move all events of gas service to gas_service::events and all logic to the versioned contract.
- bc498d6: added allow_function and disallow_function to squid

### Patch Changes

- 7a498e9: added events to its trusted address adding and removing
- cd52fed: added access to set flow limit on its and a corresponding event

## 0.8.0

### Minor Changes

- 86cde3b: Fix ITS discovery and verify it in tests.

### Patch Changes

- 9d36662: feat: export approve and execute functions
- 3464917: chore: bump sui version to 1.35.2
- f9840b2: chore: split builds for CJS, ESM, and Web

## 0.7.1

### Patch Changes

- e2c7319: create an npm task for snapshot release and cleanup workflow names

## 0.7.0

### Minor Changes

- ab20e4b: rename versioned gateway module to Gateway_v0
- 3d82969: format all packages with Move Prettier
- 3ea77b1: Add missing its events
- 1893cea: Added Versioned support to the gas_service.
- c1cddc5: change set_trusted_addresses to remove goverance dep on its.
- aeb5fff: Added versioned to the discovery module, and moved some of its functionality to a different module.
- 62ea830: Added events file and move all logic to versioned.
- eb544af: Move relayer discovery to its own package.
- bbed403: Making ITS into a versioned contract, and changing the layout

### Patch Changes

- ff8caeb: feat: added structs for versioned contracts
- 4fbb9ee: add gateway proof redundant signature check

## 0.6.4

### Patch Changes

- bc28614: chore: add a helper fucntion to get local dependencies
- 0afa15c: refactor: simplified updateMoveToml
- 323a0ce: refactor: update error codes to vector<u8>

## 0.6.3

### Patch Changes

- 9716da3: refactor: auth module in axelar_gateway package

## 0.6.2

### Patch Changes

- b0cb54e: refactor: weighted_signers module
- 39bf114: refactor: discovery module
- 7f36eea: refactor: proof module
- 8cb75ed: feat: use channel to figure out source address for its
- 544d8e1: chore: apply macro function to reduce duplication in gateway contract

## 0.6.1

### Patch Changes

- a19430c: chore: refactor gateway contract to use enum
- 396cc29: chore: include version.json in published package
- 3bcb7d3: chore: make sui workflow reusable

## 0.6.0

### Minor Changes

- 2dccf33: Using a custom hot potato object for the operators module instead of Sui's Borrow, because our design fits better this way.

### Patch Changes

- fd494a4: Updated sui rev to testnet-v1.32.0

## 0.5.0

### Minor Changes

- 26a618f: Formatted move modules with "Prettier Move" plugin to compatible with Sui 1.32.0

### Patch Changes

- ed0e5d0: chore: add more structs

## 0.4.1

### Patch Changes

- cf4ead4: Fixed publish error in docker container environment by removing the tmp package.
- fd297c7: Added Bag and Operator bcs structs
- d86325e: Renamed test package to example

## 0.4.0

### Minor Changes

- 523e24c: Use hot potato pattern with `sui::borrow` package for loan out a capabilities in operators contract.

### Patch Changes

- 86d7fa3: Include gas payment into test contract's `send_call` function
- ab7235b: Remove postinstall script and src directory from published content

## 0.3.1

### Patch Changes

- 86d7fa3: Include gas payment into test contract's `send_call` function
- ab7235b: Remove postinstall script and src directory from published content

## 0.3.0

### Minor Changes

- 5e28d52: Update to the Sui Typescript SDK v1

### Patch Changes

- 5c829ce: Remove all hardcoded addresses

## 0.2.0

### Minor Changes

- b1f9ca6: added previous signer retention in gateway setup
- 7441218: move source copy util to avoid modifying sources in place
- 2dc62d0: move package build util

### Patch Changes

- 1b8d4b6: Added UID type
