# Sui Axelar Gateway and ITS Integration

Sui is a smart contract chain that offers some unique design parameters. For this reason there have been a few differences between the implementation of smart contracts on Sui compared to EVM chains, that are used as reference

## General Limitations

| Limit | Minimum | Recommended | Sui Gateway |
|-|-|-|-|
| Cross-chain Message Size | 16 KB | 64 KB | 16 KB |
| Chain Name Length | < 20 ASCII chars | - | - |
| Signer Set Size | 40 signers | 100 signers | 313 |
| Signature Verification | 27 signatures | 67 signatures | 140 |
| Message Approval Batching | 1 | Configurable | > 105 |
| Storage Limit for Messages | Practically unlimited (2^64) | Practically unlimited (2^64) | Practically unlimited |
| Event Retention | 2 weeks | 2 months | Unlimited |

### Design Limitation

There are quite a few differences between EVM and Sui.

In Sui, there are packages and modules that can run code, similar to EVM smart contracts. A big difference however is that Sui packages/modules do not have any storage available. Storage as a concept only exists on objects, which can be defined and controlled by modules. To access and modify any storage the corresponding object needs to be available. This means that conventional EVM smart contracts effectively combine the functionality of modules and objects in Sui.

Additionally there is a lack of interfaces whatsoever. It is impossible for a module to ever call another module that is published at a later time. This means applications that want to interface with future applications must be called by those future applications, but need to only call pre-existing ones. To expand on this, we expect contract calls that are received to potentially modify the storage of multiple objects in a single call, which makes it impossible to require modules to implement a 'standardized' function that a relayer will call, because the number of arguments required varies depending on the application (or the type of call).

Package "upgrades" result in a new, upgraded package being created, while preserving the old package. This new package can modify objects created by the old package, but any external modules that are using the old package will continued to do so, until they are upgraded too. This means that maintaining packages that depend on multiple existing packages is quite difficult if the dependancies are expected to upgrade.

Finally, we do not want to require the payload of incoming calls to have a certain format, because that would mean that working applications that want to exapnd to Sui need to redesign their working protocoll to accomodate Sui, discouraging them from doing so.

### Basic Limitations

See [this doc](https://move-book.com/guides/building-against-limits.html) for reference. The gas limit for sui is 50 SUI, which is over 100 times larger than any transaction needed for this context. There is also a transaction size limit of 128KB. Objects cannot be more than 256KB in size and there cannot be more than 1024 dynamic fields created on an object on a single transaction. See below for how these limitations affect potential designs.

## Axelar Gateway

The Axelar gateway is the remote interface for the Axelar Network to interract with any given chain. The reference implementation for such a smart contract can be found [here](https://github.com/axelarnetwork/axelar-cgp-solidity), with some design requirements found specifically [here](https://github.com/axelarnetwork/axelar-gmp-sdk-solidity/blob/main/contracts/gateway/INTEGRATION.md)

The Sui message sending looks like this

```mermaid
flowchart LR
    User(User)
    SG[Source Gateway]
    MT[(MessageTicket)]

    User -->|prepare_message| SG --> MT --> |send_message| SG
    SG -.->|ContractCall event| SG
    SG -->|Confirm event| AXL
```

Receiving calls looks like this (see below for relayer discovery)

```mermaid
flowchart LR
    DG[Destination Gateway]
    RD[Relayer Discovery]
    AXL{Axelar Amplifier}
    Contract[Destination contract]
    Transaction[(Transaction)]

    AXL -->|approve_messages| DG
    Relayer -->|consume_approved_message| DG --> |ApprovedMessage| Transaction
    Relayer -->|get_transaction| RD --> Transaction --> Contract
```

The verifier/signer rotation flow looks like the following:

```mermaid
flowchart LR
    AXL{Axelar Amplifier}
    DG[Destination Gateway]

    AXL -.->|Verifier set change| AXL
    AXL -->|rotate_signers| DG
    DG -.->|SignersRotated event| DG
    DG --->|Confirm event| AXL
```
## Relayer Discovery

The only information about an incoming contract call through axelar are

- Command Id: A unique identifier for the command approving the call, 32 bytes long.
- Source Chain: The name of the source chain, as a String
- Source Address: The caller, as a String.
- Destination Chain: “Sui” for the purposes of this document
- Destination Address: The destination, a Sui address.

As we already explained, the destination address will be the `ID` of a `GatewayChannel` object that needs to be provided to consume the call. However there is no way for a relayer to know what they are supposed to call to get the call to be consumed, since they should not have access to the `GatewayChannel` object itself. This creates the need to make the destination for each incoming call publicly known so that any relayer can query it. 

### Transaction Object

The following objects are defined in the `axelar::discovery`  module and can be used to register/decode transactions.

```rust
struct Function has store, copy, drop {
	package_id: address,
	module_name: String,
	name: String,
}

/// Arguments are prefixed with:
/// - 0 for objects followed by exactly 32 bytes that cointain the object id
/// - 1 for pures followed by the bcs encoded form of the pure object
/// - 2 for the ApprovedCall object, followed by nothing (to be passed into the target function)
/// - 3 for the payload of the contract call (to be passed into the intermediate function)
/// - 4 for an argument returned from a previous move call, followed by a u8 specified which call to get the return of (0 for the first transaction AFTER the one that gets ApprovedCall out), and then another u8 specifying which argument to input.   
struct MoveCall has store, copy, drop {
	function: Function,
	arguments: vector<vector<u8>>,
	type_arguments: vector<String>,
}
    
public struct Transaction has store, copy, drop {
	is_final: bool,
	move_calls: vector<MoveCall>,
}
```

As seen above there are some options to allow for dynamic objects to be referenced that could not be known on chain, since they do not exist on chain (the `ApprovedCall` object, the payload of the incoming call and the returned arguments of a previous `MoveCall`). 
