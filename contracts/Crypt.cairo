%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_le, assert_not_zero, assert_lt
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_sub, uint256_add, uint256_check, uint256_lt

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
    BASE_UNIT.write(10**18)

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
##                FEE LOGIC                ##
#############################################

## Fee Configuration ##
@external
func setFeePercent{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    fee: felt
):
    assert_lt(0, fee)
    FEE_PERCENT.write(fee)
    return ()
end

#############################################
##              HARVEST LOGIC              ##
#############################################

@storage_var
func HARVEST_WINDOW() -> (window: felt):
end

@storage_var
func HARVEST_DELAY() -> (delay: felt):
end

@storage_var
func NEXT_HARVEST_DELAY() -> (delay: felt):
end

## @notice Sets a new harvest window.
## @param newHarvestWindow The new harvest window.
## @dev HARVEST_DELAY must be set before calling.
@external
func setHarvestWindow{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    window: felt
):
    # TODO: auth
    let (delay) = HARVEST_DELAY.read()
    assert_le(window, delay)
    HARVEST_WINDOW.write(window)
    return ()
end

## @notice Sets a new harvest delay.
## @param newHarvestDelay The new harvest delay.
@external
func setHarvestDelay{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    new_delay: felt
):
    alloc_locals

    # TODO: auth

    let (local delay) = HARVEST_DELAY.read()
    assert_not_zero(new_delay)
    assert_le(new_delay, 31536000) # 31,536,000 = 365 days = 1 year

    # If the previous delay is 0, we should set immediately
    if delay == 0:
        HARVEST_DELAY.write(new_delay)
    else:
        NEXT_HARVEST_DELAY.write(new_delay)
    end
    return ()
end


#############################################
##            FLOAT REBALANCING            ##
#############################################

## @notice The desired float percentage of holdings.
## @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
@storage_var
func TARGET_FLOAT_PERCENT() -> (percent: Uint256):
end

# const MAX_UINT256 = Uint256(2**128-1, 2**128-1)

## @notice Sets a new target float percentage.
@external
func setTargetFloatPercent{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    new_float: Uint256
):
    alloc_locals

    # TODO: auth

    uint256_check(new_float)
    let (local lt: felt) = uint256_lt(new_float, Uint256(2**128-1, 2**128-1))
    assert lt = 1
    TARGET_FLOAT_PERCENT.write(new_float)
    return ()
end

#############################################
##            STRATEGY STORAGE             ##
#############################################

## @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
## @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
@storage_var
func TOTAL_STRATEGY_HOLDINGS() -> (holdings: Uint256):
end

## @notice Data for a given strategy.
## @param trusted Whether the strategy is trusted.
## @param balance The amount of underlying tokens held in the strategy.
struct StrategyData:
    member trusted: felt # 0 (false) or 1 (true)
    member balance: felt
end

## @notice Maps strategies to data the Vault holds on them.
@storage_var
func STRATEGY_DATA(strategy: felt) -> (data: StrategyData):
end

#############################################
##             HARVEST STORAGE             ##
#############################################

## @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
## @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
@storage_var
func LAST_HARVEST_WINDOW_START() -> (start: felt):
end

## @notice A timestamp representing when the most recent harvest occurred.
@storage_var
func LAST_HARVEST() -> (harvest: felt):
end

## @notice The amount of locked profit at the end of the last harvest.
@storage_var
func MAX_LOCKED_PROFIT() -> (profit: felt):
end

#############################################
##        WITHDRAWAL QUEUE STORAGE         ##
#############################################



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

@external
func underlying{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (underlying: felt):
    let (underlying: felt) = UNDERLYING.read()
    return (underlying)
end

@external
func initialized{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (initialized: felt):
    let (initialized: felt) = INITIALIZED.read()
    return (initialized)
end