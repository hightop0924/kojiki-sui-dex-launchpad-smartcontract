module defi::master_chef {
  use std::ascii::{String};
  use std::vector;
  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};
  use sui::clock::{Self, Clock};
  use sui::balance::{Self, Balance};
  use sui::object_bag::{Self, ObjectBag};
  use sui::object_table::{Self, ObjectTable};
  use sui::table::{Self, Table};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::event;
  use sui::package::{Self, Publisher};
  
  use sake::sake::{Self, SAKE, SakeStorage};

  use library::utils::{get_coin_info_string};
  use library::math::{fdiv_u256, fmul_u256};

  const START_TIMESTAMP: u64 = 2288541374;
  const SAKE_PER_MS: u64 = 10; // 40M SAKE per year
  const SAKE_POOL_KEY: u64 = 0;

  const ERROR_POOL_ADDED_ALREADY: u64 = 1;
  const ERROR_NOT_ENOUGH_BALANCE: u64 = 2;
  const ERROR_NO_PENDING_REWARDS: u64 = 3;
  const ERROR_NO_ZERO_ALLOCATION_POINTS: u64 = 4;

  // OTW
  struct MASTER_CHEF has drop {}

  struct MasterChefStorage has key {
    id: UID,
    sake_per_ms: u64,
    total_allocation_points: u64,
    pool_keys: Table<String, PoolKey>,
    pools: ObjectTable<u64, Pool>,
    start_timestamp: u64,
    publisher: Publisher
  }

  struct Pool has key, store {
    id: UID,
    allocation_points: u64,
    last_reward_timestamp: u64,
    accrued_sake_per_share: u256,
    balance_value: u64,
    pool_key: u64
  }

  struct AccountStorage has key {
    id: UID,
    accounts: ObjectTable<u64, ObjectBag>
  }

  struct Account<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    rewards_paid: u256
  }

  struct PoolKey has store {
    key: u64
  }

  struct MasterChefAdmin has key {
    id: UID
  }

  // Events

  struct SetAllocationPoints<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct AddPool<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct Stake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct Unstake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct NewAdmin has drop, copy {
    admin: address
  }

  fun init(witness: MASTER_CHEF, ctx: &mut TxContext) {
      // Set up object_tables for the storage objects 
      let pools = object_table::new<u64, Pool>(ctx);  
      let pool_keys = table::new<String, PoolKey>(ctx);
      let accounts = object_table::new<u64, ObjectBag>(ctx);

      let coin_info_string = get_coin_info_string<SAKE>();
      
      // Register the SAKE farm in pool_keys
      table::add(
        &mut pool_keys, 
        coin_info_string, 
        PoolKey { 
          key: 0,
          }
        );

      // Register the Account object_bag
      object_table::add(
        &mut accounts,
         0,
        object_bag::new(ctx)
      );

      // Register the SAKE farm on pools
      object_table::add(
        &mut pools, 
        0, // Key is the length of the object_bag before a new element is added 
        Pool {
          id: object::new(ctx),
          allocation_points: 1000,
          last_reward_timestamp: START_TIMESTAMP,
          accrued_sake_per_share: 0,
          balance_value: 0,
          pool_key: 0
          }
      );

        // Emit
        event::emit(
          AddPool<SAKE> {
          key: 0,
          allocation_points: 1000
          }
        );

      // Share MasterChefStorage
      transfer::share_object(
        MasterChefStorage {
          id: object::new(ctx),
          pools,
          sake_per_ms: SAKE_PER_MS,
          total_allocation_points: 1000,
          pool_keys,
          start_timestamp: START_TIMESTAMP,
          publisher: package::claim(witness, ctx)
        }
      );

      // Share the Account Storage
      transfer::share_object(
        AccountStorage {
          id: object::new(ctx),
          accounts
        }
      );

      // Give the admin_cap to the deployer
      transfer::transfer(MasterChefAdmin { id: object::new(ctx) }, tx_context::sender(ctx));
  }

