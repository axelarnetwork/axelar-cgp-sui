module squid::swap_type;

use sui::bcs::BCS;

// ------
// Errors
// ------
#[error]
const EInvalidSwapType: vector<u8> = b"invalid swap type.";

// -----
// Enums
// -----
public enum SwapType has drop, copy, store {
    DeepbookV3,
    SuiTransfer,
    ItsTransfer,
}

// -----------------
// Package Functions
// -----------------
public(package) fun deepbook_v3(): SwapType {
    SwapType::DeepbookV3
}

public(package) fun sui_transfer(): SwapType {
    SwapType::SuiTransfer
}

public(package) fun its_transfer(): SwapType {
    SwapType::ItsTransfer
}

public(package) fun peel(bcs: &mut BCS): SwapType {
    let swap_type = bcs.peel_u8();
    if(swap_type == 0) {   
        SwapType::DeepbookV3
    } else if(swap_type == 1) {
        SwapType::SuiTransfer   
    } else if(swap_type == 2) {
        SwapType::ItsTransfer
    } else {
        abort (EInvalidSwapType)
    }
}
