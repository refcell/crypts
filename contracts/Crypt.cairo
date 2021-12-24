%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_sub, uint256_add

## @title Crypt
## @description Flexible, minimalist, and gas-optimized yield aggregator for earning interest on any ERC20 token.
## @description Adapted from Rari Capital's Vaults: https://github.com/Rari-Capital/vaults
## @author Alucard <github.com/a5f9t4>

#############################################
##                 STORAGE                 ##
#############################################

#############################################
##               ERC20 Logic               ##
#############################################

@storage_var
func NAME() -> (NAME: felt):
end

@storage_var
func SYMBOL() -> (SYMBOL: felt):
end

@storage_var
func DECIMALS() -> (DECIMALS: felt):
end

@storage_var
func TOTAL_SUPPLY() -> (TOTAL_SUPPLY: Uint256):
end

@storage_var
func BALANCE_OF(account: felt) -> (BALANCE: Uint256):
end

@storage_var
func ALLOWANCE(owner: felt, spender: felt) -> (REMAINING: Uint256):
end

#############################################
##               Crypt Logic               ##
#############################################

@storage_var
func UNDERLYING() -> (address: felt):
end

@storage_var
func BASE_UNIT() -> (unit: felt):
end

@storage_var
func INITIALIZED() -> (res: felt):
end

@storage_var
func FEE_PERCENT() -> (fee: felt):
end

#############################################
##               CONSTRUCTOR               ##
#############################################

@constructor
func constructor{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    underlying: felt
):
    NAME.write(0x0) # TODO: encode string to bytes
    SYMBOL.write(0x0) # TODO: encode string to bytes

    UNDERLYING.write(underlying)
    BASE_UNIT.write(10^18)

    return()
end

@external
func initialize{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}():
    let (_initialized) = INITIALIZED.read()
    assert _initialized = 0
    INITIALIZED.write(1)
    return ()
end

#############################################
##               Crypt LOGIC               ##
#############################################

## Fee Configuration ##
@external
func setFeePercent{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    fee: uint256
):
    assert fee > 0
    FEE_PERCENT.write(fee)
    return ()
end

# 


#############################################
##                                         ##
##               ERC20 LOGIC               ##
##                                         ##
## Since there is no canonical inheritance ##
## pattern, we must implement ERC20 logic. ##
##                                         ##
#############################################


@external
func approve{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    spender: felt,
    amount: Uint256
) -> (success: felt):
    ## Manually fetch the caller address ##
    let (caller) = get_caller_address()

    ## CHECKS ##
    assert_not_zero(caller)
    assert_not_zero(spender)
    uint256_check(amount)

    ## EFFECTS ##
    ALLOWANCE.write(caller, spender, amount)

    ## NO INTERACTIONS ##

    return (1) # Starknet's `true`
end

@external
func increaseAllowance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    spender: felt,
    amount: Uint256
) -> (success: felt):
    alloc_locals
    uint256_check(amount)
    let (local caller) = get_caller_address()
    let (local current_allowance: Uint256) = ALLOWANCE.read(caller, spender)

    ## Check allowance overflow ##
    let (local new_allowance: Uint256, is_overflow) = uint256_add(current_allowance, amount)
    assert (is_overflow) = 0

    assert_not_zero(caller)
    assert_not_zero(spender)
    uint256_check(amount)
    ALLOWANCE.write(caller, spender, amount)

    return (1) # Starknet's `true`
end

@external
func decreaseAllowance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    spender: felt,
    amount: Uint256
) -> (success: felt):
    alloc_locals
    uint256_check(amount)
    let (local caller) = get_caller_address()
    let (local current_allowance: Uint256) = ALLOWANCE.read(caller, spender)
    let (local new_allowance: Uint256) = uint256_sub(current_allowance, amount)

    ## Validate allowance decrease ##
    let (enough_allowance) = uint256_lt(new_allowance, current_allowance)
    assert_not_zero(enough_allowance)

    assert_not_zero(caller)
    assert_not_zero(spender)
    uint256_check(amount)
    ALLOWANCE.write(caller, spender, amount)

    return (1) # Starknet's `true`
end


@external
func transfer{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    recipient: felt,
    amount: Uint256
) -> (success: felt):
    let (sender) = get_caller_address()
    _transfer(sender, recipient, amount)

    return (1) # Starknet's `true`
end

@external
func transferFrom{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    sender: felt,
    recipient: felt,
    amount: Uint256
) -> (success: felt):
    alloc_locals
    let (local caller) = get_caller_address()
    let (local caller_allowance: Uint256) = ALLOWANCE.read(owner=sender, spender=caller)

    ## Validate allowance decrease ##
    let (enough_allowance) = uint256_le(amount, caller_allowance)
    assert_not_zero(enough_allowance)

    _transfer(sender, recipient, amount)

    # subtract allowance
    let (new_allowance: Uint256) = uint256_sub(caller_allowance, amount)
    ALLOWANCE.write(sender, caller, new_allowance)

    return (1) # Starknet's `true`
end

## INTERNAL TRANSFER LOGIC ##
func _transfer{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    sender: felt,
    recipient: felt,
    amount: Uint256
):
    alloc_locals

    ## CHECKS ##
    assert_not_zero(sender)
    assert_not_zero(recipient)
    uint256_check(amount)

    let (local sender_balance: Uint256) = BALANCE_OF.read(account=sender)
    let (enough_balance) = uint256_le(amount, sender_balance)
    assert_not_zero(enough_balance)

    ## EFFECTS ##
    ## Subtract from sender ##
    let (new_sender_balance: Uint256) = uint256_sub(sender_balance, amount)
    BALANCE_OF.write(sender, new_sender_balance)

    ## Add to recipient ##
    let (recipient_balance: Uint256) = BALANCE_OF.read(account=recipient)
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, amount)
    BALANCE_OF.write(recipient, new_recipient_balance)

    ## NO INTERACTIONS ##

    return ()
end

#############################################
##                ACCESSORS                ##
#############################################

@view
func name{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (name: felt):
    let (_name) = NAME.read()
    return (name=_name)
end

@view
func symbol{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (symbol: felt):
    let (_symbol) = SYMBOL.read()
    return (symbol=_symbol)
end

@view
func totalSupply{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (totalSupply: Uint256):
    let (_total_supply: Uint256) = TOTAL_SUPPLY.read()
    return (totalSupply=_total_supply)
end

@view
func decimals{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (decimals: felt):
    let (_decimals) = DECIMALS.read()
    return (decimals=_decimals)
end

@view
func balanceOf{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(account: felt) -> (balance: Uint256):
    let (_balance: Uint256) = BALANCE_OF.read(account=account)
    return (balance=_balance)
end

@view
func allowance{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    owner: felt,
    spender: felt
) -> (remaining: Uint256):
    let (REMAINING: Uint256) = ALLOWANCE.read(owner=owner, spender=spender)
    return (remaining=REMAINING)
end
