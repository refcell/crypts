%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import assert_le, assert_not_zero, assert_lt
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_sub, uint256_add, uint256_check, uint256_lt

from contracts.interfaces.IERC20 import IERC20

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

## @notice An ordered array of strategies representing the withdrawal queue.
## @dev The queue is processed in descending order.
## @dev Returns a tupled-array of (array_len, Strategy[])
@storage_var
func WITHDRAWAL_QUEUE() -> (queue: (felt, Strategy*)):
end

## @notice Gets the full withdrawal queue.
## @return An ordered array of strategies representing the withdrawal queue.
func getWithdrawalQueue{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (
    queue_len: felt,
    queue: Strategy*
):
    let (queue_len, queue) = WITHDRAWAL_QUEUE.read()
    return (queue_len, queue)
end

#############################################
##        DEPOSIT/WITHDRAWAL LOGIC         ##
#############################################

## @notice Deposit a specific amount of underlying tokens.
## @param underlyingAmount The amount of the underlying token to deposit.
func deposit{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    underlyingAmount: felt
):
    alloc_locals
    let (local underlying) = UNDERLYING.read()
    let (local caller) = get_caller_address()
    let (local contract) = get_contract_address()

    # Prevent zero deposits for future event handling
    assert_non_zero(underlyingAmount)

    _mint(caller, underlyingAmount.fdiv(exchangeRate(), BASE_UNIT))

    # Transfer in underlying tokens from the user.
    # This will revert if the user does not have the amount specified.
    IERC20.transferFrom(
        contract_address=underlying,
        sender=caller,
        recipient=contract,
        amount=underlyingAmount
    )
    return ()
end

## @notice Withdraw a specific amount of underlying tokens.
## @param underlyingAmount The amount of underlying tokens to withdraw.
func withdraw{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    underlyingAmount: felt
):
    alloc_locals
    let (local underlying) = UNDERLYING.read()
    let (local caller) = get_caller_address()
    let (local contract) = get_contract_address()

    # Prevent zero deposits for future event handling
    assert_non_zero(underlyingAmount)

    # Determine the equivalent amount of rvTokens and burn them.
    _burn(caller, underlyingAmount.fdiv(exchangeRate(), BASE_UNIT))

    # Withdraw from strategies if needed and transfer.
    transferUnderlyingTo(caller, underlyingAmount)

    return ()
end

## @notice Redeem a specific amount of crTokens for underlying tokens.
## @param crTokenAmount The amount of crTokens to redeem for underlying tokens.
func redeem{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    crTokenAmount: Uint256
):
    alloc_locals
    let (local underlying) = UNDERLYING.read()
    let (local caller) = get_caller_address()
    let (local contract) = get_contract_address()

    # Prevent zero deposits for future event handling
    uint256_lt(0, crTokenAmount)

    # Determine the equivalent amount of underlying tokens.
    let (er: Uint256) = exchangeRate()
    let (bu: Uint256) = BASE_UNIT.read()
    let (scaled: Uint256) = uint256_mul(crTokenAmount, er)
    let (underlyingAmount: Unit256) = uint256_div(scaled, bu)

    # Burn the provided amount of crTokens.
    _burn(caller, crTokenAmount)

    # Withdraw from strategies if needed and transfer.
    transferUnderlyingTo(caller, underlyingAmount)
    return ()
end

## @dev Transfers a specific amount of underlying tokens held in strategies and/or float to a recipient.
## @dev Only withdraws from strategies if needed and maintains the target float percentage if possible.
## @param recipient The user to transfer the underlying tokens to.
## @param underlyingAmount The amount of underlying tokens to transfer.
function transferUnderlyingTo(address recipient, uint256 underlyingAmount) internal {
    // Get the Vault's floating balance.
    uint256 float = totalFloat();

    // If the amount is greater than the float, withdraw from strategies.
    if (underlyingAmount > float) {
        // Compute the amount needed to reach our target float percentage.
        uint256 floatMissingForTarget = (totalHoldings() - underlyingAmount).fmul(targetFloatPercent, 1e18);

        // Compute the bare minimum amount we need for this withdrawal.
        uint256 floatMissingForWithdrawal = underlyingAmount - float;

        // Pull enough to cover the withdrawal and reach our target float percentage.
        pullFromWithdrawalQueue(floatMissingForWithdrawal + floatMissingForTarget);
    }

    // Transfer the provided amount of underlying tokens.
    UNDERLYING.safeTransfer(recipient, underlyingAmount);
}

#############################################
##         VAULT ACCOUNTING LOGIC          ##
#############################################

/// @notice Returns a user's Vault balance in underlying tokens.
/// @param user The user to get the underlying balance of.
/// @return The user's Vault balance in underlying tokens.
function balanceOfUnderlying(address user) external view returns (uint256) {
    return balanceOf[user].fmul(exchangeRate(), BASE_UNIT);
}

/// @notice Returns the amount of underlying tokens an rvToken can be redeemed for.
/// @return The amount of underlying tokens an rvToken can be redeemed for.
function exchangeRate() public view returns (uint256) {
    // Get the total supply of rvTokens.
    uint256 rvTokenSupply = totalSupply;

    // If there are no rvTokens in circulation, return an exchange rate of 1:1.
    if (rvTokenSupply == 0) return BASE_UNIT;

    // Calculate the exchange rate by dividing the total holdings by the rvToken supply.
    return totalHoldings().fdiv(rvTokenSupply, BASE_UNIT);
}

/// @notice Calculates the total amount of underlying tokens the Vault holds.
/// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
function totalHoldings() public view returns (uint256 totalUnderlyingHeld) {
    unchecked {
        // Cannot underflow as locked profit can't exceed total strategy holdings.
        totalUnderlyingHeld = totalStrategyHoldings - lockedProfit();
    }

    // Include our floating balance in the total.
    totalUnderlyingHeld += totalFloat();
}

/// @notice Calculates the current amount of locked profit.
/// @return The current amount of locked profit.
function lockedProfit() public view returns (uint256) {
    // Get the last harvest and harvest delay.
    uint256 previousHarvest = lastHarvest;
    uint256 harvestInterval = harvestDelay;

    unchecked {
        // If the harvest delay has passed, there is no locked profit.
        // Cannot overflow on human timescales since harvestInterval is capped.
        if (block.timestamp >= previousHarvest + harvestInterval) return 0;

        // Get the maximum amount we could return.
        uint256 maximumLockedProfit = maxLockedProfit;

        // Compute how much profit remains locked based on the last harvest and harvest delay.
        // It's impossible for the previous harvest to be in the future, so this will never underflow.
        return maximumLockedProfit - (maximumLockedProfit * (block.timestamp - previousHarvest)) / harvestInterval;
    }
}

/// @notice Returns the amount of underlying tokens that idly sit in the Vault.
/// @return The amount of underlying tokens that sit idly in the Vault.
function totalFloat() public view returns (uint256) {
    return UNDERLYING.balanceOf(address(this));
}

#############################################
##              HARVEST LOGIC              ##
#############################################


#############################################
##      STRATEGY TRUST/DISTRUST LOGIC      ##
#############################################


#############################################
##         WITHDRAWAL QUEUE LOGIC          ##
#############################################


#############################################
##          SEIZE STRATEGY LOGIC           ##
#############################################


#############################################
##                                         ##
##               ERC20 LOGIC               ##
##                                         ##
##     Absent a canonical inheritance      ##
##   pattern, we implement ERC20 logic.    ##
##                                         ##
#############################################

func _mint{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    to: felt,
    amount: Uint256
):
    alloc_locals
    assert_not_zero(recipient)
    uint256_check(amount)

    let (balance: Uint256) = BALANCE_OF.read(account=recipient)

    let (new_balance, _: Uint256) = uint256_add(balance, amount)
    BALANCE_OF.write(recipient, new_balance)

    let (local supply: Uint256) = TOTAL_SUPPLY.read()
    let (local new_supply: Uint256, is_overflow) = uint256_add(supply, amount)
    assert (is_overflow) = 0

    TOTAL_SUPPLY.write(new_supply)
    return ()
end

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