/**
* @notice It returns the number of Coin<SAKE> rewards an account is entitled to for T Pool
* @param storage The SakeStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param account The function will return the rewards for this address
* @return rewards
*/
 public fun get_pending_rewards<T>(
  storage: &MasterChefStorage,
  account_storage: &AccountStorage,
  clock_oject: &Clock,
  account: address
  ): u256 {
    
    // If the user never deposited in T Pool, return 0
    if ((!object_bag::contains<address>(object_table::borrow(&account_storage.accounts, get_pool_key<T>(storage)), account))) return 0;
    // Borrow the pool
    let pool = borrow_pool<T>(storage);
    // Borrow the user account for T pool
    let account = borrow_account<T>(storage, account_storage, account);

    // Get the value of the total number of coins deposited in the pool
    let total_balance = (pool.balance_value as u256);
    // Get the value of the number of coins deposited by the account
    let account_balance_value = (balance::value(&account.balance) as u256);

    // If the pool is empty or the user has no tokens in this pool return 0
    if (account_balance_value == 0 || total_balance == 0) return 0;

    // Save the current epoch in memory
    let current_timestamp = clock::timestamp_ms(clock_oject);
    // save the accrued sake per share in memory
    let accrued_sake_per_share = pool.accrued_sake_per_share;

    let is_sake = pool.pool_key == SAKE_POOL_KEY;

    // If the pool is not up to date, we need to increase the accrued_sake_per_share
    if (current_timestamp > pool.last_reward_timestamp) {
      // Calculate how many epochs have passed since the last update
      let timestamp_delta = ((current_timestamp - pool.last_reward_timestamp) as u256);
      // Calculate the total rewards for this pool
      let rewards = (timestamp_delta * (storage.sake_per_ms as u256)) * (pool.allocation_points as u256) / (storage.total_allocation_points as u256);
      // Update the accrued_sake_per_share
      accrued_sake_per_share = accrued_sake_per_share + if (is_sake) {
        fdiv_u256(rewards, (pool.balance_value as u256))
          } else {
          (rewards / (pool.balance_value as u256))
          };
    };
    // Calculate the rewards for the user
    return if (is_sake) {
      fmul_u256(account_balance_value, accrued_sake_per_share) - account.rewards_paid
    } else {
assert!(accrued_sake_per_share != 0, 0x2fff);
      (account_balance_value * accrued_sake_per_share) - account.rewards_paid
    } 
  }

  fun has_pool_key<T>(storage: &mut MasterChefStorage) : bool {
    table::contains<String, PoolKey>(&storage.pool_keys, get_coin_info_string<T>())
  }

