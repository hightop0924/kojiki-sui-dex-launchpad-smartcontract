module token::usdc {
  use std::option;

  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::coin::{Self, Coin, TreasuryCap};
  use sui::url;

  const AMOUNT: u64 = 600000000000000000; // 600M 60% of the supply

  struct USDC has drop {}

  fun init(witness: USDC, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<USDC>(
            witness, 
            8,
            b"USDC",
            b"USDC",
            b"USDC Token",
            option::some(url::new_unsafe_from_bytes(b"https://coinlist.animeswap.org/icons/USDC.webp")),
            ctx
        );

      let sender = tx_context::sender(ctx);  

      coin::mint_and_transfer(&mut treasury, AMOUNT, sender, ctx);

      transfer::public_transfer(treasury, sender);

      // Freeze the metadata object
      transfer::public_freeze_object(metadata);
  }

  entry fun mint(
        cap: &mut TreasuryCap<USDC>, value: u64, sender: address, ctx: &mut TxContext,
    ) {
     coin::mint_and_transfer(cap, value, sender, ctx);
  }

  /**
  * @dev A utility function to transfer IPX to a {recipient}
  * @param c The Coin<IPX> to transfer
  * @param recipient The recipient of the Coin<IPX>
  */
  public entry fun transfer(c: Coin<USDC>, recipient: address) {
    transfer::public_transfer(c, recipient);
  }
}