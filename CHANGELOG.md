# @axelar-network/axelar-cgp-sui

## 0.7.1

### Patch Changes

-   e2c7319: create an npm task for snapshot release and cleanup workflow names

## 0.7.0

### Minor Changes

-   ab20e4b: rename versioned gateway module to Gateway_v0
-   3d82969: format all packages with Move Prettier
-   3ea77b1: Add missing its events
-   1893cea: Added Versioned support to the gas_service.
-   c1cddc5: change set_trusted_addresses to remove goverance dep on its.
-   aeb5fff: Added versioned to the discovery module, and moved some of its functionality to a different module.
-   62ea830: Added events file and move all logic to versioned.
-   eb544af: Move relayer discovery to its own package.
-   bbed403: Making ITS into a versioned contract, and changing the layout

### Patch Changes

-   ff8caeb: feat: added structs for versioned contracts
-   4fbb9ee: add gateway proof redundant signature check

## 0.6.4

### Patch Changes

-   bc28614: chore: add a helper fucntion to get local dependencies
-   0afa15c: refactor: simplified updateMoveToml
-   323a0ce: refactor: update error codes to vector<u8>

## 0.6.3

### Patch Changes

-   9716da3: refactor: auth module in axelar_gateway package

## 0.6.2

### Patch Changes

-   b0cb54e: refactor: weighted_signers module
-   39bf114: refactor: discovery module
-   7f36eea: refactor: proof module
-   8cb75ed: feat: use channel to figure out source address for its
-   544d8e1: chore: apply macro function to reduce duplication in gateway contract

## 0.6.1

### Patch Changes

-   a19430c: chore: refactor gateway contract to use enum
-   396cc29: chore: include version.json in published package
-   3bcb7d3: chore: make sui workflow reusable

## 0.6.0

### Minor Changes

-   2dccf33: Using a custom hot potato object for the operators module instead of Sui's Borrow, because our design fits better this way.

### Patch Changes

-   fd494a4: Updated sui rev to testnet-v1.32.0

## 0.5.0

### Minor Changes

-   26a618f: Formatted move modules with "Prettier Move" plugin to compatible with Sui 1.32.0

### Patch Changes

-   ed0e5d0: chore: add more structs

## 0.4.1

### Patch Changes

-   cf4ead4: Fixed publish error in docker container environment by removing the tmp package.
-   fd297c7: Added Bag and Operator bcs structs
-   d86325e: Renamed test package to example

## 0.4.0

### Minor Changes

-   523e24c: Use hot potato pattern with `sui::borrow` package for loan out a capabilities in operators contract.

### Patch Changes

-   86d7fa3: Include gas payment into test contract's `send_call` function
-   ab7235b: Remove postinstall script and src directory from published content

## 0.3.1

### Patch Changes

-   86d7fa3: Include gas payment into test contract's `send_call` function
-   ab7235b: Remove postinstall script and src directory from published content

## 0.3.0

### Minor Changes

-   5e28d52: Update to the Sui Typescript SDK v1

### Patch Changes

-   5c829ce: Remove all hardcoded addresses

## 0.2.0

### Minor Changes

-   b1f9ca6: added previous signer retention in gateway setup
-   7441218: move source copy util to avoid modifying sources in place
-   2dc62d0: move package build util

### Patch Changes

-   1b8d4b6: Added UID type