/**
* @notice It allows the caller to deposit Coin<T> in T Pool. It returns any pending rewards Coin<SAKE>
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sake_storage The shared Object of SAKE
* @param clock_object The Clock object created at genesis
* @param token The Coin<T>, the caller wishes to deposit
* @return Coin<SAKE> pending rewards
*/
 fun stake_internal<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  _sake_storage: &mut SakeStorage,
  clock_object: &Clock,
  token: Coin<T>,
  amount: u64,
  ctx: &mut TxContext
 ) {
  // check if the T pool exists. if not, add T pool
  if (!has_pool_key<T>(storage)) {
    add_pool_internal<T>(storage, accounts_storage, clock_object, amount, true, ctx);
  };
  
  // We need to update the pool rewards before any mutation
  
  update_pool<T>(storage, clock_object);
  // Save the sender in memory
  let sender = tx_context::sender(ctx);
  let key = get_pool_key<T>(storage);

   // Register the sender if it is his first time depositing in this pool 
  if (!object_bag::contains<address>(object_table::borrow(&accounts_storage.accounts, key), sender)) {
    object_bag::add(
      object_table::borrow_mut(&mut accounts_storage.accounts, key),
      sender,
      Account<T> {
        id: object::new(ctx),
        balance: balance::zero<T>(),
        rewards_paid: 0
      }
    );
  };

  // Get the needed info to fetch the sender account and the pool
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, sender);
  let is_sake = pool.pool_key == SAKE_POOL_KEY;

  // Initiate the pending rewards to 0
  let pending_rewards = 0;
  
  // Save in memory the current number of coins the sender has deposited
  let account_balance_value = (balance::value(&account.balance) as u256);

  // If he has deposited tokens, he has earned Coin<SAKE>; therefore, we update the pending rewards based on the current balance
  if (account_balance_value > 0) pending_rewards = if (is_sake) {
    fmul_u256(account_balance_value, pool.accrued_sake_per_share)
  } else {
    (account_balance_value * pool.accrued_sake_per_share)
  } - account.rewards_paid;

  // Save in memory how mnay coins the sender wishes to deposit
  let token_value = coin::value(&token);

  // Update the pool balance
  pool.balance_value = pool.balance_value + token_value;
  // Update the Balance<T> on the sender account
  balance::join(&mut account.balance, coin::into_balance(token));
  // Consider all his rewards paid
  account.rewards_paid = if (is_sake) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_sake_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_sake_per_share
  };

  event::emit(
    Stake<T> {
      pool_key: key,
      amount: token_value,
      sender,
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<SAKE> rewards for the caller and sent to caller
  // sake::mint(sake_storage, &storage.publisher, (pending_rewards as u64), ctx)
 }

/**
* @notice It allows the caller to withdraw Coin<T> from T Pool. It returns any pending rewards Coin<SAKE>
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param sake_storage The shared Object of SAKE
* @param clock_object The Clock object created at genesis
* @param coin_value The value of the Coin<T>, the caller wishes to withdraw
* @return (Coin<SAKE> pending rewards, Coin<T>)
*/
 fun unstake_internal<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  sake_storage: &mut SakeStorage,
  clock_object: &Clock,
  coin_value: u64,
  ctx: &mut TxContext
 ): (Coin<SAKE>, Coin<T>) { // (Coin<SAKE> reward, staked coin)
  // Need to update the rewards of the pool before any  mutation
  update_pool<T>(storage, clock_object);
  
  // Get muobject_table struct of the Pool and Account
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  let is_sake = pool.pool_key == SAKE_POOL_KEY;

  // Save the account balance value in memory
  let account_balance_value = balance::value(&account.balance);

  // The user must have enough balance value
  assert!(account_balance_value >= coin_value, ERROR_NOT_ENOUGH_BALANCE);

  // Calculate how many rewards the caller is entitled to
  let pending_rewards = if (is_sake) {
    fmul_u256((account_balance_value as u256), pool.accrued_sake_per_share)
  } else {
    ((account_balance_value as u256) * pool.accrued_sake_per_share)
  } - account.rewards_paid;

  // Withdraw the Coin<T> from the Account
  let staked_coin = coin::take(&mut account.balance, coin_value, ctx);

  // Reduce the balance value in the pool
  pool.balance_value = pool.balance_value - coin_value;
  // Consider all pending rewards paid
  account.rewards_paid = if (is_sake) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_sake_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_sake_per_share
  };

  event::emit(
    Unstake<T> {
      pool_key: key,
      amount: coin_value,
      sender: tx_context::sender(ctx),
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<SAKE> rewards and returns the Coin<T>
  (
    sake::mint(sake_storage, &storage.publisher, (pending_rewards as u64), ctx),
    staked_coin
  )
 } 

 /**
 * @notice It allows a caller to get all his pending rewards from T Pool
 * @param storage The MasterChefStorage shared object
 * @param accounts_storage The AccountStorage shared objetct
 * @param sake_storage The shared Object of SAKE
 * @param clock_object The Clock object created at genesis
 * @return Coin<SAKE> the pending rewards
 */
 fun get_rewards_internal<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  sake_storage: &mut SakeStorage,
  clock_object: &Clock,
  ctx: &mut TxContext
 ): Coin<SAKE> {
  // Update the pool before any mutation
  update_pool<T>(storage, clock_object);
  
  // Get muobject_table Pool and Account structs
  let key = get_pool_key<T>(storage);
  let pool = borrow_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  let is_sake = pool.pool_key == SAKE_POOL_KEY;

  // Save the user balance value in memory
  let account_balance_value = (balance::value(&account.balance) as u256);

  // Calculate how many rewards the caller is entitled to
  let pending_rewards = if (is_sake) {
    fmul_u256((account_balance_value as u256), pool.accrued_sake_per_share)
  } else {
    ((account_balance_value as u256) * pool.accrued_sake_per_share)
  } - account.rewards_paid;

  // No point to keep going if there are no rewards
  assert!(pending_rewards != 0, ERROR_NO_PENDING_REWARDS);
  
  // Consider all pending rewards paid
  account.rewards_paid = if (is_sake) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_sake_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_sake_per_share
  };

  // Mint Coin<SAKE> rewards to the caller
  sake::mint(sake_storage, &storage.publisher, (pending_rewards as u64), ctx)
 }

 /**
 * @notice Updates the reward info of all pools registered in this contract
 * @param storage The MasterChefStorage shared object
 */
 fun update_all_pools_internal(storage: &mut MasterChefStorage, clock_object: &Clock) {
  // Find out how many pools are in the contract
  let length = object_table::length(&storage.pools);

  // Index to keep track of how many pools we have updated
  let index = 0;

  // Save in memory key information before mutating the storage struct
  let sake_per_ms = storage.sake_per_ms;
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;

  // Loop to iterate through all pools
  while (index < length) {
    // Borrow muobject_table Pool Struct
    let pool = object_table::borrow_mut(&mut storage.pools, index);

    // Update the pool
    update_pool_internal2(pool, clock_object, sake_per_ms, total_allocation_points, start_timestamp);

    // Increment the index
    index = index + 1;
  }
 }  

 /**
 * @notice Updates the reward info for T Pool
 * @param storage The MasterChefStorage shared object
 */
 fun update_pool_internal<T>(storage: &mut MasterChefStorage, clock_object: &Clock) {
  // Save in memory key information before mutating the storage struct
  let sake_per_ms = storage.sake_per_ms;
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;

  // Borrow muobject_table Pool Struct
  let pool = borrow_mut_pool<T>(storage);

  // Update the pool
  update_pool_internal2(
    pool, 
    clock_object,
    sake_per_ms, 
    total_allocation_points, 
    start_timestamp
  );
 }

 /**
 * @dev The implementation of update_pool
 * @param pool T Pool Struct
 * @param sake_per_ms Value of Coin<SAKE> this module mints per millisecond
 * @param total_allocation_points The sum of all pool points
 * @param start_timestamp The timestamp that this module is allowed to start minting Coin<SAKE>
 */
 fun update_pool_internal2(
  pool: &mut Pool, 
  clock_object: &Clock,
  sake_per_ms: u64, 
  total_allocation_points: u64,
  start_timestamp: u64
  ) {
  // Save the current epoch in memory  
  let current_timestamp = clock::timestamp_ms(clock_object);

  // If the pool reward info is up to date or it is not allowed to start minting return;
  if (current_timestamp == pool.last_reward_timestamp || start_timestamp > current_timestamp) return;

  // Save how many epochs have passed since the last update
  let timestamp_delta = current_timestamp - pool.last_reward_timestamp;

  // Update the current pool last reward timestamp
  pool.last_reward_timestamp = current_timestamp;

  // There is nothing to do if the pool is not allowed to mint Coin<SAKE> or if there are no coins deposited on it.
  if (pool.allocation_points == 0 || pool.balance_value == 0) return;

  // Calculate the rewards (pool_allocation * milliseconds * sake_per_epoch) / total_allocation_points
  let rewards = ((pool.allocation_points as u256) * (timestamp_delta as u256) * (sake_per_ms as u256) / (total_allocation_points as u256));

  // Update the accrued_sake_per_share
  pool.accrued_sake_per_share = pool.accrued_sake_per_share + if (pool.pool_key == SAKE_POOL_KEY) {
    fdiv_u256(rewards, (pool.balance_value as u256))
  } else {
    (rewards / (pool.balance_value as u256))
  };
 }

 /**
 * @dev The updates the allocation points of the SAKE Pool and the total allocation points
 * The SAKE Pool must have 1/3 of all other pools allocations
 * @param storage The MasterChefStorage shared object
 */
 fun update_sake_pool(storage: &mut MasterChefStorage) {
    // Save the total allocation points in memory
    let total_allocation_points = storage.total_allocation_points;

    // Borrow the SAKE muobject_table pool struct
    let pool = borrow_mut_pool<SAKE>(storage);

    // Get points of all other pools
    let all_other_pools_points = total_allocation_points - pool.allocation_points;

    // Divide by 3 to get the new sake pool allocation
    let new_sake_pool_allocation_points = all_other_pools_points / 3;

    // Calculate the total allocation points
    let total_allocation_points = total_allocation_points + new_sake_pool_allocation_points - pool.allocation_points;

    // Update pool and storage
    pool.allocation_points = new_sake_pool_allocation_points;
    storage.total_allocation_points = total_allocation_points;
 } 

  /**
  * @dev Finds T Pool from MasterChefStorage
  * @param storage The SakeStorage shared object
  * @return muobject_table T Pool
  */
 fun borrow_mut_pool<T>(storage: &mut MasterChefStorage): &mut Pool {
  let key = get_pool_key<T>(storage);
  object_table::borrow_mut(&mut storage.pools, key)
 }

