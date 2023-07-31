// The governance token (SAKE) of Interest Protocol
module sake::sake {
  use std::option;

  use sui::object::{Self, UID, ID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::vec_set::{Self, VecSet};
  use sui::tx_context;
  use sui::package::{Publisher};
  use sui::event::{emit};

  const SAKE_PRE_MINT_AMOUNT: u64 = 600000000000000000; // 600M 60% of the supply

  // Errors
  const ERROR_NOT_ALLOWED_TO_MINT: u64 = 1;
  const ERROR_NO_ZERO_ADDRESS: u64 = 2;

  struct SAKE has drop {}

  struct SakeStorage has key {
    id: UID,
    supply: Supply<SAKE>,
    minters: VecSet<ID> // List of publishers that are allowed to mint SAKE
  }

  struct SakeAdminCap has key {
    id: UID
  }

  // Events 
  struct MinterAdded has copy, drop {
    id: ID
  }

  struct MinterRemoved has copy, drop {
    id: ID
  }

  struct NewAdmin has copy, drop {
    admin: address
  }

  fun init(witness: SAKE, ctx: &mut TxContext) {
      // Create the SAKE governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<SAKE>(
            witness, 
            9,
            b"SAKE",
            b"Kojiki Protocol Token",
            b"The governance token of Kojiki Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://brown-democratic-crawdad-536.mypinata.cloud/ipfs/Qme8CV8ddPD3tLqwggyDFQi7924mo5ztFx5Jyczgu2c4vP")),
            ctx
        );
      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DNR
      let supply = coin::treasury_into_supply(treasury);

      // Pre-mint 60% of the supply to distribute
      transfer::public_transfer(
        coin::from_balance(
          balance::increase_supply(&mut supply, SAKE_PRE_MINT_AMOUNT), ctx
        ),
        @admin
      );

      transfer::transfer(
        SakeAdminCap {
          id: object::new(ctx)
        },
        tx_context::sender(ctx)
      );

      transfer::share_object(
        SakeStorage {
          id: object::new(ctx),
          supply,
          minters: vec_set::empty()
        }
      );

      // Freeze the metadata object
      transfer::public_freeze_object(metadata);
  }

  /**
  * @dev Only minters can create new Coin<SAKE>
  * @param storage The SakeStorage
  * @param publisher The Publisher object of the package who wishes to mint SAKE
  * @return Coin<SAKE> New created SAKE coin
  */
  public fun mint(storage: &mut SakeStorage, publisher: &Publisher, value: u64, ctx: &mut TxContext): Coin<SAKE> {
    assert!(is_minter(storage, object::id(publisher)), ERROR_NOT_ALLOWED_TO_MINT);

    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  /**
  * @dev This function allows anyone to burn their own SAKE.
  * @param storage The SakeStorage shared object
  * @param c The SAKE coin that will be burned
  */
  public fun burn(storage: &mut SakeStorage, c: Coin<SAKE>): u64 {
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
  * @param storage The {SakeStorage} shared object
  * @return the total supply in u64
  */
  public fun total_supply(storage: &SakeStorage): u64 {
    balance::supply_value(&storage.supply)
  }


  /**
  * @dev It allows the holder of the {SakeAdminCap} to add a minter. 
  * @param _ The SakeAdminCap to guard this function 
  * @param storage The SakeStorage shared object
  * @param publisher The package that owns this publisher will be able to mint SAKE
  *
  * It emits the MinterAdded event with the {ID} of the {Publisher}
  *
  */
  entry public fun add_minter(_: &SakeAdminCap, storage: &mut SakeStorage, id: ID) {
    vec_set::insert(&mut storage.minters, id);
    emit(
      MinterAdded {
        id
      }
    );
  }

  /**
  * @dev It allows the holder of the {SakeAdminCap} to remove a minter. 
  * @param _ The SakeAdminCap to guard this function 
  * @param storage The SakeStorage shared object
  * @param publisher The package that will no longer be able to mint SAKE
  *
  * It emits the  MinterRemoved event with the {ID} of the {Publisher}
  *
  */
  entry public fun remove_minter(_: &SakeAdminCap, storage: &mut SakeStorage, id: ID) {
    vec_set::remove(&mut storage.minters, &id);
    emit(
      MinterRemoved {
        id
      }
    );
  } 


  /**
  * @dev It gives the admin rights to the recipient. 
  * @param admin_cap The SakeAdminCap that will be transferred
  * @recipient the new admin address
  *
  * It emits the NewAdmin event with the new admin address
  *
  */
  entry public fun transfer_admin(admin_cap: SakeAdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_NO_ZERO_ADDRESS);
    transfer::transfer(admin_cap, recipient);

    emit(NewAdmin {
      admin: recipient
    });
  } 

  /**
  * @dev It indicates if a package has the right to mint SAKE
  * @param storage The SakeStorage shared object
  * @param publisher of the package 
  * @return bool true if it can mint SAKE
  */
  public fun is_minter(storage: &SakeStorage, id: ID): bool {
    vec_set::contains(&storage.minters, &id)
  }


  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SAKE {}, ctx);
  }
}