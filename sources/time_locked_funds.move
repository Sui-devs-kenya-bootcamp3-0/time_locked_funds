#[allow(unused_variable, unused_use, duplicate_alias, lint(coin_field))]
module time_locked_funds::savings {
    // Importing libraries
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::event;

    // Error codes
    const ENotRecipient: u64 = 0;
    const ETimeNotElapsed: u64 = 1;
    const ENotSender: u64 = 2;

    // Object to store funds and release conditions
    public struct LockedFunds has key, store {
        id: UID,
        funds: Coin<SUI>,
        recipient: address,
        sender: address,  // Added sender for verification
        release_time: u64, // Timestamp in milliseconds
    }

    // Event emitted when funds are locked
    public struct FundsLocked has copy, drop {
        object_id: ID,
        sender: address,
        recipient: address,
        amount: u64,
        release_time: u64,
    }

    // Event emitted when funds are released
    public struct FundsReleased has copy, drop {
        object_id: ID,
        recipient: address,
        amount: u64,
    }

    // Event emitted when funds are canceled
    public struct FundsCanceled has copy, drop {
        object_id: ID,
        sender: address,
        amount: u64,
    }

    // Lock funds for a recipient with a duration
    public entry fun lock_funds(
        funds: Coin<SUI>,
        recipient: address,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let release_time = current_time + duration_ms;

        let locked_funds = LockedFunds {
            id: object::new(ctx),
            funds,
            recipient,
            sender,  // Store the sender address
            release_time,
        };

        let object_id = object::uid_to_inner(&locked_funds.id);
        let amount = coin::value(&locked_funds.funds);

        event::emit(FundsLocked {
            object_id,
            sender,
            recipient,
            amount,
            release_time,
        });

        transfer::public_transfer(locked_funds, sender);
    }

    // Released funds to the recipient after the lock period
    public entry fun release_funds(
        locked_funds: LockedFunds,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(locked_funds.recipient == sender, ENotRecipient);
        assert!(clock::timestamp_ms(clock) >= locked_funds.release_time, ETimeNotElapsed);

        let LockedFunds { id, funds, recipient, sender: _, release_time: _ } = locked_funds;
        let object_id = object::uid_to_inner(&id);
        let amount = coin::value(&funds);

        event::emit(FundsReleased {
            object_id,
            recipient,
            amount,
        });

        transfer::public_transfer(funds, recipient);
        object::delete(id);
    }

    // Cancel the lock and return funds to the sender before release time
    public entry fun cancel_lock(
        locked_funds: LockedFunds,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_sender = tx_context::sender(ctx);
        // Verify that the caller is the original sender
        assert!(locked_funds.sender == current_sender, ENotSender);
        // Ensure cancellation is only possible before the release time
        assert!(clock::timestamp_ms(clock) < locked_funds.release_time, ETimeNotElapsed);

        let LockedFunds { id, funds, recipient: _, sender, release_time: _ } = locked_funds;
        let object_id = object::uid_to_inner(&id);
        let amount = coin::value(&funds);

        event::emit(FundsCanceled {
            object_id,
            sender,
            amount,
        });

        transfer::public_transfer(funds, sender);
        object::delete(id);
    }

    // View function to check locked funds details
    public fun get_locked_funds_details(locked_funds: &LockedFunds): (address, address, u64, u64) {
        (
            locked_funds.recipient, 
            locked_funds.sender,
            locked_funds.release_time, 
            coin::value(&locked_funds.funds)
        )
    }
}