/**
* @dev Finds T Pool from MasterChefStorage
* @param storage The SakeStorage shared object
* @return immuobject_table T Pool
*/
public fun borrow_pool<T>(storage: &MasterChefStorage): &Pool {
  let key = get_pool_key<T>(storage);
  object_table::borrow(&storage.pools, key)
 }

/**
* @dev Finds the key of a pool
* @param storage The MasterChefStorage shared object
* @return the key of T Pool
*/
 fun get_pool_key<T>(storage: &MasterChefStorage): u64 {
    table::borrow<String, PoolKey>(&storage.pool_keys, get_coin_info_string<T>()).key
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return immuobject_table AccountStruct of sender for T Pool
*/ 
 public fun borrow_account<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): &Account<T> {
  object_bag::borrow(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return immuobject_table AccountStruct of sender for T Pool
*/ 
 public fun account_exists<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): bool {
  object_bag::contains(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

/**
* @dev Finds an Account struct for T Pool
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return muobject_table AccountStruct of sender for T Pool
*/ 
fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, key: u64, sender: address): &mut Account<T> {
  object_bag::borrow_mut(object_table::borrow_mut(&mut accounts_storage.accounts, key), sender)
 }

/**
* @dev Updates the value of Coin<SAKE> this module is allowed to mint per millisecond
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param sake_per_ms the new sake_per_ms
* Requirements: 
* - The caller must be the admin
*/ 
 entry public fun update_sake_per_ms(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  clock_object: &Clock,
  sake_per_ms: u64
  ) {
    // Update all pools rewards info before updating the sake_per_epoch
    update_all_pools(storage, clock_object);
    storage.sake_per_ms = sake_per_ms;
 }

/**
* @dev Register a Pool for Coin<T> in this module
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param allocaion_points The allocation points of the new T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - Only one Pool per Coin<T>
*/ 
public entry fun add_pool<T>(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  accounts_storage: &mut AccountStorage,
  clock_object: &Clock,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  // Ensure that a new pool has an allocation
  assert!(allocation_points != 0, ERROR_NO_ZERO_ALLOCATION_POINTS);
  // Save total allocation points and start epoch in memory
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;
  // Update all pools if true
  if (update) update_all_pools(storage, clock_object);

  let coin_info_string = get_coin_info_string<T>();

  // Make sure Coin<T> has never been registered
  assert!(!table::contains(&storage.pool_keys, coin_info_string), ERROR_POOL_ADDED_ALREADY);

  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points + allocation_points;

  // Current number of pools is the key of the new pool
  let key = table::length(&storage.pool_keys);

  // Register the Account object_bag
  object_table::add(
    &mut accounts_storage.accounts,
    key,
    object_bag::new(ctx)
  );

  // Register the PoolKey
  table::add(
    &mut storage.pool_keys,
    coin_info_string,
    PoolKey {
      key
    }
  );

  // Save the current_epoch in memory
  let current_timestamp = clock::timestamp_ms(clock_object);

  // Register the Pool in SakeStorage
  object_table::add(
    &mut storage.pools,
    key,
    Pool {
      id: object::new(ctx),
      allocation_points,
      last_reward_timestamp: if (current_timestamp > start_timestamp) { current_timestamp } else { start_timestamp },
      accrued_sake_per_share: 0,
      balance_value: 0,
      pool_key: key
    }
  );

  // Emit
  event::emit(
    AddPool<T> {
      key,
      allocation_points
    }
  );

  // Update the SAKE Pool allocation
  update_sake_pool(storage);
 }

 public entry fun add_pool_internal<T>(
  storage: &mut MasterChefStorage,
  accounts_storage: &mut AccountStorage,
  clock_object: &Clock,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  // Ensure that a new pool has an allocation
  assert!(allocation_points != 0, ERROR_NO_ZERO_ALLOCATION_POINTS);
  // Save total allocation points and start epoch in memory
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;
  // Update all pools if true
  if (update) update_all_pools(storage, clock_object);

  let coin_info_string = get_coin_info_string<T>();

  // Make sure Coin<T> has never been registered
  assert!(!table::contains(&storage.pool_keys, coin_info_string), ERROR_POOL_ADDED_ALREADY);

  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points + allocation_points;

  // Current number of pools is the key of the new pool
  let key = table::length(&storage.pool_keys);

  // Register the Account object_bag
  object_table::add(
    &mut accounts_storage.accounts,
    key,
    object_bag::new(ctx)
  );

  // Register the PoolKey
  table::add(
    &mut storage.pool_keys,
    coin_info_string,
    PoolKey {
      key
    }
  );

  // Save the current_epoch in memory
  let current_timestamp = clock::timestamp_ms(clock_object);

  // Register the Pool in SakeStorage
  object_table::add(
    &mut storage.pools,
    key,
    Pool {
      id: object::new(ctx),
      allocation_points,
      last_reward_timestamp: if (current_timestamp > start_timestamp) { current_timestamp } else { start_timestamp },
      accrued_sake_per_share: 0,
      balance_value: 0,
      pool_key: key
    }
  );

  // Emit
  event::emit(
    AddPool<T> {
      key,
      allocation_points
    }
  );

  // Update the SAKE Pool allocation
  update_sake_pool(storage);
 }

/**
* @dev Updates the allocation points for T Pool
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param allocation_points The new allocation points for T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - The Pool must exist
*/ 
 entry public fun set_allocation_points<T>(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  clock_object: &Clock,
  allocation_points: u64,
  update: bool
 ) {
  // Save the total allocation points in memory
  let total_allocation_points = storage.total_allocation_points;
  // Update all pools
  if (update) update_all_pools(storage, clock_object);

  // Get Pool key and Pool muobject_table Struct
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);

  // No point to update if the new allocation_points is not different
  if (pool.allocation_points == allocation_points) return;

  // Update the total allocation points
  let total_allocation_points = total_allocation_points + allocation_points - pool.allocation_points;

  // Update the T Pool allocation points
  pool.allocation_points = allocation_points;
  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points;

  event::emit(
    SetAllocationPoints<T> {
      key,
      allocation_points
    }
  );

  // Update the SAKE Pool allocation points
  update_sake_pool(storage);
 }
 
 /**
 * @notice It allows the admin to transfer the AdminCap to a new address
 * @param admin The SAKEAdmin Struct
 * @param recipient The address of the new admin
 */
 entry public fun transfer_admin(
  admin: MasterChefAdmin,
  recipient: address
 ) {
  transfer::transfer(admin, recipient);
  event::emit(NewAdmin { admin: recipient })
 }

 /**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @param accounts_storage The AccountStorage shared object
 * @param sender The address we wish to check
 * @return balance of the account on T Pool and rewards paid 
 */
 public fun get_account_info<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): (u64, u256) {
    let account = object_bag::borrow<address, Account<T>>(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender);
    (
      balance::value(&account.balance),
      account.rewards_paid
    )
  }

