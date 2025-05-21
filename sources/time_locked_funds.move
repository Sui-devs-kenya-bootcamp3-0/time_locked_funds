#[allow(unused_variable, unused_use)]
module time_locked_funds::savings {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;

    // ======== Errors ========
    /// Error when the caller is not the designated recipient
    const ENotRecipient: u64 = 0;
    /// Error when attempting to withdraw before lock time has elapsed
    const ELockPeriodNotOver: u64 = 1;
    /// Error when the caller is not the original sender
    const ENotSender: u64 = 2;

    // ======== Types ========
    /// Struct to store locked funds and their release conditions
    /// Uses epochs instead of timestamps for simpler time tracking
    public struct LockedFunds has key, store {
        id: UID,
        funds: Coin<SUI>,
        recipient: address,
        sender: address,
        unlock_epoch: u64, // The epoch when funds become available
    }

    // ======== Events ========
    /// Event emitted when funds are locked
    public struct FundsLocked has copy, drop {
        object_id: ID,
        sender: address,
        recipient: address,
        amount: u64,
        unlock_epoch: u64,
    }

    /// Event emitted when funds are released to recipient
    public struct FundsReleased has copy, drop {
        object_id: ID,
        recipient: address,
        amount: u64,
    }

    /// Event emitted when funds are canceled by sender
    public struct FundsCanceled has copy, drop {
        object_id: ID,
        sender: address,
        amount: u64,
    }

    // ======== Public Functions ========
    /// Lock funds for a recipient with a specified lock period in epochs
    /// * `funds` - The SUI coins to lock
    /// * `recipient` - Address of the recipient who can claim after lock period
    /// * `lock_period_epochs` - Number of epochs to lock the funds
    public entry fun lock_funds(
        funds: Coin<SUI>,
        recipient: address,
        lock_period_epochs: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let unlock_epoch = current_epoch + lock_period_epochs;
        let amount = coin::value(&funds);

        let locked_funds = LockedFunds {
            id: object::new(ctx),
            funds,
            recipient,
            sender,
            unlock_epoch,
        };

        let object_id = object::uid_to_inner(&locked_funds.id);

        // Emit event for indexing and tracking
        event::emit(FundsLocked {
            object_id,
            sender,
            recipient,
            amount,
            unlock_epoch,
        });

        // Transfer the locked funds object to the recipient for easier access
        transfer::public_transfer(locked_funds, recipient);
    }

    /// Release funds to the recipient after the lock period
    /// * `locked_funds` - The LockedFunds object to release
    public entry fun release_funds(
        locked_funds: LockedFunds,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        
        // Verify that caller is the specified recipient
        assert!(locked_funds.recipient == sender, ENotRecipient);
        
        // Verify that the lock period has passed
        assert!(current_epoch >= locked_funds.unlock_epoch, ELockPeriodNotOver);

        // Destructure the locked funds object
        let LockedFunds { 
            id, 
            funds, 
            recipient, 
            sender: _, 
            unlock_epoch: _ 
        } = locked_funds;
        
        let object_id = object::uid_to_inner(&id);
        let amount = coin::value(&funds);

        // Emit event for the funds release
        event::emit(FundsReleased {
            object_id,
            recipient,
            amount,
        });

        // Transfer the funds to the recipient
        transfer::public_transfer(funds, recipient);
        
        // Clean up the object
        object::delete(id);
    }

    /// Cancel the lock and return funds to the sender (only before release time)
    /// * `locked_funds` - The LockedFunds object to cancel
    public entry fun cancel_lock(
        locked_funds: LockedFunds,
        ctx: &mut TxContext
    ) {
        let current_sender = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        
        // Verify that the caller is the original sender
        assert!(locked_funds.sender == current_sender, ENotSender);
        
        // Ensure cancellation is only possible before the unlock epoch
        assert!(current_epoch < locked_funds.unlock_epoch, ELockPeriodNotOver);

        // Destructure the locked funds object
        let LockedFunds { 
            id, 
            funds, 
            recipient: _, 
            sender, 
            unlock_epoch: _ 
        } = locked_funds;
        
        let object_id = object::uid_to_inner(&id);
        let amount = coin::value(&funds);

        // Emit event for the cancellation
        event::emit(FundsCanceled {
            object_id,
            sender,
            amount,
        });

        // Return the funds to the sender
        transfer::public_transfer(funds, sender);
        
        // Clean up the object
        object::delete(id);
    }

    // ======== View Functions ========
    /// Get details about locked funds
    /// Returns a tuple of (recipient, sender, unlock_epoch, amount)
    public fun get_locked_funds_details(locked_funds: &LockedFunds): (address, address, u64, u64) {
        (
            locked_funds.recipient, 
            locked_funds.sender,
            locked_funds.unlock_epoch, 
            coin::value(&locked_funds.funds)
        )
    }
}