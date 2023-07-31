// The governance token (SAKE) of Interest Protocol
module sake::xsake {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::balance::{Self, Supply, Balance};
  // use sui::vec_set::{Self};
  // use sui::package::{Publisher};
  // use sui::event::{emit};
  use sui::tx_context;
  use sake::sake::{SAKE};

  // Errors
  const ERROR_NOT_ALLOWED_TO_MINT: u64 = 1;
  const ERROR_NO_ZERO_ADDRESS: u64 = 2;

  struct XSAKE has drop {}

  struct XSakeStorage has key {
    id: UID,
    supply: Supply<XSAKE>,
    sake_coins: Balance<SAKE>
  }

  fun init(witness: XSAKE, ctx: &mut TxContext) {
      // Create the SAKE governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<XSAKE>(
            witness, 
            9,
            b"XSAKE",
            b"Kojiki Protocol Escrowed Coin",
            b"The Escrowed Coin of Kojiki Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://brown-democratic-crawdad-536.mypinata.cloud/ipfs/QmZmqPtULkUvzkCEnkYdGwGiRFnKEbJq3RhxSoCTsmX5Ed")),
            ctx
        );
      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DNR
      let supply = coin::treasury_into_supply(treasury);

      transfer::share_object(
        XSakeStorage {
          id: object::new(ctx),
          supply,
          sake_coins: balance::zero<SAKE>(),
        });

      // Freeze the metadata object
      transfer::public_freeze_object(metadata);
  }

  public entry fun convert_from_sake(storage: &mut XSakeStorage, sake: Coin<SAKE>, value: u64, ctx: &mut TxContext) {
    // mint xsake
    let xsake = mint(storage, value, ctx);
    let coins_in = coin::split(&mut sake, value, ctx);
    
    return_remaining_coin(sake, ctx);

    // deposit sake
    balance::join<SAKE>(&mut storage.sake_coins, coin::into_balance(coins_in));
    transfer::public_transfer(xsake, tx_context::sender(ctx));
  }

  public entry fun convert_to_sake(storage: &mut XSakeStorage, xsake: Coin<XSAKE>, value: u64, ctx: &mut TxContext) {
    // burn xsake
    let coins_in = coin::split(&mut xsake, value, ctx);
    burn(storage, coins_in);
    return_remaining_coin(xsake, ctx);
    
    // transfer sake
    let sake_balance = balance::split<SAKE>(&mut storage.sake_coins, value);
    transfer::public_transfer(coin::from_balance(sake_balance, ctx), tx_context::sender(ctx));
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
  
  /**
  * @dev Only minters can create new Coin<SAKE>
  * @param storage The XSakeStorage
  * @param publisher The Publisher object of the package who wishes to mint SAKE
  * @return Coin<SAKE> New created SAKE coin
  */
  public fun mint(storage: &mut XSakeStorage, value: u64, ctx: &mut TxContext): Coin<XSAKE> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  /**
  * @dev This function allows anyone to burn their own SAKE.
  * @param storage The XSakeStorage shared object
  * @param c The SAKE coin that will be burned
  */
  public fun burn(storage: &mut XSakeStorage, c: Coin<XSAKE>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(c))
  }

  /**
  * @dev A utility function to transfer SAKE to a {recipient}
  * @param c The Coin<SAKE> to transfer
  * @param recipient The recipient of the Coin<SAKE>
  */
  public entry fun transfer(c: coin::Coin<SAKE>, recipient: address) {
    transfer::public_transfer(c, recipient);
  }

  /**
  * @dev It returns the total supply of the Coin<X>
  * @param storage The {XSakeStorage} shared object
  * @return the total supply in u64
  */
  public fun total_supply(storage: &XSakeStorage): u64 {
    balance::supply_value(&storage.supply)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(XSAKE {}, ctx);
  }
}