/**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @return allocation_points, last_reward_timestamp, accrued_sake_per_share, balance_value of T Pool
 */
  public fun get_pool_info<T>(storage: &MasterChefStorage): (u64, u64, u256, u64) {
    let key = get_pool_key<T>(storage);
    let pool = object_table::borrow(&storage.pools, key);
    (
      pool.allocation_points,
      pool.last_reward_timestamp,
      pool.accrued_sake_per_share,
      pool.balance_value
    )
  }

  /**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @return total sake_per_ms, total_allocation_points, start_timestamp
 */
  public fun get_master_chef_storage_info(storage: &MasterChefStorage): (u64, u64, u64) {
    (
      storage.sake_per_ms,
      storage.total_allocation_points,
      storage.start_timestamp
    )
  }


/**
* @notice It allows a user to deposit a Coin<T> in a farm to earn Coin<SAKE>. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sake_storage The shared Object of SAKE
* @param clock_object The Clock object created at genesis
* @param vector_token  A list of Coin<Y>, the contract will merge all coins into with the `coin_y_amount` and return any extra value 
* @param coin_token_amount The desired amount of Coin<X> to send
*/
  entry public fun stake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    _sake_storage: &mut SakeStorage,
    clock_object: &Clock,
    coin_token: Coin<T>,
    stake_amount: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let stake_token = coin::split(&mut coin_token, stake_amount, ctx);

    // Stake and send Coin<SAKE> rewards to the caller.
    stake_internal(
      storage,
      accounts_storage,
      _sake_storage,
      clock_object,
      stake_token,
      stake_amount,
      ctx
    );

    return_remaining_coin(coin_token, ctx);
  }

/**
* @notice It allows a user to withdraw an amount of Coin<T> from a farm. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sake_storage The shared Object of SAKE
* @param clock_object The Clock object created at genesis
* @param coin_value The amount of Coin<T> the caller wishes to withdraw
*/
  entry public fun unstake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    sake_storage: &mut SakeStorage,
    clock_object: &Clock,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // Unstake yields Coin<SAKE> rewards.
    let (coin_sake, coin) = unstake_internal<T>(
        storage,
        accounts_storage,
        sake_storage,
        clock_object,
        coin_value,
        ctx
    );
    transfer::public_transfer(coin_sake, sender);
    transfer::public_transfer(coin, sender);
  }

/**
* @notice It allows a user to withdraw his/her rewards from a specific farm. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sake_storage The shared Object of SAKE
* @param clock_object The Clock object created at genesis
*/
  entry public fun get_rewards<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    sake_storage: &mut SakeStorage,
    clock_object: &Clock,
    ctx: &mut TxContext   
  ) {
    transfer::public_transfer(get_rewards_internal<T>(storage, accounts_storage, sake_storage, clock_object, ctx) ,tx_context::sender(ctx));
  }

/**
* @notice It updates the Coin<T> farm rewards calculation.
* @param storage The MasterChefStorage shared object
* @param clock_object The Clock object created at genesis
*/
  entry public fun update_pool<T>(storage: &mut MasterChefStorage, clock_object: &Clock) {
    update_pool_internal<T>(storage, clock_object);
  }

/**
* @notice It updates all pools.
* @param storage The MasterChefStorage shared object
* @param clock_object The Clock object created at genesis
*/
  entry public fun update_all_pools(storage: &mut MasterChefStorage, clock_object: &Clock) {
    update_all_pools_internal(storage, clock_object);
  }

/**
* @notice It allows a user to burn Coin<SAKE>.
* @param storage The storage of the module sake::ipx 
* @param coin_sake The Coin<SAKE>
*/
  entry public fun burn_sake(
    storage: &mut SakeStorage,
    coin_sake: Coin<SAKE>
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    sake::burn(storage, coin_sake);
  }

  /**
  * @dev A utility function to return to the frontend the allocation, pool_balance and _account balance of farm for Coin<X>
  * @param storage The MasterChefStorage shared object
  * @param accounts_storage the AccountStorage shared object of the masterchef contract
  * @param account The account of the user that has Coin<X> in the farm
  * @param farm_vector The list of farm data we will be mutation/adding
  */
  fun get_farm<X>(
    storage: &MasterChefStorage,
    accounts_storage: &AccountStorage,
    account: address,
    farm_vector: &mut vector<vector<u64>>
  ) {
     let inner_vector = vector::empty<u64>();
    let (allocation, _, _, pool_balance) = get_pool_info<X>(storage);

    vector::push_back(&mut inner_vector, allocation);
    vector::push_back(&mut inner_vector, pool_balance);

    if (account_exists<X>(storage, accounts_storage, account)) {
      let (account_balance, _) = get_account_info<X>(storage, accounts_storage, account);
      vector::push_back(&mut inner_vector, account_balance);
    } else {
      vector::push_back(&mut inner_vector, 0);
    };

    vector::push_back(farm_vector, inner_vector);
  }

  /**
  * @dev The implementation of the get_farm function. It collects information for ${num_of_farms}.
  * @param storage The MasterChefStorage shared object
  * @param accounts_storage the AccountStorage shared object of the masterchef contract
  * @param account The account of the user that has Coin<X> in the farm
  * @param num_of_farms The number of farms we wish to collect data from for a maximum of 3
  */
  public fun get_farms<A, B, C>(
    storage: &MasterChefStorage,
    accounts_storage: &AccountStorage,
    account: address,
    num_of_farms: u64
  ): vector<vector<u64>> {
    let farm_vector = vector::empty<vector<u64>>(); 

    get_farm<A>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 1) return farm_vector;

    get_farm<B>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 2) return farm_vector;

    get_farm<C>(storage, accounts_storage, account, &mut farm_vector);

    farm_vector
  }

  fun return_remaining_coin<X>(
        coin: Coin<X>,
        ctx: &mut TxContext,
  ) {
      if (coin::value(&coin) == 0) {
          coin::destroy_zero(coin);
      } else {
          transfer::public_transfer(coin, tx_context::sender(ctx));
      };
  }


  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(MASTER_CHEF {} ,ctx);
  }

  #[test_only]
  use sui::object::{ID};

  #[test_only]
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

  #[test_only]
  use defi::kojikiswap::{LPCoin};

  #[test_only]
  public fun get_publisher_id(storage: &MasterChefStorage): ID {
    let scenario = scenario();
    let (owner, one, _) = people();
    next_tx(&mut scenario, owner);
    {
        let _test = &mut scenario;
        // init_for_testing(ctx(test));
    };
    next_tx(&mut scenario, one);
    {
        let test = &mut scenario;
        let lps = test::take_shared<MasterChefStorage>(test);
        test::return_shared(lps);
    };
    test::end(scenario);
    object::id(&storage.publisher)
  }

  struct TestCoinA has drop {}
  struct TestCoinB has drop {}

  #[test]
  public fun test_stake_reward() {
    use sui::coin::{mint_for_testing as mint, burn_for_testing as burn};
    let scenario = scenario();
    let (owner, _one, _two) = people();
    next_tx(&mut scenario, owner);
    {
        let test = &mut scenario;
        init_for_testing(ctx(test));
        let clock = clock::create_for_testing(ctx(test));
        clock::share_for_testing(clock);
    };
    next_tx(&mut scenario, owner);
    {
        let test = &mut scenario;
        let masterchefstorage = test::take_shared<MasterChefStorage>(test);
        let accountstorage = test::take_shared<AccountStorage>(test);
        // let sakestorage = test::take_shared<SakeStorage>(test);
        let clock = clock::create_for_testing(ctx(test));
        // let clock = test::take_shared<Clock>(test);
        // mint LPCoin<CoinA, CoinB>
        let lpToken = mint<LPCoin<TestCoinA, TestCoinB>>(10000, ctx(test));

        // stake coinA 50, coinB 500
        let _stake_token = coin::split(&mut lpToken, 100, ctx(test));

        // Stake and send Coin<SAKE> rewards to the caller.
        // stake_internal(
        //   &mut masterchefstorage,
        //   &mut accountstorage,
        //   @0xCAFE,//&mut sakestorage,
        //   &clock,
        //   stake_token,
        //   100,
        //   ctx(test)
        // );

        clock::increment_for_testing(&mut clock, 27*24*3600*1000);

        // stake coinA 10, coinB 100

        // get_pending_reward
        let rewards = get_pending_rewards<LPCoin<TestCoinA, TestCoinB>>(
          &masterchefstorage ,
          &accountstorage,
          &clock,
          tx_context::sender(ctx(test))
        );

        assert!(rewards != 0, 0x1FFFF);
        // burn coins
        burn(lpToken);
        burn(_stake_token);

        // test::return_shared(clock);
        // balance::decrease_supply(&mut sakestorage.supply, coin::into_balance(stake_token));
        clock::destroy_for_testing(clock);
        test::return_shared(masterchefstorage);
        test::return_shared(accountstorage);
    };
    test::end(scenario);
  }

  #[test]
  fun scenario(): Scenario { test::begin(@0x1) }
  #[test]
  fun people(): (address, address, address) { (@0xBEEF, @0x1111, @0x2222) }
}
